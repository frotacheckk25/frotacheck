import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/models/checklist_model.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/image_validation.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/widgets/signed_network_image.dart';
import '../veiculos/veiculo_historico_page.dart';
import '../veiculos/veiculos_page.dart';
import 'vistoria_widgets.dart';

/// Paleta do painel de checklist (layout "Opção 4 — abas e ícones").
class _C {
  static const bg = Color(0xFF0B1220);
  static const card = Color(0xFF0F1E33);
  static const borda = Color(0xFF1E3A5A);
  static const primario = Color(0xFF00D1FF);
  static const teal = Color(0xFF00F5C3);
  static const sucesso = Color(0xFF00E676);
  static const atencao = Color(0xFFFFB824);
  static const texto = Color(0xFFFFFFFF);
  static const texto2 = Color(0xFFA0AEC0);
}

/// Checklist de saída e de retorno — mesma tela, muda só o contexto
/// (tipo = 'saida' | 'retorno'). Mantém todas as regras anteriores:
/// itens (com "não se aplica" nos opcionais), 6 fotos obrigatórias com
/// avarias por posição, KM validado contra o hodômetro, nível do tanque,
/// upload com nova tentativa e atualização do hodômetro do veículo.
class ChecklistVistoriaPage extends StatefulWidget {
  final String tipo;
  final String veiculoId;
  final String veiculoPlaca;
  final String motoristaId;

  const ChecklistVistoriaPage({
    super.key,
    required this.tipo,
    required this.veiculoId,
    required this.veiculoPlaca,
    required this.motoristaId,
  });

  @override
  State<ChecklistVistoriaPage> createState() => _ChecklistVistoriaPageState();
}

class _ChecklistVistoriaPageState extends State<ChecklistVistoriaPage> {
  final supabase = Supabase.instance.client;
  final imagePicker = ImagePicker();

  // Veículo em vistoria (pode ser trocado pelo carrossel).
  late String _veiculoId = widget.veiculoId;
  late String _placa = widget.veiculoPlaca;

  // Dados reais carregados do banco.
  List<Map<String, dynamic>> _veiculos = [];
  bool _carregandoVeiculos = true;
  String? _erroVeiculos;
  List<Map<String, dynamic>> _historico = [];
  bool _carregandoHistorico = true;

  // Estado do checklist.
  late Map<String, Object> itensVerificados;
  final List<Map<String, dynamic>> fotosCapturadas = [];
  final Map<String, Map<String, dynamic>> avarias = {};
  String? nivelTanque;
  final _kmController = TextEditingController();
  final _destinoController = TextEditingController();
  final _finalidadeController = TextEditingController();
  final _observacoesController = TextEditingController();
  bool _salvando = false;

  int _aba = 0; // 0 Checklist · 1 Veículo · 2 Fotos · 3 Observações
  final _carrosselController = ScrollController();
  DateTime _agora = DateTime.now();
  Timer? _relogio;

  bool get _isSaida => widget.tipo == 'saida';

  @override
  void initState() {
    super.initState();
    itensVerificados = {for (final item in Checklist.itensChecklist) item: false};
    _kmController.addListener(() => setState(() {}));
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _agora = DateTime.now());
    });
    _carregarVeiculos();
    _carregarHistorico();
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _kmController.dispose();
    _destinoController.dispose();
    _finalidadeController.dispose();
    _observacoesController.dispose();
    _carrosselController.dispose();
    super.dispose();
  }

  // ── Dados ──────────────────────────────────────────────────────────────────

  Future<void> _carregarVeiculos() async {
    setState(() {
      _carregandoVeiculos = true;
      _erroVeiculos = null;
    });
    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      final rows = await fetchAllRows((from, to) {
        var q = supabase
            .from('vehicles')
            .select('id, plate, brand, model, year, color, odometer, foto_url, tipo, empresa_id');
        if (auth.isMotorista && auth.driverId != null) {
          q = q.eq('driver_id', auth.driverId!);
        } else if (eid != null) {
          q = q.eq('empresa_id', eid);
        }
        return q.order('plate').order('id').range(from, to);
      });
      if (!mounted) return;
      setState(() {
        _veiculos = rows;
        _carregandoVeiculos = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _rolarAteSelecionado());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroVeiculos = friendlyError(e);
        _carregandoVeiculos = false;
      });
    }
  }

  /// Últimos checklists do veículo: observações anteriores e, no retorno, o
  /// KM registrado na saída (referência para o KM de chegada).
  Future<void> _carregarHistorico() async {
    setState(() => _carregandoHistorico = true);
    try {
      final res = await supabase
          .from('checklists')
          .select('id, tipo, observacoes, km_inicial, km_final, criado_em, data')
          .eq('veiculo_id', _veiculoId)
          .order('criado_em', ascending: false)
          .limit(10);
      if (!mounted) return;
      setState(() {
        _historico = List<Map<String, dynamic>>.from(res);
        _carregandoHistorico = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historico = [];
        _carregandoHistorico = false;
      });
    }
  }

  Map<String, dynamic>? get _veiculoAtual {
    for (final v in _veiculos) {
      if (v['id']?.toString() == _veiculoId) return v;
    }
    return null;
  }

  num? get _odometroAtual => _veiculoAtual?['odometer'] as num?;

  Map<String, dynamic>? get _ultimaSaida {
    for (final h in _historico) {
      if (h['tipo'] == 'saida' && h['km_inicial'] != null) return h;
    }
    return null;
  }

  List<Map<String, dynamic>> get _obsAnteriores => _historico
      .where((h) => (h['observacoes']?.toString().trim() ?? '').isNotEmpty)
      .take(5)
      .toList();

  // ── Veículo (carrossel) ────────────────────────────────────────────────────

  Future<void> _trocarVeiculo(Map<String, dynamic> v) async {
    final id = v['id']?.toString();
    if (id == null || id == _veiculoId || _salvando) return;
    if (fotosCapturadas.isNotEmpty || avarias.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _C.card,
          title: const Text('Trocar de veículo?', style: TextStyle(color: _C.texto)),
          content: const Text(
            'As fotos e avarias já registradas são deste veículo e serão descartadas.',
            style: TextStyle(color: _C.texto2),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trocar')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _veiculoId = id;
      _placa = v['plate']?.toString() ?? '';
      fotosCapturadas.clear();
      avarias.clear();
      _kmController.clear();
    });
    _carregarHistorico();
    _rolarAteSelecionado();
  }

  void _veiculoVizinho(int delta) {
    if (_veiculos.isEmpty) return;
    final idx = _veiculos.indexWhere((v) => v['id']?.toString() == _veiculoId);
    final novo = ((idx < 0 ? 0 : idx) + delta).clamp(0, _veiculos.length - 1);
    if (novo != idx) _trocarVeiculo(_veiculos[novo]);
  }

  void _rolarAteSelecionado() {
    if (!_carrosselController.hasClients) return;
    final idx = _veiculos.indexWhere((v) => v['id']?.toString() == _veiculoId);
    if (idx < 0) return;
    final alvo = (idx * 172.0 - 40).clamp(0.0, _carrosselController.position.maxScrollExtent);
    _carrosselController.animateTo(alvo, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _rolarCarrossel(double delta) {
    if (!_carrosselController.hasClients) return;
    final alvo = (_carrosselController.offset + delta)
        .clamp(0.0, _carrosselController.position.maxScrollExtent);
    _carrosselController.animateTo(alvo, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _adicionarVeiculo() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const VeiculosPage()));
    if (mounted) _carregarVeiculos();
  }

  void _verDetalhes() {
    final v = _veiculoAtual;
    if (v == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => VeiculoHistoricoPage(veiculo: v)));
  }

  // ── Itens ──────────────────────────────────────────────────────────────────

  int get _totalItens => Checklist.itensChecklist.length;
  int get _totalMarcados => itensVerificados.values.where(Checklist.itemOk).length;
  int get _totalFotos => Checklist.fotosObrigatorias.length;

  /// pendente → verificado; itens opcionais (extintor) passam por
  /// "não se aplica" antes de voltar a pendente.
  Object _proximoValor(String item, Object valor) {
    if (valor == Checklist.naoSeAplica) return false;
    if (valor == true) {
      return Checklist.itensOpcionais.contains(item) ? Checklist.naoSeAplica : false;
    }
    return true;
  }

  // ── Fotos ──────────────────────────────────────────────────────────────────

  Future<void> _capturarFoto(String label) async {
    if (fotosCapturadas.any((f) => f['label'] == label)) {
      final acao = await escolherAcaoFoto(context, label, avarias[label] != null);
      if (!mounted || acao == null) return;
      if (acao == AcaoFoto.avarias) {
        final r = await editarAvarias(context, label, avarias[label]);
        if (!mounted || r == null) return;
        setState(() {
          if ((r['tipos'] as List).isEmpty) {
            avarias.remove(label);
          } else {
            avarias[label] = r;
          }
        });
        return;
      }
      setState(() {
        fotosCapturadas.removeWhere((f) => f['label'] == label);
        if (acao == AcaoFoto.remover) avarias.remove(label);
      });
      if (acao == AcaoFoto.remover) return;
    }

    try {
      XFile? img;
      try {
        img = await imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 60,
          maxWidth: 900,
          maxHeight: 700,
        );
      } catch (_) {
        img = await imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 60,
          maxWidth: 900,
          maxHeight: 700,
        );
      }
      if (img != null) {
        final bytes = await img.readAsBytes();
        if (!mounted) return;
        if (!isValidImageBytes(bytes)) {
          showError(context, 'Arquivo não é uma imagem válida.');
          return;
        }
        setState(() => fotosCapturadas.add({'bytes': bytes, 'label': label}));
      }
    } catch (e) {
      debugPrint('Erro ao capturar foto ($label): $e');
      if (mounted) {
        showError(context, 'Não foi possível abrir a foto. Tente tirar de novo ou escolher outra imagem.');
      }
    }
  }

  Future<String?> _uploadComRetry(Uint8List bytes, String fileName) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await supabase.storage.from('checklists').uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        return supabase.storage.from('checklists').getPublicUrl(fileName);
      } catch (_) {
        if (attempt < 3) await Future.delayed(Duration(seconds: attempt));
      }
    }
    return null;
  }

  // ── Registro ───────────────────────────────────────────────────────────────

  void _falha(int aba, String msg) {
    setState(() => _aba = aba);
    showError(context, msg);
  }

  Future<void> _registrar() async {
    final rotuloKm = _isSaida ? 'KM de saída' : 'KM final';
    final km = int.tryParse(_kmController.text.trim());
    if (km == null || km < 0) {
      return _falha(1, 'Informe o $rotuloKm do veículo (somente números)');
    }
    if (km > Checklist.kmMaximo) {
      return _falha(1, '$rotuloKm inválido ($km). Confira o valor digitado.');
    }
    if (nivelTanque == null) return _falha(1, 'Informe o nível do tanque');
    if (fotosCapturadas.length < _totalFotos) {
      return _falha(2, 'Faltam ${_totalFotos - fotosCapturadas.length} foto(s) obrigatória(s)');
    }

    try {
      final veiculo = await supabase
          .from('vehicles')
          .select('odometer')
          .eq('id', _veiculoId)
          .maybeSingle();
      final atual = veiculo?['odometer'] as num?;
      if (atual != null && km < atual) {
        if (mounted) _falha(1, '$rotuloKm menor que o último registrado ($atual km)');
        return;
      }
    } catch (_) {}
    if (!mounted) return;

    // Itens pendentes não bloqueiam (checklist fica reprovado), mas avisa.
    final pendentes = _totalItens - _totalMarcados;
    if (pendentes > 0) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _C.card,
          title: const Text('Itens pendentes', style: TextStyle(color: _C.texto)),
          content: Text(
            '$pendentes item(ns) não foram verificados. O checklist será registrado como REPROVADO.',
            style: const TextStyle(color: _C.texto2),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar assim')),
          ],
        ),
      );
      if (seguir != true || !mounted) {
        if (mounted) setState(() => _aba = 0);
        return;
      }
    }

    setState(() => _salvando = true);
    final auth = context.read<AppAuthProvider>();
    final injetar = auth.inject;
    final pastaEmpresa = auth.effectiveEmpresaId ?? 'sem-empresa';

    try {
      final fotoUrls = <String>[];
      for (final f in fotosCapturadas) {
        final label = (f['label'] as String).toLowerCase().replaceAll(' ', '_');
        final fileName =
            '$pastaEmpresa/${widget.tipo}_${_veiculoId}_${label}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final url = await _uploadComRetry(f['bytes'] as Uint8List, fileName);
        if (url == null) {
          if (mounted) {
            showError(context, 'Falha ao enviar foto "${f['label']}". Tente novamente.');
            setState(() => _salvando = false);
          }
          return;
        }
        fotoUrls.add(url);
      }

      final avariasFinal = avariasParaSalvar(avarias);
      final obs = _observacoesController.text.trim();
      await supabase.from('checklists').insert(injetar({
        'veiculo_id': _veiculoId,
        'motorista_id': widget.motoristaId,
        'tipo': widget.tipo,
        'data': DateTime.now().toIso8601String().split('T')[0],
        'itens': itensVerificados,
        'foto_urls': fotoUrls,
        // Reprovado se faltou item OU se alguma avaria foi marcada.
        'aprovado': _totalMarcados == _totalItens && avariasFinal.isEmpty,
        'nivel_combustivel': nivelTanque,
        'avarias': avariasFinal,
        if (_isSaida) 'km_inicial': km else 'km_final': km,
        if (_isSaida && _destinoController.text.trim().isNotEmpty)
          'destino': _destinoController.text.trim(),
        if (_isSaida && _finalidadeController.text.trim().isNotEmpty)
          'finalidade': _finalidadeController.text.trim(),
        if (obs.isNotEmpty) 'observacoes': obs,
      }));

      // Atualiza o hodômetro do veículo (só sobe, nunca desce).
      try {
        await supabase
            .from('vehicles')
            .update({'odometer': km})
            .eq('id', _veiculoId)
            .lt('odometer', km);
      } catch (_) {}

      if (!mounted) return;
      showSuccess(context, _isSaida ? 'Checklist de saída registrado!' : 'Checklist de retorno registrado!');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final largo = c.maxWidth >= 1100;
          final conteudo = _conteudoPrincipal(c.maxWidth - (largo ? 360 : 0));
          return Column(
            children: [
              _cabecalho(c.maxWidth),
              Expanded(
                child: largo
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 4, 12, 24),
                              child: conteudo,
                            ),
                          ),
                          SizedBox(
                            width: 340,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 20, 20),
                              child: Column(
                                children: [
                                  _painelVeiculo(),
                                  const Spacer(),
                                  _botaoRegistrar(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _painelVeiculo(compacto: true),
                            const SizedBox(height: 12),
                            conteudo,
                            const SizedBox(height: 16),
                            _botaoRegistrar(),
                          ],
                        ),
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // Cabeçalho: voltar, "Saída - ABC-4455", status e data/hora.
  Widget _cabecalho(double largura) {
    final titulo = '${_isSaida ? 'Saída' : 'Retorno'} - $_placa';
    final data =
        '${_agora.day.toString().padLeft(2, '0')}/${_agora.month.toString().padLeft(2, '0')}/${_agora.year} '
        '${_agora.hour.toString().padLeft(2, '0')}:${_agora.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: _caixa(),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Voltar',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back, color: _C.texto),
          ),
          const Icon(Icons.directions_car_filled_outlined, color: _C.texto2, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(titulo,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _C.texto, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _C.teal.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _C.teal.withOpacity(0.6)),
            ),
            child: const Text('Em andamento',
                style: TextStyle(color: _C.teal, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          if (largura >= 560) ...[
            const Icon(Icons.calendar_month_outlined, color: _C.texto2, size: 18),
            const SizedBox(width: 6),
            Text(data, style: const TextStyle(color: _C.texto2, fontSize: 12)),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _conteudoPrincipal(double largura) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardProgresso(largura),
        const SizedBox(height: 14),
        _abas(largura),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey(_aba),
            child: switch (_aba) {
              0 => _abaChecklist(largura),
              1 => _abaVeiculo(),
              2 => _abaFotos(),
              _ => _abaObservacoes(),
            },
          ),
        ),
        const SizedBox(height: 14),
        _secaoCarrossel(),
        const SizedBox(height: 14),
        _campoObservacoes(),
      ],
    );
  }

  // Card de progresso: círculo X/Y, barra, % e KM/tanque.
  Widget _cardProgresso(double largura) {
    final pct = _totalItens == 0 ? 0.0 : _totalMarcados / _totalItens;
    final kmDigitado = int.tryParse(_kmController.text.trim());
    final kmExibido = kmDigitado ?? _odometroAtual?.toInt();
    final completo = _totalMarcados == _totalItens;

    final esquerda = Row(
      children: [
        SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: pct,
                  strokeWidth: 8,
                  backgroundColor: _C.borda,
                  valueColor: const AlwaysStoppedAnimation(_C.teal),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Text('$_totalMarcados/$_totalItens',
                  style: const TextStyle(color: _C.primario, fontSize: 22, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Checklist do Veículo',
                  style: TextStyle(color: _C.texto, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                completo ? 'Todos os itens verificados.' : 'Verifique todos os itens para continuar.',
                style: const TextStyle(color: _C.texto2, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: _C.borda,
                      valueColor: const AlwaysStoppedAnimation(_C.teal),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${(pct * 100).round()}%',
                    style: const TextStyle(color: _C.teal, fontSize: 14, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 8),
              // Pendências fora da aba de itens (fotos/KM/tanque) — texto, não só cor.
              Wrap(spacing: 10, runSpacing: 4, children: [
                _pendencia('Fotos ${fotosCapturadas.length}/$_totalFotos',
                    fotosCapturadas.length == _totalFotos, () => setState(() => _aba = 2)),
                _pendencia('KM', kmDigitado != null, () => setState(() => _aba = 1)),
                _pendencia('Tanque', nivelTanque != null, () => setState(() => _aba = 1)),
              ]),
            ],
          ),
        ),
      ],
    );

    final stats = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stat(Icons.speed_rounded, _isSaida ? 'KM atual' : 'KM informado',
            kmExibido != null ? '$kmExibido km' : '—'),
        const SizedBox(width: 10),
        _stat(Icons.local_gas_station_outlined, 'Nível do tanque', nivelTanque ?? '—'),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _caixa(),
      child: largura >= 820
          ? Row(children: [
              Expanded(child: esquerda),
              Container(width: 1, height: 80, color: _C.borda, margin: const EdgeInsets.symmetric(horizontal: 16)),
              stats,
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              esquerda,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: stats),
            ]),
    );
  }

  Widget _pendencia(String texto, bool ok, VoidCallback onTap) {
    final cor = ok ? _C.sucesso : _C.atencao;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ok ? Icons.check_circle : Icons.schedule, color: cor, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text('$texto ${ok ? 'ok' : 'pendente'}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cor, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _stat(IconData icon, String rotulo, String valor) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _C.bg.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.borda),
      ),
      child: Row(children: [
        Icon(icon, color: _C.primario, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: const TextStyle(color: _C.primario, fontSize: 11)),
            const SizedBox(height: 2),
            Text(valor,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _C.texto, fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }

  // Abas com ícone; ativa em destaque cyan/teal.
  Widget _abas(double largura) {
    const abas = [
      (Icons.check_circle_outline, 'Checklist'),
      (Icons.directions_car_outlined, 'Veículo'),
      (Icons.photo_camera_outlined, 'Fotos'),
      (Icons.description_outlined, 'Observações'),
    ];
    final soIcone = largura < 520;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: _caixa(),
      child: Row(
        children: List.generate(abas.length, (i) {
          final ativa = i == _aba;
          final (icone, rotulo) = abas[i];
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
              child: Semantics(
                button: true,
                selected: ativa,
                label: 'Aba $rotulo',
                child: InkWell(
                  key: ValueKey('aba-$rotulo'),
                  onTap: () => setState(() => _aba = i),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: ativa
                          ? LinearGradient(colors: [_C.primario.withOpacity(0.55), _C.teal.withOpacity(0.35)])
                          : null,
                      border: Border.all(color: ativa ? _C.primario : Colors.transparent),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icone, color: ativa ? _C.texto : _C.texto2, size: 20),
                        if (!soIcone) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(rotulo,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: ativa ? _C.texto : _C.texto2,
                                    fontSize: 14,
                                    fontWeight: ativa ? FontWeight.w700 : FontWeight.w500)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Aba Checklist: grid de cards dos itens ─────────────────────────────────

  static IconData _iconeItem(String item) {
    final i = item.toLowerCase();
    if (i.contains('extintor')) return Icons.fire_extinguisher;
    if (i.contains('macaco')) return Icons.car_repair;
    if (i.contains('chave')) return Icons.build_outlined;
    if (i.contains('tri')) return Icons.change_history;
    if (i.contains('pneu')) return Icons.tire_repair;
    if (i.contains('freio')) return Icons.album_outlined;
    if (i.contains('retrovisor')) return Icons.flip_outlined;
    if (i.contains('document')) return Icons.description_outlined;
    if (i.contains('luz') || i.contains('seta')) return Icons.lightbulb_outline;
    return Icons.check_box_outlined;
  }

  Widget _abaChecklist(double largura) {
    final colunas = largura >= 1000 ? 4 : (largura >= 700 ? 3 : (largura >= 420 ? 2 : 1));
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: colunas,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 92,
      ),
      itemCount: Checklist.itensChecklist.length,
      itemBuilder: (_, i) => _cardItem(Checklist.itensChecklist[i]),
    );
  }

  Widget _cardItem(String item) {
    final valor = itensVerificados[item] ?? false;
    final na = valor == Checklist.naoSeAplica;
    final ok = Checklist.itemOk(valor);
    final cor = na ? _C.texto2 : (ok ? _C.sucesso : _C.atencao);
    final status = na ? 'Não se aplica' : (ok ? 'Verificado' : 'Pendente');
    final nome = item.replaceAll(' (caso tenha)', '');

    return Semantics(
      button: true,
      label: '$nome: $status. Toque para alterar.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => itensVerificados[item] = _proximoValor(item, valor)),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: ok || na ? _C.card : _C.atencao.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ok || na ? _C.borda : _C.atencao.withOpacity(0.8)),
            ),
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (ok || na ? _C.primario : _C.atencao).withOpacity(0.08),
                  border: Border.all(color: (ok || na ? _C.primario : _C.atencao).withOpacity(0.5), width: 1.5),
                ),
                child: Icon(_iconeItem(item), color: ok || na ? _C.primario : _C.atencao, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _C.texto, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(na ? Icons.remove_circle_outline : (ok ? Icons.check_circle : Icons.schedule),
                          color: cor, size: 16),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(status,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: ok || na ? _C.texto2 : _C.atencao),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Aba Veículo: KM, tanque, destino/finalidade ────────────────────────────

  Widget _abaVeiculo() {
    final saida = _ultimaSaida;
    final kmSaidaRef = (saida?['km_inicial'] as num?)?.toInt();
    final kmDigitado = int.tryParse(_kmController.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoVistoria(
          controller: _kmController,
          label: _isSaida ? 'KM de saída do veículo *' : 'KM final do veículo *',
          icon: Icons.speed_outlined,
          keyboardType: TextInputType.number,
          hint: _odometroAtual != null ? 'Último registrado: ${_odometroAtual!.toInt()} km' : null,
        ),
        if (!_isSaida && kmSaidaRef != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'KM na última saída: $kmSaidaRef km'
              '${kmDigitado != null && kmDigitado >= kmSaidaRef ? ' · percorridos: ${kmDigitado - kmSaidaRef} km' : ''}',
              style: const TextStyle(color: _C.texto2, fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 10),
        NivelTanqueSelector(valor: nivelTanque, onChanged: (v) => setState(() => nivelTanque = v)),
        if (_isSaida) ...[
          const SizedBox(height: 10),
          CampoVistoria(
            controller: _destinoController,
            label: 'Destino (opcional)',
            icon: Icons.place_outlined,
            hint: 'Ex.: Lambari / Conceição do Rio Verde',
          ),
          const SizedBox(height: 10),
          CampoVistoria(
            controller: _finalidadeController,
            label: 'Finalidade (opcional)',
            icon: Icons.work_outline,
            hint: 'Ex.: troca de equipamentos de TI',
          ),
        ],
      ],
    );
  }

  // ── Aba Fotos: vistoria com avarias ────────────────────────────────────────

  Widget _abaFotos() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _caixa(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Vistoria do veículo',
                style: TextStyle(color: _C.texto, fontSize: 15, fontWeight: FontWeight.w700)),
            Text('${fotosCapturadas.length}/$_totalFotos fotos',
                style: TextStyle(
                    color: fotosCapturadas.length == _totalFotos ? _C.sucesso : _C.atencao,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          VistoriaFotosGrid(
            fotos: {for (final f in fotosCapturadas) f['label'] as String: f['bytes'] as Uint8List},
            avarias: avarias,
            onTap: _capturarFoto,
          ),
          const SizedBox(height: 10),
          const LegendaAvarias(),
        ],
      ),
    );
  }

  // ── Aba Observações: histórico real do veículo ─────────────────────────────

  Widget _abaObservacoes() {
    Widget corpo;
    if (_carregandoHistorico) {
      corpo = const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: _C.primario)),
      );
    } else if (_obsAnteriores.isEmpty) {
      corpo = const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Row(children: [
          Icon(Icons.inbox_outlined, color: _C.texto2),
          SizedBox(width: 10),
          Expanded(
            child: Text('Nenhuma observação anterior para este veículo.',
                style: TextStyle(color: _C.texto2, fontSize: 13)),
          ),
        ]),
      );
    } else {
      corpo = Column(
        children: _obsAnteriores.map((h) {
          final dt = DateTime.tryParse(h['criado_em']?.toString() ?? h['data']?.toString() ?? '')?.toLocal();
          final quando = dt == null
              ? ''
              : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _C.bg.withOpacity(0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.borda),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${h['tipo'] == 'retorno' ? 'Retorno' : 'Saída'}${quando.isNotEmpty ? ' · $quando' : ''}',
                  style: const TextStyle(color: _C.primario, fontSize: 11.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(h['observacoes'].toString(), style: const TextStyle(color: _C.texto, fontSize: 13)),
            ]),
          );
        }).toList(),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _caixa(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Observações anteriores deste veículo',
            style: TextStyle(color: _C.texto, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        corpo,
      ]),
    );
  }

  // ── Carrossel de veículos reais ────────────────────────────────────────────

  Widget _secaoCarrossel() {
    final podeAdicionar = context.watch<AppAuthProvider>().can(AppPermission.manageVehicles);
    Widget lista;
    if (_carregandoVeiculos) {
      lista = const SizedBox(
        height: 130,
        child: Center(child: CircularProgressIndicator(color: _C.primario)),
      );
    } else if (_erroVeiculos != null) {
      lista = SizedBox(
        height: 130,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_erroVeiculos!, style: const TextStyle(color: _C.texto2)),
            TextButton(onPressed: _carregarVeiculos, child: const Text('Tentar novamente')),
          ]),
        ),
      );
    } else if (_veiculos.isEmpty) {
      lista = const SizedBox(
        height: 80,
        child: Center(child: Text('Nenhum veículo disponível.', style: TextStyle(color: _C.texto2))),
      );
    } else {
      lista = SizedBox(
        height: 132,
        child: Row(children: [
          _setaCarrossel(Icons.chevron_left, () => _rolarCarrossel(-344)),
          Expanded(
            child: ListView.separated(
              controller: _carrosselController,
              scrollDirection: Axis.horizontal,
              itemCount: _veiculos.length + (podeAdicionar ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                if (i == _veiculos.length) return _cardAdicionar();
                return _cardVeiculo(_veiculos[i]);
              },
            ),
          ),
          _setaCarrossel(Icons.chevron_right, () => _rolarCarrossel(344)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _caixa(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.directions_car_outlined, color: _C.texto, size: 20),
          SizedBox(width: 8),
          Text('Veículo', style: TextStyle(color: _C.texto, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        lista,
      ]),
    );
  }

  Widget _setaCarrossel(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: _C.bg,
        shape: const CircleBorder(side: BorderSide(color: _C.borda)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, color: _C.texto, size: 20)),
        ),
      ),
    );
  }

  Widget _fotoVeiculo(Map<String, dynamic>? v, {double iconSize = 36}) {
    final url = v?['foto_url']?.toString();
    final placeholder = Container(
      color: _C.bg,
      child: Center(child: Icon(Icons.directions_car_filled_outlined, color: _C.borda, size: iconSize)),
    );
    if (url == null || url.isEmpty) return placeholder;
    return SignedNetworkImage(
      url: url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
    );
  }

  Widget _cardVeiculo(Map<String, dynamic> v) {
    final selecionado = v['id']?.toString() == _veiculoId;
    final nome = [v['brand'], v['model']].where((e) => (e?.toString() ?? '').isNotEmpty).join(' ');
    return Semantics(
      button: true,
      selected: selecionado,
      label: 'Veículo ${v['plate'] ?? ''}${selecionado ? ', selecionado' : ''}',
      child: GestureDetector(
        onTap: () => _trocarVeiculo(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selecionado ? _C.teal : _C.borda, width: selecionado ? 2.5 : 1),
            boxShadow: selecionado ? [BoxShadow(color: _C.teal.withOpacity(0.25), blurRadius: 12)] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(fit: StackFit.expand, children: [
              _fotoVeiculo(v),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (nome.isNotEmpty)
                      Text(nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _C.texto, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(v['plate']?.toString() ?? '',
                        style: TextStyle(
                            color: selecionado ? _C.teal : _C.texto2, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              if (selecionado)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: _C.teal, borderRadius: BorderRadius.circular(5)),
                    child: const Icon(Icons.check, color: _C.bg, size: 14),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _cardAdicionar() {
    return InkWell(
      onTap: _adicionarVeiculo,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.borda, width: 1.5),
          color: _C.bg.withOpacity(0.4),
        ),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_circle_outline, color: _C.texto2, size: 30),
          SizedBox(height: 8),
          Text('Adicionar veículo', style: TextStyle(color: _C.texto2, fontSize: 12.5)),
        ]),
      ),
    );
  }

  // ── Observações desta vistoria ─────────────────────────────────────────────

  Widget _campoObservacoes() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _caixa(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.edit_note_rounded, color: _C.texto, size: 20),
          SizedBox(width: 8),
          Text('Observações', style: TextStyle(color: _C.texto, fontSize: 15, fontWeight: FontWeight.w700)),
          SizedBox(width: 6),
          Text('(opcional)', style: TextStyle(color: _C.texto2, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _observacoesController,
          maxLines: 3,
          minLines: 2,
          style: const TextStyle(color: _C.texto),
          decoration: InputDecoration(
            hintText: 'Adicione alguma observação sobre o veículo...',
            hintStyle: const TextStyle(color: _C.texto2, fontSize: 13),
            suffixIcon: const Icon(Icons.edit_outlined, color: _C.texto2, size: 18),
            filled: true,
            fillColor: _C.bg.withOpacity(0.6),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _C.borda),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _C.primario, width: 1.5),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Painel lateral: veículo em destaque ────────────────────────────────────

  Widget _painelVeiculo({bool compacto = false}) {
    final v = _veiculoAtual;
    final nome = v == null
        ? ''
        : [v['brand'], v['model']].where((e) => (e?.toString() ?? '').isNotEmpty).join(' ');
    final idx = _veiculos.indexWhere((x) => x['id']?.toString() == _veiculoId);
    final foto = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(aspectRatio: compacto ? 16 / 9 : 4 / 3, child: _fotoVeiculo(v, iconSize: 56)),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _caixa(),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (_veiculos.length > 1) _setaCarrossel(Icons.chevron_left, () => _veiculoVizinho(-1)),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _C.primario.withOpacity(0.5)),
              ),
              child: foto,
            ),
          ),
          if (_veiculos.length > 1) _setaCarrossel(Icons.chevron_right, () => _veiculoVizinho(1)),
        ]),
        const SizedBox(height: 12),
        if (nome.isNotEmpty)
          Text(nome,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _C.texto, fontSize: 19, fontWeight: FontWeight.w700)),
        Text(_placa,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _C.texto2, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1)),
        if (_veiculos.length > 1 && _veiculos.length <= 10) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _veiculos.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == idx ? 9 : 7,
                height: i == idx ? 9 : 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == idx ? _C.primario : _C.borda,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: v == null ? null : _verDetalhes,
          icon: const Icon(Icons.directions_car_outlined, size: 18),
          label: const Text('Ver detalhes do veículo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _C.primario,
            side: const BorderSide(color: _C.primario),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ]),
    );
  }

  Widget _botaoRegistrar() {
    final rotulo = _isSaida ? 'Registrar Checklist de Saída' : 'Registrar Checklist de Retorno';
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: _salvando ? null : const LinearGradient(colors: [_C.teal, _C.primario]),
          color: _salvando ? _C.borda : null,
          boxShadow: _salvando ? null : [BoxShadow(color: _C.teal.withOpacity(0.3), blurRadius: 16)],
        ),
        child: ElevatedButton.icon(
          onPressed: _salvando ? null : _registrar,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: _C.bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: _salvando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.texto))
              : const Icon(Icons.check_circle, size: 22),
          label: Text(_salvando ? 'Enviando fotos e registrando...' : rotulo,
              style: TextStyle(
                  color: _salvando ? _C.texto : _C.bg, fontSize: 15.5, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  BoxDecoration _caixa() => BoxDecoration(
        color: _C.card.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.borda),
      );
}

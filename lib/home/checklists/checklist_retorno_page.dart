import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/models/checklist_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/image_validation.dart';
import 'vistoria_widgets.dart';

class ChecklistRetornoPage extends StatefulWidget {
  final String veiculoId;
  final String veiculoPlaca;
  final String motoristaId;

  const ChecklistRetornoPage({
    required this.veiculoId,
    required this.veiculoPlaca,
    required this.motoristaId,
    super.key,
  });

  @override
  State<ChecklistRetornoPage> createState() => _ChecklistRetornoPageState();
}

class _ChecklistRetornoPageState extends State<ChecklistRetornoPage> {
  final supabase = Supabase.instance.client;
  final imagePicker = ImagePicker();
  final observacoesController = TextEditingController();
  final kmFinalController = TextEditingController();

  late Map<String, bool> itensVerificados;
  final List<Map<String, dynamic>> fotosCapturadas = [];
  // Avarias por posição de foto (ficha de vistoria): {'Frente': {'tipos': ['R'], 'obs': '...'}}
  final Map<String, Map<String, dynamic>> avarias = {};
  String? nivelTanque;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    itensVerificados = {for (var item in Checklist.itensChecklist) item: false};
  }

  @override
  void dispose() {
    observacoesController.dispose();
    kmFinalController.dispose();
    super.dispose();
  }

  int get _totalMarcados =>
      itensVerificados.values.where((v) => v).length;

  int get _totalFotos => Checklist.fotosObrigatorias.length;

  Future<void> _capturarFoto(String label) async {
    if (fotosCapturadas.any((f) => f['label'] == label)) {
      // Já tem foto: marcar avarias, refazer ou remover.
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
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<String?> _uploadComRetry(
      Uint8List bytes, String fileName) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await supabase.storage.from('checklists').uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        return supabase.storage.from('checklists').getPublicUrl(fileName);
      } catch (_) {
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }
    return null;
  }

  Future<void> _salvarChecklist() async {
    final kmFinalTexto = kmFinalController.text.trim();
    if (kmFinalTexto.isEmpty) {
      showError(context, 'Informe o KM final do veículo');
      return;
    }
    final kmFinal = int.tryParse(kmFinalTexto);
    if (kmFinal == null || kmFinal < 0) {
      showError(context, 'Informe um KM final válido (somente números)');
      return;
    }
    if (nivelTanque == null) {
      showError(context, 'Informe o nível do tanque');
      return;
    }

    try {
      final veiculo = await supabase
          .from('vehicles')
          .select('odometer')
          .eq('id', widget.veiculoId)
          .maybeSingle();
      final atual = veiculo?['odometer'] as num?;
      if (atual != null && kmFinal < atual) {
        if (mounted) {
          showError(context, 'KM final menor que o último registrado ($atual km)');
        }
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    if (fotosCapturadas.length < _totalFotos) {
      showError(context,
          'Faltam ${_totalFotos - fotosCapturadas.length} foto(s) obrigatória(s)');
      return;
    }

    setState(() => isLoading = true);
    final auth = context.read<AppAuthProvider>();
    final injetar = auth.inject;
    final pastaEmpresa = auth.effectiveEmpresaId ?? 'sem-empresa';

    try {
      final List<String> fotoUrls = [];
      for (int i = 0; i < fotosCapturadas.length; i++) {
        final Uint8List bytes = fotosCapturadas[i]['bytes'];
        final label = (fotosCapturadas[i]['label'] as String)
            .toLowerCase()
            .replaceAll(' ', '_');
        final fileName =
            '$pastaEmpresa/retorno_${widget.veiculoId}_${label}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final url = await _uploadComRetry(bytes, fileName);
        if (url == null) {
          if (mounted) {
            showError(context,
                'Falha ao enviar foto "${fotosCapturadas[i]['label']}". Tente novamente.');
            setState(() => isLoading = false);
          }
          return;
        }
        fotoUrls.add(url);
      }

      final avariasFinal = avariasParaSalvar(avarias);
      await supabase.from('checklists').insert(injetar({
        'veiculo_id': widget.veiculoId,
        'motorista_id': widget.motoristaId,
        'tipo': 'retorno',
        'data': DateTime.now().toIso8601String().split('T')[0],
        'itens': itensVerificados,
        'foto_urls': fotoUrls,
        // Reprovado se faltou item OU se alguma avaria foi marcada.
        'aprovado': _totalMarcados == Checklist.itensChecklist.length && avariasFinal.isEmpty,
        'km_final': kmFinal,
        'nivel_combustivel': nivelTanque,
        'avarias': avariasFinal,
        if (observacoesController.text.trim().isNotEmpty)
          'observacoes': observacoesController.text.trim(),
      }));

      // Atualiza o odômetro do veículo se este for maior que o registrado
      try {
        await supabase
            .from('vehicles')
            .update({'odometer': kmFinal})
            .eq('id', widget.veiculoId)
            .lt('odometer', kmFinal);
      } catch (_) {}

      if (!mounted) return;
      showSuccess(context, 'Checklist de retorno registrado!');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Retorno · ${widget.veiculoPlaca}'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progresso
            _progressBar(),
            const SizedBox(height: 14),

            // KM Final
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: kmFinalController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'KM Final do Veículo *',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  prefixIcon: Icon(Icons.speed_outlined,
                      color: AppColors.textSecondary, size: 18),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            NivelTanqueSelector(
              valor: nivelTanque,
              onChanged: (v) => setState(() => nivelTanque = v),
            ),
            const SizedBox(height: 14),

            // Itens do checklist
            _sectionTitle('Itens do Checklist',
                '$_totalMarcados/${Checklist.itensChecklist.length}',
                AppColors.secondary),
            const SizedBox(height: 8),
            _checklistGrid(),
            const SizedBox(height: 14),

            // Fotos obrigatórias + avarias
            _sectionTitle('Vistoria do Veículo',
                '${fotosCapturadas.length}/$_totalFotos', AppColors.warning),
            const SizedBox(height: 8),
            _fotosGrid(),
            const SizedBox(height: 8),
            const LegendaAvarias(),
            const SizedBox(height: 14),

            // Observações
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: observacoesController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observações (opcional)',
                  hintText: 'Descreva anomalias encontradas...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  prefixIcon: Icon(Icons.notes_outlined,
                      color: AppColors.textSecondary, size: 18),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Botão salvar
            ElevatedButton(
              onPressed: isLoading ? null : _salvarChecklist,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text('Registrar Checklist de Retorno',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar() {
    final itensPct = Checklist.itensChecklist.isEmpty
        ? 0.0
        : _totalMarcados / Checklist.itensChecklist.length;
    final fotosPct =
        _totalFotos == 0 ? 0.0 : fotosCapturadas.length / _totalFotos;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rtl,
                  color: AppColors.secondary, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Itens verificados',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12))),
              Text('$_totalMarcados/${Checklist.itensChecklist.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: itensPct,
              backgroundColor: AppColors.backgroundSoft,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.secondary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.photo_camera,
                  color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Fotos capturadas',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12))),
              Text('${fotosCapturadas.length}/$_totalFotos',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fotosPct,
              backgroundColor: AppColors.backgroundSoft,
              valueColor: const AlwaysStoppedAnimation(AppColors.warning),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String badge, Color color) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(badge,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _checklistGrid() {
    final items = Checklist.itensChecklist;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: List.generate(items.length * 2 - 1, (i) {
          if (i.isOdd) {
            return const Divider(height: 1, thickness: 1, color: AppColors.border);
          }
          final item = items[i ~/ 2];
          final checked = itensVerificados[item] ?? false;
          final isFirst = i == 0;
          final isLast = i == items.length * 2 - 2;
          return InkWell(
            onTap: () => setState(() => itensVerificados[item] = !checked),
            borderRadius: BorderRadius.only(
              topLeft: isFirst ? const Radius.circular(12) : Radius.zero,
              topRight: isFirst ? const Radius.circular(12) : Radius.zero,
              bottomLeft: isLast ? const Radius.circular(12) : Radius.zero,
              bottomRight: isLast ? const Radius.circular(12) : Radius.zero,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: checked
                          ? AppColors.success
                          : AppColors.backgroundSoft,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: checked ? AppColors.success : AppColors.border),
                    ),
                    child: checked
                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item,
                        style: TextStyle(
                            color: checked
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: checked
                                ? FontWeight.w600
                                : FontWeight.normal)),
                  ),
                  if (checked)
                    const Icon(Icons.check_circle,
                        color: AppColors.success, size: 14),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _fotosGrid() {
    return VistoriaFotosGrid(
      fotos: {
        for (final f in fotosCapturadas) f['label'] as String: f['bytes'] as Uint8List,
      },
      avarias: avarias,
      onTap: _capturarFoto,
    );
  }
}

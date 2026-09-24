import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:frotacheck/core/auth/app_auth_provider.dart';
import 'package:frotacheck/core/enums/app_permission.dart';
import 'package:frotacheck/core/guards/permission_guard.dart';
import 'package:frotacheck/core/theme/app_theme.dart';
import 'package:frotacheck/core/utils/image_validation.dart';
import 'package:frotacheck/core/utils/signed_storage_url.dart';
import 'package:frotacheck/core/utils/snackbar_utils.dart';
import 'package:frotacheck/core/utils/driver_account_link.dart';
import 'motorista_historico_page.dart';

class MotoristasPage extends StatelessWidget {
  const MotoristasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PermissionGuard(
      permission: AppPermission.viewDrivers,
      child: _MotoristasView(),
    );
  }
}

class _MotoristasView extends StatefulWidget {
  const _MotoristasView();

  @override
  State<_MotoristasView> createState() => _MotoristasPageState();
}

class _MotoristasPageState extends State<_MotoristasView> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final searchController = TextEditingController();

  final nomeController = TextEditingController();
  final cnhController = TextEditingController();
  final telefoneController = TextEditingController();
  final categoriaController = TextEditingController();
  final emailContaController = TextEditingController();

  List<Map<String, dynamic>> motoristas = [];
  Map<String, String> _fotosAssinadas = {};
  bool carregando = true;
  bool isSaving = false;
  String? editingId;
  DateTime? cnhValidade;
  String tipoVinculo = 'clt';

  Uint8List? _novaFotoBytes;
  String? _novaFotoExt;
  String? _fotoAtualPreview;
  bool _uploadingFoto = false;

  @override
  void initState() {
    super.initState();
    carregarMotoristas();
  }

  @override
  void dispose() {
    searchController.dispose();
    nomeController.dispose();
    cnhController.dispose();
    telefoneController.dispose();
    categoriaController.dispose();
    emailContaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> carregarMotoristas() async {
    if (!mounted) return;
    setState(() => carregando = true);
    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      var q = supabase.from('drivers').select();
      if (eid != null) q = q.eq('empresa_id', eid);
      final response = await q.order('name');
      if (!mounted) return;
      setState(() {
        motoristas = List<Map<String, dynamic>>.from(
          (response as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        carregando = false;
      });
      unawaited(_resolverFotos());
    } catch (e) {
      debugPrint('Erro motoristas: $e');
      if (mounted) setState(() => carregando = false);
    }
  }

  /// Resolve as URLs assinadas das fotos dos motoristas (bucket privado).
  Future<void> _resolverFotos() async {
    final comFoto = motoristas.where((m) => (m['foto_url'] as String?)?.isNotEmpty == true).toList();
    if (comFoto.isEmpty) return;
    final entradas = await Future.wait(comFoto.map((m) async {
      final signed = await toSignedStorageUrl(m['foto_url'] as String?);
      return MapEntry(m['id'].toString(), signed ?? '');
    }));
    if (!mounted) return;
    setState(() {
      _fotosAssinadas = {for (final e in entradas) if (e.value.isNotEmpty) e.key: e.value};
    });
  }

  Future<void> salvarMotorista() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (cnhValidade == null) {
      _snackErro('Selecione a data de validade da CNH');
      return;
    }
    final hoje = DateTime.now();
    final validadeLimite = DateTime(hoje.year, hoje.month, hoje.day);
    if (editingId == null && cnhValidade!.isBefore(validadeLimite)) {
      _snackErro('A data de validade da CNH não pode ser no passado');
      return;
    }

    // Validar unicidade de CNH antes de salvar (checagem de UX; a garantia real
    // é a constraint UNIQUE(empresa_id, cnh_number) no banco — ver catch do insert/update)
    final cnhNum = cnhController.text.trim();
    if (cnhNum.isNotEmpty) {
      try {
        final eidCheck = context.read<AppAuthProvider>().effectiveEmpresaId;
        var qCnh = supabase.from('drivers').select('id').eq('cnh_number', cnhNum);
        if (eidCheck != null) qCnh = qCnh.eq('empresa_id', eidCheck);
        final existingCnh = await qCnh;
        if (!mounted) return;
        final others = (existingCnh as List)
            .where((m) => m['id']?.toString() != editingId)
            .toList();
        if (others.isNotEmpty) {
          _snackErro('Número de CNH já cadastrado para outro motorista');
          return;
        }
      } catch (_) {}
    }

    // Validar unicidade de email
    final emailConta = emailContaController.text.trim().toLowerCase();
    if (emailConta.isNotEmpty && editingId == null) {
      try {
        final existingEmail = await supabase.from('user_profiles')
            .select('user_id').eq('email', emailConta);
        if (!mounted) return;
        if ((existingEmail as List).isNotEmpty) {
          final withDriver = await supabase.from('user_profiles')
              .select('driver_id').eq('email', emailConta).not('driver_id', 'is', null);
          if (!mounted) return;
          if ((withDriver as List).isNotEmpty) {
            _snackErro('Este e-mail já está vinculado a outro motorista');
            return;
          }
        }
      } catch (_) {}
    }

    setState(() => isSaving = true);

    final payload = <String, dynamic>{
      'name': nomeController.text.trim(),
      'cnh_number': cnhController.text.trim(),
      'cnh_expiration': cnhValidade!.toIso8601String().split('T')[0],
      'tipo_vinculo': tipoVinculo,
    };

    // Campos opcionais — envia null explicitamente no update para permitir limpeza
    final telefone = telefoneController.text.trim();
    final categoria = categoriaController.text.trim().toUpperCase();
    payload['phone'] = telefone.isNotEmpty ? telefone : null;
    payload['cnh_category'] = categoria.isNotEmpty ? categoria : null;
    if (emailConta.isNotEmpty) payload['email'] = emailConta;

    final auth = context.read<AppAuthProvider>();
    String? savedDriverId = editingId;

    try {
      final isNew = editingId == null;
      if (isNew) {
        final result = await supabase
            .from('drivers')
            .insert(auth.inject(payload))
            .select();
        if (!mounted) return;

        String? driverId;
        if (result.isNotEmpty) {
          final novo = Map<String, dynamic>.from(result.first as Map);
          driverId = novo['id']?.toString();
          savedDriverId = driverId;
          setState(() {
            motoristas = [novo, ...motoristas];
            motoristas.sort((a, b) =>
                (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
          });
        }

        // Vínculo automático com conta do motorista pelo e-mail
        if (emailConta.isNotEmpty && driverId != null) {
          try {
            final uId = await _localizarContaMotorista(emailConta, auth.isMaster);
            if (uId != null) {
              await linkUserToDriver(supabase, userId: uId, driverId: driverId);
              _snackSucesso('Motorista cadastrado e vinculado à conta $emailConta!');
            } else {
              _snackSucesso('Motorista cadastrado! Conta "$emailConta" não encontrada ainda — vínculo pendente.');
            }
          } catch (e) {
            _snackErro('Motorista cadastrado, mas a conta não foi vinculada: ${friendlyError(e)}');
          }
        } else {
          _snackSucesso('Motorista cadastrado com sucesso!');
        }
      } else {
        await supabase.from('drivers').update(payload).eq('id', editingId!);
        if (!mounted) return;
        setState(() {
          final idx = motoristas.indexWhere((m) => m['id']?.toString() == editingId);
          if (idx >= 0) {
            motoristas[idx] = {...motoristas[idx], ...payload, 'id': editingId};
          }
        });

        // Ao editar, re-vincular conta se email foi preenchido
        if (emailConta.isNotEmpty) {
          bool vinculoOk = false;
          String? erroVinculo;
          try {
            final uId = await _localizarContaMotorista(emailConta, auth.isMaster);
            if (uId != null) {
              await linkUserToDriver(supabase, userId: uId, driverId: editingId!);
              vinculoOk = true;
            }
          } catch (e) {
            erroVinculo = friendlyError(e);
          }
          if (vinculoOk) {
            _snackSucesso('Motorista atualizado e vinculado à conta $emailConta!');
          } else if (erroVinculo != null) {
            _snackErro('Motorista atualizado, mas a conta não foi vinculada: $erroVinculo');
          } else {
            _snackSucesso('Motorista atualizado! Conta "$emailConta" não encontrada — vínculo pendente.');
          }
        } else {
          _snackSucesso('Motorista atualizado!');
        }
      }

      // Envia a foto (se uma nova foi escolhida) só agora que já temos o id
      // real do motorista — necessário sobretudo para motorista recém-criado.
      if (_novaFotoBytes != null && savedDriverId != null) {
        try {
          setState(() => _uploadingFoto = true);
          final pastaEmpresa = auth.effectiveEmpresaId ?? 'sem-empresa';
          final ext = _novaFotoExt ?? 'jpg';
          final mime = (ext == 'png') ? 'image/png' : 'image/jpeg';
          final path = '$pastaEmpresa/motorista-$savedDriverId.$ext';
          await supabase.storage.from('avatars').uploadBinary(
                path,
                _novaFotoBytes!,
                fileOptions: FileOptions(contentType: mime, upsert: true),
              );
          final rawUrl = supabase.storage.from('avatars').getPublicUrl(path);
          await supabase.from('drivers').update({'foto_url': rawUrl}).eq('id', savedDriverId);
          if (mounted) {
            setState(() {
              final idx = motoristas.indexWhere((m) => m['id']?.toString() == savedDriverId);
              if (idx >= 0) motoristas[idx] = {...motoristas[idx], 'foto_url': rawUrl};
            });
            unawaited(_resolverFotos());
          }
        } catch (_) {
          if (mounted) showError(context, 'Motorista salvo, mas a foto não pôde ser enviada.');
        } finally {
          if (mounted) setState(() => _uploadingFoto = false);
        }
      }

      _limparFormulario();
    } catch (e) {
      if (!mounted) return;
      if (e is PostgrestException && e.code == '23505') {
        _snackErro('Número de CNH já cadastrado para outro motorista');
      } else {
        _snackErro(friendlyError(e));
      }
      debugPrint('ERRO SALVAR MOTORISTA: $e');
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  /// Acha a conta (user_id) do motorista pelo e-mail. Admin/gestor não
  /// enxergam contas ainda pendentes (sem empresa) — a função do banco
  /// vincular_usuario_empresa localiza, vincula à empresa como MOTORISTA e
  /// recusa conta de outra empresa. Devolve null se a conta não existe.
  Future<String?> _localizarContaMotorista(String email, bool isMaster) async {
    if (isMaster) {
      final perfil = await supabase
          .from('user_profiles')
          .select('user_id')
          .eq('email', email)
          .maybeSingle();
      return perfil?['user_id']?.toString();
    }
    try {
      final res = await supabase.rpc('vincular_usuario_empresa', params: {
        'p_email': email,
        'p_role': 'MOTORISTA',
      });
      return res?.toString();
    } on PostgrestException catch (e) {
      if (e.message.contains('CONTA_NAO_ENCONTRADA')) return null;
      rethrow;
    }
  }

  Future<void> excluirMotorista(String id, String nome) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir motorista', style: TextStyle(color: Colors.white)),
        content: Text(
            'Excluir $nome permanentemente?\n\nO histórico (abastecimentos, viagens, checklists, multas) é mantido, mas deixa de aparecer vinculado a este motorista.',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (!mounted || conf != true) return;
    try {
      // Usa RPC SECURITY DEFINER para limpar todas as FKs e excluir (bypassa RLS)
      await supabase.rpc('excluir_motorista_safe', params: {'driver_id_param': id});
      if (!mounted) return;
      setState(() => motoristas.removeWhere((m) => m['id']?.toString() == id));
      _snackSucesso('$nome excluído');
    } catch (e) {
      if (!mounted) return;
      _snackErro(friendlyError(e));
    }
  }

  void editarMotorista(Map<String, dynamic> m) {
    setState(() {
      editingId = m['id']?.toString();
      nomeController.text = m['name']?.toString() ?? '';
      cnhController.text = m['cnh_number']?.toString() ?? '';
      telefoneController.text = m['phone']?.toString() ?? '';
      categoriaController.text = m['cnh_category']?.toString() ?? '';
      emailContaController.text = m['email']?.toString() ?? '';
      final raw = m['cnh_expiration']?.toString() ?? '';
      cnhValidade = DateTime.tryParse(raw);
      tipoVinculo = m['tipo_vinculo']?.toString() ?? 'clt';
      _novaFotoBytes = null;
      _novaFotoExt = null;
      _fotoAtualPreview = _fotosAssinadas[editingId];
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  void _limparFormulario() {
    nomeController.clear();
    cnhController.clear();
    telefoneController.clear();
    categoriaController.clear();
    emailContaController.clear();
    _formKey.currentState?.reset();
    setState(() {
      editingId = null;
      cnhValidade = null;
      tipoVinculo = 'clt';
      _novaFotoBytes = null;
      _novaFotoExt = null;
      _fotoAtualPreview = null;
    });
  }

  Future<void> _pickFoto() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(children: [
          Icon(Icons.add_a_photo_rounded, color: AppColors.secondary, size: 20),
          SizedBox(width: 10),
          Text('Foto do motorista', style: TextStyle(color: Colors.white, fontSize: 15)),
        ]),
        content: const Text('Escolha a origem da foto.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            icon: const Icon(Icons.camera_alt_rounded, size: 16),
            label: const Text('Câmera'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_rounded, size: 16),
            label: const Text('Galeria'),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!isValidImageBytes(bytes)) {
        if (mounted) showError(context, 'Arquivo não é uma imagem válida.');
        return;
      }
      setState(() {
        _novaFotoBytes = bytes;
        _novaFotoExt = picked.name.split('.').last.toLowerCase();
      });
    } catch (_) {
      if (mounted) showError(context, 'Não foi possível abrir a câmera/galeria.');
    }
  }

  void _snackSucesso(String msg) => showSuccess(context, msg);

  void _snackErro(String msg) => showError(context, msg);

  List<Map<String, dynamic>> get _filtrados {
    final q = searchController.text.toLowerCase().trim();
    if (q.isEmpty) return motoristas;
    return motoristas.where((m) {
      return [m['name'], m['cnh_number'], m['phone'], m['email']]
          .whereType<String>()
          .join(' ')
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  int get _vencendoCount {
    final now = DateTime.now();
    final limite = now.add(const Duration(days: 30));
    return motoristas.where((m) {
      final dt = DateTime.tryParse(m['cnh_expiration']?.toString() ?? '');
      return dt != null && !dt.isBefore(now) && dt.isBefore(limite);
    }).length;
  }

  int get _vencidasCount {
    final now = DateTime.now();
    return motoristas.where((m) {
      final dt = DateTime.tryParse(m['cnh_expiration']?.toString() ?? '');
      return dt != null && dt.isBefore(now);
    }).length;
  }

  Future<void> _pickValidade() async {
    final d = await showDatePicker(
      context: context,
      initialDate: cnhValidade ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      helpText: 'Validade da CNH',
    );
    if (d != null) setState(() => cnhValidade = d);
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  Color _cnhColor(String? raw) {
    final dt = DateTime.tryParse(raw ?? '');
    if (dt == null) return AppColors.textSecondary;
    final diff = dt.difference(DateTime.now()).inDays;
    if (diff < 0) return AppColors.danger;
    if (diff <= 30) return AppColors.warning;
    return AppColors.success;
  }

  String _cnhLabel(String? raw) {
    final dt = DateTime.tryParse(raw ?? '');
    if (dt == null) return '';
    final diff = dt.difference(DateTime.now()).inDays;
    if (diff < 0) return 'CNH vencida';
    if (diff <= 30) return 'Vence em $diff dias';
    return 'Válida';
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gestão de Motoristas'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar lista',
            onPressed: carregarMotoristas,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;
          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildStats(),
                const SizedBox(height: 20),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 400, child: _buildForm()),
                      const SizedBox(width: 20),
                      Expanded(child: _buildLista()),
                    ],
                  )
                else ...[
                  _buildForm(),
                  const SizedBox(height: 20),
                  _buildLista(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF00B8D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.people, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Gestão de Motoristas',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${motoristas.length} motorista(s) cadastrado(s)',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        _statCard('Total', '${motoristas.length}', Icons.person, AppColors.secondary),
        const SizedBox(width: 12),
        _statCard('CNH Vencendo', '$_vencendoCount', Icons.warning_amber, AppColors.warning),
        const SizedBox(width: 12),
        _statCard('CNH Válidas', '${motoristas.length - _vencidasCount - _vencendoCount}', Icons.verified, AppColors.success),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Card(
      elevation: 4,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    editingId != null ? Icons.edit_note : Icons.person_add_outlined,
                    color: editingId != null ? AppColors.warning : AppColors.secondary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    editingId != null ? 'Editar Motorista' : 'Cadastrar Motorista',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(child: _campoFoto()),
              const SizedBox(height: 18),
              _campo(
                controller: nomeController,
                label: 'Nome completo *',
                icon: Icons.person_outline,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o nome completo' : null,
              ),
              const SizedBox(height: 12),
              _campo(
                controller: cnhController,
                label: 'Número da CNH *',
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o número da CNH' : null,
              ),
              const SizedBox(height: 12),
              _campo(
                controller: categoriaController,
                label: 'Categoria da CNH (A, B, C...)',
                icon: Icons.category_outlined,
                textCapitalization: TextCapitalization.characters,
                hint: 'Ex: B, AB, C',
              ),
              const SizedBox(height: 12),
              // Seletor de data de validade da CNH
              GestureDetector(
                onTap: _pickValidade,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: cnhValidade == null
                          ? AppColors.border
                          : _cnhColor(cnhValidade!.toIso8601String()),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month,
                        color: cnhValidade == null ? AppColors.textSecondary : AppColors.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cnhValidade != null
                              ? 'Validade da CNH: ${_fmtDate(cnhValidade!.toIso8601String())}'
                              : 'Validade da CNH *  (toque para selecionar)',
                          style: TextStyle(
                            color: cnhValidade != null ? Colors.white : AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Icon(Icons.edit_calendar, color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Vínculo', style: TextStyle(color: AppColors.textSecondary.withOpacity(0.85), fontSize: 12)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'clt', label: Text('CLT'), icon: Icon(Icons.badge_outlined, size: 16)),
                  ButtonSegment(value: 'agregado', label: Text('Agregado'), icon: Icon(Icons.local_shipping_outlined, size: 16)),
                ],
                selected: {tipoVinculo},
                onSelectionChanged: (s) => setState(() => tipoVinculo = s.first),
              ),
              const SizedBox(height: 12),
              _campo(
                controller: telefoneController,
                label: 'Telefone',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                hint: '(11) 99999-9999',
              ),
              const SizedBox(height: 12),
              _campo(
                controller: emailContaController,
                label: 'E-mail da conta do motorista',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                hint: 'Ex: joao@gmail.com',
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Informe o e-mail usado na criação da conta para vincular automaticamente.',
                  style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 11),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: (isSaving || _uploadingFoto) ? null : salvarMotorista,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: editingId != null ? AppColors.warning : AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.border,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                  icon: (isSaving || _uploadingFoto)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Icon(editingId != null ? Icons.save : Icons.person_add, size: 20),
                  label: Text(
                    _uploadingFoto
                        ? 'Enviando foto...'
                        : (isSaving ? 'Salvando...' : (editingId != null ? 'ATUALIZAR MOTORISTA' : 'CADASTRAR MOTORISTA')),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (editingId != null)
                OutlinedButton.icon(
                  onPressed: _limparFormulario,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cancelar edição'),
                )
              else
                TextButton.icon(
                  onPressed: _limparFormulario,
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Limpar campos'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campoFoto() {
    final temNovaFoto = _novaFotoBytes != null;
    final temFotoAtual = _fotoAtualPreview != null;
    return GestureDetector(
      onTap: isSaving ? null : _pickFoto,
      child: Stack(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.backgroundSoft,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: temNovaFoto
                ? Image.memory(_novaFotoBytes!, fit: BoxFit.cover)
                : temFotoAtual
                    ? Image.network(_fotoAtualPreview!, fit: BoxFit.cover)
                    : const Icon(Icons.person, size: 40, color: AppColors.textSecondary),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.secondary),
        ),
        filled: true,
        fillColor: AppColors.backgroundSoft,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        errorStyle: const TextStyle(fontSize: 11),
      ),
      validator: validator,
    );
  }

  Widget _buildLista() {
    final filtrados = _filtrados;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Motoristas Cadastrados',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (!carregando)
              Text('${filtrados.length} de ${motoristas.length}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Buscar por nome ou número da CNH...',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (carregando)
          const Center(
            child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
          )
        else if (filtrados.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(Icons.people_outline, size: 48,
                    color: AppColors.textSecondary.withOpacity(0.5)),
                const SizedBox(height: 12),
                Text(
                  searchController.text.isNotEmpty
                      ? 'Nenhum motorista encontrado para "${searchController.text}"'
                      : 'Nenhum motorista cadastrado ainda',
                  style: const TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtrados.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildCard(filtrados[i]),
          ),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> m) {
    final nome = m['name']?.toString() ?? 'Sem nome';
    final cnhExp = m['cnh_expiration']?.toString();
    final cnhStatus = _cnhLabel(cnhExp);
    final cnhColor = _cnhColor(cnhExp);
    final isEditing = editingId == m['id']?.toString();
    final isAgregado = m['tipo_vinculo']?.toString() == 'agregado';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MotoristaHistoricoPage(motorista: m)),
      ),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isEditing ? AppColors.warning.withOpacity(0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEditing ? AppColors.warning : AppColors.border,
          width: isEditing ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.secondary.withOpacity(0.18),
            backgroundImage: _fotosAssinadas[m['id']?.toString()] != null
                ? NetworkImage(_fotosAssinadas[m['id']?.toString()]!)
                : null,
            child: _fotosAssinadas[m['id']?.toString()] == null
                ? Text(
                    _initials(nome),
                    style: const TextStyle(
                        color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(nome,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (isAgregado) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Agregado',
                            style: TextStyle(color: AppColors.secondary, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'CNH: ${m['cnh_number'] ?? '-'}  ${m['cnh_category'] != null ? '• Cat. ${m['cnh_category']}' : ''}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                Text(
                  'Validade: ${_fmtDate(cnhExp)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                if (m['phone'] != null && m['phone'].toString().isNotEmpty)
                  Text(
                    'Tel: ${m['phone']}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                if (m['email'] != null && m['email'].toString().isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.link, size: 11, color: AppColors.success),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          m['email'].toString(),
                          style: const TextStyle(color: AppColors.success, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                if (cnhStatus.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cnhColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(cnhStatus,
                        style: TextStyle(
                            color: cnhColor, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: AppColors.secondary, size: 20),
                onPressed: () => editarMotorista(m),
                tooltip: 'Editar',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                onPressed: () {
                  final id = m['id']?.toString();
                  if (id != null) excluirMotorista(id, nome);
                },
                tooltip: 'Excluir',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

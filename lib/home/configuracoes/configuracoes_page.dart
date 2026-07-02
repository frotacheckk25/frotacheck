import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_role.dart';

// ─── Colors ──────────────────────────────────────────────────────────────────
const _bg      = Color(0xFF080F1E);
const _surface = Color(0xFF0A1628);
const _card2   = Color(0xFF0F1C30);
const _border = Color(0xFF1E293B);
const _blue   = Color(0xFF3B82F6);
const _green  = Color(0xFF22C55E);
const _red    = Color(0xFFEF4444);
const _muted  = Color(0xFF64748B);
const _sub    = Color(0xFF94A3B8);
const _white  = Colors.white;

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _supabase = Supabase.instance.client;

  // ── Empresa ────────────────────────────────────────────────────────────────
  final _nomeCtrl      = TextEditingController();
  final _cnpjCtrl      = TextEditingController();
  final _telefoneCtrl  = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _emailRelCtrl  = TextEditingController();
  final _enderecoCtrl  = TextEditingController();

  // ── Perfil pessoal ────────────────────────────────────────────────────────
  final _perfilNomeCtrl  = TextEditingController();
  final _perfilFoneCtrl  = TextEditingController();

  // ── Segurança ─────────────────────────────────────────────────────────────
  final _senhaAtualCtrl  = TextEditingController();
  final _novaSenhaCtrl   = TextEditingController();
  final _confirmarCtrl   = TextEditingController();
  bool _showNovaSenha    = false;
  bool _showConfirmar    = false;

  // ── Notificações/Integrações ──────────────────────────────────────────────
  bool _auditoriaAtiva   = true;
  bool _alertaGasto      = true;
  bool _alertasPush      = true;
  bool _apiIntegration   = false;

  String? _empresaId;
  String? _settingsId;
  bool    _loadingPage   = true;
  bool    _savingEmpresa = false;
  bool    _savingPerfil  = false;
  bool    _savingSenha   = false;
  String? _error;

  // ── Usuários ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _usuarios  = [];
  bool _loadingUsuarios = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging && _tab.index == 1 && _usuarios.isEmpty) {
        _carregarUsuarios();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _tab.dispose();
    _nomeCtrl.dispose();     _cnpjCtrl.dispose();    _telefoneCtrl.dispose();
    _emailCtrl.dispose();    _emailRelCtrl.dispose(); _enderecoCtrl.dispose();
    _perfilNomeCtrl.dispose(); _perfilFoneCtrl.dispose();
    _senhaAtualCtrl.dispose(); _novaSenhaCtrl.dispose(); _confirmarCtrl.dispose();
    super.dispose();
  }

  // ── Init: resolve empresa_id e carrega dados ──────────────────────────────
  Future<void> _init() async {
    final auth = context.read<AppAuthProvider>();
    _empresaId = auth.effectiveEmpresaId ?? auth.empresaId;

    // Preenche perfil pessoal do usuário logado
    _perfilNomeCtrl.text = auth.profile?.nome ?? '';

    if (_empresaId == null) {
      setState(() { _loadingPage = false; _error = 'Nenhuma empresa vinculada a esta conta.'; });
      return;
    }

    setState(() { _loadingPage = true; _error = null; });
    try {
      // 1. Dados da empresa (tabela empresas)
      final empresa = await _supabase
          .from('empresas')
          .select()
          .eq('id', _empresaId!)
          .maybeSingle();

      if (empresa != null) {
        _nomeCtrl.text     = empresa['nome']?.toString()         ?? '';
        _cnpjCtrl.text     = empresa['cnpj']?.toString()         ?? '';
        _emailCtrl.text    = empresa['email']?.toString()        ?? '';
        _telefoneCtrl.text = empresa['telefone']?.toString()
            ?? empresa['phone']?.toString()                       ?? '';
        _emailRelCtrl.text = empresa['report_email']?.toString() ?? '';
        _enderecoCtrl.text = empresa['endereco']?.toString()
            ?? empresa['address']?.toString()                     ?? '';
      }

      // 2. Configurações extras (tabela company_settings, filtrada por empresa_id)
      try {
        final settings = await _supabase
            .from('company_settings')
            .select()
            .eq('empresa_id', _empresaId!)
            .maybeSingle();
        if (settings != null) {
          _settingsId     = settings['id']?.toString();
          _auditoriaAtiva = settings['auditoria_ativa'] as bool? ?? true;
          _alertaGasto    = settings['alerta_gasto']    as bool? ?? true;
          _alertasPush    = settings['alertas_push']    as bool? ?? true;
          _apiIntegration = settings['api_integration'] as bool? ?? false;
          // Complementa campos que podem estar em company_settings
          if (_telefoneCtrl.text.isEmpty) {
            _telefoneCtrl.text = settings['phone']?.toString() ?? '';
          }
          if (_emailRelCtrl.text.isEmpty) {
            _emailRelCtrl.text = settings['report_email']?.toString() ?? '';
          }
        }
      } catch (_) {/* company_settings pode não ter empresa_id — ignora */}

      if (mounted) setState(() => _loadingPage = false);
      _carregarUsuarios();
    } catch (e) {
      if (mounted) setState(() { _loadingPage = false; _error = e.toString(); });
    }
  }

  Future<void> _carregarUsuarios() async {
    if (_empresaId == null) return;
    setState(() => _loadingUsuarios = true);
    try {
      final res = await _supabase
          .from('user_profiles')
          .select()
          .eq('empresa_id', _empresaId!)
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() {
          _usuarios = (res as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loadingUsuarios = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUsuarios = false);
    }
  }

  // ── Salvar empresa ────────────────────────────────────────────────────────
  Future<void> _salvarEmpresa() async {
    if (_empresaId == null) return;
    setState(() => _savingEmpresa = true);
    try {
      // Campos garantidos na tabela empresas
      final empresaPayload = <String, dynamic>{
        'nome'  : _nomeCtrl.text.trim(),
        'cnpj'  : _cnpjCtrl.text.trim(),
        'email' : _emailCtrl.text.trim(),
      };
      // Tenta incluir colunas opcionais (ignora se não existir)
      final extraEmpresa = <String, dynamic>{
        'telefone'    : _telefoneCtrl.text.trim(),
        'report_email': _emailRelCtrl.text.trim(),
        'endereco'    : _enderecoCtrl.text.trim(),
      };
      try {
        await _supabase
            .from('empresas')
            .update({...empresaPayload, ...extraEmpresa})
            .eq('id', _empresaId!);
      } catch (_) {
        // Fallback: apenas campos básicos
        await _supabase
            .from('empresas')
            .update(empresaPayload)
            .eq('id', _empresaId!);
      }

      // Upsert configurações extras com empresa_id
      try {
        final sp = <String, dynamic>{
          'empresa_id'    : _empresaId,
          'phone'         : _telefoneCtrl.text.trim(),
          'report_email'  : _emailRelCtrl.text.trim(),
          'auditoria_ativa': _auditoriaAtiva,
          'alerta_gasto'  : _alertaGasto,
          'alertas_push'  : _alertasPush,
          'api_integration': _apiIntegration,
        };
        if (_settingsId != null) {
          await _supabase
              .from('company_settings')
              .update(sp)
              .eq('id', _settingsId!);
        } else {
          final ins = await _supabase
              .from('company_settings')
              .insert(sp)
              .select('id')
              .maybeSingle();
          if (ins != null && mounted) {
            setState(() => _settingsId = ins['id']?.toString());
          }
        }
      } catch (_) {/* Tabela pode não ter empresa_id — ignora */}

      _snack('Dados da empresa salvos com sucesso!', ok: true);
    } catch (e) {
      _snack('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _savingEmpresa = false);
    }
  }

  // ── Salvar perfil pessoal ─────────────────────────────────────────────────
  Future<void> _salvarPerfil() async {
    final auth = context.read<AppAuthProvider>();
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _savingPerfil = true);
    try {
      final payload = <String, dynamic>{'nome': _perfilNomeCtrl.text.trim()};
      if (_perfilFoneCtrl.text.trim().isNotEmpty) {
        payload['phone'] = _perfilFoneCtrl.text.trim();
      }
      await _supabase.from('user_profiles').update(payload).eq('user_id', uid);
      await auth.reload();
      _snack('Perfil atualizado!', ok: true);
    } catch (e) {
      _snack('Erro ao salvar perfil: $e');
    } finally {
      if (mounted) setState(() => _savingPerfil = false);
    }
  }

  // ── Alterar senha ─────────────────────────────────────────────────────────
  Future<void> _alterarSenha() async {
    final nova = _novaSenhaCtrl.text;
    final confirmar = _confirmarCtrl.text;
    if (nova.length < 6) { _snack('Senha deve ter pelo menos 6 caracteres'); return; }
    if (nova != confirmar) { _snack('As senhas não coincidem'); return; }
    setState(() => _savingSenha = true);
    try {
      await _supabase.auth.updateUser(UserAttributes(password: nova));
      _novaSenhaCtrl.clear();
      _senhaAtualCtrl.clear();
      _confirmarCtrl.clear();
      _snack('Senha alterada com sucesso!', ok: true);
    } catch (e) {
      _snack('Erro ao alterar senha: $e');
    } finally {
      if (mounted) setState(() => _savingSenha = false);
    }
  }

  // ── Alterar role de usuário ───────────────────────────────────────────────
  Future<void> _alterarRole(String userId, String novoRole) async {
    try {
      await _supabase
          .from('user_profiles')
          .update({'role': novoRole})
          .eq('user_id', userId);
      await _carregarUsuarios();
      _snack('Papel atualizado!', ok: true);
    } catch (e) {
      _snack('Erro: $e');
    }
  }

  Future<void> _alterarStatus(String userId, String novoStatus) async {
    try {
      await _supabase
          .from('user_profiles')
          .update({'status': novoStatus})
          .eq('user_id', userId);
      await _carregarUsuarios();
    } catch (e) {
      _snack('Erro: $e');
    }
  }

  void _snack(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? _green : _red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loadingPage) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _blue)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: _appBar(),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.report_problem_rounded, color: _red, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: _sub)),
          ]),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildEmpresa(),
          _buildUsuarios(),
          _buildSeguranca(),
          _buildNotificacoes(),
          _buildAparencia(),
          _buildIntegracoes(),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
    backgroundColor: _surface,
    elevation: 0,
    title: const Text('Configurações',
        style: TextStyle(color: _white, fontWeight: FontWeight.w700, fontSize: 16)),
    iconTheme: const IconThemeData(color: _white),
    bottom: TabBar(
      controller: _tab,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: _blue,
      indicatorWeight: 2,
      labelColor: _blue,
      unselectedLabelColor: _muted,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      tabs: const [
        Tab(text: 'Empresa'),
        Tab(text: 'Usuários'),
        Tab(text: 'Segurança'),
        Tab(text: 'Notificações'),
        Tab(text: 'Aparência'),
        Tab(text: 'Integrações'),
      ],
    ),
  );

  // ── Tab: Empresa ──────────────────────────────────────────────────────────
  Widget _buildEmpresa() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Dados da Empresa'),
        const SizedBox(height: 4),
        Text(
          'Estas informações ficam vinculadas exclusivamente à sua empresa.',
          style: const TextStyle(color: _sub, fontSize: 12),
        ),
        const SizedBox(height: 20),
        _card(Column(children: [
          _field('Nome da empresa', _nomeCtrl, hint: 'FrotaCheck Transportes LTDA'),
          _divider(),
          _field('CNPJ', _cnpjCtrl, hint: '00.000.000/0001-00'),
          _divider(),
          _field('Telefone', _telefoneCtrl, hint: '(11) 99999-9999', type: TextInputType.phone),
          _divider(),
          _field('E-mail de contato', _emailCtrl, hint: 'contato@empresa.com.br', type: TextInputType.emailAddress),
          _divider(),
          _field('E-mail para relatórios', _emailRelCtrl, hint: 'relatorios@empresa.com.br', type: TextInputType.emailAddress),
          _divider(),
          _field('Endereço', _enderecoCtrl, hint: 'Rua, número, cidade – UF'),
        ])),
        const SizedBox(height: 20),
        _saveBtn(
          label: 'Salvar Dados da Empresa',
          saving: _savingEmpresa,
          onTap: _salvarEmpresa,
          color: _blue,
        ),
      ]),
    );
  }

  // ── Tab: Usuários ─────────────────────────────────────────────────────────
  Widget _buildUsuarios() {
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        color: _surface,
        child: Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Usuários da Empresa',
                  style: TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w700)),
              Text('Gerencie acessos, papéis e status dos membros.',
                  style: TextStyle(color: _sub, fontSize: 11)),
            ]),
          ),
          TextButton(
            onPressed: _carregarUsuarios,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            child: const Text('Atualizar', style: TextStyle(color: _blue, fontSize: 12)),
          ),
        ]),
      ),
      Expanded(
        child: _loadingUsuarios
            ? const Center(child: CircularProgressIndicator(color: _blue))
            : _usuarios.isEmpty
                ? const Center(
                    child: Text('Nenhum usuário encontrado.',
                        style: TextStyle(color: _sub, fontSize: 14)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _usuarios.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _usuarioCard(_usuarios[i]),
                  ),
      ),
    ]);
  }

  Widget _usuarioCard(Map<String, dynamic> u) {
    final nome   = u['nome']?.toString() ?? u['email']?.toString() ?? '—';
    final email  = u['email']?.toString() ?? '';
    final role   = u['role']?.toString() ?? 'MOTORISTA';
    final status = u['status']?.toString() ?? 'ativo';
    final isAtivo = status == 'ativo';

    Color roleColor;
    String roleLabel;
    switch (role.toUpperCase()) {
      case 'ADMIN_EMPRESA': roleColor = _blue;  roleLabel = 'Admin'; break;
      case 'GESTOR':        roleColor = const Color(0xFF8B5CF6); roleLabel = 'Gestor'; break;
      case 'MOTORISTA':     roleColor = _green; roleLabel = 'Motorista'; break;
      default:              roleColor = _muted; roleLabel = role;
    }

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: roleColor.withOpacity(0.15),
          child: Text(
            nome.isNotEmpty ? nome[0].toUpperCase() : '?',
            style: TextStyle(color: roleColor, fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nome, style: const TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w600)),
            if (email.isNotEmpty)
              Text(email, style: const TextStyle(color: _sub, fontSize: 11)),
          ]),
        ),
        // Role badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: roleColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: roleColor.withOpacity(0.3)),
          ),
          child: Text(roleLabel, style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        // Status toggle
        GestureDetector(
          onTap: () => _alterarStatus(
            u['user_id'].toString(),
            isAtivo ? 'inativo' : 'ativo',
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isAtivo ? _green : _red).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isAtivo ? 'Ativo' : 'Inativo',
              style: TextStyle(
                color: isAtivo ? _green : _red,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Role change popup
        PopupMenuButton<String>(
          icon: const Icon(Icons.settings_rounded, color: _muted, size: 18),
          color: _card2,
          onSelected: (val) => _alterarRole(u['user_id'].toString(), val),
          itemBuilder: (_) => [
            _popupItem('ADMIN_EMPRESA', 'Tornar Admin', _blue),
            _popupItem('GESTOR',        'Tornar Gestor', const Color(0xFF8B5CF6)),
            _popupItem('MOTORISTA',     'Tornar Motorista', _green),
          ],
        ),
      ]),
    );
  }

  PopupMenuItem<String> _popupItem(String value, String label, Color color) =>
      PopupMenuItem(
        value: value,
        child: Text(label, style: TextStyle(color: color, fontSize: 13)),
      );

  // ── Tab: Segurança ────────────────────────────────────────────────────────
  Widget _buildSeguranca() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Alterar Senha'),
        const SizedBox(height: 4),
        const Text('Defina uma nova senha para sua conta.', style: TextStyle(color: _sub, fontSize: 12)),
        const SizedBox(height: 20),
        _card(Column(children: [
          _senhaField('Nova senha', _novaSenhaCtrl, _showNovaSenha,
              () => setState(() => _showNovaSenha = !_showNovaSenha)),
          _divider(),
          _senhaField('Confirmar nova senha', _confirmarCtrl, _showConfirmar,
              () => setState(() => _showConfirmar = !_showConfirmar)),
        ])),
        const SizedBox(height: 16),
        _saveBtn(label: 'Alterar Senha', saving: _savingSenha, onTap: _alterarSenha, color: _blue),

        const SizedBox(height: 32),
        _sectionTitle('Sessão'),
        const SizedBox(height: 12),
        _card(ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: _red.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.report_problem_rounded, color: _red, size: 18),
          ),
          title: const Text('Finalizar Sessão', style: TextStyle(color: _red, fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: const Text('Sair da conta e voltar à tela de login.', style: TextStyle(color: _sub, fontSize: 12)),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: _surface,
                title: const Text('Finalizar sessão?', style: TextStyle(color: _white)),
                content: const Text('Deseja realmente sair da sua conta?', style: TextStyle(color: _sub)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: _muted))),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sair', style: TextStyle(color: _red)),
                  ),
                ],
              ),
            );
            if (ok == true && mounted) {
              await context.read<AppAuthProvider>().signOut();
            }
          },
        )),
      ]),
    );
  }

  // ── Tab: Notificações ─────────────────────────────────────────────────────
  Widget _buildNotificacoes() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Alertas e Notificações'),
        const SizedBox(height: 16),
        _card(Column(children: [
          _switchItem('Auditoria de combustível',
              'Verificações automáticas de política de gasto.',
              _auditoriaAtiva,
              (v) => setState(() => _auditoriaAtiva = v)),
          _divider(),
          _switchItem('Alertas de gasto',
              'Notifica quando consumo ultrapassar limites.',
              _alertaGasto,
              (v) => setState(() => _alertaGasto = v)),
          _divider(),
          _switchItem('Notificações em tempo real',
              'Receba avisos e alertas instantâneos.',
              _alertasPush,
              (v) => setState(() => _alertasPush = v)),
        ])),
        const SizedBox(height: 20),
        _saveBtn(
          label: 'Salvar Notificações',
          saving: _savingEmpresa,
          onTap: _salvarEmpresa,
          color: _blue,
        ),
      ]),
    );
  }

  // ── Tab: Aparência ─────────────────────────────────────────────────────────
  Widget _buildAparencia() {
    final auth = context.watch<AppAuthProvider>();
    final email = _supabase.auth.currentUser?.email ?? '';
    final nome  = auth.profile?.nome ?? '';
    final role  = auth.role;

    String roleLabel = 'Usuário';
    Color  roleColor = _muted;
    if (role == AppRole.master)       { roleLabel = 'Master'; roleColor = const Color(0xFFEAB308); }
    else if (role == AppRole.adminEmpresa) { roleLabel = 'Admin';  roleColor = _blue; }
    else if (role == AppRole.gestor)  { roleLabel = 'Gestor'; roleColor = const Color(0xFF8B5CF6); }
    else if (role == AppRole.motorista){ roleLabel = 'Motorista'; roleColor = _green; }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Avatar + info
        _card(Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: roleColor.withOpacity(0.15),
              child: Text(
                nome.isNotEmpty ? nome[0].toUpperCase() : email.isNotEmpty ? email[0].toUpperCase() : '?',
                style: TextStyle(color: roleColor, fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nome.isNotEmpty ? nome : 'Sem nome',
                    style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
                Text(email, style: const TextStyle(color: _sub, fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: roleColor.withOpacity(0.3)),
                  ),
                  child: Text(roleLabel, style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ]),
        )),

        const SizedBox(height: 24),
        _sectionTitle('Meu Perfil'),
        const SizedBox(height: 4),
        const Text('Atualize seus dados pessoais.', style: TextStyle(color: _sub, fontSize: 12)),
        const SizedBox(height: 16),
        _card(Column(children: [
          _field('Nome completo', _perfilNomeCtrl, hint: 'Seu nome'),
          _divider(),
          _field('Telefone pessoal', _perfilFoneCtrl, hint: '(11) 99999-9999', type: TextInputType.phone),
          _divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('E-mail da conta', style: TextStyle(color: _sub, fontSize: 12, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Para alterar o e-mail, entre em contato com o suporte.',
                      style: TextStyle(color: _muted, fontSize: 11)),
                ]),
              ),
              Text(email, style: const TextStyle(color: _white, fontSize: 13)),
            ]),
          ),
        ])),
        const SizedBox(height: 16),
        _saveBtn(label: 'Salvar Perfil', saving: _savingPerfil, onTap: _salvarPerfil, color: _green),
      ]),
    );
  }

  // ── Tab: Integrações ──────────────────────────────────────────────────────
  Widget _buildIntegracoes() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Integrações Externas'),
        const SizedBox(height: 16),
        _card(Column(children: [
          _switchItem('Integração com ERPs',
              'Habilite conexões externas e exportações.',
              _apiIntegration,
              (v) => setState(() => _apiIntegration = v)),
          _divider(),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const Icon(Icons.settings_rounded, color: _blue, size: 20),
            title: const Text('API externa', style: TextStyle(color: _white, fontSize: 14)),
            subtitle: const Text('Configure webhooks e integrações via API.', style: TextStyle(color: _sub, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: _muted, size: 18),
            onTap: () => _snack('API externa — em breve.'),
          ),
        ])),
        const SizedBox(height: 20),
        _saveBtn(label: 'Salvar Integrações', saving: _savingEmpresa, onTap: _salvarEmpresa, color: _blue),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Widgets auxiliares
  // ════════════════════════════════════════════════════════════════════════════

  Widget _sectionTitle(String t) =>
      Text(t, style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700));

  Widget _card(Widget child) => Container(
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: child,
  );

  Widget _divider() => const Divider(height: 1, color: _border, indent: 16, endIndent: 16);

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, TextInputType? type}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: _sub, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: type,
            style: const TextStyle(color: _white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _muted, fontSize: 13),
              filled: true,
              fillColor: _card2,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _blue)),
            ),
          ),
        ]),
      );

  Widget _senhaField(String label, TextEditingController ctrl, bool visible, VoidCallback toggle) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _sub, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            obscureText: !visible,
            style: const TextStyle(color: _white, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: _card2,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _blue)),
              suffixIcon: IconButton(
                icon: Icon(visible ? Icons.settings_rounded : Icons.build_rounded, color: _muted, size: 18),
                onPressed: toggle,
              ),
            ),
          ),
        ]),
      );

  Widget _switchItem(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: SwitchListTile(
          value: value,
          title: Text(title, style: const TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(subtitle, style: const TextStyle(color: _sub, fontSize: 12)),
          onChanged: onChanged,
          activeColor: _blue,
        ),
      );

  Widget _saveBtn({
    required String label,
    required bool saving,
    required VoidCallback onTap,
    required Color color,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: saving ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: _white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _white))
              : Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  bool isSaving = false;

  SupabaseClient? _supabaseClient;
  SupabaseClient? get supabaseClient => _supabaseClient;

  void _ensureSupabaseClient() {
    try {
      _supabaseClient = Supabase.instance.client;
    } catch (e) {
      debugPrint('Supabase client capture error: $e');
      _supabaseClient = null;
    }
  }

  final empresaController = TextEditingController();
  final cnpjController = TextEditingController();
  final telefoneController = TextEditingController();
  final emailController = TextEditingController();
  final reportEmailController = TextEditingController();

  String? registroId;
  bool alertaGasto = true;
  bool apiIntegration = false;
  bool alertasPush = true;
  bool auditoriaAtiva = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    carregarDados();
  }

  @override
  void dispose() {
    _tabController.dispose();
    empresaController.dispose();
    cnpjController.dispose();
    telefoneController.dispose();
    emailController.dispose();
    reportEmailController.dispose();
    super.dispose();
  }

  Future<void> carregarDados() async {
    try {
      _ensureSupabaseClient();
      final client = supabaseClient;
      if (client == null) {
        debugPrint('Supabase client não está pronto.');
        return;
      }

      final dados = await client.from('company_settings').select().limit(1);

      if (dados.isNotEmpty) {
        final empresa = dados.first;
        setState(() {
          registroId = empresa['id']?.toString();
          empresaController.text = empresa['company_name'] ?? '';
          cnpjController.text = empresa['cnpj'] ?? '';
          telefoneController.text = empresa['phone'] ?? '';
          emailController.text = empresa['email'] ?? '';
          reportEmailController.text = empresa['report_email'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados: $e');
    }
  }

  Future<void> salvarConfiguracoes() async {
    if (_formKey.currentState?.validate() != true) return;

    _ensureSupabaseClient();
    final client = supabaseClient;
    if (client == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro: serviço não disponível. Tente novamente.'),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final payload = {
        'company_name': empresaController.text.trim(),
        'cnpj': cnpjController.text.trim(),
        'phone': telefoneController.text.trim(),
        'email': emailController.text.trim(),
        'report_email': reportEmailController.text.trim(),
      };

      if (registroId == null) {
        final result =
            await client.from('company_settings').insert(payload).select();
        if (result.isNotEmpty) {
          setState(() {
            registroId = result.first['id']?.toString();
          });
        }
      } else {
        await client
            .from('company_settings')
            .update(payload)
            .eq('id', registroId!);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.business_outlined), text: 'Empresa'),
            Tab(icon: Icon(Icons.people_outline), text: 'Usuários'),
            Tab(icon: Icon(Icons.lock_outline), text: 'Segurança'),
            Tab(icon: Icon(Icons.notifications_outlined), text: 'Notificações'),
            Tab(icon: Icon(Icons.palette_outlined), text: 'Aparência'),
            Tab(
              icon: Icon(Icons.integration_instructions_outlined),
              text: 'Integrações',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDadosEmpresa(),
          _buildUsuarios(),
          _buildSeguranca(colorScheme),
          _buildNotificacoes(colorScheme),
          _buildAparencia(),
          _buildIntegracoes(colorScheme),
        ],
      ),
    );
  }

  Widget _buildDadosEmpresa() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Dados da Empresa',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: empresaController,
                  decoration:
                      const InputDecoration(labelText: 'Nome da Empresa'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o nome da empresa'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: cnpjController,
                  decoration: const InputDecoration(labelText: 'CNPJ'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o CNPJ'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: telefoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefone'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o telefone'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Informe o e-mail';
                    if (!v.contains('@')) return 'Digite um e-mail válido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: reportEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration:
                      const InputDecoration(labelText: 'E-mail para relatórios'),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: isSaving ? null : salvarConfiguracoes,
                    icon: const Icon(Icons.save),
                    label: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Salvar Configurações'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUsuarios() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Gestão de Usuários',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Em breve: adicione, edite e controle acessos.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildSeguranca(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          children: [
            ListTile(
              leading:
                  Icon(Icons.manage_accounts_outlined, color: colorScheme.primary),
              title: const Text('Gestão de acessos'),
              subtitle: const Text('Controle perfis, permissões e logins.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Gestão de acessos — em breve.')),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading:
                  Icon(Icons.cloud_upload_outlined, color: colorScheme.primary),
              title: const Text('Backup e exportação'),
              subtitle:
                  const Text('Baixe configurações ou exporte relatórios.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Backup e exportação — em breve.')),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: Icon(Icons.key_outlined, color: colorScheme.primary),
              title: const Text('Alterar senha'),
              subtitle: const Text('Redefina a senha da conta.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Alterar senha — em breve.')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificacoes(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          children: [
            SwitchListTile(
              value: auditoriaAtiva,
              title: const Text('Auditoria de combustível'),
              subtitle:
                  const Text('Ativa verificações automáticas de política.'),
              onChanged: (v) => setState(() => auditoriaAtiva = v),
              activeColor: colorScheme.primary,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              value: alertaGasto,
              title: const Text('Alertas de gasto'),
              subtitle:
                  const Text('Notifique quando o consumo ultrapassar limites.'),
              onChanged: (v) => setState(() => alertaGasto = v),
              activeColor: colorScheme.primary,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              value: alertasPush,
              title: const Text('Notificações em tempo real'),
              subtitle: const Text('Receba avisos e alertas no app.'),
              onChanged: (v) => setState(() => alertasPush = v),
              activeColor: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAparencia() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.palette_outlined, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Aparência',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Em breve: temas, cores e personalização.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildIntegracoes(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          children: [
            SwitchListTile(
              value: apiIntegration,
              title: const Text('Integração com ERPs'),
              subtitle:
                  const Text('Habilite conexões externas e exportações.'),
              onChanged: (v) => setState(() => apiIntegration = v),
              activeColor: colorScheme.primary,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading:
                  Icon(Icons.api_outlined, color: colorScheme.primary),
              title: const Text('API externa'),
              subtitle: const Text('Configure webhooks e integrações via API.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('API externa — em breve.')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

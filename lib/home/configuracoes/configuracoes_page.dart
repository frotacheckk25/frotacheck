import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final _formKey = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;
  bool isSaving = false;

  final empresaController = TextEditingController();
  final cnpjController = TextEditingController();
  final telefoneController = TextEditingController();
  final emailController = TextEditingController();
  final timezoneController = TextEditingController();
  final reportEmailController = TextEditingController();

  String? registroId;
  bool alertaGasto = true;
  bool apiIntegration = false;
  bool alertasPush = true;
  bool auditoriaAtiva = true;

  @override
  void initState() {
    super.initState();
    carregarDados();
  }

  Future<void> carregarDados() async {
    try {
      final dados = await supabase.from('company_settings').select().limit(1);

      if (dados.isNotEmpty) {
        final empresa = dados.first;

        registroId = empresa['id'];
        empresaController.text = empresa['company_name'] ?? '';
        cnpjController.text = empresa['cnpj'] ?? '';
        telefoneController.text = empresa['phone'] ?? '';
        emailController.text = empresa['email'] ?? '';
        timezoneController.text = empresa['timezone'] ?? 'America/Sao_Paulo';
        reportEmailController.text = empresa['report_email'] ?? '';

        setState(() {});
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> salvarConfiguracoes() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      isSaving = true;
    });

    try {
      final payload = {
        'company_name': empresaController.text.trim(),
        'cnpj': cnpjController.text.trim(),
        'phone': telefoneController.text.trim(),
        'email': emailController.text.trim(),
        'timezone': timezoneController.text.trim(),
        'report_email': reportEmailController.text.trim(),
      };

      if (registroId == null) {
        await supabase.from('company_settings').insert(payload);
      } else {
        await supabase
            .from('company_settings')
            .update(payload)
            .eq('id', registroId!);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas com sucesso!')),
      );
      carregarDados();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Dados da Empresa',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: empresaController,
                        decoration: const InputDecoration(
                          labelText: 'Nome da Empresa',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe o nome da empresa';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: cnpjController,
                        decoration: const InputDecoration(labelText: 'CNPJ'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe o CNPJ';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: telefoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telefone',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe o telefone';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe o e-mail';
                          }
                          if (!value.contains('@')) {
                            return 'Digite um e-mail válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: timezoneController,
                        decoration: const InputDecoration(
                          labelText: 'Fuso horário',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: reportEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'E-mail para relatórios',
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: isSaving ? null : salvarConfiguracoes,
                          icon: const Icon(Icons.save),
                          label: isSaving
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text('Salvar Configurações'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Operações da frota'),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    value: auditoriaAtiva,
                    title: const Text('Auditoria de combustível'),
                    subtitle: const Text(
                      'Ativa verificações automáticas de política.',
                    ),
                    onChanged: (value) =>
                        setState(() => auditoriaAtiva = value),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                  SwitchListTile(
                    value: alertaGasto,
                    title: const Text('Alertas de gasto'),
                    subtitle: const Text(
                      'Notifique quando o consumo ultrapassar limites.',
                    ),
                    onChanged: (value) => setState(() => alertaGasto = value),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                  SwitchListTile(
                    value: alertasPush,
                    title: const Text('Notificações em tempo real'),
                    subtitle: const Text('Receba avisos e alertas no app.'),
                    onChanged: (value) => setState(() => alertasPush = value),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                  SwitchListTile(
                    value: apiIntegration,
                    title: const Text('Integração com ERPs'),
                    subtitle: const Text(
                      'Habilite conexões externas e exportações.',
                    ),
                    onChanged: (value) =>
                        setState(() => apiIntegration = value),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Compatibilidade e segurança'),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.security),
                    title: const Text('Gestão de acessos'),
                    subtitle: const Text(
                      'Controle perfis, permissões e logins.',
                    ),
                    trailing: const Icon(Icons.keyboard_arrow_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ação registrada no ambiente de teste: Gestão de acessos')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload),
                    title: const Text('Backup e exportação'),
                    subtitle: const Text(
                      'Baixe configurações ou exporte relatórios.',
                    ),
                    trailing: const Icon(Icons.keyboard_arrow_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ação registrada no ambiente de teste: Backup e exportação')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

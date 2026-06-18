// Build v2.1 - Layout improvements applied
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home_page.dart';
import 'register_page.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _backgroundAsset = 'assets/images/login_bg.jpg';

  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final forgotEmailController = TextEditingController();
  bool isLoading = false;

  Future<void> login() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('Login error: $e');
      debugPrint('$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao conectar: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    forgotEmailController.text = emailController.text;
    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Recuperar senha'),
          content: TextField(
            controller: forgotEmailController,
            decoration: const InputDecoration(labelText: 'E-mail'),
            keyboardType: TextInputType.emailAddress,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (shouldSend != true) return;
    final email = forgotEmailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe um email')));
      return;
    }

    try {
      // Use dynamic call to support multiple supabase versions
      await (Supabase.instance.client.auth as dynamic).resetPasswordForEmail(
        email,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email de recuperação enviado')),
      );
    } catch (e) {
      debugPrint('Reset password error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível enviar o email. Contate o administrador.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    forgotEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _backgroundAsset,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: AppColors.background),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.background.withOpacity(0.28),
                    AppColors.background.withOpacity(0.92),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 900;

                if (isMobile) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 28,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 540),
                        child: _buildFormPanel(),
                      ),
                    ),
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 40,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLeftPanel(),
                            const Spacer(),
                            _buildFeaturesSection(),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 40,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: _buildFormPanel(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: const [
            AppLogo(compact: false, iconSize: 44),
            SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FROTA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'CHECK',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 26),
        const Text(
          'Gestão completa da sua frota\nna palma da sua mão.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w400,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Monitore seus veículos, mantenha a operação conectada e\n'
          'otimize sua frota com dashboards inteligentes.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.7,
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection() {
    return Wrap(
      spacing: 24,
      runSpacing: 24,
      children: [
        _buildFeatureItem(Icons.shield, 'Seguro'),
        _buildFeatureItem(Icons.insights, 'Inteligente'),
        _buildFeatureItem(Icons.wifi, 'Conectado'),
        _buildFeatureItem(Icons.speed, 'Eficiente'),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.secondary.withOpacity(0.20),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.secondary, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFormPanel() {
    return Container(
      padding: const EdgeInsets.all(50),
      decoration: BoxDecoration(
        color: const Color(0xFF0B172D).withOpacity(0.96),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: AppColors.secondary.withOpacity(0.22),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: AppColors.secondary.withOpacity(0.14),
            blurRadius: 48,
            spreadRadius: 1,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.secondary.withOpacity(0.55),
                width: 1.2,
              ),
            ),
            child: const Text(
              'LOGIN WEB',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.secondary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.6,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 48),
          const Text(
            'Bem-vindo de volta!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Faça login para acessar sua conta',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 48),
          _buildLoginForm(),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF10233B),
              hintText: 'E-mail',
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
              prefixIcon: const Icon(Icons.email, color: AppColors.secondary),
              floatingLabelBehavior: FloatingLabelBehavior.never,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: AppColors.secondary.withOpacity(0.18),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: AppColors.secondary.withOpacity(0.18),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: AppColors.secondary.withOpacity(0.85),
                  width: 1.8,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Informe seu email';
              }
              if (!value.contains('@')) {
                return 'Digite um email válido';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: passwordController,
            obscureText: true,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF10233B),
              hintText: 'Senha',
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
              prefixIcon: const Icon(Icons.lock, color: AppColors.secondary),
              floatingLabelBehavior: FloatingLabelBehavior.never,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: AppColors.secondary.withOpacity(0.18),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: AppColors.secondary.withOpacity(0.18),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: AppColors.secondary.withOpacity(0.85),
                  width: 1.8,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Informe sua senha';
              }
              if (value.length < 6) {
                return 'A senha deve ter pelo menos 6 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPasswordDialog,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondary,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              child: const Text('Esqueceu sua senha?'),
            ),
          ),
          const SizedBox(height: 36),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF39A6FF), Color(0xFF0E66D8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF39A6FF).withOpacity(0.35),
                  blurRadius: 28,
                  spreadRadius: 1,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: isLoading ? null : login,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Entrar na conta',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 36),
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: AppColors.textSecondary.withOpacity(0.32),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'ou continue com',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: AppColors.textSecondary.withOpacity(0.32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.g_mobiledata,
                    color: Colors.white,
                    size: 22,
                  ),
                  label: const Text('Google', style: TextStyle(fontSize: 15)),
                  style:
                      OutlinedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: AppColors.secondary.withOpacity(0.30),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ).copyWith(
                        overlayColor: MaterialStateProperty.all(
                          AppColors.secondary.withOpacity(0.12),
                        ),
                      ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.window, color: Colors.white, size: 22),
                  label: const Text(
                    'Microsoft',
                    style: TextStyle(fontSize: 15),
                  ),
                  style:
                      OutlinedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: AppColors.secondary.withOpacity(0.30),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ).copyWith(
                        overlayColor: MaterialStateProperty.all(
                          AppColors.secondary.withOpacity(0.12),
                        ),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Não tem uma conta? ',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterPage()),
                  );
                },
                child: const Text(
                  'Cadastre-se',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

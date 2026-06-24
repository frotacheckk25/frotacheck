import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home_page.dart';
import 'register_page.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _sky = Color(0xFF0ea5e9);
const _skyDark = Color(0xFF0369a1);
const _navy = Color(0xFF030A16);
const _card = Color(0xFF0a1628);
const _surface = Color(0xFF112035);
const _muted = Color(0xFF8BAABB);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _bgAsset = 'assets/images/login_bg.jpg';

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _forgotCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;

  void _toggleObscure() => setState(() => _obscure = !_obscure);

  // ─── Auth ─────────────────────────────────────────────────────────────────

  Future<void> _login() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao conectar: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    _forgotCtrl.text = _emailCtrl.text;
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Recuperar senha',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _forgotCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (!mounted || send != true) return;
    final email = _forgotCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe um email')));
      return;
    }
    try {
      await (Supabase.instance.client.auth as dynamic)
          .resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email de recuperação enviado')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível enviar. Contate o administrador.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _forgotCtrl.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Background(asset: _bgAsset),
          SafeArea(
            child: LayoutBuilder(
              builder: (_, c) {
                if (c.maxWidth >= 1024) return _DesktopLayout(state: this);
                if (c.maxWidth >= 640) return _TabletLayout(state: this);
                return _MobileLayout(state: this);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Background ───────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background({required this.asset});
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: const Alignment(0.15, 0.0),
          errorBuilder: (_, _, _) => const ColoredBox(color: _navy),
        ),
        // left-to-right gradient so desktop form panel is readable
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xBB030A16), Color(0xF2030A16)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        // top-to-bottom atmospheric vignette
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Color(0xCC030A16)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Layouts ──────────────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.state});
  final _LoginPageState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
            child: _HeroPanel(),
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
                constraints: const BoxConstraints(maxWidth: 480),
                child: _FormCard(state: state),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabletLayout extends StatelessWidget {
  const _TabletLayout({required this.state});
  final _LoginPageState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              const _LogoWidget(iconSize: 36),
              const SizedBox(height: 32),
              _FormCard(state: state),
              const SizedBox(height: 32),
              const _FeaturesRow(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.state});
  final _LoginPageState state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          const _LogoWidget(iconSize: 30),
          const SizedBox(height: 20),
          const Text(
            'Gestão completa da sua frota\nna palma da sua mão.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 28),
          _FormCard(state: state),
          const SizedBox(height: 28),
          const _FeaturesRow(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Hero Panel (desktop only) ────────────────────────────────────────────────

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _LogoWidget(iconSize: 42),
        SizedBox(height: 48),
        Text(
          'Gestão completa\nda sua frota na\npalma da sua mão.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        SizedBox(height: 48),
        _FeaturesRow(),
        SizedBox(height: 48),
        _DashboardPreviewCard(),
      ],
    );
  }
}

// ─── Logo ─────────────────────────────────────────────────────────────────────

class _LogoWidget extends StatelessWidget {
  const _LogoWidget({this.iconSize = 36});
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final box = iconSize + 16;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: box,
          height: box,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_skyDark, _sky],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(box * 0.26),
            boxShadow: [
              BoxShadow(
                color: _sky.withOpacity(0.45),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(Icons.shield, color: Colors.white, size: iconSize * 0.65),
        ),
        SizedBox(width: iconSize * 0.35),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'FROTA',
              style: TextStyle(
                color: Colors.white,
                fontSize: iconSize * 0.62,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                height: 1.05,
              ),
            ),
            Text(
              'CHECK',
              style: TextStyle(
                color: _sky,
                fontSize: iconSize * 0.62,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                height: 1.05,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Feature badges ───────────────────────────────────────────────────────────

class _FeaturesRow extends StatelessWidget {
  const _FeaturesRow();

  static const _items = [
    (Icons.shield_outlined, 'Seguro'),
    (Icons.psychology_outlined, 'Inteligente'),
    (Icons.wifi_tethering, 'Conectado'),
    (Icons.speed, 'Eficiente'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 28,
      runSpacing: 16,
      children: _items.map((e) => _FeatureBadge(icon: e.$1, label: e.$2)).toList(),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _sky.withOpacity(0.10),
            shape: BoxShape.circle,
            border: Border.all(color: _sky.withOpacity(0.25), width: 1.5),
          ),
          child: Icon(icon, color: _sky, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Dashboard preview card (hero) ────────────────────────────────────────────

class _DashboardPreviewCard extends StatelessWidget {
  const _DashboardPreviewCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _sky.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _sky.withOpacity(0.18), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.public, color: _sky, size: 14),
                  const SizedBox(width: 8),
                  const Text(
                    'MONITORAMENTO EM TEMPO REAL',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.7),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: 0.96,
                          strokeWidth: 4.5,
                          backgroundColor: Colors.white12,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(_sky),
                        ),
                        const Text(
                          '96%',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FROTA ATIVA',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '47 / 49 veículos',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Form Card ────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  const _FormCard({required this.state});
  final _LoginPageState state;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          decoration: BoxDecoration(
            color: _card.withOpacity(0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.07), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 48,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Platform badge
              Align(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _sky.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _sky.withOpacity(0.35),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    kIsWeb ? 'ACESSO WEB' : 'ACESSO MOBILE',
                    style: const TextStyle(
                      color: _sky,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Bem-vindo de volta!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Faça login para acessar sua conta',
                style: TextStyle(color: _muted, fontSize: 14),
              ),
              const SizedBox(height: 28),
              _LoginForm(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Login Form ───────────────────────────────────────────────────────────────

class _LoginForm extends StatelessWidget {
  const _LoginForm({required this.state});
  final _LoginPageState state;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: state._formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Email
          _InputField(
            controller: state._emailCtrl,
            hint: 'E-mail',
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Informe seu email';
              if (!v.contains('@')) return 'Email inválido';
              return null;
            },
          ),
          const SizedBox(height: 14),
          // Password
          _InputField(
            controller: state._passCtrl,
            hint: 'Senha',
            icon: Icons.lock_outline,
            obscure: state._obscure,
            suffix: IconButton(
              icon: Icon(
                state._obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _muted,
                size: 20,
              ),
              onPressed: state._toggleObscure,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Informe sua senha';
              if (v.length < 6) return 'Mínimo 6 caracteres';
              return null;
            },
          ),
          // Forgot password
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: state._forgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: _sky,
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 0,
                ),
              ),
              child: const Text(
                'Esqueceu a senha?',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Login button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: state._loading ? null : state._login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _sky,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _sky.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: state._loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Entrar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          // Divider
          Row(
            children: [
              Expanded(
                child: Divider(color: Colors.white.withOpacity(0.10)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ou continue com',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ),
              Expanded(
                child: Divider(color: Colors.white.withOpacity(0.10)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Social buttons
          Row(
            children: [
              Expanded(
                child: _SocialButton(
                  label: 'Google',
                  icon: const Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Login com Google em breve')),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SocialButton(
                  label: 'Microsoft',
                  icon: const Icon(
                    Icons.window,
                    color: Colors.white70,
                    size: 18,
                  ),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Login com Microsoft em breve'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Register link
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Não tem uma conta? ',
                style: TextStyle(color: _muted, fontSize: 14),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterPage()),
                ),
                child: const Text(
                  'Cadastre-se',
                  style: TextStyle(
                    color: _sky,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
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

// ─── Input Field ──────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboard,
    this.obscure = false,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboard;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        filled: true,
        fillColor: _surface,
        hintText: hint,
        hintStyle: const TextStyle(color: _muted, fontSize: 14),
        prefixIcon: Icon(icon, color: _sky, size: 20),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _sky, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}

// ─── Social Button ────────────────────────────────────────────────────────────

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon,
        label: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: _surface,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

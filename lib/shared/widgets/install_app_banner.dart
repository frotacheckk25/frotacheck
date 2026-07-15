import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/pwa_install.dart';

const _kDismissedKey = 'fc_install_banner_dismissed';

/// Banner "Instalar FrotaCheck" — some no primeiro acesso via Web, quando o
/// navegador sinaliza (beforeinstallprompt) que o app pode ser instalado.
/// Não faz nada em nativo (Android já é o próprio app instalado).
class InstallAppBanner extends StatefulWidget {
  const InstallAppBanner({super.key});

  @override
  State<InstallAppBanner> createState() => _InstallAppBannerState();
}

class _InstallAppBannerState extends State<InstallAppBanner> {
  bool _dismissed = true;
  InstallBannerKind _kind = InstallBannerKind.none;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_kDismissedKey) ?? false;
    if (!mounted) return;
    setState(() => _dismissed = dismissed);
    installBannerKindStream().listen((kind) {
      if (!mounted) return;
      setState(() => _kind = kind);
    });
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDismissedKey, true);
    if (!mounted) return;
    setState(() => _dismissed = true);
  }

  Future<void> _install() async {
    setState(() => _prompting = true);
    await promptInstall();
    if (!mounted) return;
    setState(() => _prompting = false);
    // O evento só pode ser usado uma vez — depois de disparar o prompt
    // (aceito ou não pelo usuário), o navegador não reoferece a mesma
    // instância, então o banner não tem mais o que fazer.
    await _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _kind == InstallBannerKind.none) return const SizedBox.shrink();
    final isIos = _kind == InstallBannerKind.iosManual;

    return SafeArea(
      bottom: false,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isIos ? Icons.ios_share_rounded : Icons.install_mobile_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Instalar FrotaCheck',
                      style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isIos
                          ? 'Toque em Compartilhar e depois em "Adicionar à Tela de Início".'
                          : 'Acesso rápido na tela inicial, sem precisar do navegador.',
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_prompting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              else ...[
                if (!isIos)
                  TextButton(
                    onPressed: _install,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Instalar', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                IconButton(
                  onPressed: _dismiss,
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                  tooltip: 'Fechar',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

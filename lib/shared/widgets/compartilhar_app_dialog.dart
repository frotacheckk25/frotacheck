import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config/app_links.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_utils.dart';

/// Modal "Compartilhar App" — QR Code + link oficial do PWA + opções de
/// compartilhamento para uma empresa específica. Usado no botão
/// "Compartilhar App" da tela Empresas (MASTER) e reutilizável de qualquer
/// outro lugar que precise compartilhar o app para uma empresa em particular.
Future<void> showCompartilharAppDialog(BuildContext context, {required String empresaNome}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Row(
        children: [
          const Icon(Icons.qr_code_2_rounded, color: AppColors.secondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Compartilhar App — $empresaNome',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                data: kFrotaCheckPwaUrl,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(
              kFrotaCheckPwaUrl,
              style: const TextStyle(color: AppColors.secondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: kFrotaCheckPwaUrl));
                    if (context.mounted) showSuccess(context, 'Link copiado!');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copiar Link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final mensagem = frotaCheckShareMessage(empresaNome);
                    try {
                      // Fallbacks do share_plus desligados de propósito — ver
                      // o mesmo comentário em distribuicao_app_page.dart.
                      await SharePlus.instance.share(
                        ShareParams(
                          text: mensagem,
                          subject: 'FrotaCheck',
                          downloadFallbackEnabled: false,
                          mailToFallbackEnabled: false,
                        ),
                      );
                    } catch (_) {
                      if (!context.mounted) return;
                      try {
                        await Clipboard.setData(ClipboardData(text: mensagem));
                        if (context.mounted) {
                          showSuccess(context, 'Mensagem copiada! Cole no WhatsApp ou E-mail.');
                        }
                      } catch (e) {
                        if (context.mounted) showError(context, friendlyError(e));
                      }
                    }
                  },
                  icon: const Icon(Icons.share_rounded, size: 16, color: Colors.white),
                  label: const Text('Compartilhar', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar', style: TextStyle(color: AppColors.secondary)),
        ),
      ],
    ),
  );
}

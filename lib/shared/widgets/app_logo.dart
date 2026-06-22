import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  final double iconSize;
  final double spacing;
  final bool compact;

  const AppLogo({
    super.key,
    this.iconSize = 30,
    this.spacing = 12,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // tenta carregar imagem de logo em assets/images/logo_shield.png
    final logoAsset = 'assets/images/logo_shield.png';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconSize + 24,
          height: iconSize + 24,
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Image.asset(
              logoAsset,
              width: iconSize,
              height: iconSize,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.shield, size: iconSize, color: Colors.white),
            ),
          ),
        ),
        if (!compact) ...[
          SizedBox(width: spacing),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'FROTA CHECK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Gestão de frota',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

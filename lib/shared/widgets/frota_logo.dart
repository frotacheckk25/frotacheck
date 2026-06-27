import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class FrotaLogo extends StatelessWidget {
  final double iconSize;
  final double spacing;
  final bool compact;

  const FrotaLogo({
    super.key,
    this.iconSize = 30,
    this.spacing = 12,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconSize + 10,
          height: iconSize + 10,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              'F',
              style: TextStyle(
                color: Colors.white,
                fontSize: iconSize * 0.7,
                fontWeight: FontWeight.bold,
              ),
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
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Gestão de frota empresarial',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

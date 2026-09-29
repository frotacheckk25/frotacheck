import 'package:flutter/material.dart';
import 'checklist_vistoria_page.dart';

/// Checklist de retorno — usa o painel de vistoria compartilhado com a saída
/// (checklist_vistoria_page.dart), mudando só o contexto da operação.
class ChecklistRetornoPage extends StatelessWidget {
  final String veiculoId;
  final String veiculoPlaca;
  final String motoristaId;

  const ChecklistRetornoPage({
    required this.veiculoId,
    required this.veiculoPlaca,
    required this.motoristaId,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ChecklistVistoriaPage(
        tipo: 'retorno',
        veiculoId: veiculoId,
        veiculoPlaca: veiculoPlaca,
        motoristaId: motoristaId,
      );
}

import 'package:flutter/material.dart';
import 'checklist_vistoria_page.dart';

/// Checklist de saída — usa o painel de vistoria compartilhado com o retorno
/// (checklist_vistoria_page.dart), mudando só o contexto da operação.
class ChecklistSaidaPage extends StatelessWidget {
  final String veiculoId;
  final String veiculoPlaca;
  final String motoristaId;

  const ChecklistSaidaPage({
    required this.veiculoId,
    required this.veiculoPlaca,
    required this.motoristaId,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ChecklistVistoriaPage(
        tipo: 'saida',
        veiculoId: veiculoId,
        veiculoPlaca: veiculoPlaca,
        motoristaId: motoristaId,
      );
}

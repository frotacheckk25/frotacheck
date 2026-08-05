import 'package:flutter/material.dart';

/// Tipos de veículo suportados pelo cadastro — valores batem com o CHECK
/// constraint de vehicles.tipo no banco (ver docs/MIGRATION_TIPO_FOTO_VEICULO.sql).
const veiculoTipos = <String, String>{
  'carro': 'Carro',
  'caminhao': 'Caminhão',
  'van': 'Van',
  'onibus': 'Ônibus',
  'moto': 'Moto',
};

IconData iconeParaTipoVeiculo(String? tipo) {
  switch (tipo) {
    case 'caminhao':
      return Icons.local_shipping;
    case 'van':
      return Icons.airport_shuttle;
    case 'onibus':
      return Icons.directions_bus;
    case 'moto':
      return Icons.two_wheeler;
    case 'carro':
    default:
      return Icons.directions_car;
  }
}

String labelTipoVeiculo(String? tipo) => veiculoTipos[tipo] ?? 'Carro';

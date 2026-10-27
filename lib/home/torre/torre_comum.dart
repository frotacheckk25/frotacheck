import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Peças comuns da Torre de Controle (rastreamento dos veículos).

/// Sem posição nova há mais que isso, durante a viagem = "sem sinal".
const limiteSemSinal = Duration(minutes: 15);

/// Parado no mesmo lugar há mais que isso, durante a viagem = alerta.
const limiteParado = Duration(minutes: 30);

/// Acima disso (km/h) é excesso de velocidade para caminhão.
const limiteVelocidade = 90;

enum SituacaoVeiculo {
  emMovimento('Em movimento', AppColors.success, Icons.local_shipping),
  parado('Parado', AppColors.warning, Icons.pause_circle),
  semSinal('Sem sinal', AppColors.danger, Icons.signal_wifi_off),
  foraDeViagem('Fora de viagem', AppColors.muted, Icons.local_parking);

  const SituacaoVeiculo(this.rotulo, this.cor, this.icone);
  final String rotulo;
  final Color cor;
  final IconData icone;
}

SituacaoVeiculo situacaoVeiculo({
  required bool emViagem,
  DateTime? ultimaPosicao,
  DateTime? paradoDesde,
  required DateTime agora,
}) {
  if (!emViagem) return SituacaoVeiculo.foraDeViagem;
  if (ultimaPosicao == null || agora.difference(ultimaPosicao) > limiteSemSinal) return SituacaoVeiculo.semSinal;
  if (paradoDesde != null && agora.difference(paradoDesde) > limiteParado) return SituacaoVeiculo.parado;
  return SituacaoVeiculo.emMovimento;
}

/// Distância em metros entre dois pontos (fórmula de haversine).
double distanciaMetros(double lat1, double lng1, double lat2, double lng2) {
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * 6371000 * math.asin(math.min(1, math.sqrt(a)));
}

/// "agora", "há 5 min", "há 2 h 10 min", "há 3 dias".
String haQuanto(DateTime? quando, {DateTime? agora}) {
  if (quando == null) return 'sem posição';
  final d = (agora ?? DateTime.now()).difference(quando);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return d.inMinutes % 60 == 0 ? 'há ${d.inHours} h' : 'há ${d.inHours} h ${d.inMinutes % 60} min';
  return d.inDays == 1 ? 'há 1 dia' : 'há ${d.inDays} dias';
}

/// Quando o celular manda a posição: andando, a cada 2 min; parado (menos de
/// 150 m desde o último envio), a cada 5 min — poupa bateria e dados e mesmo
/// assim a torre sabe que o celular está vivo.
bool deveEnviarPosicao({required DateTime agora, DateTime? ultimoEnvio, double? metrosDesdeUltimo}) {
  if (ultimoEnvio == null) return true;
  final passou = agora.difference(ultimoEnvio);
  final andando = metrosDesdeUltimo == null || metrosDesdeUltimo >= 150;
  return passou >= (andando ? const Duration(minutes: 2) : const Duration(minutes: 5));
}

/// Link para abrir o ponto no Google Maps.
Uri linkMapa(double lat, double lng) => Uri.parse('https://www.google.com/maps?q=$lat,$lng');

/// Link para o Google Street View no ponto (sem chave de API).
Uri linkStreetView(double lat, double lng) =>
    Uri.parse('https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=$lat,$lng');

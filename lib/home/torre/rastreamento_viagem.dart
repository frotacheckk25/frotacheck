import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import 'rastreio_gps.dart';
import 'torre_comum.dart';

/// Situação do rastreamento mostrada ao motorista.
class EstadoRastreio {
  const EstadoRastreio({required this.rotulo, this.ultimoEnvio, this.aviso});
  final String rotulo; // "Pouso Alegre → São Paulo"
  final DateTime? ultimoEnvio;
  final String? aviso; // GPS negado, sem internet...
}

/// Envia a posição do celular do motorista para a Torre de Controle durante a
/// viagem em andamento — e só nela (LGPD). Sem internet, guarda as posições e
/// manda quando voltar. Um só por app (singleton).
class RastreamentoViagem {
  RastreamentoViagem._() {
    // saiu da conta: para de rastrear na hora
    Supabase.instance.client.auth.onAuthStateChange.listen((d) {
      if (d.event == AuthChangeEvent.signedOut) unawaited(parar());
    });
  }
  static final instancia = RastreamentoViagem._();

  /// null = desligado
  final estado = ValueNotifier<EstadoRastreio?>(null);

  String? _viagemId, _veiculoId;
  StreamSubscription<LeituraGps>? _gps;
  Timer? _relogio;
  LeituraGps? _ultimaLeitura, _ultimaEnviada;
  DateTime? _ultimoEnvio;
  final List<Map<String, dynamic>> _fila = [];
  bool _enviando = false;

  String? get viagemAtual => _viagemId;

  /// Liga o envio se o motorista tem viagem em andamento e desliga quando ela
  /// acaba — vale para a viagem aberta pelo gestor e para quando o app é
  /// recarregado no meio da viagem. As telas iniciais chamam ao carregar.
  Future<void> sincronizar({String? driverId}) async {
    final supabase = Supabase.instance.client;
    try {
      var id = driverId;
      if (id == null) {
        final uid = supabase.auth.currentUser?.id;
        if (uid == null) return;
        final p = await supabase.from('user_profiles').select('driver_id').eq('user_id', uid).maybeSingle();
        id = p?['driver_id']?.toString();
        if (id == null) return;
      }
      final v = await supabase
          .from('viagens')
          .select('id, veiculo_id, origem, destino')
          .eq('motorista_id', id)
          .eq('status', 'em_progresso')
          .order('data_inicio', ascending: false)
          .limit(1)
          .maybeSingle();
      if (v == null || v['veiculo_id'] == null) {
        await parar();
        return;
      }
      await iniciar(viagemId: v['id'].toString(), veiculoId: v['veiculo_id'].toString(), rotulo: '${v['origem'] ?? ''} → ${v['destino'] ?? ''}');
    } catch (e) {
      debugPrint('Rastreamento da viagem: $e');
    }
  }

  Future<void> iniciar({required String viagemId, required String veiculoId, String rotulo = ''}) async {
    if (_viagemId == viagemId) return;
    await parar();
    _viagemId = viagemId;
    _veiculoId = veiculoId;
    _ultimoEnvio = null;
    _ultimaEnviada = null;
    estado.value = EstadoRastreio(rotulo: rotulo);
    _gps = fluxoGps().listen(
      (l) {
        _ultimaLeitura = l;
        _talvezEnviar();
      },
      onError: (Object e) => _avisar('Permita a localização do celular para a torre acompanhar a viagem.'),
      cancelOnError: false,
    );
    _relogio = Timer.periodic(const Duration(minutes: 1), (_) {
      manterTelaAcesa(true);
      _talvezEnviar();
    });
    await manterTelaAcesa(true);
  }

  /// Para de rastrear (fim da viagem). Antes, tenta mandar o que está guardado.
  Future<void> parar() async {
    if (_viagemId == null) return;
    await _gps?.cancel();
    _gps = null;
    _relogio?.cancel();
    _relogio = null;
    await _descarregar();
    await manterTelaAcesa(false);
    _viagemId = null;
    _veiculoId = null;
    _ultimaLeitura = null;
    _fila.clear();
    estado.value = null;
  }

  void _avisar(String aviso) {
    final e = estado.value;
    if (e != null) estado.value = EstadoRastreio(rotulo: e.rotulo, ultimoEnvio: e.ultimoEnvio, aviso: aviso);
  }

  void _talvezEnviar() {
    final l = _ultimaLeitura, viagem = _viagemId, veiculo = _veiculoId;
    if (l == null || viagem == null || veiculo == null) return;
    final anterior = _ultimaEnviada;
    final metros = anterior == null ? null : distanciaMetros(anterior.latitude, anterior.longitude, l.latitude, l.longitude);
    final agora = DateTime.now();
    if (!deveEnviarPosicao(agora: agora, ultimoEnvio: _ultimoEnvio, metrosDesdeUltimo: metros)) return;
    _fila.add({
      'vehicle_id': veiculo,
      'viagem_id': viagem,
      'latitude': l.latitude,
      'longitude': l.longitude,
      if (l.velocidadeKmh != null) 'velocidade_kmh': double.parse(l.velocidadeKmh!.clamp(0, 300).toStringAsFixed(1)),
      if (l.precisaoM != null) 'precisao_m': double.parse(l.precisaoM!.toStringAsFixed(1)),
      if (l.rumo != null) 'rumo': double.parse(l.rumo!.clamp(0, 360).toStringAsFixed(1)),
      // leitura velha (GPS sem sinal) vai com a hora da leitura; nova, com a hora do envio
      'registrado_em': (agora.difference(l.quando) > const Duration(minutes: 3) ? l.quando : agora).toUtc().toIso8601String(),
    });
    if (_fila.length > 500) _fila.removeAt(0);
    _ultimoEnvio = agora;
    _ultimaEnviada = l;
    _descarregar();
  }

  Future<void> _descarregar() async {
    if (_enviando || _fila.isEmpty) return;
    _enviando = true;
    final lote = List<Map<String, dynamic>>.of(_fila);
    try {
      await Supabase.instance.client.from('rastreamento_posicoes').insert(lote);
      _fila.removeRange(0, lote.length);
      final e = estado.value;
      if (e != null) estado.value = EstadoRastreio(rotulo: e.rotulo, ultimoEnvio: DateTime.now());
    } catch (e) {
      if (e.toString().contains('viagem em andamento')) {
        // a viagem foi encerrada por outra tela/pessoa: para de rastrear
        _fila.clear();
        _enviando = false;
        unawaited(parar());
        return;
      }
      _avisar('Sem internet agora: ${_fila.length} posição(ões) guardada(s) para enviar.');
    } finally {
      _enviando = false;
    }
  }
}

/// Faixa mostrada ao motorista enquanto a viagem está sendo rastreada.
class AvisoRastreamento extends StatelessWidget {
  const AvisoRastreamento({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<EstadoRastreio?>(
        valueListenable: RastreamentoViagem.instancia.estado,
        builder: (ctx, e, _) {
          if (e == null) return const SizedBox.shrink();
          final ok = e.aviso == null;
          final cor = ok ? AppColors.success : AppColors.warning;
          final texto = ok
              ? 'Viagem em andamento${e.rotulo.isEmpty ? '' : ' (${e.rotulo})'}: sua localização vai para a torre de controle'
                  '${e.ultimoEnvio != null ? ' (enviada ${haQuanto(e.ultimoEnvio)})' : ''}.'
                  '${kIsWeb ? ' Mantenha o FrotaCheck aberto na tela durante a viagem.' : ''}'
              : e.aviso!;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: cor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(ok ? Icons.satellite_alt_rounded : Icons.warning_amber_rounded, color: cor, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
            ]),
          );
        },
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formato_br.dart';

/// Peças comuns das telas de Ordens de Serviço e Plano Preventivo.

String dataBrManut(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '-';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String isoDia(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

double? numeroBrDe(String s) => lerNumeroBr(s);

const statusOs = {
  'aberta': ('Aberta', AppColors.info),
  'em_execucao': ('Em execução', AppColors.warning),
  'concluida': ('Concluída', AppColors.success),
  'cancelada': ('Cancelada', AppColors.muted),
};

/// Situação de um item do plano preventivo em relação ao odômetro e à data de hoje.
enum SituacaoPlano { vencido, proximo, emDia, semRegistro }

class AnalisePlano {
  const AnalisePlano(this.situacao, this.proximoKm, this.proximaData, this.faltamKm, this.faltamDias);
  final SituacaoPlano situacao;
  final int? proximoKm;
  final DateTime? proximaData;
  final int? faltamKm;
  final int? faltamDias;

  String get rotulo => switch (situacao) {
        SituacaoPlano.vencido => 'Vencido',
        SituacaoPlano.proximo => 'Próximo',
        SituacaoPlano.emDia => 'Em dia',
        SituacaoPlano.semRegistro => 'Sem registro',
      };

  Color get cor => switch (situacao) {
        SituacaoPlano.vencido => AppColors.danger,
        SituacaoPlano.proximo => AppColors.warning,
        SituacaoPlano.emDia => AppColors.success,
        SituacaoPlano.semRegistro => AppColors.muted,
      };

  /// Texto curto: "faltam 1.200 km · 20 dias" / "vencido há 300 km".
  String get resumo {
    final partes = <String>[];
    if (faltamKm != null) {
      partes.add(faltamKm! >= 0 ? 'faltam ${_milhar(faltamKm!)} km' : 'passou ${_milhar(-faltamKm!)} km');
    }
    if (faltamDias != null) {
      partes.add(faltamDias! >= 0 ? 'faltam $faltamDias dias' : 'venceu há ${-faltamDias!} dias');
    }
    return partes.join(' · ');
  }
}

String _milhar(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String kmBr(num? n) => n == null ? '-' : '${_milhar(n.round())} km';

AnalisePlano analisarPlano(Map<String, dynamic> item, num? odometro, {DateTime? hoje}) {
  final agora = hoje ?? DateTime.now();
  final dia = DateTime(agora.year, agora.month, agora.day);
  final intKm = (item['intervalo_km'] as num?)?.toInt();
  final intDias = (item['intervalo_dias'] as num?)?.toInt();
  final ultKm = (item['ultima_km'] as num?)?.toInt();
  final ultData = DateTime.tryParse(item['ultima_data']?.toString() ?? '');
  if (ultKm == null && ultData == null) {
    return const AnalisePlano(SituacaoPlano.semRegistro, null, null, null, null);
  }
  final proxKm = (intKm != null && ultKm != null) ? ultKm + intKm : null;
  final proxData = (intDias != null && ultData != null) ? ultData.add(Duration(days: intDias)) : null;
  final faltamKm = (proxKm != null && odometro != null) ? proxKm - odometro.round() : null;
  final faltamDias = proxData?.difference(dia).inDays;
  final margemKm = intKm == null ? 0 : (intKm * 0.1).round().clamp(500, 5000);
  SituacaoPlano s;
  if ((faltamKm != null && faltamKm <= 0) || (faltamDias != null && faltamDias < 0)) {
    s = SituacaoPlano.vencido;
  } else if ((faltamKm != null && faltamKm <= margemKm) || (faltamDias != null && faltamDias <= 15)) {
    s = SituacaoPlano.proximo;
  } else {
    s = SituacaoPlano.emDia;
  }
  return AnalisePlano(s, proxKm, proxData, faltamKm, faltamDias);
}

/// Plano padrão para caminhões (o gestor ajusta os intervalos depois).
const planoPadraoCaminhao = <(String, int?, int?)>[
  ('Troca de óleo do motor', 10000, 180),
  ('Filtro de óleo', 10000, null),
  ('Filtro de combustível', 20000, null),
  ('Filtro de ar', 20000, 365),
  ('Revisão de freios', 20000, 180),
  ('Alinhamento e balanceamento', 10000, null),
  ('Lubrificação do chassi', 5000, null),
  ('Óleo da caixa e do diferencial', 80000, 730),
];

/// Empresa em que a tela trabalha: a do usuário ou, para o MASTER, a escolhida no seletor.
mixin EmpresaDaTela<T extends StatefulWidget> on State<T> {
  List<Map<String, dynamic>> empresasMaster = [];
  String? empresaMaster;

  String? get empresaAtual => context.read<AppAuthProvider>().effectiveEmpresaId ?? empresaMaster;
  bool get mostrarSeletorEmpresa => context.read<AppAuthProvider>().effectiveEmpresaId == null && empresasMaster.isNotEmpty;

  Future<void> prepararEmpresa() async {
    if (context.read<AppAuthProvider>().effectiveEmpresaId != null || empresasMaster.isNotEmpty) return;
    empresasMaster = List<Map<String, dynamic>>.from(
        await Supabase.instance.client.from('empresas').select('id, nome').order('nome', ascending: true));
    empresaMaster ??= empresasMaster.isNotEmpty ? empresasMaster.first['id'].toString() : null;
  }

  Widget seletorEmpresa(VoidCallback aoTrocar) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: DropdownButtonFormField<String>(
          initialValue: empresaMaster,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Empresa (visão master)', prefixIcon: Icon(Icons.apartment_rounded)),
          items: [
            for (final e in empresasMaster)
              DropdownMenuItem(value: e['id'].toString(), child: Text(e['nome'].toString(), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            setState(() => empresaMaster = v);
            aoTrocar();
          },
        ),
      );
}

Widget chipStatus(String texto, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
      child: Text(texto, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.bold)),
    );

Widget botaoAcao(String t, IconData i, Color c, VoidCallback? onTap) => OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(i, size: 17, color: c),
      label: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c.withValues(alpha: 0.5)),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

Widget cartaoManut({required Widget child, VoidCallback? onTap}) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

Widget vazioManut(IconData i, String t) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 54, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(t, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
        ]),
      ),
    );

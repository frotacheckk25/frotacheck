import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/models/checklist_model.dart';
import '../../core/theme/app_theme.dart';

/// Componentes da vistoria do veículo, compartilhados pelos checklists de
/// saída e de retorno — seguem a ficha de vistoria usada pelos clientes:
/// fotos por posição, avarias marcadas por posição (R/A/T/F/E) e nível do
/// tanque.

/// Legenda de avarias da ficha do cliente.
const Map<String, String> kTiposAvaria = {
  'R': 'Risco',
  'A': 'Amassado',
  'T': 'Trinca',
  'F': 'Falta/Quebra',
  'E': 'Outros',
};

/// Níveis de tanque da ficha (marcação de combustível).
const List<String> kNiveisTanque = ['Reserva', '1/4', '1/2', '3/4', 'Cheio'];

Color corAvaria(String sigla) => switch (sigla) {
      'R' => const Color(0xFFF59E0B),
      'A' => const Color(0xFFEF4444),
      'T' => const Color(0xFF8B5CF6),
      'F' => const Color(0xFFDC2626),
      _ => const Color(0xFF64748B),
    };

/// Avarias de uma posição: {'tipos': ['R','A'], 'obs': '...'}.
/// Só entram no mapa final as posições com ao menos um tipo marcado.
Map<String, dynamic> avariasParaSalvar(Map<String, Map<String, dynamic>> avarias) => {
      for (final e in avarias.entries)
        if (((e.value['tipos'] as List?) ?? const []).isNotEmpty) e.key: e.value,
    };

enum AcaoFoto { avarias, refazer, remover }

/// Menu ao tocar numa foto já tirada.
Future<AcaoFoto?> escolherAcaoFoto(BuildContext context, String posicao, bool temAvaria) {
  return showModalBottomSheet<AcaoFoto>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(posicao,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.report_gmailerrorred_rounded, color: AppColors.warning),
            title: Text(temAvaria ? 'Editar avarias' : 'Marcar avarias',
                style: const TextStyle(color: Colors.white)),
            subtitle: const Text('Risco, amassado, trinca, falta/quebra, outros',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, AcaoFoto.avarias),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: AppColors.secondary),
            title: const Text('Refazer foto', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, AcaoFoto.refazer),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.danger),
            title: const Text('Remover foto', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, AcaoFoto.remover),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Marca as avarias de uma posição. Devolve null se o usuário cancelar.
Future<Map<String, dynamic>?> editarAvarias(
  BuildContext context,
  String posicao,
  Map<String, dynamic>? atual,
) {
  final selecionados = <String>{...((atual?['tipos'] as List?)?.cast<String>() ?? const [])};
  final obsCtrl = TextEditingController(text: atual?['obs']?.toString() ?? '');
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Avarias · $posicao',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Marque tudo o que foi encontrado nesta posição.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kTiposAvaria.entries.map((t) {
                final sel = selecionados.contains(t.key);
                final cor = corAvaria(t.key);
                return FilterChip(
                  selected: sel,
                  onSelected: (v) => setS(() => v ? selecionados.add(t.key) : selecionados.remove(t.key)),
                  label: Text('${t.key} · ${t.value}'),
                  labelStyle: TextStyle(
                      color: sel ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                  selectedColor: cor,
                  checkmarkColor: Colors.white,
                  backgroundColor: AppColors.backgroundSoft,
                  side: BorderSide(color: sel ? cor : AppColors.border),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: obsCtrl,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Observação (opcional)',
                hintText: 'Ex.: risco de 10 cm na porta traseira',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.backgroundSoft,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, <String, dynamic>{'tipos': <String>[], 'obs': ''}),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: const BorderSide(color: AppColors.success),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Sem avarias'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, <String, dynamic>{
                    'tipos': kTiposAvaria.keys.where(selecionados.contains).toList(),
                    'obs': obsCtrl.text.trim(),
                  }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Salvar'),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
}

/// Grade das posições de foto da vistoria, com as avarias marcadas em cada uma.
class VistoriaFotosGrid extends StatelessWidget {
  final Map<String, Uint8List> fotos;
  final Map<String, Map<String, dynamic>> avarias;
  final void Function(String posicao) onTap;

  const VistoriaFotosGrid({
    super.key,
    required this.fotos,
    required this.avarias,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labels = Checklist.fotosObrigatorias;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: labels.length,
      itemBuilder: (context, i) {
        final label = labels[i];
        final bytes = fotos[label];
        final tipos = ((avarias[label]?['tipos'] as List?) ?? const []).cast<String>();
        final temFoto = bytes != null;
        final temAvaria = tipos.isNotEmpty;
        final corBorda = !temFoto
            ? AppColors.border
            : (temAvaria ? AppColors.warning : AppColors.success);

        return GestureDetector(
          onTap: () => onTap(label),
          child: Container(
            decoration: BoxDecoration(
              color: temFoto ? corBorda.withOpacity(0.1) : AppColors.backgroundSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: corBorda, width: temFoto ? 1.5 : 1),
            ),
            child: temFoto
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      ),
                      if (temAvaria)
                        Positioned(
                          top: 4,
                          left: 4,
                          right: 4,
                          child: Wrap(
                            spacing: 3,
                            runSpacing: 3,
                            children: tipos
                                .map((t) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: corAvaria(t),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(t,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800)),
                                    ))
                                .toList(),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                          ),
                          child: Text(label,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo, color: AppColors.textSecondary, size: 20),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(label,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// Legenda das avarias (mostrada abaixo da grade de fotos).
class LegendaAvarias extends StatelessWidget {
  const LegendaAvarias({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        const Text('Toque na foto para marcar avarias:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ...kTiposAvaria.entries.map((t) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: corAvaria(t.key), shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text('${t.key} - ${t.value}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            )),
      ],
    );
  }
}

/// Seletor do nível do tanque (obrigatório na ficha).
class NivelTanqueSelector extends StatelessWidget {
  final String? valor;
  final ValueChanged<String> onChanged;

  const NivelTanqueSelector({super.key, required this.valor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: valor == null ? AppColors.border : AppColors.secondary.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.local_gas_station_outlined, color: AppColors.textSecondary, size: 18),
            SizedBox(width: 8),
            Text('Nível do tanque *',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kNiveisTanque.map((n) {
              final sel = n == valor;
              return ChoiceChip(
                label: Text(n),
                selected: sel,
                onSelected: (_) => onChanged(n),
                selectedColor: AppColors.secondary,
                backgroundColor: AppColors.backgroundSoft,
                labelStyle: TextStyle(
                    color: sel ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12),
                side: BorderSide(color: sel ? AppColors.secondary : AppColors.border),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Campo de texto no mesmo visual dos checklists.
class CampoVistoria extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? hint;

  const CampoVistoria({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

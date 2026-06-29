import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/models/checklist_model.dart';
import '../../core/theme/app_theme.dart';

class ChecklistRetornoPage extends StatefulWidget {
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
  State<ChecklistRetornoPage> createState() => _ChecklistRetornoPageState();
}

class _ChecklistRetornoPageState extends State<ChecklistRetornoPage> {
  final supabase = Supabase.instance.client;
  final imagePicker = ImagePicker();
  final observacoesController = TextEditingController();
  final kmFinalController = TextEditingController();

  late Map<String, bool> itensVerificados;
  final List<Map<String, dynamic>> fotosCapturadas = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    itensVerificados = {for (var item in Checklist.itensChecklist) item: false};
  }

  @override
  void dispose() {
    observacoesController.dispose();
    kmFinalController.dispose();
    super.dispose();
  }

  int get _totalMarcados =>
      itensVerificados.values.where((v) => v).length;

  int get _totalFotos => Checklist.fotosObrigatorias.length;

  Future<void> _capturarFoto(String label) async {
    if (fotosCapturadas.any((f) => f['label'] == label)) {
      setState(() => fotosCapturadas.removeWhere((f) => f['label'] == label));
      return;
    }

    try {
      XFile? img;
      try {
        img = await imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 60,
          maxWidth: 900,
          maxHeight: 700,
        );
      } catch (_) {
        img = await imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 60,
          maxWidth: 900,
          maxHeight: 700,
        );
      }
      if (img != null) {
        final bytes = await img.readAsBytes();
        if (!mounted) return;
        setState(() => fotosCapturadas.add({'bytes': bytes, 'label': label}));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao capturar foto: $e')));
      }
    }
  }

  Future<void> _salvarChecklist() async {
    if (kmFinalController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o KM final do veículo')),
      );
      return;
    }

    if (fotosCapturadas.length < _totalFotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Faltam ${_totalFotos - fotosCapturadas.length} foto(s) obrigatória(s)'),
        ),
      );
      return;
    }

    setState(() => isLoading = true);
    final injetar = context.read<AppAuthProvider>().inject;

    try {
      // Tenta fazer upload das fotos — falha silenciosa se o bucket não existir
      final List<String> fotoUrls = [];
      bool uploadFalhou = false;
      for (int i = 0; i < fotosCapturadas.length; i++) {
        try {
          final Uint8List bytes = fotosCapturadas[i]['bytes'];
          final label = (fotosCapturadas[i]['label'] as String)
              .toLowerCase()
              .replaceAll(' ', '_');
          final fileName =
              'retorno_${widget.veiculoId}_${label}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await supabase.storage.from('checklists').uploadBinary(
                fileName,
                bytes,
                fileOptions: const FileOptions(upsert: true),
              );
          fotoUrls.add(
              supabase.storage.from('checklists').getPublicUrl(fileName));
        } catch (_) {
          uploadFalhou = true;
        }
      }

      await supabase.from('checklists').insert(injetar({
        'veiculo_id': widget.veiculoId,
        'motorista_id': widget.motoristaId,
        'tipo': 'retorno',
        'data': DateTime.now().toIso8601String().split('T')[0],
        'itens': itensVerificados,
        'foto_urls': fotoUrls,
        'aprovado': _totalMarcados == Checklist.itensChecklist.length,
        'km_final': int.tryParse(kmFinalController.text.trim()) ?? 0,
        if (observacoesController.text.trim().isNotEmpty)
          'observacoes': observacoesController.text.trim(),
      }));

      if (!mounted) return;
      if (uploadFalhou) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Checklist salvo! Fotos não foram enviadas (bucket não configurado no Supabase).'),
            backgroundColor: AppColors.warning,
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checklist de retorno registrado!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Retorno · ${widget.veiculoPlaca}'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progresso
            _progressBar(),
            const SizedBox(height: 14),

            // KM Final
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: kmFinalController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'KM Final do Veículo *',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  prefixIcon: Icon(Icons.speed_outlined,
                      color: AppColors.textSecondary, size: 18),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Itens do checklist
            _sectionTitle('Itens do Checklist',
                '$_totalMarcados/${Checklist.itensChecklist.length}',
                AppColors.secondary),
            const SizedBox(height: 8),
            _checklistGrid(),
            const SizedBox(height: 14),

            // Fotos obrigatórias
            _sectionTitle('Fotos Obrigatórias',
                '${fotosCapturadas.length}/$_totalFotos', AppColors.warning),
            const SizedBox(height: 8),
            _fotosGrid(),
            const SizedBox(height: 14),

            // Observações
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: observacoesController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observações (opcional)',
                  hintText: 'Descreva anomalias encontradas...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  prefixIcon: Icon(Icons.notes_outlined,
                      color: AppColors.textSecondary, size: 18),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Botão salvar
            ElevatedButton(
              onPressed: isLoading ? null : _salvarChecklist,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text('Registrar Checklist de Retorno',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar() {
    final itensPct = Checklist.itensChecklist.isEmpty
        ? 0.0
        : _totalMarcados / Checklist.itensChecklist.length;
    final fotosPct =
        _totalFotos == 0 ? 0.0 : fotosCapturadas.length / _totalFotos;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rtl,
                  color: AppColors.secondary, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Itens verificados',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12))),
              Text('$_totalMarcados/${Checklist.itensChecklist.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: itensPct,
              backgroundColor: AppColors.backgroundSoft,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.secondary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.photo_camera,
                  color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Fotos capturadas',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12))),
              Text('${fotosCapturadas.length}/$_totalFotos',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fotosPct,
              backgroundColor: AppColors.backgroundSoft,
              valueColor: const AlwaysStoppedAnimation(AppColors.warning),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String badge, Color color) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(badge,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _checklistGrid() {
    final items = Checklist.itensChecklist;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: List.generate(items.length * 2 - 1, (i) {
          if (i.isOdd) {
            return const Divider(height: 1, thickness: 1, color: AppColors.border);
          }
          final item = items[i ~/ 2];
          final checked = itensVerificados[item] ?? false;
          final isFirst = i == 0;
          final isLast = i == items.length * 2 - 2;
          return InkWell(
            onTap: () => setState(() => itensVerificados[item] = !checked),
            borderRadius: BorderRadius.only(
              topLeft: isFirst ? const Radius.circular(12) : Radius.zero,
              topRight: isFirst ? const Radius.circular(12) : Radius.zero,
              bottomLeft: isLast ? const Radius.circular(12) : Radius.zero,
              bottomRight: isLast ? const Radius.circular(12) : Radius.zero,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: checked
                          ? AppColors.success
                          : AppColors.backgroundSoft,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: checked ? AppColors.success : AppColors.border),
                    ),
                    child: checked
                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item,
                        style: TextStyle(
                            color: checked
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: checked
                                ? FontWeight.w600
                                : FontWeight.normal)),
                  ),
                  if (checked)
                    const Icon(Icons.check_circle,
                        color: AppColors.success, size: 14),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _fotosGrid() {
    final labels = Checklist.fotosObrigatorias;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: labels.length,
      itemBuilder: (context, i) {
        final label = labels[i];
        final foto =
            fotosCapturadas.where((f) => f['label'] == label).firstOrNull;
        final temFoto = foto != null;

        return GestureDetector(
          onTap: () => _capturarFoto(label),
          child: Container(
            decoration: BoxDecoration(
              color: temFoto
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.backgroundSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: temFoto ? AppColors.success : AppColors.border,
                width: temFoto ? 1.5 : 1,
              ),
            ),
            child: temFoto
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.memory(
                          foto['bytes'] as Uint8List,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 3,
                        right: 3,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 10),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 3, horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(9)),
                          ),
                          child: Text(label,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600),
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
                      const Icon(Icons.add_a_photo,
                          color: AppColors.textSecondary, size: 20),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(label,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 9,
                                fontWeight: FontWeight.w500),
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

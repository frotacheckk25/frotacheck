import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/models/veiculo_model.dart';
import '../../core/models/motorista_model.dart';
import '../../core/theme/app_theme.dart';
import './checklist_saida_page.dart';
import './checklist_retorno_page.dart';
import './historico_checklist_page.dart';

class SelecionarVeiculoChecklistPage extends StatefulWidget {
  const SelecionarVeiculoChecklistPage({super.key});

  @override
  State<SelecionarVeiculoChecklistPage> createState() =>
      _SelecionarVeiculoChecklistPageState();
}

class _SelecionarVeiculoChecklistPageState
    extends State<SelecionarVeiculoChecklistPage> {
  final supabase = Supabase.instance.client;

  List<Veiculo> veiculos = [];
  List<Motorista> motoristas = [];
  bool isLoading = true;
  String? erroCarregamento;

  String? veiculoSelecionado;
  String? motoristaSelecionado;
  String tipoChecklist = 'saida';

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() { isLoading = true; erroCarregamento = null; });
    try {
      final auth = context.read<AppAuthProvider>();
      List<Map<String, dynamic>> veiculosResult;
      if (auth.isMotorista && auth.driverId != null) {
        veiculosResult = await supabase
            .from('vehicles')
            .select('id, plate, model')
            .eq('driver_id', auth.driverId!)
            .order('plate');
      } else {
        veiculosResult = await supabase
            .from('vehicles')
            .select('id, plate, model')
            .order('plate');
      }
      final motoristasResult = await supabase.from('drivers').select('id, name').order('name');

      if (!mounted) return;
      setState(() {
        veiculos = List<Map<String, dynamic>>.from(veiculosResult)
            .map((e) => Veiculo.fromMap(e))
            .toList();
        motoristas = List<Map<String, dynamic>>.from(motoristasResult)
            .map((e) => Motorista.fromMap(e))
            .toList();
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          erroCarregamento = e.toString();
          isLoading = false;
        });
      }
    }
  }

  Future<void> _iniciarChecklist() async {
    if (veiculoSelecionado == null || motoristaSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um veículo e um motorista')),
      );
      return;
    }

    final veiculo = veiculos.firstWhere((v) => v.id == veiculoSelecionado);
    if (!mounted) return;

    final page = tipoChecklist == 'saida'
        ? ChecklistSaidaPage(
            veiculoId: veiculoSelecionado!,
            veiculoPlaca: veiculo.placa ?? '',
            motoristaId: motoristaSelecionado!,
          )
        : ChecklistRetornoPage(
            veiculoId: veiculoSelecionado!,
            veiculoPlaca: veiculo.placa ?? '',
            motoristaId: motoristaSelecionado!,
          );

    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Checklist'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Histórico',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const HistoricoChecklistPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : erroCarregamento != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.danger, size: 48),
                        const SizedBox(height: 12),
                        const Text('Erro ao carregar dados',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(erroCarregamento!,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _carregarDados,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0ea5e9), Color(0xFF6366f1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.checklist_rtl, color: Colors.white, size: 28),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Checklist de Veículo',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  Text('Selecione o veículo, motorista e tipo',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Tipo de checklist
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Tipo de Checklist'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _tipoBtn(
                                    'Saída',
                                    Icons.arrow_circle_up_outlined,
                                    'saida',
                                    AppColors.secondary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _tipoBtn(
                                    'Retorno',
                                    Icons.arrow_circle_down_outlined,
                                    'retorno',
                                    AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Veículo
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Veículo *'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: veiculoSelecionado,
                              decoration: _dec('Selecione o veículo',
                                  Icons.directions_car_outlined),
                              dropdownColor: AppColors.surface,
                              style: const TextStyle(color: Colors.white),
                              items: veiculos.map((v) {
                                return DropdownMenuItem(
                                  value: v.id,
                                  child: Text(
                                    '${v.placa ?? ''} — ${v.modelo ?? ''}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) =>
                                  setState(() => veiculoSelecionado = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Motorista
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Motorista *'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: motoristaSelecionado,
                              decoration: _dec('Selecione o motorista',
                                  Icons.person_outline),
                              dropdownColor: AppColors.surface,
                              style: const TextStyle(color: Colors.white),
                              items: motoristas.map((m) {
                                return DropdownMenuItem(
                                  value: m.id,
                                  child: Text(m.nome ?? '-',
                                      style:
                                          const TextStyle(color: Colors.white)),
                                );
                              }).toList(),
                              onChanged: (v) =>
                                  setState(() => motoristaSelecionado = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Botão iniciar
                      ElevatedButton.icon(
                        onPressed: _iniciarChecklist,
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                        label: Text(
                          tipoChecklist == 'saida'
                              ? 'Iniciar Checklist de Saída'
                              : 'Iniciar Checklist de Retorno',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tipoChecklist == 'saida'
                              ? AppColors.secondary
                              : AppColors.success,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4));

  Widget _tipoBtn(String label, IconData icon, String value, Color color) {
    final selected = tipoChecklist == value;
    return GestureDetector(
      onTap: () => setState(() => tipoChecklist = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : AppColors.backgroundSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? color : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : AppColors.textSecondary, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: selected ? color : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
        filled: true,
        fillColor: AppColors.backgroundSoft,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.secondary)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

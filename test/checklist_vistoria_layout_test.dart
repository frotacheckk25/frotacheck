// Garante que o painel de checklist (layout com abas e ícones) monta sem
// estouro de layout em desktop, tablet e celular, e em todas as abas.
// Sem backend: as consultas falham e a tela mostra os estados de erro/vazio.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/core/auth/app_auth_provider.dart';
import 'package:frotacheck/home/checklists/checklist_vistoria_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://teste.supabase.co',
      publishableKey: 'sb_publishable_teste',
      authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage()),
    );
  });

  const tamanhos = {
    'desktop': Size(1600, 900),
    'tablet': Size(900, 1100),
    'celular': Size(390, 844),
  };

  for (final tipo in ['saida', 'retorno']) {
    for (final t in tamanhos.entries) {
      testWidgets('checklist $tipo sem overflow — ${t.key}', (tester) async {
        tester.view.physicalSize = t.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => AppAuthProvider(),
            child: MaterialApp(
              theme: ThemeData.dark(),
              home: ChecklistVistoriaPage(
                tipo: tipo,
                veiculoId: 'v1',
                veiculoPlaca: 'ABC-4455',
                motoristaId: 'm1',
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        Future<void> abrirAba(String nome) async {
          await tester.tap(find.byKey(ValueKey('aba-$nome')));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 400));
        }

        // Percorre as 4 abas.
        for (final aba in ['Checklist', 'Veículo', 'Fotos', 'Observações']) {
          await abrirAba(aba);
          expect(tester.takeException(), isNull, reason: 'aba $aba em ${t.key}');
        }

        // Volta ao Checklist, marca um item e confere o contador.
        await abrirAba('Checklist');
        expect(find.text('0/5'), findsOneWidget);
        await tester.ensureVisible(find.text('Macaco').last);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Macaco').last);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('1/5'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

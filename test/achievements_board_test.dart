import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:othli_front/screens/achievements/achievements_page.dart';

import 'fixtures/achievements_fixture.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final size in const [Size(375, 900), Size(1400, 1000)]) {
    testWidgets('la vitrina de Logros se ve sin desbordes en ${size.width.toInt()} px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AchievementsBoard(
            titles: kDemoTitles,
            owned: kDemoOwned,
            activeId: 'altepetlahtolli',
            log: kDemoLog,
            progress: kDemoProgress,
            totalUsers: 13,
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Logros'), findsOneWidget);
      // Título, significado en náhuatl y cómo se consigue
      expect(find.text('Pochtecatl'), findsWidgets);
      expect(find.text('«El comerciante viajero»'), findsWidgets);
      expect(find.text('Completa 10 viajes.'), findsWidgets);
      // Cuándo y cuánto tardó, y rareza
      expect(find.textContaining('Lo conseguiste el 24 oct 2026'), findsWidgets);
      expect(find.textContaining('te tomó 3 semanas'), findsWidgets);
      expect(find.text('Raro'), findsWidgets);
    });
  }

  testWidgets('por rareza agrupa en niveles de rareza', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AchievementsBoard(
          titles: kDemoTitles,
          owned: kDemoOwned,
          activeId: 'viajero',
          log: kDemoLog,
          progress: kDemoProgress,
          totalUsers: 13,
        ),
      ),
    ));
    await tester.tap(find.text('Por rareza'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('LEGENDARIO'), findsOneWidget);
    expect(find.text('Casi nadie los tiene'), findsOneWidget);
  });
}

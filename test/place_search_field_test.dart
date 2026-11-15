import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/widgets/ohtli_service_icon.dart';
import 'package:othli_front/widgets/ohtli_ui.dart';
import 'package:othli_front/widgets/place_search_field.dart';

/// El paso "¿Desde dónde inicia tu recorrido?" pone el buscador y las tarjetas dentro de un
/// IntrinsicHeight para dibujar la línea lateral del punto 1 al 2: todo debe medirse sin errores.
void main() {
  testWidgets('buscador y tarjetas se dibujan junto a la línea lateral', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    String? cleared;

    Widget point(String title) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 30,
                child: Column(children: [
                  const Icon(Icons.trip_origin_rounded),
                  Expanded(child: Container(width: 2, color: Colors.teal)),
                ]),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title),
                    PlaceSearchField(
                      controller: controller,
                      onSelected: (_, _, _) {},
                      onCleared: () => cleared = title,
                    ),
                    SizedBox(
                      height: 62,
                      child: Row(children: [
                        Expanded(
                          child: OhtliSurface(
                            onTap: () {},
                            child: Row(children: const [
                              SizedBox(
                                  width: 38,
                                  height: 38,
                                  child: FittedBox(child: OhtliServiceIcon(icon: Icons.home_rounded, color: Colors.teal, size: 44))),
                              Text('Zócalo'),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: Column(children: [point('1 · INICIO'), point('2 · FINAL')])),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Zócalo'), findsNWidgets(2));

    // Escribir y borrar no rompe el diseño (fuera de web no hay sugerencias).
    await tester.enterText(find.byType(TextField).first, 'Coyoacán');
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Borrar').first);
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(cleared, isNotNull);
  });
}

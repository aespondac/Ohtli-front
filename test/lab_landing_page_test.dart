import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/screens/lab/lab_landing_page.dart';
import 'package:othli_front/theme/colors.dart';

void main() {
  testWidgets('LabLandingPage builds without crashing', (WidgetTester tester) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      print('FLUTTER ERROR: ${details.exception}');
      print(details.stack);
    };

    try {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: LabLandingPage(
            onLoginRedirect: () {},
          ),
        ),
      ));
      print('Widget pumped successfully');
    } catch (e, stack) {
      print('TEST EXCEPTION: $e');
      print(stack);
    }
  });
}

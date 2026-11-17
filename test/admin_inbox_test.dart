import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/admin_inbox.dart';

void main() {
  test('las tres secciones avisan por correo salvo que se apaguen', () {
    expect(AdminInbox.emailFlagsOf(null).values, everyElement(isTrue));
    final flags = AdminInbox.emailFlagsOf({'reports': false, 'feedback': true});
    expect(flags[AdminInboxSection.donations], isTrue);
    expect(flags[AdminInboxSection.reports], isFalse);
    expect(flags[AdminInboxSection.feedback], isTrue);
  });

  test('las llaves son las que lee functions/feedback.js', () {
    expect([for (final s in AdminInboxSection.values) s.key], ['donations', 'reports', 'feedback']);
    expect([for (final s in AdminInboxSection.values) s.label], ['Donaciones', 'Reportes', 'Comentarios']);
  });
}

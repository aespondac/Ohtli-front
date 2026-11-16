import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/itinerary_blackboard_service.dart';
import 'package:othli_front/services/public_profiles.dart';
import 'package:othli_front/services/social_graph.dart';
import 'package:othli_front/services/user_private_data.dart';

void main() {
  group('PublicProfiles', () {
    test('solo copia los campos de presentación', () {
      final visible = PublicProfiles.pick({
        'displayName': 'Ana',
        'photoURL': 'https://x/y.jpg',
        'usertag': 'ana',
        'activeTitleId': 'viajero',
        'profilePrivate': false,
        'phone': '5555555555',
        'addresses': [
          {'street': 'Calle 1'},
        ],
        'taste_vector': [0.1, 0.2],
        'friends': ['b'],
        'deletedAt': 'x',
        'onboarding_completed': true,
      });
      expect(visible.keys, unorderedEquals(['displayName', 'photoURL', 'usertag', 'activeTitleId', 'profilePrivate']));
    });

    test('ningún dato privado ni lista social puede llegar al perfil visible', () {
      for (final f in [...UserPrivateData.fields.where((f) => f != 'isDeleted'), ...SocialGraph.graphFields, ...SocialGraph.closeFields]) {
        expect(PublicProfiles.fields.contains(f), isFalse, reason: f);
      }
    });
  });

  test('si el motor no responde, el error lleva el mensaje para el usuario (sin itinerario simulado)', () {
    const e = ItineraryApiUnavailableException('job_1');
    expect(e.jobId, 'job_1');
    expect(e.toString(), ItineraryBlackboardService.apiUnavailableMessage);
  });
}

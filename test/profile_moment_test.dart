import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/profile_moment.dart';
import 'package:othli_front/models/trip_model.dart';

void main() {
  test('momento ida y vuelta desde el documento del perfil', () {
    final m = ProfileMoment(url: 'https://x/a.jpg', tripId: 't1', tripTitle: 'Coyoacán', caption: 'Mercado', date: DateTime(2026, 11, 3));
    final back = ProfileMoment.listFrom([m.toMap()]).single;
    expect(back.url, m.url);
    expect(back.tripId, 't1');
    expect(back.caption, 'Mercado');
    expect(back.date, DateTime(2026, 11, 3));
  });

  test('listFrom ignora entradas rotas y respeta el máximo', () {
    final raw = [
      'basura',
      {'url': '', 'tripId': 't'},
      for (var i = 0; i < 20; i++) {'url': 'https://x/$i.jpg', 'tripId': 't$i'},
    ];
    final list = ProfileMoment.listFrom(raw);
    expect(list.length, ProfileMoment.maxMoments);
    expect(list.first.url, 'https://x/0.jpg');
    expect(ProfileMoment.listFrom(null), isEmpty);
  });

  test('candidatos: portada, fotos de paradas e imágenes, sin repetir ni data:', () {
    final trip = Trip.fromMap({'title': 'Centro', 'coverUrl': 'https://x/cover.jpg', 'userId': 'u'}, 't');
    final content = TripContent(sections: [
      PlaceSection(
        id: 'p1',
        title: 'Bellas Artes',
        description: '',
        rating: 5,
        mainPhotoUrl: 'https://x/ba.jpg',
        secondaryPhotoUrls: ['https://x/ba2.jpg', 'https://x/cover.jpg', 'data:image/png;base64,AAA'],
      ),
      TextImageSection(id: 'ti', markdownText: '', imageUrl: 'https://x/nota.jpg', layout: 'left'),
    ]);
    final c = momentCandidates(trip, content);
    expect(c.map((e) => e.url), ['https://x/cover.jpg', 'https://x/ba.jpg', 'https://x/ba2.jpg', 'https://x/nota.jpg']);
    expect(c[1].caption, 'Bellas Artes');
  });
}

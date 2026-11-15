import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/section_merge.dart';

PlaceSection place(String id, {String title = '', String photo = '', String? tag}) => PlaceSection(
      id: id,
      title: title,
      description: '',
      rating: 0,
      mainPhotoUrl: photo,
      secondaryPhotoUrls: const ['', ''],
      changeTag: tag,
    );

void main() {
  test('lo editado mientras se guardaba no se pierde', () {
    final before = [place('a'), TextSection(id: 't', markdownText: 'hola')];
    final uploaded = List<TripSection>.of(before);
    // Durante el guardado se escribió un título, se cambió el texto y se agregó un bloque.
    final current = [place('a', title: 'Explora', tag: 'mejora'), TextSection(id: 't', markdownText: 'hola de nuevo'), place('b', title: 'Nuevo')];
    final merged = mergeUploadedPhotos(current, before, uploaded);
    expect((merged[0] as PlaceSection).title, 'Explora');
    expect((merged[0] as PlaceSection).changeTag, 'mejora');
    expect((merged[1] as TextSection).markdownText, 'hola de nuevo');
    expect(merged.length, 3);
  });

  test('la foto subida reemplaza a la local si no cambió', () {
    final before = [place('a', photo: 'data:image/png;base64,AAA')];
    final uploaded = [place('a', photo: 'https://storage/a.jpg')];
    final current = [place('a', title: 'Con título', photo: 'data:image/png;base64,AAA')];
    final merged = mergeUploadedPhotos(current, before, uploaded).first as PlaceSection;
    expect(merged.mainPhotoUrl, 'https://storage/a.jpg');
    expect(merged.title, 'Con título');
  });

  test('una foto cambiada durante el guardado se respeta', () {
    final before = [place('a', photo: 'data:image/png;base64,AAA')];
    final uploaded = [place('a', photo: 'https://storage/a.jpg')];
    final current = [place('a', photo: 'data:image/png;base64,BBB')];
    final merged = mergeUploadedPhotos(current, before, uploaded).first as PlaceSection;
    expect(merged.mainPhotoUrl, 'data:image/png;base64,BBB');
  });

  test('texto con imagen: conserva el texto nuevo y toma la URL subida', () {
    final before = [TextImageSection(id: 'i', markdownText: 'a', imageUrl: 'data:x', layout: 'left')];
    final uploaded = [TextImageSection(id: 'i', markdownText: 'a', imageUrl: 'https://storage/i.jpg', layout: 'left')];
    final current = [TextImageSection(id: 'i', markdownText: 'a y b', imageUrl: 'data:x', layout: 'right')];
    final merged = mergeUploadedPhotos(current, before, uploaded).first as TextImageSection;
    expect(merged.imageUrl, 'https://storage/i.jpg');
    expect(merged.markdownText, 'a y b');
    expect(merged.layout, 'right');
  });
}

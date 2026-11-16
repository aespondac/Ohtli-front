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

  group('merge a 3 vías (edición en vivo)', () {
    TextSection text(String id, String md) => TextSection(id: id, markdownText: md);
    List<String> ids(List<TripSection> xs) => [for (final s in xs) s.id];
    String md(TripSection s) => (s as TextSection).markdownText;

    test('lo que cambió otro y yo no toqué, entra', () {
      final base = [place('a', title: 'Museo'), text('t', 'hola')];
      final local = List<TripSection>.of(base);
      final remote = [place('a', title: 'Museo Frida'), text('t', 'hola')];
      final m = mergeSections(base, local, remote);
      expect((m.sections[0] as PlaceSection).title, 'Museo Frida');
      expect(m.changedIds, {'a'});
      expect(m.conflicts, isEmpty);
    });

    test('lo que yo edité se queda y lo del otro en otro campo también entra', () {
      final base = [place('a', title: 'Museo')];
      final local = [place('a', title: 'Museo', photo: 'https://x/mia.jpg')];
      final remote = [place('a', title: 'Museo Frida')];
      final m = mergeSections(base, local, remote).sections.single as PlaceSection;
      expect(m.title, 'Museo Frida');
      expect(m.mainPhotoUrl, 'https://x/mia.jpg');
    });

    test('mis cambios sin conflicto no se marcan', () {
      final base = [text('t', 'hola')];
      final m = mergeSections(base, [text('t', 'hola mundo')], base);
      expect(md(m.sections.single), 'hola mundo');
      expect(m.changedIds, isEmpty);
      expect(m.conflicts, isEmpty);
      expect(m.touchesLocal, isFalse);
    });

    test('dos ediciones en partes distintas del mismo texto se combinan', () {
      final base = [text('t', 'Llegamos al Zócalo. Comimos tacos.')];
      final local = [text('t', 'Llegamos temprano al Zócalo. Comimos tacos.')];
      final remote = [text('t', 'Llegamos al Zócalo. Comimos tacos de canasta.')];
      final m = mergeSections(base, local, remote);
      expect(md(m.sections.single), 'Llegamos temprano al Zócalo. Comimos tacos de canasta.');
      expect(m.conflicts, isEmpty);
    });

    test('conflicto en el mismo bloque: gana lo local y queda marcado', () {
      final base = [text('t', 'Comimos tacos.')];
      final local = [text('t', 'Comimos pozole.')];
      final remote = [text('t', 'Comimos tamales.')];
      final m = mergeSections(base, local, remote);
      expect(md(m.sections.single), 'Comimos pozole.');
      expect(m.conflicts.keys, ['t']);
      expect(md(m.conflicts['t']!), 'Comimos tamales.');
    });

    test('conflicto en un campo que no es texto: gana lo local', () {
      final base = [place('a', photo: '')];
      final local = [place('a', photo: 'https://x/mia.jpg')];
      final remote = [place('a', photo: 'https://x/suya.jpg')];
      final m = mergeSections(base, local, remote);
      expect((m.sections.single as PlaceSection).mainPhotoUrl, 'https://x/mia.jpg');
      expect(m.conflicts.containsKey('a'), isTrue);
    });

    test('los bloques nuevos del otro entran en su posición relativa', () {
      final base = [text('a', '1'), text('b', '2'), text('c', '3')];
      final local = List<TripSection>.of(base);
      final remote = [text('a', '1'), text('n1', 'nuevo'), text('n2', 'otro'), text('b', '2'), text('c', '3'), text('z', 'fin')];
      final m = mergeSections(base, local, remote);
      expect(ids(m.sections), ['a', 'n1', 'n2', 'b', 'c', 'z']);
      expect(m.changedIds, {'n1', 'n2', 'z'});
    });

    test('mis bloques nuevos y los suyos conviven', () {
      final base = [text('a', '1'), text('b', '2')];
      final local = [text('a', '1'), text('mio', 'yo'), text('b', '2')];
      final remote = [text('a', '1'), text('b', '2'), text('suyo', 'otro')];
      expect(ids(mergeSections(base, local, remote).sections), ['a', 'mio', 'b', 'suyo']);
      // Un bloque nuevo al principio, antes del primero que ya existía.
      final remote2 = [text('suyo', 'otro'), text('a', '1'), text('b', '2')];
      expect(ids(mergeSections(base, local, remote2).sections), ['suyo', 'a', 'mio', 'b']);
    });

    test('un borrado remoto de algo que no toqué se quita', () {
      final base = [text('a', '1'), text('b', '2')];
      final m = mergeSections(base, List<TripSection>.of(base), [text('a', '1')]);
      expect(ids(m.sections), ['a']);
      expect(m.removedIds, {'b'});
    });

    test('un borrado remoto de algo que edité se queda y se marca', () {
      final base = [text('a', '1'), text('b', '2')];
      final m = mergeSections(base, [text('a', '1'), text('b', '2 y más')], [text('a', '1')]);
      expect(ids(m.sections), ['a', 'b']);
      expect(m.conflicts.containsKey('b'), isTrue);
      expect(m.conflicts['b'], isNull);
    });

    test('lo que borré aquí se queda borrado aunque el otro lo haya cambiado (y se avisa)', () {
      final base = [text('a', '1'), text('b', '2')];
      final m = mergeSections(base, [text('a', '1')], [text('a', '1'), text('b', '2 cambiado')]);
      expect(ids(m.sections), ['a']);
      expect(md(m.deletedHereChangedThere['b']!), '2 cambiado');
      // Si el otro no lo había cambiado, no hay aviso.
      expect(mergeSections(base, [text('a', '1')], base).deletedHereChangedThere, isEmpty);
    });

    test('si solo el otro reordenó, se toma su orden; si reordené yo, el mío', () {
      final base = [text('a', '1'), text('b', '2'), text('c', '3')];
      final reorderedThere = [text('c', '3'), text('a', '1'), text('b', '2')];
      final m = mergeSections(base, List<TripSection>.of(base), reorderedThere);
      expect(ids(m.sections), ['c', 'a', 'b']);
      expect(m.reordered, isTrue);
      final mine = [text('b', '2'), text('a', '1'), text('c', '3')];
      expect(ids(mergeSections(base, mine, reorderedThere).sections), ['b', 'a', 'c']);
      // Yo agregué un bloque y el otro reordenó: entra mi bloque junto a su vecino.
      final withNew = [text('a', '1'), text('mio', 'x'), text('b', '2'), text('c', '3')];
      expect(ids(mergeSections(base, withNew, reorderedThere).sections), ['c', 'a', 'mio', 'b']);
    });

    test('es idempotente: combinar con lo mismo no cambia nada', () {
      final base = [place('a', title: 'Museo'), text('t', 'hola')];
      final local = [place('a', title: 'Museo Frida'), text('t', 'hola')];
      final m = mergeSections(base, local, base);
      expect(m.touchesLocal, isFalse);
      expect(identical(m.sections[0], local[0]), isTrue);
      final again = mergeSections(local, local, local);
      expect(again.touchesLocal, isFalse);
    });

    test('cambio de tipo de bloque: entra entero si yo no lo toqué', () {
      final base = [text('t', 'hola')];
      final remote = [TextImageSection(id: 't', markdownText: 'hola', imageUrl: '', layout: 'left')];
      final m = mergeSections(base, List<TripSection>.of(base), remote);
      expect(m.sections.single, isA<TextImageSection>());
    });

    test('bloques de tipos desconocidos se conservan', () {
      final base = [UnknownSection({'id': 'v', 'type': 'vote', 'votes': {'ana': 'si'}})];
      final local = [UnknownSection({'id': 'v', 'type': 'vote', 'votes': {'ana': 'si', 'yo': 'no'}})];
      final remote = [UnknownSection({'id': 'v', 'type': 'vote', 'votes': {'ana': 'si', 'luis': 'si'}})];
      final m = mergeSections(base, local, remote);
      // Los mapas anidados se combinan llave por llave: los dos votos se quedan.
      expect((m.sections.single as UnknownSection).raw['votes'], {'ana': 'si', 'yo': 'no', 'luis': 'si'});
      expect(m.conflicts, isEmpty);
    });
  });

  group('mergeText', () {
    test('mismo punto: se quedan las dos inserciones', () {
      expect(mergeText('ab', 'aXb', 'aYb').text, 'aXYb');
      expect(mergeText('ab', 'aXb', 'aXb').text, 'aXb');
    });
    test('ediciones que se enciman: conflicto', () {
      final r = mergeText('el museo abre', 'el museo cierra', 'el museo abrió');
      expect(r.conflict, isTrue);
      expect(r.text, 'el museo cierra');
    });
    test('ediciones cercanas que no se enciman: se quedan las dos', () {
      expect(mergeText('el museo abre', 'el gran museo abre', 'el museo abre tarde').text, 'el gran museo abre tarde');
    });
    test('borrar y escribir en otro lado', () {
      expect(mergeText('uno dos tres', 'uno tres', 'uno dos tres cuatro').text, 'uno tres cuatro');
    });
  });

  group('mapTextOffset', () {
    test('el cursor se mueve con lo que otro escribió antes', () {
      // Cursor después de "hola" (4); otro escribió "¡" al principio.
      expect(mapTextOffset('hola mundo', '¡hola mundo', 4), 5);
      // Lo que se escribe después del cursor no lo mueve.
      expect(mapTextOffset('hola mundo', 'hola mundo!', 4), 4);
      // Borraron texto antes del cursor.
      expect(mapTextOffset('hola gran mundo', 'hola mundo', 12), 7);
    });
  });

  group('fotos que quitó este editor', () {
    test('solo las que estaban en lo sincronizado y ya no están aquí ni en la nube', () {
      final base = [place('a', photo: 'https://s/a_main_1.jpg'), place('b', photo: 'https://s/b_main_1.jpg')];
      // Quité la foto de "a"; el otro agregó "c" con una foto que yo no conocía.
      final local = [place('a'), place('b', photo: 'https://s/b_main_1.jpg')];
      final written = [place('a'), place('b', photo: 'https://s/b_main_1.jpg'), place('c', photo: 'https://s/c_main_9.jpg')];
      expect(photosRemovedHere(base: base, local: local, written: written), {'https://s/a_main_1.jpg'});
    });
    test('si la nube todavía la usa (otro la puso en otro bloque), no se borra', () {
      final base = [place('a', photo: 'https://s/x.jpg')];
      final local = [place('a')];
      final written = [place('a'), place('b', photo: 'https://s/x.jpg')];
      expect(photosRemovedHere(base: base, local: local, written: written), isEmpty);
    });
    test('las fotos que solo conoce el otro nunca se borran', () {
      final base = [place('a')];
      final local = [place('a')];
      final written = [place('a', photo: 'https://s/suya.jpg')];
      expect(photosRemovedHere(base: base, local: local, written: written), isEmpty);
    });
  });
}

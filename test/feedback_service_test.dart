import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/feedback_service.dart';

void main() {
  test('stopIds toma los poi_id de la ruta sin repetir', () {
    final ids = FeedbackService.stopIds({
      'route': [
        {'poi_id': 'osm_1'},
        {'poiId': 'osm_2'},
        {'poi_id': 'osm_1'},
        {'name': 'sin id'},
      ],
    });
    expect(ids, ['osm_1', 'osm_2']);
  });

  test('el viaje recuerda qué paradas propuso el motor', () {
    final trip = Trip.fromMap({
      'title': 'Ruta',
      'createdAt': Timestamp.now(),
      'recommendation': {'poi_ids': ['osm_1', 'osm_2'], 'job_id': 'job_x'},
    }, 't1');
    expect(trip.recommendedPoiIds, ['osm_1', 'osm_2']);
    expect(trip.recommendationJobId, 'job_x');
    expect(Trip.fromMap({'title': 'Manual'}, 't2').recommendedPoiIds, isEmpty);
  });

  test('describeBrowser resume el navegador sin la cadena completa', () {
    expect(
      FeedbackService.describeBrowser(
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36'),
      'Chrome · macOS',
    );
    expect(
      FeedbackService.describeBrowser(
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'),
      'Safari · iOS',
    );
    expect(
      FeedbackService.describeBrowser('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36 Edg/131.0'),
      'Edge · Windows',
    );
    expect(FeedbackService.describeBrowser('Mozilla/5.0 (Android 14; Mobile; rv:132.0) Gecko/132.0 Firefox/132.0'), 'Firefox · Android');
  });

  test('buildComment recorta, valida la categoría y solo guarda campos permitidos', () {
    final doc = FeedbackService.buildComment(
      uid: 'u1',
      message: '  ${'a' * 2500}  ',
      category: 'no-existe',
      screen: 'planear_con_ia',
      browser: 'Chrome · macOS',
      context: {for (var i = 0; i < 12; i++) 'k$i': 'v$i', 'vacío': ''},
      createdAt: 'ahora',
    );
    expect((doc['message'] as String).length, FeedbackService.commentMaxLength);
    expect(doc['category'], 'other');
    expect(doc['uid'], 'u1');
    expect((doc['context'] as Map).length, 8);
    expect(doc.containsKey('viewport'), isFalse);
    // Los mismos campos que acepta firestore.rules en app_feedback
    const allowed = {
      'uid', 'message', 'category', 'screen', 'appVersion', 'browser', 'viewport', 'language', 'context', 'device',
      'system', 'user', 'errors', 'screenshots', 'status', 'createdAt',
    };
    expect(allowed.containsAll(doc.keys), isTrue);
  });

  test('buildComment con dispositivo, sistema, cuenta, errores y capturas', () {
    final doc = FeedbackService.buildComment(
      uid: 'u1',
      message: 'Falla el mapa',
      category: 'bug',
      screen: 'planear_con_ia',
      device: {for (var i = 0; i < 30; i++) 'k$i': 'v$i'},
      system: {'version': '1.1.0', 'tema': 'oscuro'},
      user: {'uid': 'otro', 'nombre': 'Ana', 'correo': 'ana@correo.test'},
      errors: [for (var i = 0; i < 14; i++) {'message': 'e$i'}],
      screenshots: ['a.png', 'b.png', 'c.png', 'd.png'],
      createdAt: 'ahora',
    );
    expect(doc['status'], FeedbackService.statusNew);
    expect((doc['device'] as Map).length, 20);
    expect((doc['user'] as Map)['uid'], 'u1', reason: 'el uid de la cuenta no se puede cambiar');
    final errors = doc['errors'] as List;
    expect(errors.length, 10);
    expect((errors.last as Map)['message'], 'e13', reason: 'se quedan los más recientes');
    expect(doc['screenshots'], ['a.png', 'b.png', 'c.png']);
  });

  test('AppFeedback lee comentarios nuevos y viejos', () {
    final viejo = AppFeedback.fromMap('f1', {
      'uid': 'u1',
      'message': 'hola',
      'category': 'idea',
      'browser': 'Chrome · macOS',
      'viewport': '1200x800',
    });
    expect(viejo.isNew, isTrue);
    expect(viejo.device['navegador'], 'Chrome · macOS');
    expect(viejo.user['uid'], 'u1');
    expect(viejo.userName, 'Viajero Ohtli');

    final nuevo = AppFeedback.fromMap('f2', {
      'uid': 'u2',
      'message': 'falla',
      'category': 'bug',
      'status': 'resolved',
      'user': {'nombre': 'Ana', 'correo': 'ana@correo.test'},
      'device': {'navegador': 'Safari · iOS'},
      'errors': [
        {'message': 'boom', 'where': 'widgets'},
      ],
      'screenshots': ['app_feedback/u2/f2/1.png'],
    });
    expect(nuevo.isNew, isFalse);
    expect(nuevo.userName, 'Ana');
    expect(nuevo.errors.single['message'], 'boom');
    expect(nuevo.screenshots.single, 'app_feedback/u2/f2/1.png');
  });

  test('FeedbackAttachment usa la extensión del tipo de imagen', () {
    expect(FeedbackAttachment(Uint8List(1), 'image/png').extension, 'png');
    expect(FeedbackAttachment(Uint8List(1), 'image/jpeg').extension, 'jpg');
    expect(FeedbackAttachment(Uint8List(1), 'image/webp').extension, 'webp');
  });
}

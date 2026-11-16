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
}

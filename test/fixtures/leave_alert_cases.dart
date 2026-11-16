// Casos compartidos del aviso «hora de salir» del modo viaje. Los usan las dos implementaciones:
//  - test/trip_follow_leave_alert_test.dart (lib/services/trip_follow.dart, la app)
//  - functions/test/trip_follow.test.js (functions/trip_follow.js, el servidor)
// Si cambias el cálculo o el texto en un lado, cámbialo en el otro y actualiza estos casos.
// El JSON va en la cadena cruda de abajo (functions/test lo extrae de ahí).
const String leaveAlertCasesJson = r'''
[
  {
    "name": "a pie con coordenadas, aviso pronto",
    "now": "11:41",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Bellas Artes",
        "lat": 19.4352,
        "lng": -99.1412,
        "arrivalTime": "10:00",
        "departureTime": "11:30",
        "arrivedAt": "10:05"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "walking",
        "durationMins": 10
      },
      {
        "id": "b",
        "type": "place",
        "title": "Zócalo",
        "lat": 19.4326,
        "lng": -99.1332,
        "arrivalTime": "12:00",
        "departureTime": "13:00"
      }
    ],
    "expected": {
      "alert": "soon",
      "stopId": "a",
      "nextId": "b",
      "leaveBy": "11:45",
      "travelMins": 15,
      "title": "Sal en 4 min de Bellas Artes",
      "body": "Para llegar a Zócalo a las 12:00 (unos 15 min a pie)."
    }
  },
  {
    "name": "metro: manda el traslado planeado si es más largo",
    "now": "12:30",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Zócalo",
        "lat": 19.4326,
        "lng": -99.1332,
        "arrivalTime": "11:00",
        "departureTime": "12:30",
        "arrivedAt": "11:02"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "metro",
        "durationMins": 30
      },
      {
        "id": "b",
        "type": "place",
        "title": "Castillo de Chapultepec",
        "lat": 19.4204,
        "lng": -99.1819,
        "arrivalTime": "13:00"
      }
    ],
    "expected": {
      "alert": "now",
      "stopId": "a",
      "nextId": "b",
      "leaveBy": "12:30",
      "travelMins": 30,
      "title": "Es hora de salir de Zócalo",
      "body": "Para llegar a Castillo de Chapultepec a las 13:00 (unos 30 min en metro)."
    }
  },
  {
    "name": "última parada: salida planeada",
    "now": "14:52",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Coyoacán",
        "arrivalTime": "13:00",
        "departureTime": "15:00",
        "arrivedAt": "13:10"
      }
    ],
    "expected": {
      "alert": "soon",
      "stopId": "a",
      "nextId": null,
      "leaveBy": "15:00",
      "travelMins": null,
      "title": "Sal en 8 min de Coyoacán",
      "body": "El plan era salir a las 15:00."
    }
  },
  {
    "name": "siguiente sin hora: salida planeada rumbo a ella",
    "now": "13:05",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Mercado",
        "departureTime": "13:00",
        "arrivedAt": "12:00"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "bus",
        "durationMins": 20
      },
      {
        "id": "b",
        "type": "place",
        "title": "Museo"
      }
    ],
    "expected": {
      "alert": "now",
      "stopId": "a",
      "nextId": "b",
      "leaveBy": "13:00",
      "travelMins": 20,
      "title": "Es hora de salir de Mercado",
      "body": "El plan era salir a las 13:00 rumbo a Museo."
    }
  },
  {
    "name": "muy temprano: nada",
    "now": "10:00",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Bellas Artes",
        "lat": 19.4352,
        "lng": -99.1412,
        "arrivalTime": "10:00",
        "arrivedAt": "10:05"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "walking",
        "durationMins": 10
      },
      {
        "id": "b",
        "type": "place",
        "title": "Zócalo",
        "lat": 19.4326,
        "lng": -99.1332,
        "arrivalTime": "12:00"
      }
    ],
    "expected": null
  },
  {
    "name": "ya muy tarde: nada",
    "now": "12:10",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Bellas Artes",
        "lat": 19.4352,
        "lng": -99.1412,
        "arrivalTime": "10:00",
        "arrivedAt": "10:05"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "walking",
        "durationMins": 10
      },
      {
        "id": "b",
        "type": "place",
        "title": "Zócalo",
        "lat": 19.4326,
        "lng": -99.1332,
        "arrivalTime": "12:00"
      }
    ],
    "expected": null
  },
  {
    "name": "sin coordenadas: el traslado escrito",
    "now": "18:10",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Cantina",
        "arrivalTime": "17:00",
        "arrivedAt": "17:00"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "taxi",
        "durationMins": 12
      },
      {
        "id": "b",
        "type": "place",
        "title": "Teatro",
        "arrivalTime": "18:30"
      }
    ],
    "expected": {
      "alert": "soon",
      "stopId": "a",
      "nextId": "b",
      "leaveBy": "18:18",
      "travelMins": 12,
      "title": "Sal en 8 min de Cantina",
      "body": "Para llegar a Teatro a las 18:30 (unos 12 min en taxi)."
    }
  },
  {
    "name": "parada sin nombre y segundos en la hora",
    "now": "18:10:30",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "  ",
        "arrivalTime": "17:00",
        "arrivedAt": "17:00"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "other",
        "durationMins": 12
      },
      {
        "id": "b",
        "type": "place",
        "title": "",
        "arrivalTime": "18:30"
      }
    ],
    "expected": {
      "alert": "soon",
      "stopId": "a",
      "nextId": "b",
      "leaveBy": "18:18",
      "travelMins": 12,
      "title": "Sal en 8 min de esta parada",
      "body": "Para llegar a la siguiente parada a las 18:30 (unos 12 min)."
    }
  },
  {
    "name": "ya salieron de todas: nada",
    "now": "11:55",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Bellas Artes",
        "lat": 19.4352,
        "lng": -99.1412,
        "arrivalTime": "10:00",
        "arrivedAt": "10:05",
        "leftAt": "11:50"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "walking",
        "durationMins": 10
      },
      {
        "id": "b",
        "type": "place",
        "title": "Zócalo",
        "lat": 19.4326,
        "lng": -99.1332,
        "arrivalTime": "12:00"
      }
    ],
    "expected": null
  },
  {
    "name": "la abierta es la última con llegada; la siguiente pendiente",
    "now": "15:50",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Desayuno",
        "arrivalTime": "09:00",
        "arrivedAt": "09:00",
        "leftAt": "10:00"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "walking",
        "durationMins": 5
      },
      {
        "id": "b",
        "type": "place",
        "title": "Museo",
        "arrivalTime": "10:05",
        "departureTime": "12:00",
        "arrivedAt": "10:10"
      },
      {
        "id": "n1",
        "type": "text",
        "text": "nota"
      },
      {
        "id": "t2",
        "type": "transfer",
        "mode": "metrobus",
        "durationMins": 25
      },
      {
        "id": "c",
        "type": "place",
        "title": "Comida",
        "arrivalTime": "16:00",
        "location": {
          "lat": 19.43,
          "lng": -99.16
        }
      }
    ],
    "expected": {
      "alert": "now",
      "stopId": "b",
      "nextId": "c",
      "leaveBy": "15:35",
      "travelMins": 25,
      "title": "Es hora de salir de Museo",
      "body": "Para llegar a Comida a las 16:00 (unos 25 min en metrobús)."
    }
  },
  {
    "name": "cruza la medianoche hacia atrás",
    "now": "00:05",
    "sections": [
      {
        "id": "a",
        "type": "place",
        "title": "Fiesta",
        "arrivalTime": "00:00",
        "arrivedAt": "00:00"
      },
      {
        "id": "t1",
        "type": "transfer",
        "mode": "walking",
        "durationMins": 20
      },
      {
        "id": "b",
        "type": "place",
        "title": "Casa",
        "arrivalTime": "00:15"
      }
    ],
    "expected": {
      "alert": "now",
      "stopId": "a",
      "nextId": "b",
      "leaveBy": "23:55",
      "travelMins": 20,
      "title": "Es hora de salir de Fiesta",
      "body": "Para llegar a Casa a las 00:15 (unos 20 min a pie)."
    }
  }
]

''';

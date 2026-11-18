import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:othli_front/services/achievements_service.dart';

/// Datos de ejemplo de la vitrina de Logros (pruebas y demo local).
final Map<String, Map<String, dynamic>> kDemoTitles = {
  'viajero': {'name': 'Viajero', 'description': 'Miembro de la comunidad Ohtli.', 'holders': 13},
  'ometeotl': {'name': 'Ometeotl', 'description': 'La energía primordial.', 'holders': 1},
  'altepetlahtolli': {'name': 'Altepetlahtolli', 'description': 'Respondió un estudio.', 'holders': 3},
  'tlamatini': {'name': 'Tlamatini', 'description': 'Avisó qué faltaba.', 'holders': 2},
  'tlamatini_2': {'name': 'Tlamatini II', 'description': '5 reportes.', 'holders': 0},
  'tlamatini_3': {'name': 'Tlamatini III', 'description': '20 reportes.', 'holders': 0},
  'pochtecatl_1': {'name': 'Pochtecatl I', 'description': '3 viajes.', 'holders': 4},
  'pochtecatl_2': {'name': 'Pochtecatl II', 'description': '10 viajes.', 'holders': 1},
  'pochtecatl_3': {'name': 'Pochtecatl III', 'description': '25 viajes.', 'holders': 0},
  'ichtaca': {'name': 'Ichtaca', 'description': 'Lo escondido.', 'holders': 0},
  'recorre_alcaldias': {'name': 'Recorre alcaldías', 'description': '16 alcaldías.', 'holders': 0},
  'tlacuilo_1': {'name': 'Tlacuilo I', 'description': 'Primera crónica.', 'holders': 6},
  'tlacuilo_2': {'name': 'Tlacuilo II', 'description': '5 crónicas.', 'holders': 0},
  'tlacuilo_3': {'name': 'Tlacuilo III', 'description': '15 crónicas.', 'holders': 0},
  'cencalli': {'name': 'Cencalli', 'description': 'Familia.', 'holders': 2},
  'calpixqui': {'name': 'Calpixqui', 'description': 'Organizó un viaje grupal.', 'holders': 0},
  'amini': {'name': 'Amini', 'description': 'El cazador.', 'holders': 0},
  'xiuhpohualli': {'name': 'Xiuhpohualli', 'description': 'Cuatro estaciones.', 'holders': 0},
  'namictli': {'name': 'Namictli', 'description': 'En pareja.', 'comingSoon': true},
  'tlaxtlahuilli': {'name': 'Tlaxtlahuilli', 'description': 'La paga.', 'comingSoon': true},
};

const kDemoOwned = {'viajero', 'ometeotl', 'altepetlahtolli', 'tlamatini', 'pochtecatl_1', 'tlacuilo_1', 'cencalli'};

final Map<String, dynamic> kDemoLog = {
  'pochtecatl_1': {
    'startedAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
    'earnedAt': Timestamp.fromDate(DateTime(2026, 10, 24)),
  },
  'tlacuilo_1': {'earnedAt': Timestamp.fromDate(DateTime(2026, 11, 3))},
  'cencalli': {'earnedAt': Timestamp.fromDate(DateTime(2026, 11, 16))},
};

const kDemoProgress = {
  'pochtecatl_2': AchievementProgress(7, 10, false),
  'ichtaca': AchievementProgress(3, 10, false),
  'recorre_alcaldias': AchievementProgress(5, 16, false),
  'tlamatini_2': AchievementProgress(1, 5, false),
  'tlacuilo_2': AchievementProgress(1, 5, false),
  'xiuhpohualli': AchievementProgress(2, 4, false),
  'calpixqui': AchievementProgress(0, 1, false),
};

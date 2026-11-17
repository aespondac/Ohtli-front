import 'dart:math';

/// Banco de nombres en clave para proyectos confidenciales: palabras en náhuatl (como los títulos
/// de Ohtli) sin relación con ningún tema de investigación, para que el nombre no revele nada.
/// La unicidad la garantiza `lab_codenames/{palabra}` (solo se puede crear una vez).
const kCodenameBank = <String>[
  'Tecolotl', 'Ocelotl', 'Cuauhtli', 'Coyotl', 'Mazatl', 'Tochtli', 'Ozomatli', 'Itzcuintli',
  'Quetzalli', 'Huitzilin', 'Papalotl', 'Cuetzpalin', 'Ayotl', 'Michin', 'Tecuani', 'Tototl',
  'Zolin', 'Cozcacuauhtli', 'Chapolin', 'Azcatl', 'Xolotl', 'Tzinacan', 'Pipiltzin', 'Huexolotl',
  'Atl', 'Tletl', 'Ehecatl', 'Tepetl', 'Citlalli', 'Metztli', 'Tonatiuh', 'Mixtli',
  'Quiahuitl', 'Cepayahuitl', 'Atoyatl', 'Texcalli', 'Oztotl', 'Tlalli', 'Ilhuicatl', 'Ameyalli',
  'Xochitl', 'Ahuacatl', 'Cacahuatl', 'Ocotl', 'Ahuehuetl', 'Nopalli', 'Metl', 'Cempoalli',
  'Tlaolli', 'Etl', 'Chilli', 'Tomatl', 'Xocotl', 'Zapotl', 'Ahuatl', 'Acatl',
  'Tecpatl', 'Calli', 'Malinalli', 'Cipactli', 'Olin', 'Itztli', 'Chalchihuitl', 'Teocuitlatl',
];

/// Elige un nombre que no esté en [taken]; si el banco se agota, agrega un número.
String pickCodename(Set<String> taken, {Random? random}) {
  final rnd = random ?? Random();
  final free = kCodenameBank.where((w) => !taken.contains(w)).toList();
  if (free.isNotEmpty) return free[rnd.nextInt(free.length)];
  for (var n = 2;; n++) {
    final again = kCodenameBank.where((w) => !taken.contains('$w $n')).toList();
    if (again.isNotEmpty) return '${again[rnd.nextInt(again.length)]} $n';
  }
}

String codenameLabel(String codename) => 'Proyecto $codename';

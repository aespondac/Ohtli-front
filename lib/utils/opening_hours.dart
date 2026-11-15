/// Convierte el horario en formato OpenStreetMap (`Mo-Su 09:00-21:00`, `Tu-Su 10:00-18:00;
/// Mo off`, `24/7`…) en texto en español para mostrar:
/// `Todos los días 9:00–21:00`, `Mar–Dom 10:00–18:00 · Lun cerrado`.
/// Lo que no reconoce lo deja como venía; un número de teléfono (dato mal capturado) da ''.
String formatOpeningHours(String raw) {
  // Algunos registros traen el texto entre comillas ("Agenda tu cita")
  final s = raw.trim().replaceAll(RegExp(r'^["“”]+|["“”]+$'), '').trim();
  if (s.isEmpty) return s;
  final lower = s.toLowerCase();
  if (lower == '24/7' || lower == 'mo-su 00:00-24:00' || lower == '00:00-24:00') return 'Abierto las 24 horas';
  if (lower == 'sunrise-sunset') return 'Del amanecer al atardecer';
  if (RegExp(r'^[\d\s()+-]{7,}$').hasMatch(s) && !s.contains(':')) return '';
  return _splitRules(s).map(_formatRule).where((r) => r.isNotEmpty).join(' · ');
}

const String _dayAlt = 'Mo|Tu|We|Th|Fr|Sa|Su|PH';

/// Reglas separadas por ";" o por ", " seguido de un día cuando lo anterior ya tenía
/// horas ("Fr-Sa 13:00-24:00, Su 12:00-22:00"), pero no en listas de días ("Mo, We, Th 15:00").
List<String> _splitRules(String s) {
  final out = <String>[];
  for (final part in s.split(';')) {
    var current = '';
    final pieces = part.split(RegExp(r',\s*'));
    for (final piece in pieces) {
      final startsWithDay = RegExp('^\\s*($_dayAlt)\\b').hasMatch(piece);
      final currentHasTime = RegExp(r'\d').hasMatch(current);
      if (current.isNotEmpty && startsWithDay && currentHasTime) {
        out.add(current.trim());
        current = piece;
      } else {
        current = current.isEmpty ? piece : '$current, $piece';
      }
    }
    if (current.trim().isNotEmpty) out.add(current.trim());
  }
  return out;
}

const Map<String, String> _days = {
  'Mo': 'Lun',
  'Tu': 'Mar',
  'We': 'Mié',
  'Th': 'Jue',
  'Fr': 'Vie',
  'Sa': 'Sáb',
  'Su': 'Dom',
  'PH': 'festivos',
};

String _formatRule(String rule) {
  // Separa la parte de días (antes del primer dígito) de la de horas
  final firstDigit = rule.indexOf(RegExp(r'\d'));
  var days = firstDigit < 0 ? rule : rule.substring(0, firstDigit);
  var hours = firstDigit < 0 ? '' : rule.substring(firstDigit);

  days = days.trim();
  final isOff = RegExp(r'\b(off|closed)\b', caseSensitive: false).hasMatch(days);
  days = days.replaceAll(RegExp(r'\b(off|closed)\b', caseSensitive: false), '').trim();
  if (RegExp('^Mo\\s*-\\s*Su\$').hasMatch(days)) {
    days = 'Todos los días';
  } else if (RegExp('\\b($_dayAlt)\\b').hasMatch(days)) {
    final items = days
        .split(RegExp(r'\s*,\s*'))
        .where((d) => d.isNotEmpty)
        .map((d) => d.replaceAllMapped(
              RegExp('\\b($_dayAlt)\\b(?:\\s*-\\s*\\b($_dayAlt)\\b)?'),
              (m) => m[2] == null ? _days[m[1]]! : '${_days[m[1]]}–${_days[m[2]]}',
            ))
        .toList();
    days = items.length > 1 ? '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}' : items.join();
  }

  if (hours.isNotEmpty) {
    hours = hours
        // 09:00 → 9:00
        .replaceAllMapped(RegExp(r'\b(\d{1,2}):(\d{2})\b'), (m) => '${int.parse(m[1]!)}:${m[2]}')
        // rangos con guion largo; un cierre a las 0:00 se lee mejor como 24:00
        .replaceAllMapped(RegExp(r'(\d)\s*-\s*(\d{1,2}:\d{2})'), (m) => '${m[1]}–${m[2] == '0:00' ? '24:00' : m[2]}')
        .replaceAll(RegExp(r'\s*,\s*'), ', ')
        .trim();
  }

  final parts = [
    if (days.isNotEmpty) days,
    if (hours.isNotEmpty) hours,
    if (isOff) 'cerrado',
  ];
  return parts.join(' ');
}

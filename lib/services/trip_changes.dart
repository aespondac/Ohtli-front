import '../models/trip_model.dart';
import 'markdown_helpers.dart';
import 'trip_transfers.dart';

/// Describe en palabras lo que cambió entre dos versiones del contenido de un viaje.
/// Lo usa la fe de erratas: después del viaje, cada cambio queda con quién y cuándo.

String _name(PlaceSection p) => p.title.trim().isEmpty ? 'una parada' : '«${p.title.trim()}»';

String _money(double v) {
  final whole = v.round().abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return '${v < 0 ? '-' : ''}\$${buf.toString()}';
}

String _hours(String? a, String? b) {
  final x = (a ?? '').trim(), y = (b ?? '').trim();
  if (x.isEmpty && y.isEmpty) return 'sin horario';
  if (y.isEmpty) return x;
  return '$x–$y';
}

String _firstLine(String md) {
  final line = md
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'\[![A-Z]+\]'), '').replaceAll(RegExp(r'[#>*_`~\[\]|]'), '').trim())
      .firstWhere((l) => l.isNotEmpty && !RegExp(r'^-+$').hasMatch(l.replaceAll(' ', '')), orElse: () => '');
  return line.length > 40 ? '${line.substring(0, 40)}…' : line;
}

/// Nombre corto del tipo de bloque, con artículo ("la tabla", "un texto"…).
String _what(TripSection s, {bool definite = false}) {
  if (s is PlaceSection) return s.unplanned ? 'el desvío ${_name(s)}' : 'la parada ${_name(s)}';
  if (s is TransferSection) return 'el traslado ${describeTransfer(s)}';
  if (s is SplitSection) return definite ? 'la separación del grupo' : 'una separación del grupo';
  if (s is ProposalSection) {
    final q = s.question.trim();
    return q.isEmpty ? (definite ? 'la propuesta de lugares' : 'una propuesta de lugares') : 'la propuesta «$q»';
  }
  if (s is TextImageSection) {
    final l = _firstLine(s.markdownText);
    return l.isEmpty ? (definite ? 'la imagen' : 'una imagen') : 'la imagen «$l»';
  }
  if (s is TextSection) {
    final md = s.markdownText;
    if (parseTableMarkdown(md) != null) return definite ? 'la tabla' : 'una tabla';
    final isNote = parseAlertMarkdown(md) != null;
    final l = _firstLine(md);
    if (isNote) return l.isEmpty ? (definite ? 'la nota' : 'una nota') : 'la nota «$l»';
    return l.isEmpty ? (definite ? 'el texto' : 'un texto') : 'el texto «$l»';
  }
  return 'un bloque';
}

List<String> _placeChanges(PlaceSection a, PlaceSection b) {
  final out = <String>[];
  final n = _name(b);
  if (a.title.trim() != b.title.trim()) out.add('Se renombró ${_name(a)} como $n');
  if (a.description.trim() != b.description.trim()) out.add('Se editó la descripción de $n');
  if (a.rating != b.rating) out.add('Calificación de $n: ${a.rating > 0 ? '${a.rating} ★' : 'sin calificar'} → ${b.rating > 0 ? '${b.rating} ★' : 'sin calificar'}');
  if (a.cost != b.cost) out.add('Presupuesto de $n: ${_money(a.cost)} → ${_money(b.cost)}');
  if (a.realCost != b.realCost) {
    out.add('Gasto real de $n: ${a.realCost == null ? 'sin registrar' : _money(a.realCost!)} → ${b.realCost == null ? 'sin registrar' : _money(b.realCost!)}');
  }
  if ((a.arrivalTime ?? '') != (b.arrivalTime ?? '') || (a.departureTime ?? '') != (b.departureTime ?? '')) {
    out.add('Horario de $n: ${_hours(a.arrivalTime, a.departureTime)} → ${_hours(b.arrivalTime, b.departureTime)}');
  }
  if ((a.arrivedAt ?? '') != (b.arrivedAt ?? '') || (a.leftAt ?? '') != (b.leftAt ?? '')) {
    out.add('Hora real en $n: ${_hours(a.arrivedAt, a.leftAt)} → ${_hours(b.arrivedAt, b.leftAt)}');
  }
  final photosA = {a.mainPhotoUrl, ...a.secondaryPhotoUrls}..remove('');
  final photosB = {b.mainPhotoUrl, ...b.secondaryPhotoUrls}..remove('');
  final added = photosB.difference(photosA).length, removed = photosA.difference(photosB).length;
  if (added > 0) out.add(added == 1 ? 'Se agregó una foto a $n' : 'Se agregaron $added fotos a $n');
  if (removed > 0) out.add(removed == 1 ? 'Se quitó una foto de $n' : 'Se quitaron $removed fotos de $n');
  if ((a.coverUrl ?? '') != (b.coverUrl ?? '')) out.add((b.coverUrl ?? '').isEmpty ? 'Se quitó la portada de $n' : 'Cambió la portada de $n');
  if (a.lat != b.lat || a.lng != b.lng) out.add('Se cambió la ubicación de $n');
  if (a.unplanned != b.unplanned) out.add(b.unplanned ? '$n pasó a ser un desvío' : '$n pasó a ser una parada del plan');
  if (a.branchId != b.branchId) out.add('Cambió quién va a $n');
  if (a.meetup != b.meetup && b.meetup) out.add('$n es ahora el punto de reencuentro');
  return out;
}

List<String> _splitChanges(SplitSection a, SplitSection b) {
  final out = <String>[];
  String name(TripBranch x) => x.name.trim().isEmpty ? 'un grupo' : '«${x.name.trim()}»';
  final before = {for (final x in a.branches) x.id: x};
  final after = {for (final x in b.branches) x.id: x};
  for (final x in b.branches) {
    final old = before[x.id];
    if (old == null) {
      out.add('Se agregó el grupo ${name(x)}');
      continue;
    }
    if (old.name.trim() != x.name.trim()) out.add('Se renombró el grupo ${name(old)} como ${name(x)}');
    if (old.memberIds.toSet().difference(x.memberIds.toSet()).isNotEmpty || x.memberIds.toSet().difference(old.memberIds.toSet()).isNotEmpty) {
      out.add('Cambió quién va en ${name(x)}');
    }
    if (old.rejoins != x.rejoins) out.add(x.rejoins ? '${name(x)} se reencuentra con el grupo' : '${name(x)} ya no se reencuentra con el grupo');
  }
  for (final x in a.branches) {
    if (!after.containsKey(x.id)) out.add('Se quitó el grupo ${name(x)}');
  }
  return out;
}

List<String> _proposalChanges(ProposalSection a, ProposalSection b) {
  final out = <String>[];
  if (a.question.trim() != b.question.trim()) out.add('Cambió la pregunta de ${_what(a, definite: true)} a «${b.question.trim()}»');
  final before = {for (final c in a.candidates) c.id: c};
  final after = {for (final c in b.candidates) c.id: c};
  String place(ProposalCandidate c) => c.title.trim().isEmpty ? 'un lugar' : '«${c.title.trim()}»';
  for (final c in b.candidates) {
    if (!before.containsKey(c.id)) out.add('Se propuso ${place(c)} en ${_what(b, definite: true)}');
  }
  for (final c in a.candidates) {
    if (!after.containsKey(c.id)) out.add('Se quitó ${place(c)} de ${_what(b, definite: true)}');
  }
  return out;
}

/// Lista de cambios legibles entre [before] y [after]. Como máximo [limit] líneas.
List<String> describeTripChanges(List<TripSection> before, List<TripSection> after, {int limit = 14}) {
  final out = <String>[];
  final beforeById = {for (final s in before) s.id: s};
  final afterById = {for (final s in after) s.id: s};

  for (final s in after) {
    final old = beforeById[s.id];
    if (old == null) {
      out.add(s is PlaceSection && s.unplanned ? 'Se agregó el desvío ${_name(s)}' : 'Se agregó ${_what(s)}');
      continue;
    }
    if (old.runtimeType != s.runtimeType) {
      out.add('Se reemplazó ${_what(old, definite: true)} por ${_what(s)}');
    } else if (s is PlaceSection && old is PlaceSection) {
      out.addAll(_placeChanges(old, s));
    } else if (s is TransferSection && old is TransferSection) {
      if (old.mode != s.mode || old.durationMins != s.durationMins || old.cost != s.cost || old.notes != s.notes || old.isEstimated != s.isEstimated) {
        out.add('Traslado: ${describeTransfer(old)} → ${describeTransfer(s)}${s.cost > 0 ? ' · ${_money(s.cost)}' : ''}');
      }
    } else if (s is TextImageSection && old is TextImageSection) {
      if (old.imageUrl != s.imageUrl) out.add('Cambió ${_what(s, definite: true)}');
      if (old.markdownText != s.markdownText || old.layout != s.layout) out.add('Se editó ${_what(s, definite: true)}');
    } else if (s is TextSection && old is TextSection) {
      if (old.markdownText != s.markdownText) out.add('Se editó ${_what(s, definite: true)}');
    } else if (s is ProposalSection && old is ProposalSection) {
      out.addAll(_proposalChanges(old, s));
    } else if (s is SplitSection && old is SplitSection) {
      out.addAll(_splitChanges(old, s));
    }
  }
  for (final s in before) {
    if (!afterById.containsKey(s.id)) out.add('Se quitó ${_what(s, definite: true)}');
  }

  // Mismos bloques en otro orden.
  final commonBefore = [for (final s in before) if (afterById.containsKey(s.id)) s.id];
  final commonAfter = [for (final s in after) if (beforeById.containsKey(s.id)) s.id];
  if (commonBefore.join('|') != commonAfter.join('|')) out.add('Se cambió el orden de los bloques');

  if (out.length > limit) {
    final extra = out.length - (limit - 1);
    return [...out.take(limit - 1), 'y $extra cambios más'];
  }
  return out;
}

/// Cambios en los datos generales del viaje (título, descripción, portada, fecha, visibilidad).
List<String> describeTripInfoChanges(Trip before, Trip after) {
  final out = <String>[];
  if (before.title.trim() != after.title.trim()) out.add('Título: «${before.title.trim()}» → «${after.title.trim()}»');
  if (before.description.trim() != after.description.trim()) out.add('Se editó la descripción del viaje');
  if (before.coverUrl != after.coverUrl) out.add('Cambió la portada del viaje');
  final da = before.travelDate, db = after.travelDate;
  if ((da == null) != (db == null) || (da != null && db != null && (da.year != db.year || da.month != db.month || da.day != db.day))) {
    out.add('Cambió la fecha del viaje');
  }
  if (before.visibility != after.visibility || before.status != after.status) {
    final pub = after.status == 'published' && after.visibility == 'public';
    out.add(pub ? 'Se publicó para todos' : 'Cambió quién puede ver el viaje');
  }
  return out;
}

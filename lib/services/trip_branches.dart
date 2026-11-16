import 'dart:math' as math;

import '../models/trip_model.dart';
import 'trip_transfers.dart';

/// El grupo separado en ramas (ver [SplitSection]): de dónde se llega a cada parada, dónde
/// termina cada quien y los horarios por rama. Todo sobre la lista plana de bloques: las
/// paradas de una rama llevan `branchId` y el reencuentro es una parada con `meetup`.

/// Carril de un bloque: la rama (`branchId`) o '' para lo que hace todo el grupo.
String laneOf(TripSection s) {
  if (s is PlaceSection) return s.branchId ?? '';
  if (s is TransferSection) return s.branchId ?? '';
  if (s is ProposalSection) return s.branchId ?? '';
  return '';
}

/// Cómo se recorre el viaje con ramas.
class BranchLayout {
  /// Para cada parada (por id), las paradas desde las que se llega: una normalmente, varias
  /// en un reencuentro, ninguna en la primera.
  final Map<String, List<String>> from;

  /// Rama de cada parada (por id); '' si es de todo el grupo.
  final Map<String, String> laneOfPlace;

  /// Dónde termina el viaje: la última parada del grupo o, si se separaron sin
  /// reencontrarse, la última de cada rama (varios puntos de llegada).
  final List<String> endIds;

  const BranchLayout(this.from, this.laneOfPlace, this.endIds);
}

BranchLayout branchLayout(List<TripSection> sections) {
  final from = <String, List<String>>{};
  final lanes = <String, String>{};
  final ends = <String>[];
  String? lastMain;
  SplitSection? split;
  final lastByBranch = <String, String?>{};

  void closeSplit({required bool meetup}) {
    final s = split;
    if (s == null) return;
    for (final b in s.branches) {
      // Sin reencuentro, o si esta rama no se reencuentra: termina en su última parada.
      if (!meetup || !b.rejoins) {
        final last = lastByBranch[b.id];
        if (last != null && last != lastMain) ends.add(last);
      }
    }
    split = null;
    lastByBranch.clear();
  }

  for (final s in sections) {
    if (s is SplitSection) {
      closeSplit(meetup: false);
      split = s;
      for (final b in s.branches) {
        lastByBranch[b.id] = lastMain;
      }
      continue;
    }
    if (s is! PlaceSection) continue;
    final active = split;
    final branch = active?.branch(s.branchId);
    if (active != null && branch != null) {
      final prev = lastByBranch[branch.id];
      from[s.id] = [?prev];
      lanes[s.id] = branch.id;
      lastByBranch[branch.id] = s.id;
    } else if (active != null) {
      // Una parada de todo el grupo cierra la separación: es el reencuentro.
      final preds = <String>[
        for (final b in active.branches)
          if (b.rejoins && lastByBranch[b.id] != null) lastByBranch[b.id]!,
      ];
      from[s.id] = preds.isEmpty ? [?lastMain] : preds.toSet().toList();
      lanes[s.id] = '';
      closeSplit(meetup: true);
      lastMain = s.id;
    } else {
      from[s.id] = [?lastMain];
      lanes[s.id] = '';
      lastMain = s.id;
    }
  }
  if (split != null) {
    // Terminó separado: cada rama acaba donde quedó.
    final s = split!;
    for (final b in s.branches) {
      final last = lastByBranch[b.id];
      if (last != null && last != lastMain && !ends.contains(last)) ends.add(last);
    }
    final anyBranchMoved = s.branches.any((b) => lastByBranch[b.id] != null && lastByBranch[b.id] != lastMain);
    if (!anyBranchMoved && lastMain != null) ends.add(lastMain);
  } else if (lastMain != null) {
    ends.add(lastMain);
  }
  return BranchLayout(from, lanes, ends);
}

/// Horarios en cascada por rama: cada rama lleva su reloj desde que se separan, y en el
/// reencuentro la llegada es la de la rama más tardía. Igual que [recalculateSchedule] sin
/// ramas: llegada = salida anterior + traslado; salida = llegada + estancia.
List<TripSection> recalculateScheduleByBranch(List<TripSection> sections,
    {String startTime = '10:00', int defaultStayMins = 60}) {
  final out = <TripSection>[];
  int? mainClock;
  final clock = <String, int?>{};
  final pending = <String, int>{};
  SplitSection? split;

  for (final s in sections) {
    if (s is SplitSection) {
      split = s;
      for (final b in s.branches) {
        clock[b.id] = mainClock;
        pending[b.id] = 0;
      }
      out.add(s);
      continue;
    }
    if (s is TransferSection) {
      final lane = split?.branch(s.branchId) != null ? s.branchId! : '';
      pending[lane] = (pending[lane] ?? 0) + (s.durationMins ?? 0);
      out.add(s);
      continue;
    }
    if (s is! PlaceSection) {
      out.add(s);
      continue;
    }
    final a = parseClockMinutes(s.arrivalTime);
    final d = parseClockMinutes(s.departureTime);
    final stay = (a != null && d != null && d > a) ? d - a : defaultStayMins;
    final start = parseClockMinutes(startTime) ?? 600;
    final active = split;
    final branch = active?.branch(s.branchId);
    int arrival;
    if (active != null && branch != null) {
      final c = clock[branch.id];
      arrival = c == null ? (a ?? start) : c + (pending[branch.id] ?? 0);
      pending[branch.id] = 0;
      clock[branch.id] = arrival + stay;
    } else if (active != null) {
      // Reencuentro: esperan a la rama que llega al último.
      final arrivals = <int>[
        for (final b in active.branches)
          if (b.rejoins && clock[b.id] != null) clock[b.id]! + (pending[b.id] ?? 0),
      ];
      arrival = arrivals.isNotEmpty
          ? arrivals.reduce(math.max)
          : (mainClock == null ? (a ?? start) : mainClock + (pending[''] ?? 0));
      split = null;
      clock.clear();
      pending.removeWhere((k, _) => k.isNotEmpty);
      pending[''] = 0;
      mainClock = arrival + stay;
    } else {
      arrival = mainClock == null ? (a ?? start) : mainClock + (pending[''] ?? 0);
      pending[''] = 0;
      mainClock = arrival + stay;
    }
    out.add(s.copyWith(arrivalTime: formatClock(arrival), departureTime: formatClock(arrival + stay)));
  }
  return out;
}

/// Inserta traslados estimados que falten, cada uno en su rama: entre paradas seguidas de la
/// misma rama, del punto donde se separan a la primera de cada rama, y de la última de cada
/// rama al reencuentro. Devuelve la lista y cuántos agregó.
(List<TripSection>, int) fillMissingTransfersByBranch(
    List<TripSection> sections, String modeId, String Function() newId) {
  final byId = {for (final s in sections) s.id: s};
  final layout = branchLayout(sections);
  // Traslados que ya hay antes de cada parada, por rama (los que aparecen desde la parada
  // anterior de esa rama).
  final out = <TripSection>[];
  final sawTransfer = <String, bool>{};
  SplitSection? split;
  int added = 0;
  for (final s in sections) {
    if (s is SplitSection) {
      split = s;
      for (final b in s.branches) {
        sawTransfer[b.id] = false;
      }
      out.add(s);
      continue;
    }
    if (s is TransferSection) {
      final lane = split?.branch(s.branchId) != null ? s.branchId! : '';
      sawTransfer[lane] = true;
      out.add(s);
      continue;
    }
    if (s is PlaceSection) {
      final froms = layout.from[s.id] ?? const [];
      final lane = layout.laneOfPlace[s.id] ?? '';
      final isMeetup = lane.isEmpty && split != null;
      for (final f in froms) {
        final prev = byId[f];
        if (prev is! PlaceSection) continue;
        // En el reencuentro, cada rama trae su traslado (con su branchId).
        final fromLane = isMeetup ? (layout.laneOfPlace[f] ?? '') : lane;
        if (sawTransfer[fromLane] == true) continue;
        final t = estimateTransfer(prev, s, modeId, id: newId());
        if (t != null) {
          out.add(fromLane.isEmpty ? t : t.copyWith(branchId: fromLane));
          added++;
        }
      }
      if (isMeetup) {
        split = null;
        sawTransfer.clear();
      }
      sawTransfer[isMeetup ? '' : lane] = false;
      out.add(s);
      continue;
    }
    out.add(s);
  }
  return (out, added);
}

/// Las paradas que le tocan a [uid]: las de todo el grupo y las de su rama. Si no está en
/// ninguna rama de una separación, ve todas las ramas.
List<PlaceSection> placesFor(List<TripSection> sections, String uid) {
  final out = <PlaceSection>[];
  SplitSection? split;
  Set<String>? mine;
  for (final s in sections) {
    if (s is SplitSection) {
      split = s;
      final assigned = {for (final b in s.branches) if (b.memberIds.contains(uid)) b.id};
      mine = assigned.isEmpty ? null : assigned;
      continue;
    }
    if (s is! PlaceSection) continue;
    final branch = split?.branch(s.branchId);
    if (branch != null) {
      if (mine == null || mine.contains(branch.id)) out.add(s);
    } else {
      if (split != null) {
        split = null;
        mine = null;
      }
      out.add(s);
    }
  }
  return out;
}

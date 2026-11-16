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

/// La separación que rige al bloque en [index]: la última antes de él que sigue abierta, es
/// decir, sin una parada de todo el grupo en medio (esa parada es el reencuentro y la cierra).
/// Null si el bloque no va después de una separación.
SplitSection? splitBefore(List<TripSection> sections, int index) {
  SplitSection? active;
  for (int i = 0; i < index && i < sections.length; i++) {
    final s = sections[i];
    if (s is SplitSection) {
      active = s;
    } else if (s is PlaceSection && active != null && active.branch(s.branchId) == null) {
      active = null;
    }
  }
  return active;
}

/// ¿El viaje tiene alguna separación?
bool hasBranches(List<TripSection> sections) => sections.any((s) => s is SplitSection);

/// Posición de cada rama dentro de su separación (para darle un color estable).
Map<String, int> branchIndexes(List<TripSection> sections) => {
      for (final s in sections.whereType<SplitSection>())
        for (int i = 0; i < s.branches.length; i++) s.branches[i].id: i,
    };

/// Todas las ramas del viaje por id.
Map<String, TripBranch> branchesById(List<TripSection> sections) => {
      for (final s in sections.whereType<SplitSection>())
        for (final b in s.branches) b.id: b,
    };

/// Rama que le toca al traslado en [index]: la de la parada a la que llega; si llega al
/// reencuentro, la de la parada de la que sale. Null si va con todo el grupo.
String? transferBranchFor(List<TripSection> sections, int index) {
  final split = splitBefore(sections, index);
  if (split == null) return null;
  for (int i = index + 1; i < sections.length; i++) {
    final s = sections[i];
    if (s is PlaceSection) {
      if (split.branch(s.branchId) != null) return s.branchId;
      break;
    }
  }
  for (int i = index - 1; i >= 0; i--) {
    final s = sections[i];
    if (identical(s, split)) return null;
    if (s is PlaceSection) return split.branch(s.branchId) != null ? s.branchId : null;
  }
  return null;
}

/// Las paradas que une el traslado en [index]: la siguiente y la anterior de su misma rama
/// (si la rama aún no tiene paradas, el punto donde se separaron). Sin ramas, las vecinas.
(PlaceSection?, PlaceSection?) transferEnds(List<TripSection> sections, int index) {
  PlaceSection? next;
  for (int i = index + 1; i < sections.length; i++) {
    final s = sections[i];
    if (s is PlaceSection) {
      next = s;
      break;
    }
  }
  PlaceSection? flatPrev() {
    for (int i = index - 1; i >= 0; i--) {
      final s = sections[i];
      if (s is PlaceSection) return s;
    }
    return null;
  }

  final split = splitBefore(sections, index);
  if (split == null) return (flatPrev(), next);
  final self = index < sections.length ? sections[index] : null;
  final String? own = self is TransferSection && split.branch(self.branchId) != null ? self.branchId : null;
  final lane = own ?? transferBranchFor(sections, index);
  if (lane == null) return (flatPrev(), next);
  for (int i = index - 1; i >= 0; i--) {
    final s = sections[i];
    if (s is PlaceSection && s.branchId == lane) return (s, next);
    if (identical(s, split)) {
      for (int j = i - 1; j >= 0; j--) {
        final x = sections[j];
        if (x is PlaceSection) return (x, next);
      }
      return (null, next);
    }
  }
  return (flatPrev(), next);
}

/// La rama que de verdad aplica a cada bloque (paradas, traslados y propuestas), por id. Los
/// que van con todo el grupo no aparecen. Una parada con `branchId` fuera de una separación,
/// o de una rama que ya no existe, es de todo el grupo.
Map<String, String> blockLanes(List<TripSection> sections) {
  final out = <String, String>{};
  SplitSection? active;
  for (final s in sections) {
    if (s is SplitSection) {
      active = s;
      continue;
    }
    final lane = laneOf(s);
    final branch = active?.branch(lane.isEmpty ? null : lane);
    if (branch != null) {
      out[s.id] = branch.id;
    } else if (s is PlaceSection && active != null) {
      active = null;
    }
  }
  return out;
}

/// Las paradas donde el grupo se reencuentra: la primera de todo el grupo tras separarse.
Set<String> meetupIds(List<TripSection> sections) {
  final out = <String>{};
  SplitSection? active;
  for (final s in sections) {
    if (s is SplitSection) {
      active = s;
    } else if (s is PlaceSection && active != null && active.branch(s.branchId) == null) {
      out.add(s.id);
      active = null;
    }
  }
  return out;
}

/// Todo lo que la interfaz necesita para pintar las ramas de un viaje.
class BranchView {
  /// ¿El viaje se separa en algún momento?
  final bool active;
  final BranchLayout layout;
  final Map<String, String> lanes;
  final Map<String, int> _index;
  final Map<String, TripBranch> _byId;
  final Set<String> meetups;

  BranchView._(this.active, this.layout, this.lanes, this._index, this._byId, this.meetups);

  factory BranchView.of(List<TripSection> sections) => BranchView._(
        hasBranches(sections),
        branchLayout(sections),
        blockLanes(sections),
        branchIndexes(sections),
        branchesById(sections),
        meetupIds(sections),
      );

  /// Rama del bloque [id], o null si va con todo el grupo.
  TripBranch? branchOf(String id) {
    final lane = lanes[id];
    return lane == null ? null : _byId[lane];
  }

  /// Posición de la rama dentro de su separación (para el color).
  int indexOf(String branchId) => _index[branchId] ?? 0;

  bool isMeetup(String placeId) => meetups.contains(placeId);

  /// Punto de llegada (solo se marca en viajes que se separan).
  bool isEnd(String placeId) => active && layout.endIds.contains(placeId);
}

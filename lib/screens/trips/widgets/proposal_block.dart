import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/trip_model.dart';
import '../../../services/proposal_votes.dart';
import '../../../theme/colors.dart';
import '../../../widgets/ohtli_ui.dart';

/// Color estable para cada persona (mismo criterio que la presencia del editor).
Color voterColor(String uid) {
  const palette = [Color(0xFFD9480F), Color(0xFF2B8A3E), Color(0xFF5F3DC4), Color(0xFFC2255C), Color(0xFF1971C2), Color(0xFFE67700)];
  return palette[uid.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff) % palette.length];
}

/// Iniciales de quien votó, con su nombre al pasar el cursor.
class VoterBubbles extends StatelessWidget {
  final List<String> uids;
  final Map<String, String> names;
  final String? myUid;
  final bool isDark;

  const VoterBubbles({super.key, required this.uids, required this.names, this.myUid, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    const max = 6;
    final shown = uids.take(max).toList();
    Widget bubble(Widget child, Color color) => Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: isDark ? const Color(0xFF1E1E22) : Colors.white, width: 2),
          ),
          child: child,
        );
    final items = <Widget>[
      for (final u in shown)
        Tooltip(
          message: u == myUid ? 'Tú' : (names[u] ?? 'Alguien del grupo'),
          child: bubble(
            Text(_initial(names[u]), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
            voterColor(u),
          ),
        ),
      if (uids.length > max)
        bubble(
          Text('+${uids.length - max}',
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1F2A2A))),
          isDark ? const Color(0xFF3A3A3E) : OhtliColors.cantera,
        ),
    ];
    // Encimadas un poco, como las caras de los coautores.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < items.length; i++)
          Align(widthFactor: i == items.length - 1 ? 1 : 0.72, alignment: Alignment.centerLeft, child: items[i]),
      ],
    );
  }

  static String _initial(String? name) {
    final n = (name ?? '').trim();
    return n.isEmpty ? '?' : n.characters.first.toUpperCase();
  }
}

/// Lugares propuestos con sus votos. Lo usan el editor y el visor (ahí solo se vota).
class ProposalCandidateList extends StatelessWidget {
  final List<ProposalCandidate> candidates;

  /// uid → id del lugar que eligió. Null si no se pueden ver los votos (vista previa, sin acceso).
  final Map<String, String>? votes;
  final Map<String, String> names;
  final String? myUid;
  final bool canVote;
  final bool isDark;

  /// Votar por un lugar (o quitar el voto con null).
  final ValueChanged<String?>? onVote;

  /// Quitar un lugar de la propuesta; solo se ofrece en los que [canRemove] permite.
  final ValueChanged<ProposalCandidate>? onRemove;
  final bool Function(ProposalCandidate)? canRemove;

  const ProposalCandidateList({
    super.key,
    required this.candidates,
    required this.votes,
    required this.names,
    required this.isDark,
    this.myUid,
    this.canVote = false,
    this.onVote,
    this.onRemove,
    this.canRemove,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final v = votes == null ? null : validVotes(votes!, candidates);
    final leader = v == null ? null : proposalWinner(candidates, v);
    final String? mine = (v != null && myUid != null) ? v[myUid] : null;

    if (candidates.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : OhtliColors.innerCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: OhtliColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.add_location_alt_outlined, size: 20, color: sub),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Aún no hay lugares propuestos.', style: GoogleFonts.inter(fontSize: 13, color: sub)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _candidateRow(c, v, leader, mine, fg, sub),
          ),
      ],
    );
  }

  Widget _candidateRow(ProposalCandidate c, Map<String, String>? v, ProposalCandidate? leader, String? mine, Color fg, Color sub) {
    final voters = v == null ? const <String>[] : votersOf(v, c.id);
    final bool leading = leader != null && leader.id == c.id;
    final bool isMine = mine == c.id;
    final String who = c.proposedBy == myUid && myUid != null
        ? 'Lo propusiste tú'
        : (c.proposedByName.trim().isEmpty ? 'Propuesta del grupo' : 'Propuso ${c.proposedByName.trim()}');
    final Widget photo = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 54,
        height: 54,
        child: c.photoUrl.startsWith('http')
            ? Image.network(c.photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => _photoFallback())
            : _photoFallback(),
      ),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: leading ? OhtliColors.cempasuchil.withValues(alpha: 0.7) : OhtliColors.cardBorder,
          width: leading ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          photo,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.title.trim().isEmpty ? 'Lugar sin nombre' : c.title.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.bold, color: fg),
                      ),
                    ),
                    if (leading && voters.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const Tooltip(
                        message: 'Va ganando',
                        child: Icon(Icons.emoji_events_rounded, size: 16, color: OhtliColors.cempasuchil),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$who${c.cost > 0 ? ' · \$${c.cost.toStringAsFixed(0)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: sub),
                ),
                if (v != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (voters.isNotEmpty) ...[
                        VoterBubbles(uids: voters, names: names, myUid: myUid, isDark: isDark),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        voters.isEmpty ? 'Sin votos' : '${voters.length} ${voters.length == 1 ? 'voto' : 'votos'}',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: voters.isEmpty ? sub : fg),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (canVote && onVote != null && v != null)
                OhtliChoiceChip(
                  label: isMine ? 'Tu voto' : 'Votar',
                  icon: isMine ? Icons.check_rounded : Icons.how_to_vote_rounded,
                  selected: isMine,
                  onTap: () => onVote!(isMine ? null : c.id),
                ),
              if (onRemove != null && (canRemove?.call(c) ?? false))
                IconButton(
                  tooltip: 'Quitar este lugar',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onRemove!(c),
                  icon: Icon(Icons.close_rounded, size: 18, color: sub),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoFallback() => Container(
        color: OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.25 : 0.10),
        alignment: Alignment.center,
        child: const Icon(Icons.place_rounded, size: 24, color: OhtliColors.stormyTeal),
      );
}

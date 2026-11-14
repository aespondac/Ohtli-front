import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/trip_social_service.dart';
import '../../theme/colors.dart';

/// Colores de las burbujas estilo iMessage.
const Color kBubbleMine = Color(0xFF0A84FF);
Color bubbleOther(bool isDark) => isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE9E9EB);

/// Fila con las 6 reacciones rápidas. [selected] resalta la reacción actual.
class TapbackPicker extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onPick;
  final bool isDark;

  const TapbackPicker({super.key, required this.selected, required this.onPick, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in kTapbacks)
            Tooltip(
              message: t.label,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onPick(selected == t.id ? null : t.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected == t.id ? kBubbleMine.withValues(alpha: 0.22) : Colors.transparent,
                  ),
                  child: Text(t.emoji, style: const TextStyle(fontSize: 21)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Abre el selector de reacciones como un menú flotante sobre [anchorContext].
Future<void> showTapbackMenu({
  required BuildContext anchorContext,
  required String? selected,
  required ValueChanged<String?> onPick,
  required bool isDark,
  List<Widget> extraActions = const [],
  Offset? globalPosition,
}) async {
  HapticFeedback.selectionClick();
  final overlay = Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
  final box = anchorContext.findRenderObject() as RenderBox?;
  final Offset origin = globalPosition ?? (box != null ? box.localToGlobal(Offset.zero, ancestor: overlay) : Offset.zero);
  await showDialog<void>(
    context: anchorContext,
    barrierColor: Colors.black.withValues(alpha: 0.12),
    builder: (ctx) {
      final size = MediaQuery.of(ctx).size;
      const pickerWidth = 6 * 38.0 + 12;
      final left = (origin.dx).clamp(8.0, size.width - pickerWidth - 8);
      final top = (origin.dy - 58).clamp(8.0, size.height - 160);
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TapbackPicker(
                    selected: selected,
                    isDark: isDark,
                    onPick: (k) {
                      Navigator.of(ctx).pop();
                      onPick(k);
                    },
                  ),
                  if (extraActions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: 190,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4))],
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: extraActions),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Chips "❤️ 3 · 👍 1" con el resumen de reacciones; al tocar muestra quién reaccionó.
class ReactionSummary extends StatelessWidget {
  final Map<String, String> byUser;
  final String? myUid;
  final Map<String, String> memberNames;
  final bool isDark;
  final bool compact;

  const ReactionSummary({
    super.key,
    required this.byUser,
    required this.myUid,
    required this.memberNames,
    required this.isDark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final summary = summarizeReactions(byUser);
    if (summary.isEmpty) return const SizedBox.shrink();
    final mine = myUid != null ? byUser[myUid] : null;
    final who = byUser.entries
        .where((e) => tapbackOf(e.value) != null)
        .map((e) => '${tapbackOf(e.value)!.emoji} ${e.key == myUid ? 'Tú' : (memberNames[e.key] ?? 'Viajero')}')
        .join('\n');
    return Tooltip(
      message: who,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: mine != null ? kBubbleMine.withValues(alpha: 0.6) : (isDark ? Colors.white12 : Colors.black12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in summary) ...[
              Text(e.key.emoji, style: TextStyle(fontSize: compact ? 12 : 14)),
              if (e.value > 1 || !compact)
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 4),
                  child: Text('${e.value}',
                      style: GoogleFonts.inter(
                          fontSize: compact ? 10.5 : 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.7))),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Barra social debajo de cada bloque: reacciones, botón para reaccionar y hilo de notas.
class BlockSocialBar extends StatelessWidget {
  final Map<String, String> reactions;
  final int noteCount;
  final bool threadOpen;
  final String? myUid;
  final Map<String, String> memberNames;
  final bool isDark;
  final ValueChanged<String?> onReact;
  final VoidCallback onToggleThread;

  const BlockSocialBar({
    super.key,
    required this.reactions,
    required this.noteCount,
    required this.threadOpen,
    required this.myUid,
    required this.memberNames,
    required this.isDark,
    required this.onReact,
    required this.onToggleThread,
  });

  @override
  Widget build(BuildContext context) {
    final mine = myUid != null ? reactions[myUid] : null;
    final Color tone = isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ReactionSummary(byUser: reactions, myUid: myUid, memberNames: memberNames, isDark: isDark),
          Builder(
            builder: (btnCtx) => _PillButton(
              icon: mine == null ? Icons.add_reaction_outlined : null,
              leading: mine != null ? Text(tapbackOf(mine)!.emoji, style: const TextStyle(fontSize: 14)) : null,
              label: mine == null ? 'Reaccionar' : 'Tu reacción',
              color: tone,
              isDark: isDark,
              onTap: () => showTapbackMenu(anchorContext: btnCtx, selected: mine, onPick: onReact, isDark: isDark),
            ),
          ),
          _PillButton(
            icon: threadOpen ? Icons.expand_less_rounded : Icons.chat_bubble_outline_rounded,
            label: noteCount == 0 ? 'Nota para el grupo' : (noteCount == 1 ? '1 nota' : '$noteCount notas'),
            color: noteCount > 0 ? kBubbleMine : tone,
            isDark: isDark,
            onTap: onToggleThread,
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _PillButton({this.icon, this.leading, required this.label, required this.color, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) leading! else if (icon != null) Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hilo de notas de un bloque con burbujas estilo iMessage y su caja para escribir.
class NoteThread extends StatefulWidget {
  final List<TripNote> notes;
  final String myUid;
  final bool canModerate;
  final Map<String, String> memberNames;
  final bool isDark;
  final Future<void> Function(String text) onSend;
  final Future<void> Function(TripNote note, String text) onEdit;
  final Future<void> Function(TripNote note) onDelete;
  final Future<void> Function(TripNote note, String? kind) onReact;

  const NoteThread({
    super.key,
    required this.notes,
    required this.myUid,
    required this.canModerate,
    required this.memberNames,
    required this.isDark,
    required this.onSend,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
  });

  @override
  State<NoteThread> createState() => _NoteThreadState();
}

class _NoteThreadState extends State<NoteThread> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  TripNote? _editing;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (_editing != null) {
        await widget.onEdit(_editing!, text);
      } else {
        await widget.onSend(text);
      }
      _controller.clear();
      _editing = null;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar la nota. Revisa tu conexión.', style: GoogleFonts.inter())),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _clock(DateTime? d) {
    if (d == null) return 'Enviando…';
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) return '$h:$m';
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} ${months[d.month - 1]} · $h:$m';
  }

  void _openBubbleMenu(BuildContext bubbleCtx, TripNote note, Offset? at) {
    final mine = note.authorId == widget.myUid;
    final Color fg = widget.isDark ? Colors.white : OhtliColors.onyx;
    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) => Builder(
          builder: (c) => ListTile(
            dense: true,
            leading: Icon(icon, size: 18, color: color ?? fg),
            title: Text(label, style: GoogleFonts.inter(fontSize: 13.5, color: color ?? fg)),
            onTap: () {
              Navigator.of(c).pop();
              onTap();
            },
          ),
        );
    showTapbackMenu(
      anchorContext: bubbleCtx,
      globalPosition: at,
      selected: note.reactions[widget.myUid],
      isDark: widget.isDark,
      onPick: (k) => widget.onReact(note, k),
      extraActions: [
        action(Icons.copy_rounded, 'Copiar', () => Clipboard.setData(ClipboardData(text: note.text))),
        if (mine)
          action(Icons.edit_rounded, 'Editar', () {
            setState(() => _editing = note);
            _controller.text = note.text;
            _focus.requestFocus();
          }),
        if (mine || widget.canModerate)
          action(Icons.delete_outline_rounded, 'Borrar', () => widget.onDelete(note), color: Colors.redAccent),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    final isDark = widget.isDark;
    final List<Widget> rows = [];
    for (int i = 0; i < notes.length; i++) {
      final n = notes[i];
      final prev = i > 0 ? notes[i - 1] : null;
      final next = i < notes.length - 1 ? notes[i + 1] : null;
      bool sameGroup(TripNote? a, TripNote b) =>
          a != null &&
          a.authorId == b.authorId &&
          (a.createdAt == null || b.createdAt == null || b.createdAt!.difference(a.createdAt!).inMinutes.abs() < 10);
      final firstOfGroup = !sameGroup(prev, n);
      final lastOfGroup = next == null || !sameGroup(n, next);
      rows.add(_Bubble(
        note: n,
        mine: n.authorId == widget.myUid,
        showName: firstOfGroup && n.authorId != widget.myUid,
        showAvatar: lastOfGroup,
        tail: lastOfGroup,
        footer: lastOfGroup ? '${_clock(n.createdAt)}${n.editedAt != null ? ' · editada' : ''}' : null,
        myUid: widget.myUid,
        memberNames: widget.memberNames,
        isDark: isDark,
        onMenu: (ctx, at) => _openBubbleMenu(ctx, n, at),
        spacingTop: i == 0 ? 0 : (firstOfGroup ? 12 : 3),
      ));
    }

    final bool canSend = _controller.text.trim().isNotEmpty && !_sending;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1D) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Deja una nota para quienes van contigo. Solo los miembros del viaje la ven.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white54 : OhtliColors.subtleText),
              ),
            ),
          ...rows,
          if (_editing != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  const Icon(Icons.edit_rounded, size: 14, color: kBubbleMine),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Editando tu nota',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kBubbleMine)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _editing = null);
                      _controller.clear();
                    },
                    child: Text('Cancelar', style: GoogleFonts.inter(fontSize: 12)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: TripSocialService.maxNoteLength,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    style: GoogleFonts.inter(fontSize: 14, color: isDark ? Colors.white : OhtliColors.onyx),
                    decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      hintText: 'Nota para el grupo',
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: isDark ? Colors.white38 : Colors.black38),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: canSend ? 1 : 0.35,
                child: Material(
                  color: kBubbleMine,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: canSend ? _submit : null,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(_editing != null ? Icons.check_rounded : Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final TripNote note;
  final bool mine;
  final bool showName;
  final bool showAvatar;
  final bool tail;
  final String? footer;
  final String myUid;
  final Map<String, String> memberNames;
  final bool isDark;
  final void Function(BuildContext ctx, Offset? at) onMenu;
  final double spacingTop;

  const _Bubble({
    required this.note,
    required this.mine,
    required this.showName,
    required this.showAvatar,
    required this.tail,
    required this.footer,
    required this.myUid,
    required this.memberNames,
    required this.isDark,
    required this.onMenu,
    required this.spacingTop,
  });

  @override
  Widget build(BuildContext context) {
    final hasReactions = summarizeReactions(note.reactions).isNotEmpty;
    const r = Radius.circular(18);
    const small = Radius.circular(5);
    final radius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: !mine && tail ? small : r,
      bottomRight: mine && tail ? small : r,
    );
    final Color bg = mine ? kBubbleMine : bubbleOther(isDark);
    final Color fg = mine ? Colors.white : (isDark ? Colors.white : Colors.black87);

    final bubble = Builder(
      builder: (bctx) => GestureDetector(
        onLongPressStart: (d) => onMenu(bctx, d.globalPosition),
        onSecondaryTapDown: (d) => onMenu(bctx, d.globalPosition),
        onDoubleTap: () => onMenu(bctx, null),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 420),
              margin: EdgeInsets.only(top: hasReactions ? 12 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(color: bg, borderRadius: radius),
              child: Text(note.text, style: GoogleFonts.inter(fontSize: 14, height: 1.35, color: fg)),
            ),
            if (hasReactions)
              Positioned(
                top: -2,
                left: mine ? -10 : null,
                right: mine ? null : -10,
                child: ReactionSummary(byUser: note.reactions, myUid: myUid, memberNames: memberNames, isDark: isDark, compact: true),
              ),
          ],
        ),
      ),
    );

    final avatar = SizedBox(
      width: 26,
      child: showAvatar && !mine
          ? CircleAvatar(
              radius: 13,
              backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.18),
              backgroundImage: (note.authorPhoto != null && note.authorPhoto!.isNotEmpty) ? NetworkImage(note.authorPhoto!) : null,
              child: (note.authorPhoto == null || note.authorPhoto!.isEmpty)
                  ? Text(
                      note.authorName.isNotEmpty ? note.authorName.characters.first.toUpperCase() : '?',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal),
                    )
                  : null,
            )
          : null,
    );

    return Padding(
      padding: EdgeInsets.only(top: spacingTop),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 2),
              child: Text(note.authorName,
                  style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white54 : OhtliColors.subtleText)),
            ),
          Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[avatar, const SizedBox(width: 6)],
              Flexible(child: bubble),
              if (mine) const SizedBox(width: 4),
            ],
          ),
          if (footer != null)
            Padding(
              padding: EdgeInsets.only(top: 3, left: mine ? 0 : 40, right: mine ? 4 : 0),
              child: Text(footer!, style: GoogleFonts.inter(fontSize: 10.5, color: isDark ? Colors.white38 : Colors.black38)),
            ),
        ],
      ),
    );
  }
}

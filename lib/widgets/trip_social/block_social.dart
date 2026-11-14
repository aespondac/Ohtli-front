import 'dart:async';

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
  final bool compact;
  final VoidCallback? onMore;

  const TapbackPicker({
    super.key,
    required this.selected,
    required this.onPick,
    required this.isDark,
    this.compact = false,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final double cell = compact ? 32 : 38;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: compact ? 3 : 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in kTapbacks)
            Tooltip(
              message: t.label,
              waitDuration: const Duration(milliseconds: 500),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onPick(selected == t.id ? null : t.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: cell,
                  height: cell,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected == t.id ? kBubbleMine.withValues(alpha: 0.22) : Colors.transparent,
                  ),
                  child: Text(t.emoji, style: TextStyle(fontSize: compact ? 17 : 21)),
                ),
              ),
            ),
          if (onMore != null)
            Tooltip(
              message: 'Más opciones',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onMore,
                child: SizedBox(
                  width: cell,
                  height: cell,
                  child: Icon(Icons.more_horiz_rounded, size: compact ? 18 : 20, color: isDark ? Colors.white70 : Colors.black54),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Abre el selector de reacciones como un menú flotante (pulsación larga en táctil).
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

/// Reporta si el puntero está encima (para mostrar controles solo al pasar el cursor).
class HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  const HoverBuilder({super.key, required this.builder});

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// Al pasar el cursor sobre [child] aparece encima la barra de reacciones, como en iMessage.
/// En pantallas táctiles se abre con una pulsación larga.
class HoverTapback extends StatefulWidget {
  final Widget child;
  final String? selected;
  final ValueChanged<String?> onPick;
  final bool isDark;

  /// Lado del que sale la barra: a la izquierda para bloques y mensajes ajenos, a la derecha para los propios.
  final bool alignRight;
  final Offset offset;
  final VoidCallback? onMore;
  final List<Widget> Function(BuildContext menuContext)? longPressActions;

  const HoverTapback({
    super.key,
    required this.child,
    required this.selected,
    required this.onPick,
    required this.isDark,
    this.alignRight = false,
    this.offset = const Offset(0, -4),
    this.onMore,
    this.longPressActions,
  });

  @override
  State<HoverTapback> createState() => _HoverTapbackState();
}

class _HoverTapbackState extends State<HoverTapback> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  bool _inTarget = false;
  bool _inBar = false;
  Timer? _hideTimer;

  void _sync() {
    _hideTimer?.cancel();
    if (_inTarget || _inBar) {
      if (!_portal.isShowing) _portal.show();
    } else {
      // Pequeña espera para poder mover el cursor del bloque a la barra.
      _hideTimer = Timer(const Duration(milliseconds: 180), () {
        if (mounted && !_inTarget && !_inBar && _portal.isShowing) _portal.hide();
      });
    }
  }

  void _hideNow() {
    _hideTimer?.cancel();
    _inBar = false;
    _inTarget = false;
    if (_portal.isShowing) _portal.hide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Alignment target = widget.alignRight ? Alignment.topRight : Alignment.topLeft;
    final Alignment follower = widget.alignRight ? Alignment.bottomRight : Alignment.bottomLeft;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: target,
            followerAnchor: follower,
            offset: widget.offset,
            child: MouseRegion(
              onEnter: (_) {
                _inBar = true;
                _sync();
              },
              onExit: (_) {
                _inBar = false;
                _sync();
              },
              child: Material(
                color: Colors.transparent,
                child: TapbackPicker(
                  compact: true,
                  selected: widget.selected,
                  isDark: widget.isDark,
                  onMore: widget.onMore == null
                      ? null
                      : () {
                          _hideNow();
                          widget.onMore!();
                        },
                  onPick: (k) {
                    _hideNow();
                    widget.onPick(k);
                  },
                ),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) {
            _inTarget = true;
            _sync();
          },
          onExit: (_) {
            _inTarget = false;
            _sync();
          },
          child: Builder(
            builder: (ctx) => GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onLongPressStart: (d) => showTapbackMenu(
                anchorContext: ctx,
                globalPosition: d.globalPosition,
                selected: widget.selected,
                isDark: widget.isDark,
                onPick: widget.onPick,
                extraActions: widget.longPressActions?.call(ctx) ?? const [],
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastilla "❤️ 3 · 👍 1" con el resumen de reacciones; al pasar el cursor muestra quién reaccionó.
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
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9, vertical: compact ? 2 : 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: mine != null ? kBubbleMine.withValues(alpha: 0.6) : (isDark ? Colors.white12 : Colors.black12)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))],
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

/// Barra debajo de cada bloque en pantallas angostas: reacciones y mensajes.
class BlockSocialBar extends StatelessWidget {
  final Map<String, String> reactions;
  final int noteCount;
  final bool threadOpen;
  final String? myUid;
  final bool canInteract;
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
    required this.canInteract,
    required this.memberNames,
    required this.isDark,
    required this.onReact,
    required this.onToggleThread,
  });

  @override
  Widget build(BuildContext context) {
    final mine = myUid != null ? reactions[myUid] : null;
    final Color tone = isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.65);
    final children = <Widget>[
      if (canInteract)
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
      if (canInteract || noteCount > 0)
        _PillButton(
          icon: threadOpen ? Icons.expand_less_rounded : Icons.chat_bubble_outline_rounded,
          label: noteCount == 0 ? 'Mensaje' : (noteCount == 1 ? '1 mensaje' : '$noteCount mensajes'),
          color: noteCount > 0 ? kBubbleMine : tone,
          isDark: isDark,
          onTap: onToggleThread,
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: children),
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

/// "14 nov · 13:12" (con año si no es el actual).
String formatNoteStamp(DateTime? d) {
  if (d == null) return 'Enviando…';
  const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  final year = d.year == DateTime.now().year ? '' : ' ${d.year}';
  return '${d.day} ${months[d.month - 1]}$year · $h:$m';
}

/// Mensajes de un bloque en burbujas estilo iMessage.
/// [compact]: versión para el margen junto al bloque (sin fondo; la caja para escribir aparece al pedirla).
class NoteThread extends StatefulWidget {
  final List<TripNote> notes;
  final String? myUid;
  final bool canWrite;
  final bool canModerate;
  final bool compact;

  /// En el margen: muestra "＋ Mensaje" aunque no haya mensajes (al pasar el cursor por el bloque).
  final bool revealAdd;
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
    required this.canWrite,
    required this.canModerate,
    required this.memberNames,
    required this.isDark,
    required this.onSend,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    this.compact = false,
    this.revealAdd = false,
  });

  @override
  State<NoteThread> createState() => _NoteThreadState();
}

class _NoteThreadState extends State<NoteThread> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  TripNote? _editing;
  bool _sending = false;
  bool _composerOpen = false;

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
      if (widget.compact) _composerOpen = false;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el mensaje. Revisa tu conexión.', style: GoogleFonts.inter())),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startEdit(TripNote note) {
    setState(() {
      _editing = note;
      _composerOpen = true;
    });
    _controller.text = note.text;
    _focus.requestFocus();
  }

  List<Widget> _menuActions(BuildContext menuCtx, TripNote note) {
    final mine = note.authorId == widget.myUid;
    final Color fg = widget.isDark ? Colors.white : OhtliColors.onyx;
    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
          dense: true,
          leading: Icon(icon, size: 18, color: color ?? fg),
          title: Text(label, style: GoogleFonts.inter(fontSize: 13.5, color: color ?? fg)),
          onTap: () {
            Navigator.of(menuCtx).pop();
            onTap();
          },
        );
    return [
      action(Icons.copy_rounded, 'Copiar', () => Clipboard.setData(ClipboardData(text: note.text))),
      if (mine) action(Icons.edit_rounded, 'Editar', () => _startEdit(note)),
      if (mine || widget.canModerate) action(Icons.delete_outline_rounded, 'Borrar', () => widget.onDelete(note), color: Colors.redAccent),
    ];
  }

  void _openMoreMenu(BuildContext ctx, TripNote note) {
    showTapbackMenu(
      anchorContext: ctx,
      selected: widget.myUid != null ? note.reactions[widget.myUid] : null,
      isDark: widget.isDark,
      onPick: (k) => widget.onReact(note, k),
      extraActions: _menuActions(ctx, note),
    );
  }

  Widget _composer() {
    final isDark = widget.isDark;
    final bool canSend = _controller.text.trim().isNotEmpty && !_sending;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): _submit,
              const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
                    _composerOpen = false;
                    _editing = null;
                    _controller.clear();
                  }),
            },
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.compact,
              minLines: 1,
              maxLines: 5,
              maxLength: TripSocialService.maxNoteLength,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.inter(fontSize: 13.5, color: isDark ? Colors.white : OhtliColors.onyx),
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                hintText: _editing != null ? 'Edita tu mensaje' : 'Mensaje',
                hintStyle: GoogleFonts.inter(fontSize: 13.5, color: isDark ? Colors.white38 : Colors.black38),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                filled: true,
                fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
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
                width: 32,
                height: 32,
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_editing != null ? Icons.check_rounded : Icons.arrow_upward_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
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
      final mine = widget.myUid != null && n.authorId == widget.myUid;
      Widget bubble = _Bubble(
        note: n,
        mine: mine,
        compact: widget.compact,
        showName: firstOfGroup && !mine,
        showAvatar: lastOfGroup,
        tail: lastOfGroup,
        footer: lastOfGroup ? '${formatNoteStamp(n.createdAt)}${n.editedAt != null ? ' · editado' : ''}' : null,
        myUid: widget.myUid,
        memberNames: widget.memberNames,
        isDark: isDark,
        spacingTop: i == 0 ? 0 : (firstOfGroup ? 12 : 3),
        decorate: widget.canWrite
            ? (child) => Builder(
                  builder: (bctx) => HoverTapback(
                    alignRight: mine,
                    selected: widget.myUid != null ? n.reactions[widget.myUid] : null,
                    isDark: isDark,
                    onPick: (k) => widget.onReact(n, k),
                    onMore: () => _openMoreMenu(bctx, n),
                    longPressActions: (menuCtx) => _menuActions(menuCtx, n),
                    child: child,
                  ),
                )
            : null,
      );
      rows.add(bubble);
    }

    final bool showAddPill = widget.canWrite && !_composerOpen && widget.revealAdd;
    final Widget addPill = AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: showAddPill ? 1 : 0,
      child: IgnorePointer(
        ignoring: !showAddPill,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            shape: StadiumBorder(side: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => setState(() => _composerOpen = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_comment_outlined, size: 15, color: kBubbleMine),
                    const SizedBox(width: 5),
                    Text(notes.isEmpty ? 'Mensaje' : 'Responder',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kBubbleMine)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.compact) {
      if (notes.isEmpty && !widget.canWrite) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...rows,
          if (widget.canWrite) ...[
            const SizedBox(height: 8),
            if (_composerOpen) _composer() else addPill,
          ],
        ],
      );
    }

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
          if (notes.isEmpty && widget.canWrite)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Deja un mensaje en este bloque. Lo verá quien lea el viaje.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white54 : OhtliColors.subtleText),
              ),
            ),
          ...rows,
          if (widget.canWrite) ...[
            const SizedBox(height: 10),
            _composer(),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final TripNote note;
  final bool mine;
  final bool compact;
  final bool showName;
  final bool showAvatar;
  final bool tail;
  final String? footer;
  final String? myUid;
  final Map<String, String> memberNames;
  final bool isDark;
  final double spacingTop;
  final Widget Function(Widget child)? decorate;

  const _Bubble({
    required this.note,
    required this.mine,
    required this.compact,
    required this.showName,
    required this.showAvatar,
    required this.tail,
    required this.footer,
    required this.myUid,
    required this.memberNames,
    required this.isDark,
    required this.spacingTop,
    this.decorate,
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

    Widget bubble = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: compact ? 230 : 420),
          margin: EdgeInsets.only(top: hasReactions ? 12 : 0),
          padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 13, vertical: compact ? 7 : 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            boxShadow: compact ? [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))] : null,
          ),
          child: Text(note.text, style: GoogleFonts.inter(fontSize: compact ? 13 : 14, height: 1.35, color: fg)),
        ),
        if (hasReactions)
          Positioned(
            top: -2,
            left: mine ? -10 : null,
            right: mine ? null : -10,
            child: ReactionSummary(byUser: note.reactions, myUid: myUid, memberNames: memberNames, isDark: isDark, compact: true),
          ),
      ],
    );
    if (decorate != null) bubble = decorate!(bubble);

    final avatar = SizedBox(
      width: compact ? 0 : 24,
      child: showAvatar && !mine && !compact
          ? CircleAvatar(
              radius: 12,
              backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.18),
              backgroundImage: (note.authorPhoto != null && note.authorPhoto!.isNotEmpty) ? NetworkImage(note.authorPhoto!) : null,
              child: (note.authorPhoto == null || note.authorPhoto!.isEmpty)
                  ? Text(
                      note.authorName.isNotEmpty ? note.authorName.characters.first.toUpperCase() : '?',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal),
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
              padding: EdgeInsets.only(left: compact ? 6 : 36, bottom: 2),
              child: Text(note.authorName,
                  style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white54 : OhtliColors.subtleText)),
            ),
          Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.max,
            children: [
              if (!mine && !compact) ...[avatar, const SizedBox(width: 6)],
              Flexible(child: bubble),
              if (mine) const SizedBox(width: 4),
            ],
          ),
          if (footer != null)
            Padding(
              padding: EdgeInsets.only(top: 3, left: mine ? 0 : (compact ? 6 : 36), right: mine ? 4 : 0),
              child: Text(footer!, style: GoogleFonts.inter(fontSize: 10.5, color: isDark ? Colors.white38 : Colors.black38)),
            ),
        ],
      ),
    );
  }
}

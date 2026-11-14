// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/trip_transfers.dart';
import '../../theme/colors.dart';
import '../../widgets/image_cropper_dialog.dart';

/// Herramientas del viajero: diálogos para registrar lo que pasa en el viaje
/// (desvíos, traslados, precio real, texto, imagen, tabla y nota). Solo piden los
/// datos; quien los llama decide cómo se guardan.

/// Lugar del viaje donde se inserta algo nuevo ("después de …").
typedef BlockOption = ({String id, String label, bool isPlace});

class DetourDraft {
  final String afterId;
  final String name;
  final String note;
  const DetourDraft(this.afterId, this.name, this.note);
}

class TransferDraft {
  final String afterId;
  final String mode;
  final int? minutes;
  final double cost;
  final String note;
  const TransferDraft(this.afterId, this.mode, this.minutes, this.cost, this.note);
}

enum BlockKind { text, note, table, image }

class BlockDraft {
  final String afterId;
  final BlockKind kind;
  final String markdown;

  /// Solo para [BlockKind.image]: la foto recortada como data URL.
  final String? imageDataUrl;
  const BlockDraft(this.afterId, this.kind, this.markdown, {this.imageDataUrl});
}

Color _fg(bool isDark) => isDark ? Colors.white : const Color(0xFF1F2A2A);
Color _sub(bool isDark) => isDark ? Colors.white60 : OhtliColors.subtleText;

/// Campo relleno. La etiqueta va como texto de ayuda dentro del campo (sin etiqueta flotante,
/// que se encimaba con el texto en campos compactos); [floating] la deja flotar (desplegables).
InputDecoration _field(String label, bool isDark, {String? hint, String? prefix, bool floating = false}) => InputDecoration(
      labelText: floating ? label : null,
      hintText: floating ? hint : (hint != null ? '$label · $hint' : label),
      prefixText: prefix,
      isDense: true,
      filled: true,
      fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF4F6F5),
      labelStyle: GoogleFonts.inter(fontSize: 13, color: _sub(isDark)),
      hintStyle: GoogleFonts.inter(fontSize: 13, color: _sub(isDark).withValues(alpha: 0.7)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );

/// Marco común de los diálogos de herramientas.
Future<T?> _toolDialog<T>(
  BuildContext context, {
  required bool isDark,
  required IconData icon,
  required String title,
  required String? subtitle,
  required Widget Function(BuildContext ctx, StateSetter setState) body,
  required String action,
  required T? Function() onSubmit,
  bool Function()? canSubmit,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: OhtliColors.stormyTeal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, size: 19, color: OhtliColors.stormyTeal),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: _fg(isDark))),
                          if (subtitle != null) Text(subtitle, style: GoogleFonts.inter(fontSize: 12.5, color: _sub(isDark))),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded), tooltip: 'Cerrar'),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(child: SingleChildScrollView(child: body(ctx, setState))),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancelar', style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: (canSubmit?.call() ?? true)
                          ? () {
                              final r = onSubmit();
                              if (r != null) Navigator.of(ctx).pop(r);
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: OhtliColors.stormyTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(action, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _afterPicker(List<BlockOption> options, String value, ValueChanged<String> onChanged, bool isDark, {bool placesOnly = false}) {
  final list = placesOnly ? options.where((o) => o.isPlace).toList() : options;
  return DropdownButtonFormField<String>(
    value: list.any((o) => o.id == value) ? value : (list.isEmpty ? null : list.last.id),
    isExpanded: true,
    decoration: _field(placesOnly ? 'Después de la parada' : 'Ponerlo después de', isDark, floating: true),
    dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
    items: [
      for (final o in list)
        DropdownMenuItem(
          value: o.id,
          child: Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13.5, color: _fg(isDark))),
        ),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

/// Elige una foto del dispositivo y la recorta (3:4). Devuelve un data URL JPEG.
Future<String?> pickAndCropPhoto(BuildContext context, {double aspectRatio = 3 / 4}) {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is! String || !context.mounted) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final Uint8List bytes = base64Decode(result.split(',').last);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => OhtliImageCropperDialog(
          imageBytes: bytes,
          isCircle: false,
          aspectRatio: aspectRatio,
          onCropped: (dataUrl) {
            if (!completer.isCompleted) completer.complete(dataUrl);
          },
        ),
      ).then((_) {
        if (!completer.isCompleted) completer.complete(null);
      });
    });
    reader.readAsDataUrl(files.first);
  });
  input.click();
  return completer.future;
}

Future<double?> askRealCost(BuildContext context, {required String placeName, double? current, double estimated = 0, required bool isDark}) {
  final ctrl = TextEditingController(text: (current ?? (estimated > 0 ? estimated : null))?.toStringAsFixed(0) ?? '');
  return _toolDialog<double>(
    context,
    isDark: isDark,
    icon: Icons.payments_rounded,
    title: 'Precio real',
    subtitle: placeName,
    action: 'Guardar',
    body: (ctx, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text('¿Cuánto gastaron aquí?', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: _sub(isDark))),
        ),
        TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: GoogleFonts.inter(fontSize: 15, color: _fg(isDark)),
          decoration: _field('0', isDark, prefix: '\$ '),
        ),
        if (estimated > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Estimado en el plan: \$${estimated.toStringAsFixed(0)} MXN', style: GoogleFonts.inter(fontSize: 12, color: _sub(isDark))),
          ),
      ],
    ),
    onSubmit: () => double.tryParse(ctrl.text.trim()),
  );
}

Future<DetourDraft?> askDetour(BuildContext context, {required List<BlockOption> options, required String initialAfter, required bool isDark}) {
  final name = TextEditingController();
  final note = TextEditingController();
  String after = initialAfter;
  return _toolDialog<DetourDraft>(
    context,
    isDark: isDark,
    icon: Icons.alt_route_rounded,
    title: 'Desvío',
    subtitle: 'Un lugar que no estaba en el plan. Se dibuja como una rama de la ruta.',
    action: 'Agregar desvío',
    canSubmit: () => name.text.trim().isNotEmpty,
    body: (ctx, setState) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: name,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.inter(fontSize: 14, color: _fg(isDark)),
          decoration: _field('¿Dónde se desviaron?', isDark, hint: 'Ej. Nevería en la esquina'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: note,
          minLines: 2,
          maxLines: 4,
          style: GoogleFonts.inter(fontSize: 14, color: _fg(isDark)),
          decoration: _field('¿Qué pasó ahí? (opcional)', isDark),
        ),
        const SizedBox(height: 10),
        _afterPicker(options, after, (v) => setState(() => after = v), isDark, placesOnly: true),
      ],
    ),
    onSubmit: () => DetourDraft(after, name.text.trim(), note.text.trim()),
  );
}

Future<TransferDraft?> askTransfer(BuildContext context, {required List<BlockOption> options, required String initialAfter, required bool isDark}) {
  String after = initialAfter;
  String mode = 'walking';
  final minutes = TextEditingController();
  final cost = TextEditingController();
  final note = TextEditingController();
  return _toolDialog<TransferDraft>(
    context,
    isDark: isDark,
    icon: Icons.route_rounded,
    title: 'Traslado',
    subtitle: 'Cómo se movieron de una parada a la siguiente.',
    action: 'Guardar traslado',
    body: (ctx, setState) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _afterPicker(options, after, (v) => setState(() => after = v), isDark, placesOnly: true),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in kTransferModes)
              ChoiceChip(
                selected: mode == m.id,
                onSelected: (_) => setState(() => mode = m.id),
                showCheckmark: false,
                avatar: Icon(m.icon, size: 16, color: mode == m.id ? Colors.white : OhtliColors.stormyTeal),
                label: Text(m.label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: mode == m.id ? Colors.white : _fg(isDark))),
                selectedColor: OhtliColors.stormyTeal,
                backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF4F6F5),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: minutes,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.inter(fontSize: 14, color: _fg(isDark)),
                decoration: _field('Minutos', isDark),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                style: GoogleFonts.inter(fontSize: 14, color: _fg(isDark)),
                decoration: _field('Costo', isDark, prefix: '\$ '),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: note,
          style: GoogleFonts.inter(fontSize: 14, color: _fg(isDark)),
          decoration: _field('Nota (opcional)', isDark, hint: 'Ej. Línea 2, bajen en Coyoacán'),
        ),
      ],
    ),
    onSubmit: () => TransferDraft(after, mode, int.tryParse(minutes.text.trim()), double.tryParse(cost.text.trim()) ?? 0, note.text.trim()),
  );
}

/// Texto, nota, tabla o imagen dentro del viaje.
Future<BlockDraft?> askBlock(BuildContext context, {required BlockKind kind, required List<BlockOption> options, required String initialAfter, required bool isDark}) {
  String after = initialAfter;
  final text = TextEditingController();
  String? image;
  String noteType = 'NOTE';
  // Tabla: encabezados y filas editables; la última columna puede sumarse como dinero.
  final headers = [TextEditingController(text: 'Concepto'), TextEditingController(text: 'Monto')];
  final rows = <List<TextEditingController>>[
    [TextEditingController(), TextEditingController()],
  ];
  bool money = true;

  String tableMarkdown() {
    String cell(String s) => s.replaceAll('|', '/').trim();
    final h = <String>[
      for (int i = 0; i < headers.length; i++)
        (i == headers.length - 1 && money) ? '${cell(headers[i].text)} [money:MXN:total]' : cell(headers[i].text),
    ];
    final body = rows.where((r) => r.any((c) => c.text.trim().isNotEmpty)).map((r) => '| ${r.map((c) => cell(c.text)).join(' | ')} |');
    return ['| ${h.join(' | ')} |', '|${List.filled(h.length, '---').join('|')}|', ...body].join('\n');
  }

  final (IconData icon, String title, String? subtitle) = switch (kind) {
    BlockKind.text => (Icons.notes_rounded, 'Texto', 'Cuenten algo del viaje. Admite **negritas** y *cursivas*.'),
    BlockKind.note => (Icons.sticky_note_2_rounded, 'Nota', 'Un aviso destacado: un consejo, una advertencia o algo a recordar.'),
    BlockKind.table => (Icons.table_chart_rounded, 'Tabla', 'Ideal para cuentas, horarios o listas.'),
    BlockKind.image => (Icons.image_rounded, 'Imagen', 'Una foto con un texto al lado.'),
  };

  return _toolDialog<BlockDraft>(
    context,
    isDark: isDark,
    icon: icon,
    title: title,
    subtitle: subtitle,
    action: 'Agregar',
    canSubmit: () => switch (kind) {
      BlockKind.image => image != null,
      BlockKind.table => rows.any((r) => r.any((c) => c.text.trim().isNotEmpty)),
      _ => text.text.trim().isNotEmpty,
    },
    body: (ctx, setState) {
      final List<Widget> children = [];
      if (kind == BlockKind.image) {
        children.add(
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final picked = await pickAndCropPhoto(ctx);
              if (picked != null) setState(() => image = picked);
            },
            child: Container(
              height: 170,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF4F6F5),
                borderRadius: BorderRadius.circular(14),
                image: image == null ? null : DecorationImage(image: MemoryImage(base64Decode(image!.split(',').last)), fit: BoxFit.cover),
              ),
              alignment: Alignment.center,
              child: image == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_photo_alternate_rounded, size: 30, color: OhtliColors.stormyTeal),
                        const SizedBox(height: 6),
                        Text('Elegir foto', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.stormyTeal)),
                      ],
                    )
                  : null,
            ),
          ),
        );
        children.add(const SizedBox(height: 10));
      }
      if (kind == BlockKind.note) {
        children.add(Wrap(
          spacing: 6,
          children: [
            for (final t in const [('NOTE', 'Nota'), ('TIP', 'Consejo'), ('WARNING', 'Aviso')])
              ChoiceChip(
                selected: noteType == t.$1,
                onSelected: (_) => setState(() => noteType = t.$1),
                showCheckmark: false,
                label: Text(t.$2, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: noteType == t.$1 ? Colors.white : _fg(isDark))),
                selectedColor: OhtliColors.stormyTeal,
                backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF4F6F5),
                side: BorderSide.none,
              ),
          ],
        ));
        children.add(const SizedBox(height: 10));
      }
      if (kind == BlockKind.table) {
        Widget cellField(TextEditingController c, {bool header = false}) => Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: TextField(
                  controller: c,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: header ? FontWeight.w700 : FontWeight.w400, color: _fg(isDark)),
                  decoration: _field('', isDark).copyWith(labelText: null, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                ),
              ),
            );
        children.add(Row(children: [for (final h in headers) cellField(h, header: true)]));
        for (final r in rows) {
          children.add(Row(children: [for (final c in r) cellField(c)]));
        }
        children.add(Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => rows.add([for (final _ in headers) TextEditingController()])),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('Fila', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
            if (headers.length < 4)
              TextButton.icon(
                onPressed: () => setState(() {
                  headers.insert(headers.length - 1, TextEditingController(text: 'Columna'));
                  for (final r in rows) {
                    r.insert(r.length - 1, TextEditingController());
                  }
                }),
                icon: const Icon(Icons.view_column_rounded, size: 18),
                label: Text('Columna', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            const Spacer(),
            Text('Sumar la última', style: GoogleFonts.inter(fontSize: 12, color: _sub(isDark))),
            Switch(value: money, activeColor: OhtliColors.stormyTeal, onChanged: (v) => setState(() => money = v)),
          ],
        ));
      } else {
        children.add(TextField(
          controller: text,
          autofocus: kind != BlockKind.image,
          minLines: kind == BlockKind.image ? 2 : 4,
          maxLines: 8,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.inter(fontSize: 14, height: 1.45, color: _fg(isDark)),
          decoration: _field(kind == BlockKind.image ? 'Texto junto a la foto' : 'Escribe aquí', isDark),
        ));
      }
      children.add(const SizedBox(height: 10));
      children.add(_afterPicker(options, after, (v) => setState(() => after = v), isDark));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    },
    onSubmit: () {
      switch (kind) {
        case BlockKind.text:
          return BlockDraft(after, kind, text.text.trim());
        case BlockKind.note:
          final body = text.text.trim().split('\n').map((l) => '> $l').join('\n');
          return BlockDraft(after, kind, '> [!$noteType]\n$body');
        case BlockKind.table:
          return BlockDraft(after, kind, tableMarkdown());
        case BlockKind.image:
          return BlockDraft(after, kind, text.text.trim(), imageDataUrl: image);
      }
    },
  );
}

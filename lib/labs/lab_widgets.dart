// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'package:web/web.dart' as web;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import '../utils/web_helpers.dart';

String fmtNum(dynamic v, {int digits = 1, String suffix = ''}) {
  if (v == null) return '—';
  if (v is num) return '${v.toStringAsFixed(digits)}$suffix';
  return '$v$suffix';
}

String fmtDate(dynamic ts) {
  DateTime? d;
  try {
    d = (ts as dynamic)?.toDate() as DateTime?;
  } catch (_) {}
  if (d == null) return '—';
  d = d.toLocal();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

void downloadText(String filename, String content, {String mime = 'text/plain'}) {
  downloadBytes(utf8.encode(content), filename, '$mime;charset=utf-8');
}

String toCsv(List<String> header, List<List<dynamic>> rows) {
  String cell(dynamic v) {
    final s = v == null ? '' : (v is num ? v.toString() : '$v');
    return s.contains(RegExp(r'[",\n;]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return [header.map(cell).join(','), ...rows.map((r) => r.map(cell).join(','))].join('\n');
}

/// Encoder JSON que tolera Timestamps de Firestore.
String toJsonPretty(Object? data) => const JsonEncoder.withIndent('  ').convert(_jsonSafe(data));

Object? _jsonSafe(Object? v) {
  if (v == null || v is num || v is String || v is bool) return v;
  if (v is Map) return {for (final e in v.entries) '${e.key}': _jsonSafe(e.value)};
  if (v is Iterable) return v.map(_jsonSafe).toList();
  try {
    final d = (v as dynamic).toDate() as DateTime;
    return d.toUtc().toIso8601String();
  } catch (_) {
    return '$v';
  }
}

class LabCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const LabCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: OhtliColors.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: OhtliColors.cardBorder),
        ),
        child: child,
      );
}

class LabSectionTitle extends StatelessWidget {
  final String text;
  final String? caption;
  const LabSectionTitle(this.text, {super.key, this.caption});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(caption!, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, height: 1.4)),
            ),
        ]),
      );
}

class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color? color;
  const MetricTile({super.key, required this.label, required this.value, this.hint, this.color});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: OhtliColors.innerCardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OhtliColors.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: color ?? OhtliColors.onyx)),
          if (hint != null) Text(hint!, style: GoogleFonts.inter(fontSize: 10.5, color: OhtliColors.subtleText)),
        ]),
      );
}

/// Barras horizontales simples (sin dependencias de gráficas).
class LabBars extends StatelessWidget {
  final List<MapEntry<String, double>> data;
  final double? maxValue;
  final String unit;
  final double? threshold;
  final Color color;
  const LabBars({
    super.key,
    required this.data,
    this.maxValue,
    this.unit = '',
    this.threshold,
    this.color = OhtliColors.stormyTeal,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Text('Sin datos', style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText));
    }
    final maxV = maxValue ?? data.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);
    return Column(
      children: data.map((e) {
        final frac = maxV <= 0 ? 0.0 : (e.value / maxV).clamp(0.0, 1.0);
        final over = threshold != null && e.value > threshold!;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 120,
              child: Text(e.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.onyx)),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                return Stack(children: [
                  Container(height: 14, decoration: BoxDecoration(color: OhtliColors.innerCardBg, borderRadius: BorderRadius.circular(4))),
                  Container(
                    height: 14,
                    width: c.maxWidth * frac,
                    decoration: BoxDecoration(
                      color: over ? OhtliColors.cempasuchil : color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  if (threshold != null && maxV > 0)
                    Positioned(
                      left: (c.maxWidth * (threshold! / maxV)).clamp(0, c.maxWidth - 2),
                      child: Container(width: 2, height: 14, color: OhtliColors.xoconostle),
                    ),
                ]);
              }),
            ),
            SizedBox(
              width: 64,
              child: Text(' ${e.value.toStringAsFixed(1)}$unit',
                  textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

class StatusDot extends StatelessWidget {
  final String status;
  const StatusDot(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = switch (status) {
      'completed' => const Color(0xFF3F8F5B),
      'running' => OhtliColors.cempasuchil,
      'error' || 'timeout' || 'failed' => const Color(0xFFC0392B),
      _ => OhtliColors.subtleText,
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(status, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
    ]);
  }
}

TextStyle labCell({bool bold = false}) =>
    GoogleFonts.inter(fontSize: 11.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: OhtliColors.onyx);

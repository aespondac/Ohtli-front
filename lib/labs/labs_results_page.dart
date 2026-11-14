// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import 'lab_access.dart';
import 'lab_article.dart';
import 'lab_repository.dart';
import 'lab_widgets.dart';
import 'labs_top_bar.dart';

/// labs.ohtli.quest/news (y /resultados): blog público de resultados de Ohtli Labs.
/// Solo muestra artículos publicados con visibilidad pública; no requiere iniciar sesión.
/// /news/<ruta> abre un artículo.
///
/// Estilo sobrio (igual que los documentos legales): el artículo más reciente como
/// entrada principal y después "Más entradas".
class LabsResultsPage extends StatelessWidget {
  final String? slug;
  final VoidCallback onOpenEval;
  const LabsResultsPage({super.key, this.slug, required this.onOpenEval});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 760;
    final hPad = isMobile ? 20.0 : 56.0;
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: const LabsTopBar(current: LabsSection.news),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(isMobile: isMobile, hPad: hPad, articleMode: slug != null),
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, isMobile ? 28 : 48, hPad, 64),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: slug == null ? 1040 : 820),
                child: slug == null ? _PostList(isMobile: isMobile) : _Article(slug: slug!, isMobile: isMobile),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _openPost(Map<String, dynamic> m) => html.window.location.href = '/news/${m['slug']}';

String _byline(Map<String, dynamic> m) {
  final authors = (m['authors'] ?? '').toString();
  return [if (authors.isNotEmpty) authors, fmtDate(m['publishedAt'] ?? m['updatedAt'])].join(' · ');
}

// ───────────────────────── Encabezado ─────────────────────────

class _Header extends StatelessWidget {
  final bool isMobile;
  final double hPad;
  final bool articleMode;
  const _Header({required this.isMobile, required this.hPad, required this.articleMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(hPad, isMobile ? 28 : (articleMode ? 28 : 56), hPad, isMobile ? 24 : (articleMode ? 28 : 44)),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        border: Border(bottom: BorderSide(color: OhtliColors.cardBorder)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: articleMode ? 820 : 1040),
          child: articleMode
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => html.window.location.href = '/news',
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Todas las noticias'),
                    style: TextButton.styleFrom(
                      foregroundColor: OhtliColors.onyx,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Noticias',
                        style: GoogleFonts.outfit(
                            fontSize: isMobile ? 30 : 44, fontWeight: FontWeight.w700, color: OhtliColors.onyx, letterSpacing: isMobile ? -0.5 : -1.0)),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Text(
                        'Artículos del laboratorio sobre la evaluación del sistema multiagente de itinerarios para la Ciudad de México '
                        '(Trabajo Terminal 2026-B156, ESCOM-IPN). Cada artículo cita corridas reproducibles con su configuración.',
                        style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.subtleText, height: 1.6),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ───────────────────────── Lista de entradas ─────────────────────────

class _PostList extends StatelessWidget {
  final bool isMobile;
  const _PostList({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: LabRepository.instance.watchPublishedPosts([LabVisibility.public]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)));
        }
        final posts = (snap.data?.docs ?? []).map((d) => d.data()).toList()
          ..sort((a, b) {
            DateTime at(Map<String, dynamic> m) {
              try {
                return ((m['publishedAt'] ?? m['updatedAt']) as dynamic).toDate() as DateTime;
              } catch (_) {
                return DateTime(1970);
              }
            }

            return at(b).compareTo(at(a));
          });
        if (posts.isEmpty) return const _Empty();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Featured(post: posts.first, isMobile: isMobile),
            if (posts.length > 1) ...[
              const SizedBox(height: 48),
              Text('Más entradas', style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (context, c) {
                final cols = isMobile ? 1 : (c.maxWidth < 760 ? 2 : 3);
                const gap = 20.0;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: posts.skip(1).map((p) => SizedBox(width: w, child: _EntryCard(post: p))).toList(),
                );
              }),
            ],
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Text('Aún no hay artículos publicados. Vuelve pronto.', style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.subtleText)),
    );
  }
}

Widget _readMore(String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: OhtliColors.accentText)),
        const SizedBox(width: 6),
        Icon(Icons.arrow_forward_rounded, size: 16, color: OhtliColors.accentText),
      ],
    );

/// Entrada principal: el artículo más reciente.
class _Featured extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool isMobile;
  const _Featured({required this.post, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final summary = (post['summary'] ?? '').toString();
    return Material(
      color: OhtliColors.cardBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _openPost(post),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 24 : 40),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: OhtliColors.cardBorder)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ARTÍCULO MÁS RECIENTE',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: OhtliColors.accentText)),
              const SizedBox(height: 16),
              Text('${post['title'] ?? ''}',
                  style: GoogleFonts.outfit(
                      fontSize: isMobile ? 26 : 36, fontWeight: FontWeight.w700, color: OhtliColors.onyx, height: 1.15, letterSpacing: -0.6)),
              const SizedBox(height: 10),
              Text(_byline(post), style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText)),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Text(summary,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 16, color: OhtliColors.onyx.withValues(alpha: 0.82), height: 1.7)),
                ),
              ],
              const SizedBox(height: 22),
              _readMore('Leer artículo'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entrada secundaria.
class _EntryCard extends StatelessWidget {
  final Map<String, dynamic> post;
  const _EntryCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final summary = (post['summary'] ?? '').toString();
    return Material(
      color: OhtliColors.cardBg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _openPost(post),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 240,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: OhtliColors.cardBorder)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fmtDate(post['publishedAt'] ?? post['updatedAt']),
                  style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
              const SizedBox(height: 10),
              Text('${post['title'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700, color: OhtliColors.onyx, height: 1.2)),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(summary,
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.55)),
              ],
              const Spacer(),
              _readMore('Leer artículo'),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Artículo ─────────────────────────

class _Article extends StatelessWidget {
  final String slug;
  final bool isMobile;
  const _Article({required this.slug, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: LabRepository.instance.postBySlug(slug, [LabVisibility.public]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)));
        }
        final post = snap.data;
        if (post == null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Este artículo no existe o aún no es público.',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
              const SizedBox(height: 10),
              TextButton(onPressed: () => html.window.location.href = '/news', child: const Text('Ver todas las noticias')),
            ]),
          );
        }
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 24 : 44),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: LabArticleView(post: post),
        );
      },
    );
  }
}

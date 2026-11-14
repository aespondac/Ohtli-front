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
class LabsResultsPage extends StatelessWidget {
  final String? slug;
  final VoidCallback onOpenEval;
  const LabsResultsPage({super.key, this.slug, required this.onOpenEval});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 760;
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: const LabsTopBar(current: LabsSection.news),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 40, vertical: 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: slug == null ? const _PostList() : _Article(slug: slug!),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostList extends StatelessWidget {
  const _PostList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: LabRepository.instance.watchPublishedPosts([LabVisibility.public]),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Resultados de las pruebas de Ohtli',
              style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 6),
          Text(
            'Artículos del laboratorio sobre la evaluación del sistema multiagente de itinerarios para la Ciudad de México '
            '(Trabajo Terminal 2026-B156, ESCOM-IPN). Cada artículo cita corridas reproducibles con su configuración.',
            style: GoogleFonts.inter(fontSize: 14, height: 1.5, color: OhtliColors.subtleText),
          ),
          const SizedBox(height: 20),
          if (snap.connectionState == ConnectionState.waiting) const Center(child: CircularProgressIndicator()),
          if (snap.connectionState != ConnectionState.waiting && docs.isEmpty)
            LabCard(child: Text('Aún no hay resultados publicados.', style: labCell())),
          for (final d in docs)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => html.window.location.href = '/news/${d.data()['slug']}',
                child: LabCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(fmtDate(d.data()['publishedAt']), style: labCell()),
                    const SizedBox(height: 4),
                    Text('${d.data()['title']}', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                    if ((d.data()['summary'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${d.data()['summary']}',
                            maxLines: 3, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13.5, height: 1.45, color: OhtliColors.onyx)),
                      ),
                    const SizedBox(height: 8),
                    Text('Leer artículo →', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal)),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

class _Article extends StatelessWidget {
  final String slug;
  const _Article({required this.slug});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: LabRepository.instance.postBySlug(slug, [LabVisibility.public]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final post = snap.data;
        if (post == null) {
          return LabCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Este artículo no existe o aún no es público.', style: labCell(bold: true)),
              TextButton(onPressed: () => html.window.location.href = '/news', child: const Text('Ver todos los resultados')),
            ]),
          );
        }
        return LabCard(padding: const EdgeInsets.all(28), child: LabArticleView(post: post));
      },
    );
  }
}

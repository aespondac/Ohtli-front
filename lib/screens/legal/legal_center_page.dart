// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_theme_toggle.dart';
import '../../widgets/ohtli_service_icon.dart';
import 'legal_content.dart';

/// Centro legal: Términos, Aviso de privacidad, Cookies, API y Labs en una sola vista.
class LegalCenterPage extends StatefulWidget {
  final LegalDocId initialDoc;
  final VoidCallback onBack;

  const LegalCenterPage({super.key, this.initialDoc = LegalDocId.terms, required this.onBack});

  @override
  State<LegalCenterPage> createState() => _LegalCenterPageState();
}

class _LegalCenterPageState extends State<LegalCenterPage> {
  late LegalDocId _current = widget.initialDoc;
  late final List<LegalDoc> _docs = _visibleDocs();

  /// Términos, privacidad y cookies siempre; los de la API solo en api.ohtli.quest y los
  /// de Labs solo en labs/lab.ohtli.quest (o si se abrió directamente ese documento).
  List<LegalDoc> _visibleDocs() {
    final host = kIsWeb ? (html.window.location.hostname ?? '') : '';
    final params = Uri.base.queryParameters;
    final isApi = host.startsWith('api.') || params.containsKey('testApi');
    final isLabs = host.startsWith('labs.') || host.startsWith('lab.') || params.containsKey('testLab') || params.containsKey('testLabApp');
    return kLegalDocs.where((d) {
      if (d.id == widget.initialDoc) return true;
      if (d.id == LegalDocId.api) return isApi;
      if (d.id == LegalDocId.labs) return isLabs;
      return true;
    }).toList();
  }
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _sectionKeys = {};

  static const Map<LegalDocId, (IconData, Color)> _docIcons = {
    LegalDocId.terms: (Icons.gavel_rounded, OhtliColors.stormyTeal),
    LegalDocId.privacy: (Icons.privacy_tip_rounded, OhtliColors.xoconostle),
    LegalDocId.cookies: (Icons.cookie_rounded, OhtliColors.cempasuchil),
    LegalDocId.api: (Icons.api_rounded, Color(0xFF3949AB)),
    LegalDocId.labs: (Icons.science_rounded, Color(0xFF00897B)),
  };

  @override
  void initState() {
    super.initState();
    _syncUrl();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _select(LegalDocId id) {
    if (id == _current) return;
    setState(() {
      _current = id;
      _sectionKeys.clear();
    });
    _syncUrl();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // Refleja el documento en la URL para que se pueda compartir el enlace directo
  void _syncUrl() {
    if (!kIsWeb) return;
    try {
      html.window.history.replaceState(null, legalDocById(_current).title, legalDocById(_current).path);
    } catch (_) {}
  }

  void _scrollToSection(int i) {
    final ctx = _sectionKeys[i]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic, alignment: 0.05);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 900;
    final doc = legalDocById(_current);
    final hPad = isMobile ? 20.0 : (width * 0.045).clamp(40.0, 96.0);

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isMobile, hPad),
            Expanded(
              child: isMobile
                  ? SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_buildDocChips(), const SizedBox(height: 20), _buildDocument(doc, isMobile)],
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPad),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 280, child: _buildSidebar(doc)),
                          const SizedBox(width: 48),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _scroll,
                              padding: const EdgeInsets.only(top: 8, bottom: 64),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 820),
                                  child: _buildDocument(doc, isMobile),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isMobile, double hPad) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OhtliColors.cardBorder))),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: widget.onBack,
            icon: Icon(Icons.arrow_back_rounded, color: OhtliColors.onyx),
            style: IconButton.styleFrom(
              backgroundColor: OhtliColors.cardBg,
              shape: CircleBorder(side: BorderSide(color: OhtliColors.cardBorder)),
            ),
          ),
          const SizedBox(width: 14),
          SvgPicture.asset('assets/logo.svg', height: 22, colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn)),
          const SizedBox(width: 10),
          Text('Legal', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.subtleText)),
          const Spacer(),
          const OhtliThemeToggle(),
        ],
      ),
    );
  }

  Widget _buildSidebar(LegalDoc doc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 28, bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DOCUMENTOS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: OhtliColors.subtleText)),
          const SizedBox(height: 12),
          for (final d in _docs) _sidebarItem(d),
          const SizedBox(height: 28),
          Text('EN ESTE DOCUMENTO', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: OhtliColors.subtleText)),
          const SizedBox(height: 10),
          for (var i = 0; i < doc.sections.length; i++)
            InkWell(
              onTap: () => _scrollToSection(i),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text(doc.sections[i].title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sidebarItem(LegalDoc d) {
    final selected = d.id == _current;
    final (icon, color) = _docIcons[d.id]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? OhtliColors.cardBg : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _select(d.id),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? OhtliColors.cardBorder : Colors.transparent),
            ),
            child: Row(
              children: [
                OhtliServiceIcon(icon: icon, color: color, size: 34, soft: !selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    d.navLabel,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? OhtliColors.onyx : OhtliColors.subtleText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final d in _docs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(d.navLabel),
                selected: d.id == _current,
                onSelected: (_) => _select(d.id),
                showCheckmark: false,
                labelStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: d.id == _current ? Colors.white : OhtliColors.onyx,
                ),
                selectedColor: OhtliColors.stormyTeal,
                backgroundColor: OhtliColors.cardBg,
                side: BorderSide(color: d.id == _current ? OhtliColors.stormyTeal : OhtliColors.cardBorder),
                shape: const StadiumBorder(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDocument(LegalDoc doc, bool isMobile) {
    final (icon, color) = _docIcons[doc.id]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: isMobile ? 4 : 28),
        OhtliServiceIcon(icon: icon, color: color, size: 52),
        const SizedBox(height: 18),
        Text(
          doc.title,
          style: GoogleFonts.outfit(
            fontSize: isMobile ? 28 : 40,
            fontWeight: FontWeight.w800,
            color: OhtliColors.onyx,
            letterSpacing: isMobile ? -0.6 : -1.2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metaPill(Icons.event_rounded, 'Vigente desde el ${LegalInfo.effectiveDate}'),
            _metaPill(Icons.history_rounded, 'Versión ${LegalInfo.version}'),
          ],
        ),
        const SizedBox(height: 22),
        Text(doc.intro, style: GoogleFonts.inter(fontSize: 16, color: OhtliColors.onyx.withValues(alpha: 0.85), height: 1.65)),
        const SizedBox(height: 24),
        _buildSummary(doc, color),
        const SizedBox(height: 12),
        for (var i = 0; i < doc.sections.length; i++) _buildSection(i, doc.sections[i]),
        const SizedBox(height: 28),
        _buildContactCard(),
      ],
    );
  }

  Widget _metaPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: OhtliColors.subtleText),
          const SizedBox(width: 6),
          Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
        ],
      ),
    );
  }

  Widget _buildSummary(LegalDoc doc, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.12), OhtliColors.cardBg],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: color),
              const SizedBox(width: 6),
              Text('En resumen', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            ],
          ),
          const SizedBox(height: 12),
          for (final s in doc.summary)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_rounded, size: 17, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s, style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.onyx, height: 1.5))),
                ],
              ),
            ),
          Text('Este resumen no sustituye el texto completo.',
              style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: OhtliColors.subtleText)),
        ],
      ),
    );
  }

  Widget _buildSection(int i, LegalSection section) {
    final key = _sectionKeys.putIfAbsent(i, () => GlobalKey());
    final paragraphs = section.body.split('\n');
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          const SizedBox(height: 10),
          for (final p in paragraphs)
            if (p.trim().isEmpty)
              const SizedBox(height: 8)
            else if (p.startsWith('• '))
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Container(width: 5, height: 5, decoration: BoxDecoration(color: OhtliColors.accentText, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _paragraph(p.substring(2))),
                  ],
                ),
              )
            else
              Padding(padding: const EdgeInsets.only(bottom: 4), child: _paragraph(p)),
        ],
      ),
    );
  }

  Widget _paragraph(String text) {
    return SelectableText(text, style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.onyx.withValues(alpha: 0.82), height: 1.7));
  }

  Widget _buildContactCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        children: [
          const OhtliServiceIcon(icon: Icons.mail_rounded, color: OhtliColors.stormyTeal, size: 46),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('¿Dudas o solicitudes?', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                const SizedBox(height: 2),
                SelectableText(
                  'Escríbenos a ${LegalInfo.privacyEmail}',
                  style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar correo',
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: LegalInfo.privacyEmail));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Correo copiado', style: GoogleFonts.inter(color: Colors.white)),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: OhtliColors.stormyTeal,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: Icon(Icons.copy_rounded, color: OhtliColors.subtleText),
          ),
        ],
      ),
    );
  }
}

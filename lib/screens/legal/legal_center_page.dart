import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_theme_toggle.dart';
import 'legal_content.dart';

/// Página de un documento legal (Términos, Privacidad, Cookies, API o Labs).
/// Cada documento es independiente y todos comparten el mismo diseño sobrio:
/// encabezado con vigencia y versión, índice lateral, puntos clave y texto completo.
class LegalCenterPage extends StatefulWidget {
  final LegalDocId initialDoc;
  final VoidCallback onBack;

  const LegalCenterPage({super.key, this.initialDoc = LegalDocId.terms, required this.onBack});

  @override
  State<LegalCenterPage> createState() => _LegalCenterPageState();
}

class _LegalCenterPageState extends State<LegalCenterPage> {
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _sectionKeys = {};

  LegalDoc get _doc => legalDocById(widget.initialDoc);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToSection(int i) {
    final ctx = _sectionKeys[i]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic, alignment: 0.04);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 980;
    final hPad = isMobile ? 20.0 : (width * 0.05).clamp(40.0, 112.0);
    final doc = _doc;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(doc.intro, style: _bodyStyle.copyWith(fontSize: 16.5, height: 1.75)),
        const SizedBox(height: 28),
        _buildKeyPoints(doc),
        for (var i = 0; i < doc.sections.length; i++) _buildSection(i, doc.sections[i]),
        const SizedBox(height: 48),
        _buildContact(),
        const SizedBox(height: 28),
        Text(
          'La versión vigente de este documento es la publicada en esta página. '
          '© ${DateTime.now().year} ${LegalInfo.responsible}. Todos los derechos reservados.',
          style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText, height: 1.5),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(hPad),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(doc, isMobile, hPad),
                    Padding(
                      padding: EdgeInsets.fromLTRB(hPad, isMobile ? 28 : 48, hPad, 64),
                      child: isMobile
                          ? body
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 250, child: _buildToc(doc)),
                                const SizedBox(width: 64),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
                                  ),
                                ),
                              ],
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

  TextStyle get _bodyStyle => GoogleFonts.inter(fontSize: 15.5, color: OhtliColors.onyx.withValues(alpha: 0.84), height: 1.8);

  // ───────────────────────── Barra superior ─────────────────────────

  Widget _buildTopBar(double hPad) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      decoration: BoxDecoration(
        color: OhtliColors.cloudDancer,
        border: Border(bottom: BorderSide(color: OhtliColors.cardBorder)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Volver'),
            style: TextButton.styleFrom(
              foregroundColor: OhtliColors.onyx,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 22, color: OhtliColors.cardBorder),
          const SizedBox(width: 16),
          SvgPicture.asset('assets/logo.svg', height: 20, colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn)),
          const Spacer(),
          const OhtliThemeToggle(),
        ],
      ),
    );
  }

  // ───────────────────────── Encabezado del documento ─────────────────────────

  Widget _buildHeader(LegalDoc doc, bool isMobile, double hPad) {
    final meta = <(IconData, String)>[
      (Icons.event_outlined, 'Vigente desde el ${LegalInfo.effectiveDate}'),
      (Icons.tag_rounded, 'Versión ${LegalInfo.version}'),
      (Icons.account_balance_outlined, 'Responsable: ${LegalInfo.responsible}'),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(hPad, isMobile ? 32 : 56, hPad, isMobile ? 28 : 44),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        border: Border(bottom: BorderSide(color: OhtliColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Text(
              doc.title,
              style: GoogleFonts.outfit(
                fontSize: isMobile ? 30 : 44,
                fontWeight: FontWeight.w700,
                color: OhtliColors.onyx,
                letterSpacing: isMobile ? -0.5 : -1.0,
                height: 1.12,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              for (final m in meta)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(m.$1, size: 15, color: OhtliColors.subtleText),
                    const SizedBox(width: 7),
                    Text(m.$2, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: OhtliColors.subtleText)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Índice ─────────────────────────

  Widget _buildToc(LegalDoc doc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONTENIDO', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.8, color: OhtliColors.subtleText)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: OhtliColors.cardBorder, width: 1.5))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < doc.sections.length; i++)
                InkWell(
                  onTap: () => _scrollToSection(i),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 7, 8, 7),
                    child: Text(
                      doc.sections[i].title,
                      style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.35),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────── Puntos clave ─────────────────────────

  Widget _buildKeyPoints(LegalDoc doc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Puntos clave', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          const SizedBox(height: 14),
          for (final s in doc.summary)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_rounded, size: 17, color: OhtliColors.accentText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s, style: GoogleFonts.inter(fontSize: 14.5, color: OhtliColors.onyx.withValues(alpha: 0.9), height: 1.55))),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text('Este resumen es informativo y no sustituye el texto completo.',
              style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
        ],
      ),
    );
  }

  // ───────────────────────── Secciones ─────────────────────────

  Widget _buildSection(int i, LegalSection section) {
    final key = _sectionKeys.putIfAbsent(i, () => GlobalKey());
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.only(top: 32),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: OhtliColors.cardBorder))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title,
              style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.w700, color: OhtliColors.onyx, letterSpacing: -0.2)),
          const SizedBox(height: 14),
          for (final p in section.body.split('\n'))
            if (p.trim().isEmpty)
              const SizedBox(height: 10)
            else if (p.startsWith('• '))
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 11),
                      child: Container(width: 6, height: 1.5, color: OhtliColors.onyx.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: SelectableText(p.substring(2), style: _bodyStyle)),
                  ],
                ),
              )
            else
              Padding(padding: const EdgeInsets.only(bottom: 4), child: SelectableText(p, style: _bodyStyle)),
        ],
      ),
    );
  }

  // ───────────────────────── Contacto ─────────────────────────

  Widget _buildContact() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mail_outline_rounded, size: 22, color: OhtliColors.accentText),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contacto', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                const SizedBox(height: 4),
                Text('Para dudas sobre este documento o para ejercer tus derechos, escríbenos a:',
                    style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.5)),
                const SizedBox(height: 6),
                SelectableText(LegalInfo.privacyEmail,
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: OhtliColors.accentText)),
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
            icon: Icon(Icons.copy_rounded, size: 19, color: OhtliColors.subtleText),
          ),
        ],
      ),
    );
  }
}

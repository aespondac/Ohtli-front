// ignore_for_file: deprecated_member_use

import '../../widgets/ohtli_account_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_theme_toggle.dart';
import '../../widgets/ohtli_service_icon.dart';
import '../places/places_page.dart';
import '../legal/legal_content.dart';

/// Estado comercial de cada producto de la API.
enum _ApiStatus { available, beta, soon }

class _ApiProduct {
  final IconData icon;
  final String name;
  final String tagline;
  final String description;
  final _ApiStatus status;
  final Color color;

  const _ApiProduct(this.icon, this.name, this.tagline, this.description, this.status, this.color);
}

/// Landing comercial de api.ohtli.quest (B2B y desarrolladores).
/// No expone rutas ni detalles de implementación; el acceso es empresarial y bajo solicitud.
class ApiLandingPage extends StatefulWidget {
  final VoidCallback onLoginRedirect;
  final VoidCallback? onRegisterRedirect;
  final void Function(LegalDocId doc)? onOpenLegal;

  /// Nombre de la cuenta de Ohtli con sesión (SSO); null si no hay sesión.
  final String? accountLabel;

  const ApiLandingPage({
    super.key,
    required this.onLoginRedirect,
    this.onRegisterRedirect,
    this.onOpenLegal,
    this.accountLabel,
  });

  @override
  State<ApiLandingPage> createState() => _ApiLandingPageState();
}

class _ApiLandingPageState extends State<ApiLandingPage> {
  final _scrollController = ScrollController();
  final _productsKey = GlobalKey();
  final _useCasesKey = GlobalKey();
  final _devKey = GlobalKey();

  late final Future<int> _catalogCount = PlacesPage.loadCatalog().then((l) => l.length).catchError((_) => 0);

  static const List<_ApiProduct> _products = [
    _ApiProduct(
      Icons.travel_explore_rounded,
      'Places API',
      'Catálogo cultural enriquecido',
      'Lugares de la CDMX con categoría, ubicación, precio estimado, horarios, alcaldía, ambiente y una descripción curada con IA.',
      _ApiStatus.available,
      Color(0xFF2C666E),
    ),
    _ApiProduct(
      Icons.route_rounded,
      'Itinerary API',
      'Rutas optimizadas con IA',
      'Itinerarios que respetan tiempo, presupuesto y gustos, con paradas ordenadas para aprovechar mejor el recorrido.',
      _ApiStatus.available,
      Color(0xFFE2711D),
    ),
    _ApiProduct(
      Icons.fingerprint_rounded,
      'Cultural Match API',
      'Afinidad cultural',
      'Convierte preferencias en un perfil cultural y encuentra los lugares que mejor conectan con cada persona.',
      _ApiStatus.available,
      Color(0xFF6C3953),
    ),
    _ApiProduct(
      Icons.graphic_eq_rounded,
      'Vibe & Mood API',
      'Lectura del ambiente',
      'Interpreta el ambiente y el estado de ánimo asociados a un lugar o a una descripción en lenguaje natural.',
      _ApiStatus.beta,
      Color(0xFF3949AB),
    ),
    _ApiProduct(
      Icons.layers_rounded,
      'Layers Weight API',
      'Capas para decidir',
      'Indicadores por lugar sobre seguridad, costo y tiempo de visita para alimentar tus modelos de decisión.',
      _ApiStatus.soon,
      Color(0xFF00897B),
    ),
    _ApiProduct(
      Icons.hub_rounded,
      'Honeyspots API',
      'Ubicaciones similares',
      'A partir de un lugar objetivo, sugiere zonas de la CDMX con un perfil parecido. Ideal para expansión y site selection.',
      _ApiStatus.soon,
      Color(0xFF8D6E63),
    ),
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
    }
  }

  VoidCallback get _register => widget.onRegisterRedirect ?? widget.onLoginRedirect;

  double _hPad(double w) => w < 700 ? 20 : (w < 1100 ? 40 : (w * 0.045).clamp(56.0, 120.0));

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 800;
    final pad = EdgeInsets.symmetric(horizontal: _hPad(width));

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: pad, child: _buildNav(isMobile)),
              Padding(padding: pad, child: _buildHero(isMobile)),
              SizedBox(height: isMobile ? 40 : 64),
              Padding(padding: pad, child: _buildStats(isMobile)),
              SizedBox(key: _productsKey, height: isMobile ? 64 : 104),
              Padding(padding: pad, child: _buildProducts(isMobile, width)),
              SizedBox(key: _useCasesKey, height: isMobile ? 64 : 104),
              Padding(padding: pad, child: _buildUseCases(isMobile, width)),
              SizedBox(key: _devKey, height: isMobile ? 64 : 104),
              Padding(padding: pad, child: _buildIntegration(isMobile, width)),
              SizedBox(height: isMobile ? 64 : 104),
              Padding(padding: pad, child: _buildFinalCta(isMobile)),
              const SizedBox(height: 48),
              Padding(padding: pad, child: _buildFooter(isMobile)),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Navegación ─────────────────────────

  Widget _buildNav(bool isMobile) {
    Widget link(String label, GlobalKey key) => TextButton(
          onPressed: () => _scrollTo(key),
          style: TextButton.styleFrom(
            foregroundColor: OhtliColors.subtleText,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          child: Text(label),
        );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 16 : 24),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/logo.svg',
            height: isMobile ? 22 : 26,
            colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: OhtliColors.onyx, borderRadius: BorderRadius.circular(8)),
            child: Text('API',
                style: GoogleFonts.firaCode(fontSize: 11.5, fontWeight: FontWeight.w700, color: OhtliColors.cloudDancer, letterSpacing: 0.6)),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 32),
            link('Productos', _productsKey),
            link('Casos de uso', _useCasesKey),
            link('Seguridad', _devKey),
          ],
          const Spacer(),
          const OhtliThemeToggle(),
          SizedBox(width: isMobile ? 4 : 10),
          if (widget.accountLabel != null)
            OhtliAccountChip(compact: isMobile)
          else if (!isMobile)
            TextButton(
              onPressed: widget.onLoginRedirect,
              style: TextButton.styleFrom(
                foregroundColor: OhtliColors.onyx,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              child: const Text('Iniciar sesión'),
            ),
          const SizedBox(width: 6),
          ElevatedButton(
            onPressed: _register,
            style: ElevatedButton.styleFrom(
              backgroundColor: OhtliColors.onyx,
              foregroundColor: OhtliColors.cloudDancer,
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 20, vertical: 13),
              shape: const StadiumBorder(),
              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            child: Text(isMobile ? 'Acceso' : 'Solicitar acceso'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Portada ─────────────────────────

  Widget _buildHero(bool isMobile) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'OHTLI API · INTELIGENCIA GEOESPACIAL',
          style: GoogleFonts.firaCode(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: OhtliColors.accentText),
        ),
        const SizedBox(height: 18),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'La inteligencia cultural\nde la CDMX, '),
            TextSpan(text: 'en una API.', style: TextStyle(color: OhtliColors.accentText)),
          ]),
          style: GoogleFonts.outfit(
            fontSize: isMobile ? 38 : 60,
            fontWeight: FontWeight.w800,
            color: OhtliColors.onyx,
            height: 1.02,
            letterSpacing: isMobile ? -1.0 : -2.0,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Text(
            'Lugares enriquecidos, afinidad semántica e itinerarios optimizados para que tu producto entienda la ciudad. '
            'Pensada para empresas de turismo, movilidad, retail y para equipos de desarrollo.',
            style: GoogleFonts.inter(fontSize: isMobile ? 15.5 : 17, color: OhtliColors.subtleText, height: 1.6),
          ),
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: _register,
              icon: const Icon(Icons.vpn_key_rounded, size: 18),
              label: const Text('Solicitar acceso empresarial'),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
                shape: const StadiumBorder(),
                textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _scrollTo(_devKey),
              icon: const Icon(Icons.verified_user_rounded, size: 18),
              label: const Text('Cómo integrarla'),
              style: OutlinedButton.styleFrom(
                foregroundColor: OhtliColors.onyx,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
                side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.18)),
                shape: const StadiumBorder(),
                textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ],
        ),
      ],
    );

    final code = _CodeWindow(
      title: 'Ejemplo de respuesta',
      lines: const [
        _CodeLine('{', _Tone.plain),
        _CodeLine('  "name": "Museo del Axolote",', _Tone.string),
        _CodeLine('  "category": "museo",', _Tone.string),
        _CodeLine('  "alcaldia": "Álvaro Obregón",', _Tone.string),
        _CodeLine('  "price_level": 1,', _Tone.number),
        _CodeLine('  "vibe": ["cultural", "histórico", "arte"],', _Tone.string),
        _CodeLine('  "affinity": 0.94', _Tone.number),
        _CodeLine('}', _Tone.plain),
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const SizedBox(height: 16), text, const SizedBox(height: 36), code],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 11, child: text),
          const SizedBox(width: 48),
          Expanded(flex: 10, child: code),
        ],
      ),
    );
  }

  // ───────────────────────── Cifras ─────────────────────────

  Widget _buildStats(bool isMobile) {
    return FutureBuilder<int>(
      future: _catalogCount,
      builder: (context, snap) {
        final count = snap.data ?? 0;
        final items = [
          (count >= 1000 || count == 0 ? '1,000+' : '$count', 'lugares culturales curados'),
          ('IA', 'afinidad cultural semántica'),
          ('HTTPS', 'acceso cifrado y controlado'),
          ('CDMX', 'cobertura de las 16 alcaldías'),
        ];
        return LayoutBuilder(builder: (context, c) {
          final itemW = isMobile ? (c.maxWidth - 16) / 2 : (c.maxWidth - 48) / 4;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: items
                .map((it) => Container(
                      width: itemW,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: OhtliColors.cardBg,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: OhtliColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.$1,
                              style: GoogleFonts.outfit(fontSize: isMobile ? 26 : 34, fontWeight: FontWeight.w800, color: OhtliColors.onyx, letterSpacing: -0.8)),
                          const SizedBox(height: 4),
                          Text(it.$2, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4)),
                        ],
                      ),
                    ))
                .toList(),
          );
        });
      },
    );
  }

  // ───────────────────────── Encabezado de sección ─────────────────────────

  Widget _sectionHeader(String eyebrow, String title, String subtitle, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(eyebrow.toUpperCase(),
            style: GoogleFonts.firaCode(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: OhtliColors.accentText)),
        const SizedBox(height: 12),
        Text(title,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 28 : 42,
              fontWeight: FontWeight.w800,
              color: OhtliColors.onyx,
              letterSpacing: isMobile ? -0.6 : -1.3,
              height: 1.08,
            )),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(subtitle, style: GoogleFonts.inter(fontSize: 15.5, color: OhtliColors.subtleText, height: 1.55)),
        ),
      ],
    );
  }

  // ───────────────────────── Productos ─────────────────────────

  Widget _buildProducts(bool isMobile, double width) {
    final cols = isMobile ? 1 : (width < 1150 ? 2 : 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'Productos',
          'Una plataforma, varias capas de inteligencia',
          'Empieza con el catálogo y suma afinidad, itinerarios y análisis conforme crece tu producto.',
          isMobile,
        ),
        const SizedBox(height: 32),
        LayoutBuilder(builder: (context, c) {
          const gap = 18.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: _products.map((p) => SizedBox(width: w, child: _ProductCard(product: p))).toList(),
          );
        }),
      ],
    );
  }

  // ───────────────────────── Casos de uso ─────────────────────────

  Widget _buildUseCases(bool isMobile, double width) {
    final cases = [
      (Icons.hotel_rounded, 'Turismo y hotelería', 'Recomienda experiencias a tus huéspedes y arma itinerarios de un día desde tu propiedad.'),
      (Icons.local_shipping_rounded, 'Movilidad y logística', 'Ordena paradas y estima tiempos de visita con rutas optimizadas sobre la red de la ciudad.'),
      (Icons.storefront_rounded, 'Retail y expansión', 'Entiende el entorno cultural y comercial de una zona antes de abrir una sucursal.'),
      (Icons.campaign_rounded, 'Marketing y agencias', 'Segmenta audiencias por afinidad cultural y activa campañas en los lugares correctos.'),
      (Icons.account_balance_rounded, 'Gobierno y cultura', 'Mide y difunde la oferta cultural por alcaldía con datos abiertos y enriquecidos.'),
      (Icons.code_rounded, 'Apps y startups', 'Integra lugares y rutas inteligentes en tu app sin construir tu propio motor.'),
    ];
    final cols = isMobile ? 1 : (width < 1150 ? 2 : 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Casos de uso', 'Hecha para empresas y para quien construye', 'B2B para integrar inteligencia de ciudad en tu operación; B2D para lanzar productos más rápido.', isMobile),
        const SizedBox(height: 32),
        LayoutBuilder(builder: (context, c) {
          const gap = 18.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: cases
                .map((u) => SizedBox(
                      width: w,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: OhtliColors.cardBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OhtliServiceIcon(icon: u.$1, color: OhtliColors.stormyTeal, size: 46, soft: true),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u.$2, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                                  const SizedBox(height: 6),
                                  Text(u.$3, style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          );
        }),
      ],
    );
  }

  // ───────────────────────── Integración y seguridad ─────────────────────────

  Widget _buildIntegration(bool isMobile, double width) {
    final steps = [
      ('1', 'Solicita tu acceso', 'Cuéntanos qué vas a construir y el volumen que esperas.'),
      ('2', 'Recibe tus credenciales', 'Te damos acceso empresarial y la documentación privada de integración.'),
      ('3', 'Integra con acompañamiento', 'Nuestro equipo técnico te acompaña hasta tu salida a producción.'),
    ];
    final pillars = [
      (Icons.key_rounded, 'Acceso controlado', 'Acceso empresarial por cuenta y bajo solicitud; la documentación técnica se comparte solo con clientes.', OhtliColors.stormyTeal),
      (Icons.lock_rounded, 'Cifrado en tránsito', 'Todas las solicitudes viajan por HTTPS.', OhtliColors.xoconostle),
      (Icons.privacy_tip_rounded, 'Privacidad primero', 'Trabajamos con información de lugares; los perfiles de gustos de las personas son privados.', OhtliColors.cempasuchil),
      (Icons.cloud_done_rounded, 'Infraestructura en la nube', 'Servicios sin servidor que escalan con la demanda de tu producto.', const Color(0xFF3949AB)),
    ];

    final stepsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Integración', 'De la solicitud a producción', 'Un proceso acompañado, pensado para equipos de producto y de ingeniería.', isMobile),
        const SizedBox(height: 28),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: OhtliColors.onyx, shape: BoxShape.circle),
                  child: Text(s.$1, style: GoogleFonts.firaCode(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.cloudDancer)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$2, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                      const SizedBox(height: 3),
                      Text(s.$3, style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final security = LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 520 ? 1 : 2;
      const gap = 16.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: pillars
            .map((p) => Container(
                  width: w,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: OhtliColors.cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: OhtliColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OhtliServiceIcon(icon: p.$1, color: p.$4, size: 48),
                      const SizedBox(height: 16),
                      Text(p.$2, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                      const SizedBox(height: 5),
                      Text(p.$3, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.5)),
                    ],
                  ),
                ))
            .toList(),
      );
    });

    if (isMobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [stepsColumn, const SizedBox(height: 12), security]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 9, child: stepsColumn),
        const SizedBox(width: 48),
        Expanded(flex: 12, child: Padding(padding: const EdgeInsets.only(top: 40), child: security)),
      ],
    );
  }

  // ───────────────────────── Llamado final y pie ─────────────────────────

  Widget _buildFinalCta(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 56, vertical: isMobile ? 40 : 64),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isMobile ? 28 : 36),
        color: const Color(0xFF0A090C),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lleva la ciudad a tu producto',
              style: GoogleFonts.outfit(fontSize: isMobile ? 30 : 46, fontWeight: FontWeight.w800, color: Colors.white, height: 1.05, letterSpacing: -1)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              'Cuéntanos tu caso de uso y te damos acceso empresarial, acompañamiento técnico y un plan a la medida de tu volumen.',
              style: GoogleFonts.inter(fontSize: 15, color: Colors.white.withValues(alpha: 0.75), height: 1.55),
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton(
                onPressed: _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.cempasuchil,
                  foregroundColor: const Color(0xFF1A120B),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 19),
                  shape: const StadiumBorder(),
                  textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                child: const Text('Solicitar acceso empresarial'),
              ),
              TextButton(
                onPressed: widget.onLoginRedirect,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19),
                  textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                child: const Text('Ya tengo cuenta'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isMobile) {
    return Container(
      padding: const EdgeInsets.only(top: 28),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: OhtliColors.cardBorder))),
      child: Flex(
        direction: isMobile ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SvgPicture.asset('assets/logo.svg', height: 20, colorFilter: ColorFilter.mode(OhtliColors.onyx, BlendMode.srcIn)),
          const SizedBox(width: 12, height: 8),
          Text('Ohtli API · © ${DateTime.now().year} Ohtli',
              style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
          if (!isMobile) const Spacer(),
          if (widget.onOpenLegal != null)
            Wrap(
              spacing: 4,
              children: [
                for (final (label, doc) in const [
                  ('Términos de la API', LegalDocId.api),
                  ('Privacidad', LegalDocId.privacy),
                  ('Cookies', LegalDocId.cookies),
                ])
                  TextButton(
                    onPressed: () => widget.onOpenLegal!(doc),
                    style: TextButton.styleFrom(
                      foregroundColor: OhtliColors.subtleText,
                      textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    child: Text(label),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── Piezas visuales ─────────────────────────

class _ProductCard extends StatefulWidget {
  final _ApiProduct product;
  const _ProductCard({required this.product});

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final (String statusLabel, Color statusColor) = switch (p.status) {
      _ApiStatus.available => ('Disponible', const Color(0xFF10B981)),
      _ApiStatus.beta => ('Beta', OhtliColors.cempasuchil),
      _ApiStatus.soon => ('Próximamente', OhtliColors.subtleText),
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        height: 300,
        padding: const EdgeInsets.all(24),
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: OhtliColors.cardBg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _hover ? p.color.withValues(alpha: 0.5) : OhtliColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: (_hover ? p.color : Colors.black).withValues(alpha: _hover ? 0.18 : 0.04),
              blurRadius: _hover ? 30 : 12,
              offset: Offset(0, _hover ? 16 : 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OhtliServiceIcon(icon: p.icon, color: p.color, size: 56),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(30)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(statusLabel, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: statusColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(p.name, style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
            Text(p.tagline, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: p.color)),
            const SizedBox(height: 10),
            Text(p.description,
                maxLines: 4, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.5)),
            const Spacer(),
            Row(
              children: [
                Icon(
                  p.status == _ApiStatus.available ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 16,
                  color: p.status == _ApiStatus.available ? const Color(0xFF10B981) : OhtliColors.subtleText,
                ),
                const SizedBox(width: 6),
                Text(
                  switch (p.status) {
                    _ApiStatus.available => 'Lista para integrar',
                    _ApiStatus.beta => 'Acceso anticipado para clientes',
                    _ApiStatus.soon => 'En desarrollo · lista de espera',
                  },
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _Tone { plain, command, string, number }

class _CodeLine {
  final String text;
  final _Tone tone;
  const _CodeLine(this.text, this.tone);
}

/// Ventana de código siempre oscura (estilo terminal), con botón para copiar.
class _CodeWindow extends StatelessWidget {
  final String title;
  final List<_CodeLine> lines;

  const _CodeWindow({required this.title, required this.lines});

  Color _color(_Tone t) => switch (t) {
        _Tone.command => const Color(0xFF7EE0C3),
        _Tone.string => const Color(0xFFFFC97A),
        _Tone.number => const Color(0xFF9AB8FF),
        _Tone.plain => const Color(0xFFE6E4DF),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E0F12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 40, offset: const Offset(0, 20))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
            child: Row(
              children: [
                for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)])
                  Container(
                    margin: const EdgeInsets.only(right: 7),
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white.withValues(alpha: 0.55))),
                ),
                IconButton(
                  tooltip: 'Copiar',
                  iconSize: 17,
                  color: Colors.white.withValues(alpha: 0.6),
                  onPressed: () {
                    final text = lines.map((l) => l.text.replaceFirst(RegExp(r'^\$ '), '')).join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Código copiado', style: GoogleFonts.inter(color: Colors.white)),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: OhtliColors.stormyTeal,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines
                  .map((l) => Text(
                        l.text.isEmpty ? ' ' : l.text,
                        style: GoogleFonts.firaCode(fontSize: 13, height: 1.65, color: _color(l.tone)),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

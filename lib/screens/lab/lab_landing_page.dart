import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_theme_toggle.dart';
import '../../widgets/ohtli_service_icon.dart';
import 'widgets/particles_background.dart';

class LabLandingPage extends StatefulWidget {
  final VoidCallback onLoginRedirect;

  const LabLandingPage({
    super.key,
    required this.onLoginRedirect,
  });

  @override
  State<LabLandingPage> createState() => _LabLandingPageState();
}

class _LabLandingPageState extends State<LabLandingPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _experimentsSectionKey = GlobalKey();
  final GlobalKey _pipelineSectionKey = GlobalKey();

  void _scrollToKey(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _openProductionSite() {
    if (kIsWeb) {
      html.window.open('https://ohtli.quest', '_blank');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo animado sutil de partículas
          const Positioned.fill(
            child: Opacity(
              opacity: 0.35,
              child: ParticlesBackground(),
            ),
          ),

          // Contenido principal
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children: [
                    // Header de navegación prolijo y funcional
                    _buildHeader(isMobile),

                    // Hero Principal con propósito explícito de banco de pruebas pre-producción
                    _buildHeroSection(isMobile),

                    // Barra de telemetría y KPIs de Labs
                    _buildTelemetryStrip(isMobile),

                    const SizedBox(height: 48),

                    // Sección: Pipeline de Integración (De Labs a Ohtli.quest)
                    Container(
                      key: _pipelineSectionKey,
                      child: _buildPipelineSection(isMobile),
                    ),

                    const SizedBox(height: 64),

                    // Sección: Experimentos en Validación
                    Container(
                      key: _experimentsSectionKey,
                      child: _buildExperimentsSection(isMobile),
                    ),

                    // Sección de aislamiento de sandbox y seguridad
                    _buildSandboxAssuranceSection(isMobile),

                    // Footer
                    _buildFooter(isMobile),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        color: OhtliColors.cloudDancer.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(color: OhtliColors.cardBorder),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo + Tag Labs
          Row(
            children: [
              SvgPicture.asset(
                'assets/logo.svg',
                height: 30,
                colorFilter: ColorFilter.mode(OhtliColors.onyx, BlendMode.srcIn),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.science_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      'LABS',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Opciones centrales para Desktop
          if (!isMobile)
            Row(
              children: [
                _buildNavTextButton(
                  title: 'Pipeline a Ohtli.quest',
                  onTap: () => _scrollToKey(_pipelineSectionKey),
                ),
                const SizedBox(width: 8),
                _buildNavTextButton(
                  title: 'Experimentos',
                  onTap: () => _scrollToKey(_experimentsSectionKey),
                ),
                const SizedBox(width: 8),
                _buildNavTextButton(
                  title: 'Ohtli.quest ↗',
                  onTap: _openProductionSite,
                  isExternal: true,
                ),
              ],
            ),

          // Botones de acción derecha
          Row(
            children: [
              if (!isMobile) ...[
                // Badge de estado en tiempo real
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: OhtliColors.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: OhtliColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981), // Verde activo
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Banco de Pruebas Activo',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OhtliColors.subtleText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const OhtliThemeToggle(),
              const SizedBox(width: 6),
              // Reporte y tablero de resultados de las pruebas (labs.ohtli.quest/resultados)
              TextButton.icon(
                onPressed: () => html.window.location.href = '/resultados',
                icon: const Icon(Icons.insights_rounded, size: 16),
                label: Text(isMobile ? 'Resultados' : 'Resultados y paper',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: widget.onLoginRedirect,
                icon: const Icon(Icons.login_rounded, size: 16),
                label: Text(
                  isMobile ? 'Acceso' : 'Ingresar a Labs',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.onyx,
                  foregroundColor: OhtliColors.cloudDancer,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavTextButton({
    required String title,
    required VoidCallback onTap,
    bool isExternal = false,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: OhtliColors.subtleText,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: isExternal ? FontWeight.w600 : FontWeight.w500,
          color: isExternal ? OhtliColors.stormyTeal : OhtliColors.onyx,
        ),
      ),
    );
  }

  Widget _buildHeroSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 48,
        vertical: isMobile ? 48 : 80,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Chip superior de propósito
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: OhtliColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hub_rounded, size: 16, color: OhtliColors.stormyTeal),
                const SizedBox(width: 8),
                Text(
                  'LABORATORIO DE INNOVACIÓN DE OHTLI',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: OhtliColors.stormyTeal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Título Principal
          Text(
            'Donde la innovación se prueba\nantes de llegar a ti',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 42 : 72,
              fontWeight: FontWeight.w800,
              color: OhtliColors.onyx,
              height: 1.08,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Párrafo descriptivo enfocado en la función de staging y evaluación
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              'Ohtli Labs es nuestro laboratorio de innovación. Aquí nacen los nuevos modelos de recomendación cultural, de rutas y de agentes de IA, y se ponen a prueba en un entorno aislado y protegido. Solo lo que demuestra ser útil, estable y seguro llega a Ohtli.quest.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 16 : 19,
                fontWeight: FontWeight.w400,
                color: OhtliColors.subtleText,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 36),

          // Botones de llamada a la acción
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: widget.onLoginRedirect,
                icon: const Icon(Icons.science_rounded, size: 18),
                label: const Text('Iniciar Banco de Pruebas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _scrollToKey(_experimentsSectionKey),
                icon: const Icon(Icons.explore_rounded, size: 18),
                label: const Text('Ver Experimentos en Curso'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OhtliColors.onyx,
                  side: BorderSide(color: OhtliColors.cardBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryStrip(bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 48),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              children: [
                _buildKpiItem('5 experimentos', 'En evaluación activa', Icons.science_rounded),
                const Divider(height: 24),
                _buildKpiItem('IA aplicada', 'Modelos culturales propios', Icons.psychology_rounded),
                const Divider(height: 24),
                _buildKpiItem('Entorno aislado', 'Separado de producción', Icons.verified_user_rounded),
                const Divider(height: 24),
                _buildKpiItem('Validación continua', 'Antes de cada lanzamiento', Icons.rocket_launch_rounded),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildKpiItem('5 experimentos', 'En evaluación activa', Icons.science_rounded),
                _buildVerticalDivider(),
                _buildKpiItem('IA aplicada', 'Modelos culturales propios', Icons.psychology_rounded),
                _buildVerticalDivider(),
                _buildKpiItem('Entorno aislado', 'Separado de producción', Icons.verified_user_rounded),
                _buildVerticalDivider(),
                _buildKpiItem('Validación continua', 'Antes de cada lanzamiento', Icons.rocket_launch_rounded),
              ],
            ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 40,
      width: 1,
      color: OhtliColors.cardBorder,
    );
  }

  Widget _buildKpiItem(String title, String subtitle, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: OhtliColors.stormyTeal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: OhtliColors.stormyTeal),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: OhtliColors.onyx,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: OhtliColors.subtleText,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPipelineSection(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 48,
        vertical: 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: OhtliColors.cempasuchil.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'DE LA IDEA A PRODUCCIÓN',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: const Color(0xFFB85900),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Innovación con controles en cada etapa',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 28 : 40,
              fontWeight: FontWeight.w800,
              color: OhtliColors.onyx,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              'Cada función recorre cuatro fases con revisiones de calidad, rendimiento y seguridad antes de llegar a las personas que usan Ohtli.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: OhtliColors.subtleText,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 48),

          // 4 tarjetas de fases
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _buildPipelineCard(
                step: '01',
                title: 'Investigación y prototipo',
                badge: 'Idea',
                description: 'Partimos de una hipótesis clara y diseñamos nuevos modelos de recomendación y agentes de IA para resolverla.',
                icon: Icons.lightbulb_rounded,
                color: const Color(0xFF6C5CE7),
              ),
              _buildPipelineCard(
                step: '02',
                title: 'Banco de pruebas',
                badge: 'labs.ohtli.quest',
                description: 'La comunidad lo prueba en un entorno aislado mientras medimos calidad, velocidad y estabilidad.',
                icon: Icons.science_rounded,
                color: OhtliColors.stormyTeal,
                isCurrent: true,
              ),
              _buildPipelineCard(
                step: '03',
                title: 'Revisión de seguridad',
                badge: 'Control de calidad',
                description: 'Revisamos permisos, uso de datos, costos y compatibilidad antes de aprobar cualquier lanzamiento.',
                icon: Icons.verified_user_rounded,
                color: OhtliColors.xoconostle,
              ),
              _buildPipelineCard(
                step: '04',
                title: 'Lanzamiento',
                badge: 'ohtli.quest',
                description: 'Lo que supera todas las pruebas se integra a la experiencia de viaje para todas las personas.',
                icon: Icons.rocket_launch_rounded,
                color: const Color(0xFF10B981),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineCard({
    required String step,
    required String title,
    required String badge,
    required String description,
    required IconData icon,
    required Color color,
    bool isCurrent = false,
  }) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent ? color : OhtliColors.cardBorder,
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isCurrent ? color.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                step,
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OhtliServiceIcon(icon: icon, color: color, size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: OhtliColors.subtleText,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExperimentsSection(bool isMobile) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        ),
        border: Border(
          top: BorderSide(color: OhtliColors.cardBorder),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 64,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'CATÁLOGO EXPERIMENTAL',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: OhtliColors.stormyTeal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Lo que estamos construyendo',
                      style: GoogleFonts.outfit(
                        fontSize: isMobile ? 26 : 36,
                        fontWeight: FontWeight.w800,
                        color: OhtliColors.onyx,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Prueba cada herramienta, comparte lo que encuentres y ayúdanos a decidir qué llega a Ohtli.quest.',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: OhtliColors.subtleText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),

          // Grid de experimentos
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              _buildExperimentCard(
                category: 'GEOINTELIGENCIA',
                status: 'CASI LISTO',
                statusColor: const Color(0xFF10B981),
                targetModule: 'Ohtli.quest / Lugares',
                title: 'Descubridor de lugares',
                description: 'Encuentra y consolida lugares de varias fuentes para una zona de la ciudad y los valida antes de publicarlos.',
                icon: Icons.travel_explore_rounded,
                color: OhtliColors.stormyTeal,
                metrics: 'Cobertura CDMX · Validación previa',
              ),
              _buildExperimentCard(
                category: 'MODELOS SEMÁNTICOS',
                status: 'BETA',
                statusColor: OhtliColors.xoconostle,
                targetModule: 'Ohtli.quest / Recomendaciones',
                title: 'Perfil cultural con IA',
                description: 'Traduce los gustos de cada viajero en una huella cultural y la compara con los lugares para encontrar los más afines.',
                icon: Icons.fingerprint_rounded,
                color: OhtliColors.xoconostle,
                metrics: 'Afinidad semántica · Privado por diseño',
              ),
              _buildExperimentCard(
                category: 'MOVILIDAD URBANA',
                status: 'BETA',
                statusColor: const Color(0xFFE2711D),
                targetModule: 'Ohtli.quest / Planificador',
                title: 'Motor de rutas',
                description: 'Calcula recorridos a pie, en bici y en auto sobre la red de la ciudad, con infraestructura propia.',
                icon: Icons.route_rounded,
                color: const Color(0xFFE2711D),
                metrics: 'A pie · Bici · Auto',
              ),
              _buildExperimentCard(
                category: 'AGENTES AUTÓNOMOS',
                status: 'ALFA',
                statusColor: const Color(0xFF6C5CE7),
                targetModule: 'Ohtli.quest / Asistente Virtual',
                title: 'Consola de agentes',
                description: 'Conversa con los agentes de IA de Ohtli y revisa paso a paso cómo razonan y responden.',
                icon: Icons.smart_toy_rounded,
                color: const Color(0xFF6C5CE7),
                metrics: 'Transparencia · Diagnóstico',
              ),
              _buildExperimentCard(
                category: 'NUEVOS SERVICIOS',
                status: 'EN PRUEBAS',
                statusColor: const Color(0xFF00CEC9),
                targetModule: 'api.ohtli.quest',
                title: 'Servicios experimentales',
                description: 'Nuevos análisis de ambiente y estado de ánimo que se evalúan antes de sumarse a la API de Ohtli.',
                icon: Icons.auto_awesome_rounded,
                color: const Color(0xFF00CEC9),
                metrics: 'Ambiente · Estado de ánimo',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExperimentCard({
    required String category,
    required String status,
    required Color statusColor,
    required String targetModule,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String metrics,
  }) {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera de la tarjeta con gradiente sutil
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.15),
                  color.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OhtliServiceIcon(icon: icon, color: color, size: 52),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: OhtliColors.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Cuerpo de la tarjeta
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: OhtliColors.onyx,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: OhtliColors.subtleText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),

                // Destino en Ohtli.quest
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: OhtliColors.cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: OhtliColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.turn_right_rounded, size: 14, color: OhtliColors.stormyTeal),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          targetModule,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: OhtliColors.stormyTeal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Botón para ingresar al experimento
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onLoginRedirect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OhtliColors.cardBg,
                      foregroundColor: OhtliColors.onyx,
                      elevation: 0,
                      side: BorderSide(color: OhtliColors.cardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Probar en Sandbox',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSandboxAssuranceSection(bool isMobile) {
    final pillars = [
      (Icons.shield_rounded, 'Entorno aislado', 'Los experimentos usan datos de prueba separados de producción y no tocan cuentas, viajes ni información personal de Ohtli.quest.', OhtliColors.stormyTeal),
      (Icons.lock_person_rounded, 'Acceso autenticado', 'Para entrar a Labs se inicia sesión y se aceptan los términos del laboratorio; cada prueba queda asociada a una cuenta.', OhtliColors.xoconostle),
      (Icons.fact_check_rounded, 'Pruebas automáticas', 'Cada cambio pasa por pruebas automáticas antes de publicarse; si alguna falla, no se despliega.', const Color(0xFF3949AB)),
      (Icons.privacy_tip_rounded, 'Privacidad por diseño', 'Los perfiles de gustos son privados y solo su dueño puede consultarlos o modificarlos.', OhtliColors.cempasuchil),
    ];
    return Container(
      width: double.infinity,
      color: OhtliColors.cardBg,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: isMobile ? 48 : 72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Text(
                'SEGURIDAD DESDE EL DISEÑO',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: OhtliColors.accentText),
              ),
              const SizedBox(height: 12),
              Text(
                'Experimentar sin poner en riesgo a nadie',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: isMobile ? 28 : 38,
                  fontWeight: FontWeight.w800,
                  color: OhtliColors.onyx,
                  letterSpacing: -0.8,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  'La innovación en Ohtli avanza rápido porque está protegida: cada experimento vive en un espacio controlado hasta que demuestra ser seguro.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.subtleText, height: 1.55),
                ),
              ),
              const SizedBox(height: 36),
              LayoutBuilder(builder: (context, c) {
                final cols = isMobile ? 1 : (c.maxWidth < 900 ? 2 : 4);
                const gap = 18.0;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: pillars
                      .map((p) => Container(
                            width: w,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: OhtliColors.innerCardBg,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: OhtliColors.cardBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OhtliServiceIcon(icon: p.$1, color: p.$4, size: 50),
                                const SizedBox(height: 18),
                                Text(p.$2, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                                const SizedBox(height: 6),
                                Text(p.$3, style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.5)),
                              ],
                            ),
                          ))
                      .toList(),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(bool isMobile) {
    return Container(
      color: const Color(0xFF0A090C),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 64,
        vertical: 48,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SvgPicture.asset(
                    'assets/logo.svg',
                    height: 24,
                    colorFilter: const ColorFilter.mode(Color(0xFFF0EEE9), BlendMode.srcIn),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Ohtli Labs',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF0EEE9),
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: _openProductionSite,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1E22),
                  foregroundColor: const Color(0xFFF0EEE9),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Ir a Ohtli.quest', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_outward_rounded, size: 14),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0x22FFFFFF), height: 1),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '© ${DateTime.now().year} Ohtli Labs · Laboratorio de innovación',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFFF0EEE9).withValues(alpha: 0.5),
                ),
              ),
              InkWell(
                onTap: () {
                  if (kIsWeb) {
                    html.window.open('/#/labs/tyc', '_self');
                  }
                },
                child: Text(
                  'Términos de Labs',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFFF0EEE9).withValues(alpha: 0.7),
                    decoration: TextDecoration.underline,
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

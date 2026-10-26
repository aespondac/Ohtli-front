import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/colors.dart';
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
                  title: 'Ohtli.quest (Prod) ↗',
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
                  'ENTORNO DE PRUEBAS PREVIO A OHTLI.QUEST',
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
            'El banco de pruebas para\nel futuro de Ohtli.quest',
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
              'Ohtli Labs es el banco de experimentación y calibración técnica. Aquí evaluamos modelos de recomendación cultural, motores de ruteo y agentes geospaciales en un sandbox aislado antes de incorporarlos a la experiencia principal de Ohtli.quest.',
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
                _buildKpiItem('5 Experimentos', 'En validación activa', Icons.tune_rounded),
                const Divider(height: 24),
                _buildKpiItem('Yollotl Engine', 'v2.4 en Staging', Icons.memory_rounded),
                const Divider(height: 24),
                _buildKpiItem('Sandbox Aislado', 'Cero impacto a prod', Icons.security_rounded),
                const Divider(height: 24),
                _buildKpiItem('Destino Ohtli.quest', 'Integración continua', Icons.rocket_launch_rounded),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildKpiItem('5 Experimentos', 'En validación activa', Icons.tune_rounded),
                _buildVerticalDivider(),
                _buildKpiItem('Yollotl Engine', 'v2.4 en Staging', Icons.memory_rounded),
                _buildVerticalDivider(),
                _buildKpiItem('Sandbox Aislado', 'Cero impacto a prod', Icons.security_rounded),
                _buildVerticalDivider(),
                _buildKpiItem('Destino Ohtli.quest', 'Integración continua', Icons.rocket_launch_rounded),
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
              'CICLO DE GRADUACIÓN DE CARACTERÍSTICAS',
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
            'De la hipótesis en Labs a producción en Ohtli.quest',
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
              'Cada función pasa por un pipeline estricto de 4 fases para garantizar que no degrade la experiencia ni la velocidad de los usuarios de Ohtli.',
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
                title: 'Prototipo & Modelado',
                badge: 'Yollotl Core',
                description: 'Diseño de prompts de agentes, fórmulas vectoriales y esquemas de extracción en microservicios.',
                icon: Icons.code_rounded,
                color: const Color(0xFF6C5CE7),
              ),
              _buildPipelineCard(
                step: '02',
                title: 'Banco de Pruebas (Labs)',
                badge: 'lab.ohtli.quest',
                description: 'Pruebas de estrés por la comunidad, simulación de respuestas de red y calibración de latencia.',
                icon: Icons.science_rounded,
                color: OhtliColors.stormyTeal,
                isCurrent: true,
              ),
              _buildPipelineCard(
                step: '03',
                title: 'Candidato a Release',
                badge: 'Staging QA',
                description: 'Auditoría de cuotas de APIs, persistencia Firestore y compatibilidad móvil antes de aprobación.',
                icon: Icons.verified_rounded,
                color: OhtliColors.xoconostle,
              ),
              _buildPipelineCard(
                step: '04',
                title: 'Producción Ohtli.quest',
                badge: 'ohtli.quest',
                description: 'Integración en el generador de itinerarios y feed accesible para todos los viajeros finales.',
                icon: Icons.public_rounded,
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
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 12),
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
                      'Experimentos en evaluación activa',
                      style: GoogleFonts.outfit(
                        fontSize: isMobile ? 26 : 36,
                        fontWeight: FontWeight.w800,
                        color: OhtliColors.onyx,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Prueba cada herramienta, detecta inconsistencias y evalúa los resultados antes de su lanzamiento a producción.',
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
                status: 'CANDIDATO A PROD v1.0',
                statusColor: const Color(0xFF10B981),
                targetModule: 'Ohtli.quest / Explorador de POIs',
                title: 'Caza Lugares (Motor Recolector)',
                description: 'Dada una coordenada geográfica y radio, consulta y consolida lugares desde múltiples fuentes y permite replicar registros validados a producción.',
                icon: Icons.travel_explore_rounded,
                color: OhtliColors.stormyTeal,
                metrics: 'Soporte CDMX · Replicación Firestore',
              ),
              _buildExperimentCard(
                category: 'MODELOS SEMÁNTICOS',
                status: 'BETA v0.9',
                statusColor: OhtliColors.xoconostle,
                targetModule: 'Ohtli.quest / Onboarding & Matching',
                title: 'Vector de Gustos & Vibe (768d)',
                description: 'Construye la receta semántica de identidad cultural del viajero y genera el embedding vectorial con cálculo de similitud coseno contra lugares reales.',
                icon: Icons.fingerprint_rounded,
                color: OhtliColors.xoconostle,
                metrics: '768 dimensiones · Similitud coseno',
              ),
              _buildExperimentCard(
                category: 'MOVILIDAD URBANA',
                status: 'BETA v0.8',
                statusColor: const Color(0xFFE2711D),
                targetModule: 'Ohtli.quest / Planificador de Rutas',
                title: 'Ruteo OSRM & Ye',
                description: 'Motor de ruteo y optimización espacial sobre OpenStreetMap, independiente de cuotas externas, con perfiles de auto, bicicleta y caminata.',
                icon: Icons.directions_car_rounded,
                color: const Color(0xFFE2711D),
                metrics: 'Perfiles Car/Bike/Foot · GeoJSON',
              ),
              _buildExperimentCard(
                category: 'AGENTES AUTÓNOMOS',
                status: 'ALPHA v0.4',
                statusColor: const Color(0xFF6C5CE7),
                targetModule: 'Ohtli.quest / Asistente Virtual',
                title: 'Consola de Agentes I/O',
                description: 'Pruebas directas de diálogo con agentes de recolección y comparación. Inspección de entradas y salidas estructuradas sin filtros UI.',
                icon: Icons.smart_toy_rounded,
                color: const Color(0xFF6C5CE7),
                metrics: 'Inspección cruda · Diagnóstico I/O',
              ),
              _buildExperimentCard(
                category: 'ARQUITECTURA DISTRIBUIDA',
                status: 'ACTIVO EN STAGING',
                statusColor: const Color(0xFF00CEC9),
                targetModule: 'api.ohtli.quest / Gateway',
                title: 'APIs Satélite & Microservicios',
                description: 'Endpoints experimentales de exploración OEP, análisis de Vibe y evaluación de estado de ánimo integrados al gateway de Google Cloud Run.',
                icon: Icons.api_rounded,
                color: const Color(0xFF00CEC9),
                metrics: 'Cloud Run · Endpoints OEP/Vibe',
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OhtliColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 28, color: color),
                ),
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
    return Container(
      width: double.infinity,
      color: OhtliColors.cardBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 48,
        vertical: 40,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: OhtliColors.innerCardBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.shield_outlined, size: 32, color: OhtliColors.stormyTeal),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aislamiento de Entorno & Seguridad Garantizada',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: OhtliColors.onyx,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Las sesiones y llamadas ejecutadas en Ohtli Labs operan en colecciones de staging y no interfieren con cuentas de viajeros ni itinerarios en ohtli.quest. Una vez validada la estabilidad, el equipo de ingeniería sincroniza los modelos mediante canalizaciones seguras de CI/CD.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: OhtliColors.subtleText,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
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
                '© 2026 Ohtli Labs. Banco de Pruebas Pre-Producción.',
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

import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import '../../theme/colors.dart';
import '../../widgets/user_profile_helper.dart';

class LabsDashboardPage extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onTryOsrm;
  final VoidCallback onTryAgents;
  final VoidCallback onTryApis;
  final VoidCallback onTryRecolector;
  final VoidCallback onTryTasteVector;

  const LabsDashboardPage({
    super.key,
    required this.onLogout,
    required this.onTryOsrm,
    required this.onTryAgents,
    required this.onTryApis,
    required this.onTryRecolector,
    required this.onTryTasteVector,
  });

  @override
  State<LabsDashboardPage> createState() => _LabsDashboardPageState();
}

class _LabsDashboardPageState extends State<LabsDashboardPage> with SingleTickerProviderStateMixin {
  bool _acceptedTerms = false;
  bool _isLoading = false;

  late TabController _tabController;
  String _selectedCategory = 'Todos';
  String _searchQuery = '';

  // Telemetría states
  bool _isPingingServices = false;
  Map<String, String> _serviceStatus = {
    'Gateway (api.ohtli.quest)': 'Pendiente',
    'Yollotl Recolector Engine': 'Pendiente',
    'OSRM Routing Engine': 'Pendiente',
    'Firestore Labs Sync': 'Online',
  };
  Map<String, int> _serviceLatency = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openProductionSite() {
    if (kIsWeb) {
      html.window.open('https://ohtli.quest', '_blank');
    }
  }

  Future<void> _joinWaitlist() async {
    if (!_acceptedTerms) return;

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await UserProfileHelper.syncLabsWaitlistProfile(user);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ocurrió un error: $e', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _isPingingServices = true;
      _serviceStatus['Gateway (api.ohtli.quest)'] = 'Verificando...';
      _serviceStatus['Yollotl Recolector Engine'] = 'Verificando...';
      _serviceStatus['OSRM Routing Engine'] = 'Verificando...';
    });

    final stopwatch = Stopwatch();

    // 1. Gateway
    try {
      stopwatch.start();
      final res = await http.get(Uri.parse('https://api.ohtli.quest/health')).timeout(const Duration(seconds: 4));
      stopwatch.stop();
      _serviceStatus['Gateway (api.ohtli.quest)'] = res.statusCode == 200 ? 'Operativo (200 OK)' : 'HTTP ${res.statusCode}';
      _serviceLatency['Gateway (api.ohtli.quest)'] = stopwatch.elapsedMilliseconds;
    } catch (e) {
      _serviceStatus['Gateway (api.ohtli.quest)'] = 'Inaccesible / Timeout';
    }

    // 2. Yollotl Engine
    try {
      stopwatch.reset();
      stopwatch.start();
      final res = await http.get(Uri.parse('https://api.ohtli.quest/v1/api/recolector/health')).timeout(const Duration(seconds: 4));
      stopwatch.stop();
      _serviceStatus['Yollotl Recolector Engine'] = res.statusCode == 200 ? 'Operativo (200 OK)' : 'HTTP ${res.statusCode}';
      _serviceLatency['Yollotl Recolector Engine'] = stopwatch.elapsedMilliseconds;
    } catch (e) {
      _serviceStatus['Yollotl Recolector Engine'] = 'Sandbox Mock Activo';
    }

    // 3. OSRM
    try {
      stopwatch.reset();
      stopwatch.start();
      final res = await http.get(Uri.parse('https://api.ohtli.quest/api/osrm/health')).timeout(const Duration(seconds: 4));
      stopwatch.stop();
      _serviceStatus['OSRM Routing Engine'] = res.statusCode == 200 ? 'Operativo (200 OK)' : 'HTTP ${res.statusCode}';
      _serviceLatency['OSRM Routing Engine'] = stopwatch.elapsedMilliseconds;
    } catch (e) {
      _serviceStatus['OSRM Routing Engine'] = 'Sandbox Mock Activo';
    }

    if (mounted) {
      setState(() {
        _isPingingServices = false;
      });
    }
  }

  void _showIntegrationSpecs(BuildContext context, {
    required String title,
    required String targetModule,
    required String status,
    required String readiness,
    required List<String> acceptanceCriteria,
    required String endpoint,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.integration_instructions_rounded, color: OhtliColors.stormyTeal),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ficha de Integración a Ohtli.quest',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: OhtliColors.onyx,
                            ),
                          ),
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: OhtliColors.subtleText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: OhtliColors.onyx),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: OhtliColors.cardBorder),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _buildModalInfoItem('Destino en Ohtli.quest', targetModule, Icons.pin_drop_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildModalInfoItem('Readiness a Prod', readiness, Icons.analytics_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildModalInfoItem('Endpoint en Staging', endpoint, Icons.link_rounded),
              const SizedBox(height: 24),

              Text(
                'Criterios de Aceptación para Producción:',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: OhtliColors.onyx,
                ),
              ),
              const SizedBox(height: 12),
              ...acceptanceCriteria.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c,
                        style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withValues(alpha: 0.8)),
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.onyx,
                    foregroundColor: OhtliColors.cloudDancer,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalInfoItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: OhtliColors.stormyTeal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: OhtliColors.cardBg,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        titleSpacing: 24,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.science_rounded, size: 20, color: OhtliColors.stormyTeal),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Ohtli Labs',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: OhtliColors.onyx,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: OhtliColors.innerCardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: OhtliColors.cardBorder),
                      ),
                      child: Text(
                        'STAGING WORKBENCH',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: OhtliColors.subtleText,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Banco de Pruebas Pre-Producción',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: OhtliColors.subtleText,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (!isMobile) ...[
            // Botón rápido de retorno a Ohtli.quest
            TextButton.icon(
              onPressed: _openProductionSite,
              icon: const Icon(Icons.open_in_new_rounded, size: 14),
              label: const Text('Ir a Ohtli.quest'),
              style: TextButton.styleFrom(
                foregroundColor: OhtliColors.stormyTeal,
                textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: Icon(Icons.logout_rounded, color: OhtliColors.onyx),
            onPressed: widget.onLogout,
            tooltip: 'Cerrar sesión',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('labs_waitlist').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error al cargar información: ${snapshot.error}', style: GoogleFonts.inter()),
            );
          }

          final doc = snapshot.data;
          final bool isRegistered = doc != null && doc.exists;
          final Map<String, dynamic> data = isRegistered ? doc.data() as Map<String, dynamic> : {};
          final String status = data['status'] ?? 'pending';

          if (!isRegistered) {
            return _buildTermsView();
          } else if (status == 'pending') {
            return _buildWaitlistView();
          } else if (status == 'approved') {
            return _buildApprovedWorkbench(isMobile);
          } else {
            return _buildRejectedView();
          }
        },
      ),
    );
  }

  Widget _buildApprovedWorkbench(bool isMobile) {
    return Column(
      children: [
        // Barra de pestañas superior del Workbench
        Container(
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            border: Border(bottom: BorderSide(color: OhtliColors.cardBorder)),
          ),
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                indicatorColor: OhtliColors.stormyTeal,
                indicatorWeight: 3,
                labelColor: OhtliColors.stormyTeal,
                unselectedLabelColor: OhtliColors.subtleText,
                labelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
                unselectedLabelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.science_rounded, size: 18),
                    text: 'Experimentos & Playgrounds',
                  ),
                  Tab(
                    icon: Icon(Icons.table_chart_rounded, size: 18),
                    text: 'Pipeline a Ohtli.quest',
                  ),
                  Tab(
                    icon: Icon(Icons.monitor_heart_rounded, size: 18),
                    text: 'Telemetría & Diagnóstico',
                  ),
                ],
              ),
            ],
          ),
        ),

        // Contenido de las pestañas
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildExperimentsTab(isMobile),
              _buildPipelineTab(isMobile),
              _buildTelemetryTab(isMobile),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExperimentsTab(bool isMobile) {
    final experiments = [
      {
        'id': 'recolector',
        'title': 'Caza Lugares (Motor Recolector)',
        'category': 'Geointeligencia',
        'status': 'CANDIDATO A PROD v1.0',
        'statusColor': const Color(0xFF10B981),
        'desc': 'Consolida información de lugares a través de múltiples fuentes de datos dadas coordenadas geográficas y un radio. Cuenta con replicación selectiva a la base de producción.',
        'targetModule': 'Ohtli.quest / Explorador de POIs',
        'readiness': '92% Listo',
        'icon': Icons.travel_explore_rounded,
        'color': OhtliColors.stormyTeal,
        'onTap': widget.onTryRecolector,
        'acceptanceCriteria': [
          'Tasa de resolución de coordenadas > 95%',
          'Replicación a colección de producción sin duplicados',
          'Respuesta de geocodificación < 800ms',
        ],
        'endpoint': 'https://api.ohtli.quest/v1/api/recolector/explore',
      },
      {
        'id': 'taste_vector',
        'title': 'Vector de Gustos & Vibe',
        'category': 'IA & Vectores',
        'status': 'BETA v0.9',
        'statusColor': OhtliColors.xoconostle,
        'desc': 'Simula el onboarding cultural, construye la receta semántica en lenguaje natural y genera el vector de 768 dimensiones para afinidad con lugares.',
        'targetModule': 'Ohtli.quest / Onboarding y Matching',
        'readiness': '88% Listo',
        'icon': Icons.fingerprint_rounded,
        'color': OhtliColors.xoconostle,
        'onTap': widget.onTryTasteVector,
        'acceptanceCriteria': [
          'Generación de vector 768d normalizado',
          'Similitud coseno consistente entre perfiles y categorías afines',
          'Persistencia en el perfil del usuario',
        ],
        'endpoint': 'https://api.ohtli.quest/v1/taste/generate',
      },
      {
        'id': 'osrm',
        'title': 'Ruteo OSRM & Ye',
        'category': 'Movilidad & Ruteo',
        'status': 'BETA v0.8',
        'statusColor': const Color(0xFFE2711D),
        'desc': 'Motor de cálculo de rutas y optimización de trayectos peatonales, en bicicleta y automóvil impulsado por OSRM y el algoritmo de Ye.',
        'targetModule': 'Ohtli.quest / Planificador de Itinerarios',
        'readiness': '78% Listo',
        'icon': Icons.directions_car_rounded,
        'color': const Color(0xFFE2711D),
        'onTap': widget.onTryOsrm,
        'acceptanceCriteria': [
          'Trazado de rutas peatonales con tiempos precisos en CDMX',
          'Soporte multi-paradas para itinerarios diarios',
          'Consumo cero de cuotas Google Maps Directions',
        ],
        'endpoint': 'https://api.ohtli.quest/api/osrm/route',
      },
      {
        'id': 'agents',
        'title': 'Consola de Agentes I/O',
        'category': 'Agentes IA',
        'status': 'ALPHA v0.4',
        'statusColor': const Color(0xFF6C5CE7),
        'desc': 'Consolas de entrada y salida crudas para interactuar directamente con los agentes autónomos de recolección, comparación y síntesis.',
        'targetModule': 'Ohtli.quest / Asistente Virtual Inteligente',
        'readiness': '50% Listo',
        'icon': Icons.smart_toy_rounded,
        'color': const Color(0xFF6C5CE7),
        'onTap': widget.onTryAgents,
        'acceptanceCriteria': [
          'Esquemas JSON estructurados en las respuestas de agentes',
          'Manejo resiliente de caídas y timeouts de LLM',
          'Alineación semántica con el tono de voz de Ohtli',
        ],
        'endpoint': 'https://api.ohtli.quest/v1/agent/recolector/test',
      },
      {
        'id': 'apis',
        'title': 'APIs Satélite & Microservicios',
        'category': 'APIs',
        'status': 'ACTIVO EN STAGING',
        'statusColor': const Color(0xFF00CEC9),
        'desc': 'Consola para interactuar con los endpoints de OEP (Places), análisis de Vibe y detección de estado de ánimo en Google Cloud Run.',
        'targetModule': 'api.ohtli.quest / Backend Core',
        'readiness': '82% Listo',
        'icon': Icons.api_rounded,
        'color': const Color(0xFF00CEC9),
        'onTap': widget.onTryApis,
        'acceptanceCriteria': [
          'Latencia P95 < 500ms en Cloud Run',
          'Esquemas validados con Swagger / OpenAPI',
          'Validación de cuotas de App Check',
        ],
        'endpoint': 'https://api.ohtli.quest/v1/api/vibe',
      },
    ];

    final filtered = experiments.where((e) {
      final matchesCategory = _selectedCategory == 'Todos' || e['category'] == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          (e['title'] as String).toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (e['desc'] as String).toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de contexto
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.info_outline_rounded, color: OhtliColors.stormyTeal),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Objetivo de Pruebas: Calibración y Certificación Pre-Producción',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: OhtliColors.onyx,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ejecuta casos límite, valida tiempos de respuesta y verifica la consistencia de los datos en este banco de pruebas antes de autorizar su integración definitiva en Ohtli.quest.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: OhtliColors.subtleText,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Filtros y Buscador
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...['Todos', 'Geointeligencia', 'IA & Vectores', 'Movilidad & Ruteo', 'Agentes IA', 'APIs'].map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedCategory = cat);
                  },
                  selectedColor: OhtliColors.stormyTeal,
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : OhtliColors.onyx.withValues(alpha: 0.7),
                  ),
                  backgroundColor: OhtliColors.cardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 24),

          // Grid de experimentos filtrados
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: filtered.map((e) {
              return _buildDashboardExperimentCard(
                title: e['title'] as String,
                category: e['category'] as String,
                status: e['status'] as String,
                statusColor: e['statusColor'] as Color,
                desc: e['desc'] as String,
                targetModule: e['targetModule'] as String,
                readiness: e['readiness'] as String,
                icon: e['icon'] as IconData,
                color: e['color'] as Color,
                onTap: e['onTap'] as VoidCallback?,
                onShowSpecs: () {
                  _showIntegrationSpecs(
                    context,
                    title: e['title'] as String,
                    targetModule: e['targetModule'] as String,
                    status: e['status'] as String,
                    readiness: e['readiness'] as String,
                    acceptanceCriteria: e['acceptanceCriteria'] as List<String>,
                    endpoint: e['endpoint'] as String,
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardExperimentCard({
    required String title,
    required String category,
    required String status,
    required Color statusColor,
    required String desc,
    required String targetModule,
    required String readiness,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    required VoidCallback onShowSpecs,
  }) {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la tarjeta
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    status,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
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
                  desc,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: OhtliColors.subtleText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),

                // Chip de destino
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: OhtliColors.innerCardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: OhtliColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.rocket_launch_rounded, size: 12, color: OhtliColors.stormyTeal),
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
                const SizedBox(height: 16),
              ],
            ),
          ),

          Divider(height: 1, thickness: 1, color: OhtliColors.cardBorder),

          // Botones inferiores de acción
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Probar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OhtliColors.stormyTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onShowSpecs,
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  tooltip: 'Ver Ficha de Integración a Ohtli.quest',
                  style: IconButton.styleFrom(
                    foregroundColor: OhtliColors.subtleText,
                    backgroundColor: OhtliColors.innerCardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: OhtliColors.cardBorder),
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

  Widget _buildPipelineTab(bool isMobile) {
    final features = [
      {
        'name': 'Caza Lugares (Recolector Multi-Fuente)',
        'target': 'Ohtli.quest / Explorador de POIs',
        'status': 'Candidato a Release',
        'progress': 0.92,
        'color': const Color(0xFF10B981),
        'notes': 'Pruebas de replicación de Firestore exitosas. Pendiente prueba de alta carga en CDMX Centro.',
      },
      {
        'name': 'Vector Semántico & Vibe (768d)',
        'target': 'Ohtli.quest / Onboarding & Matching',
        'status': 'Beta Activa',
        'progress': 0.88,
        'color': OhtliColors.xoconostle,
        'notes': 'Normalización vectorial probada. En calibración de ponderaciones para categorías gastronómicas.',
      },
      {
        'name': 'Ruteo OSRM & Algoritmo de Ye',
        'target': 'Ohtli.quest / Planificador de Rutas',
        'status': 'Beta Activa',
        'progress': 0.78,
        'color': const Color(0xFFE2711D),
        'notes': 'Rutas peatonales operativas. Pruebas de integración con el visor de mapas en progreso.',
      },
      {
        'name': 'APIs Satélite en Google Cloud Run',
        'target': 'api.ohtli.quest / Microservicios',
        'status': 'En Staging',
        'progress': 0.82,
        'color': const Color(0xFF00CEC9),
        'notes': 'Configuración de App Check y cuotas validada. P95 latency en 340ms.',
      },
      {
        'name': 'Consola de Agentes Autónomos',
        'target': 'Ohtli.quest / Asistente Inteligente',
        'status': 'Alpha Temprana',
        'progress': 0.50,
        'color': const Color(0xFF6C5CE7),
        'notes': 'Definiendo esquemas de salida y validación de prompts de razonamiento.',
      },
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Matriz de Graduación a Ohtli.quest (Release Pipeline)',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Monitorea el progreso de cada funcionalidad desde el banco de pruebas hasta su integración final en la aplicación de producción.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: OhtliColors.subtleText,
            ),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Column(
              children: features.map((f) {
                final progress = f['progress'] as double;
                final color = f['color'] as Color;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f['name'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Destino: ${f['target']}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: OhtliColors.stormyTeal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                              Text(
                                f['status'] as String,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: OhtliColors.subtleText,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: OhtliColors.innerCardBg,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        f['notes'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: OhtliColors.subtleText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(height: 1, color: OhtliColors.cardBorder),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryTab(bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Telemetría y Estado de Microservicios',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: OhtliColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Verifica la salud de los servicios experimentales y su latencia en Staging.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: OhtliColors.subtleText,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _isPingingServices ? null : _runDiagnostics,
                icon: _isPingingServices
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Ejecutar Ping de Diagnóstico'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Tarjetas de servicios
          ..._serviceStatus.entries.map((entry) {
            final serviceName = entry.key;
            final status = entry.value;
            final latency = _serviceLatency[serviceName];
            final isOk = status.contains('Operativo') || status == 'Online';

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: OhtliColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: OhtliColors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isOk ? const Color(0xFF10B981) : const Color(0xFFE2711D),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serviceName,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: OhtliColors.onyx,
                          ),
                        ),
                        Text(
                          'Estado: $status',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: OhtliColors.subtleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (latency != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: OhtliColors.innerCardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: OhtliColors.cardBorder),
                      ),
                      child: Text(
                        '${latency}ms',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTermsView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: OhtliColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.science_rounded, color: OhtliColors.stormyTeal, size: 32),
              ),
              const SizedBox(height: 24),
              Text(
                'Acreditación de Tester en Labs',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: OhtliColors.onyx,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ohtli Labs es el banco de pruebas pre-producción. Como tester calificado, tendrás acceso a algoritmos de recomendación, modelos vectoriales y motores de ruteo antes de su integración a Ohtli.quest.',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: OhtliColors.subtleText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _acceptedTerms,
                        onChanged: (val) => setState(() => _acceptedTerms = val ?? false),
                        activeColor: OhtliColors.stormyTeal,
                        side: BorderSide(color: OhtliColors.subtleText),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          text: 'Acepto los ',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: OhtliColors.onyx.withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                          children: [
                            TextSpan(
                              text: 'Términos y Condiciones de Ohtli Labs',
                              style: GoogleFonts.inter(
                                color: OhtliColors.stormyTeal,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  if (kIsWeb) {
                                    html.window.open('/#/labs/tyc', '_blank');
                                  }
                                },
                            ),
                            const TextSpan(
                              text: ' y comprendo que el software en Labs es un banco de pruebas experimental.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _acceptedTerms ? 1.0 : 0.4,
                  child: ElevatedButton(
                    onPressed: _isLoading || !_acceptedTerms ? null : _joinWaitlist,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OhtliColors.stormyTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Ingresar al Workbench de Labs',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitlistView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 540),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: OhtliColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_empty_rounded, color: OhtliColors.stormyTeal, size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                'Solicitud en Revisión',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: OhtliColors.onyx,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tu cuenta ha sido encolada para acceder a las pruebas de laboratorio de Ohtli Labs. Te notificaremos en cuanto tu perfil sea validado para interactuar con los motores en Staging.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: OhtliColors.subtleText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _openProductionSite,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Ir a Ohtli.quest'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OhtliColors.onyx,
                      side: BorderSide(color: OhtliColors.cardBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('Cerrar sesión'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OhtliColors.onyx,
                      foregroundColor: OhtliColors.cloudDancer,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRejectedView() {
    return Center(
      child: Text(
        'Lo sentimos, tu acceso a Labs no pudo ser habilitado en este momento.',
        style: GoogleFonts.inter(fontSize: 18),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Un experimento de Ohtli Labs. Es la única lista: la usan la portada pública
/// (labs.ohtli.quest) y el menú de Labs, para que nombre y estado no difieran entre pantallas.
class LabExperiment {
  final String id; // ruta: /labs/<id>
  final String title;
  final String category;
  final String description;
  final String status;
  final Color statusColor;
  final IconData icon;
  final Color color;
  final String targetModule;
  final String metrics;

  const LabExperiment({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.status,
    required this.statusColor,
    required this.icon,
    required this.color,
    required this.targetModule,
    required this.metrics,
  });

  String get path => '/labs/$id';
}

const kLabExperiments = <LabExperiment>[
  LabExperiment(
    id: 'recolector',
    title: 'Descubridor de lugares',
    category: 'GEOINTELIGENCIA',
    description: 'Encuentra y consolida lugares de varias fuentes para una zona de la ciudad y los valida antes de publicarlos.',
    status: 'CASI LISTO',
    statusColor: Color(0xFF10B981),
    icon: Icons.travel_explore_rounded,
    color: OhtliColors.stormyTeal,
    targetModule: 'Ohtli.quest / Lugares',
    metrics: 'Cobertura CDMX · Validación previa',
  ),
  LabExperiment(
    id: 'taste',
    title: 'Perfil cultural con IA',
    category: 'MODELOS SEMÁNTICOS',
    description: 'Traduce los gustos de cada viajero en una huella cultural y la compara con los lugares para encontrar los más afines.',
    status: 'BETA',
    statusColor: OhtliColors.xoconostle,
    icon: Icons.fingerprint_rounded,
    color: OhtliColors.xoconostle,
    targetModule: 'Ohtli.quest / Recomendaciones',
    metrics: 'Afinidad semántica · Privado por diseño',
  ),
  LabExperiment(
    id: 'osrm',
    title: 'Motor de rutas',
    category: 'MOVILIDAD URBANA',
    description: 'Calcula recorridos a pie, en bici y en auto sobre la red de la ciudad, con infraestructura propia.',
    status: 'BETA',
    statusColor: Color(0xFFE2711D),
    icon: Icons.route_rounded,
    color: Color(0xFFE2711D),
    targetModule: 'Ohtli.quest / Planificador',
    metrics: 'A pie · Bici · Auto',
  ),
  LabExperiment(
    id: 'agents',
    title: 'Consola de agentes',
    category: 'AGENTES AUTÓNOMOS',
    description: 'Conversa con los agentes de IA de Ohtli y revisa paso a paso cómo razonan y responden.',
    status: 'ALFA',
    statusColor: Color(0xFF6C5CE7),
    icon: Icons.smart_toy_rounded,
    color: Color(0xFF6C5CE7),
    targetModule: 'Ohtli.quest / Asistente Virtual',
    metrics: 'Transparencia · Diagnóstico',
  ),
  LabExperiment(
    id: 'apis',
    title: 'Servicios experimentales',
    category: 'NUEVOS SERVICIOS',
    description: 'Nuevos análisis de ambiente y estado de ánimo que se evalúan antes de sumarse a la API de Ohtli.',
    status: 'EN PRUEBAS',
    statusColor: Color(0xFF00CEC9),
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF00CEC9),
    targetModule: 'api.ohtli.quest',
    metrics: 'Ambiente · Estado de ánimo',
  ),
  LabExperiment(
    id: 'afinidad',
    title: 'Validación de afinidad',
    category: 'EVALUACIÓN',
    description: 'Comprueba que el puntaje de afinidad mide lo que dice: pruebas automáticas contra el motor y '
        'calificación a ciegas de lugares del sistema contra lugares al azar.',
    status: 'NUEVO',
    statusColor: Color(0xFF2F6F4F),
    icon: Icons.fact_check_rounded,
    color: Color(0xFF2F6F4F),
    targetModule: 'Ohtli.quest / Recomendaciones',
    metrics: 'Coherencia · Discriminación · Sistema vs. azar',
  ),
];

LabExperiment? experimentById(String id) {
  for (final e in kLabExperiments) {
    if (e.id == id) return e;
  }
  return null;
}

/// Marca que un experimento se muestra dentro del Labs unificado: sin barra propia ni botón de
/// volver (el menú lateral ya da la navegación y el encabezado lo pone Labs).
class LabEmbedded extends InheritedWidget {
  const LabEmbedded({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LabEmbedded>() != null;

  @override
  bool updateShouldNotify(LabEmbedded oldWidget) => false;
}

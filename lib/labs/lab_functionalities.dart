import 'lab_sma_page.dart';
import 'research/lab_models.dart' show kPlatformProjectId;

/// Funcionalidades del sistema que se registran en código y tienen tablero propio. El sistema
/// multiagente es en realidad varias: cada parte vive como una funcionalidad del proyecto de la
/// plataforma, con su propia página, accesos (IAM) y bitácora.
///
/// Su configuración (IAM) se guarda en un documento opcional de `lab_features/{id}`; como no tiene
/// `studyIds`, los testers nunca lo ven como función en prueba.
class LabModule {
  final String id;
  final String projectId;
  final String title;
  final String description;
  final SmaModule sma;
  const LabModule({required this.id, required this.title, required this.description, required this.sma, this.projectId = kPlatformProjectId});
}

const kLabModules = [
  LabModule(
    id: 'sma_critico',
    title: 'Agente Crítico: éxito de las recomendaciones',
    description: 'IER (elegida, sin cambios, realizada y compartida) y su desglose por tema, política, estilo de apertura, '
        'medio de traslado e intención.',
    sma: SmaModule.critico,
  ),
  LabModule(
    id: 'sma_politicas',
    title: 'Políticas que aprenden',
    description: 'Bandido de Thompson por contexto: uso e IER de cada brazo del Generador.',
    sma: SmaModule.politicas,
  ),
  LabModule(
    id: 'sma_curador',
    title: 'Agente Curador: categorías emergentes',
    description: 'Categorías que nacen de intenciones mal cubiertas, con su evidencia; se activan o retiran desde aquí.',
    sma: SmaModule.curador,
  ),
  LabModule(
    id: 'sma_mensajes',
    title: 'Mensajes entre agentes',
    description: 'Pedidos del Comparador y el Generador al Recolector (cobertura baja, tema sin candidatos) y su resultado.',
    sma: SmaModule.mensajes,
  ),
];

LabModule? moduleById(String id) {
  for (final m in kLabModules) {
    if (m.id == id) return m;
  }
  return null;
}

List<LabModule> modulesOf(String projectId) => [for (final m in kLabModules) if (m.projectId == projectId) m];

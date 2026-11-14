/// Contenido de los documentos legales de Ohtli.
///
/// Redactado conforme al marco mexicano (LFPDPPP 2025 y Ley Federal de Protección al
/// Consumidor). Debe revisarlo una persona abogada antes de considerarlo definitivo.
/// Los párrafos que empiezan con "• " se muestran como viñetas.

enum LegalDocId { terms, privacy, cookies, api, labs }

class LegalSection {
  final String title;
  final String body;
  const LegalSection(this.title, this.body);
}

class LegalDoc {
  final LegalDocId id;
  final String navLabel;
  final String title;
  final String path;
  final String intro;
  final List<String> summary;
  final List<LegalSection> sections;

  const LegalDoc({
    required this.id,
    required this.navLabel,
    required this.title,
    required this.path,
    required this.intro,
    required this.summary,
    required this.sections,
  });
}

class LegalInfo {
  LegalInfo._();
  static const responsible = 'Ohtli';
  static const location = 'Ciudad de México, México';
  static const privacyEmail = 'privacidad@ohtli.quest';
  static const effectiveDate = '14 de noviembre de 2026';
  static const version = '2.0';
}

const _r = LegalInfo.responsible;
const _mail = LegalInfo.privacyEmail;

const List<LegalDoc> kLegalDocs = [
  // ───────────────────────────── Términos ─────────────────────────────
  LegalDoc(
    id: LegalDocId.terms,
    navLabel: 'Términos y condiciones',
    title: 'Términos y condiciones de uso',
    path: '/tyc',
    intro: 'Estos términos regulan el uso de ohtli.quest y de sus servicios. Te pedimos leerlos con calma: al crear una cuenta o usar Ohtli aceptas lo que aquí se describe.',
    summary: [
      'Puedes explorar lugares y crónicas públicas sin cuenta; para crear rutas, guardar lugares y publicar necesitas registrarte.',
      'Tu contenido sigue siendo tuyo; solo nos das permiso de mostrarlo según la visibilidad que elijas.',
      'Precios, horarios y recomendaciones son orientativos: verifica antes de visitar un lugar.',
      'Puedes dar de baja tu cuenta cuando quieras desde la configuración.',
    ],
    sections: [
      LegalSection('1. Quiénes somos', '$_r es una plataforma de recomendación y planificación de rutas culturales en la Ciudad de México, con domicilio en ${LegalInfo.location}. Para cualquier asunto relacionado con estos términos puedes escribirnos a $_mail.'),
      LegalSection('2. Aceptación', 'Al registrarte o usar el servicio manifiestas que leíste y aceptas estos términos y el Aviso de Privacidad. Si no estás de acuerdo, te pedimos no usar Ohtli.'),
      LegalSection('3. El servicio', 'Ohtli te permite descubrir lugares, recibir recomendaciones según tus gustos, generar itinerarios con apoyo de inteligencia artificial y documentar tus viajes en crónicas que puedes compartir.\n\nAlgunas secciones son públicas y no requieren cuenta (la portada, el catálogo de lugares y las crónicas que sus autores publican). Las funciones personales, como guardar lugares, crear rutas o publicar, requieren una cuenta.'),
      LegalSection('4. Tu cuenta', '• Debes tener al menos 18 años o contar con la autorización de quien ejerza tu patria potestad o tutela.\n• La información que registres debe ser verdadera y estar actualizada.\n• Eres responsable de mantener la confidencialidad de tu contraseña y de la actividad de tu cuenta. Avísanos de inmediato si detectas un acceso no autorizado.\n• Puedes iniciar sesión con correo y contraseña o con tu cuenta de Google.'),
      LegalSection('5. Recomendaciones e información de lugares', 'Las recomendaciones, itinerarios, precios estimados, horarios y descripciones se generan a partir de fuentes públicas, datos propios y modelos de inteligencia artificial. Son orientativos y pueden contener errores o cambiar sin aviso.\n\nAntes de visitar un lugar confirma su horario, costo y condiciones de acceso. Tú decides qué lugares visitar y cómo trasladarte; cuida tu seguridad y respeta los reglamentos de cada sitio.'),
      LegalSection('6. Tu contenido', 'Conservas los derechos sobre las fotos, textos y crónicas que publiques. Al subirlos nos otorgas una licencia no exclusiva, gratuita y revocable para alojarlos, adaptarlos al formato de la plataforma y mostrarlos a las personas que elijas según la visibilidad que configures (privado, amigos o público). Esta licencia termina cuando eliminas el contenido o tu cuenta, salvo copias de respaldo temporales.\n\nGarantizas que tienes derecho a publicar ese contenido y que no infringe derechos de terceros.'),
      LegalSection('7. Conducta no permitida', '• Publicar contenido ilegal, violento, discriminatorio, sexual explícito o que invada la privacidad de otras personas.\n• Acosar, suplantar o engañar a otras personas.\n• Extraer de forma automatizada el catálogo o el contenido de la plataforma.\n• Intentar vulnerar la seguridad, eludir controles de acceso o sobrecargar los servidores.\n• Usar Ohtli con fines distintos a los permitidos por estos términos o por la ley.'),
      LegalSection('8. Propiedad intelectual', 'La marca Ohtli, el diseño de la plataforma, los textos editoriales y los modelos de recomendación son propiedad de $_r o de sus licenciantes. Parte de la información de lugares proviene de OpenStreetMap (© colaboradores de OpenStreetMap, licencia ODbL) y de otras fuentes abiertas, que conservan sus propias licencias.'),
      LegalSection('9. Servicios de terceros', 'Ohtli se apoya en servicios de terceros, como Google (alojamiento, autenticación y mapas) y OpenStreetMap (mapas y rutas). Su uso puede estar sujeto a los términos de esos proveedores. Los enlaces a sitios externos se ofrecen por conveniencia; no controlamos su contenido.'),
      LegalSection('10. Suspensión y baja', 'Puedes dar de baja tu cuenta en cualquier momento desde la configuración de tu cuenta. Podemos suspender o cancelar cuentas que incumplan estos términos, dando aviso cuando sea posible y salvo que la ley o la seguridad de otras personas lo impidan.'),
      LegalSection('11. Responsabilidad', 'Trabajamos para que Ohtli esté disponible y funcione correctamente, pero el servicio se ofrece en su estado actual y puede tener interrupciones o errores. En la medida permitida por la ley, $_r no será responsable por daños indirectos derivados del uso de la información o de las visitas que realices. Nada en estos términos limita los derechos que te otorga la Ley Federal de Protección al Consumidor.'),
      LegalSection('12. Cambios a estos términos', 'Podemos actualizar estos términos. Publicaremos la versión vigente en esta página con su fecha y, si el cambio es relevante, te avisaremos dentro de la app o por correo antes de que entre en vigor.'),
      LegalSection('13. Ley aplicable y jurisdicción', 'Estos términos se rigen por las leyes federales de los Estados Unidos Mexicanos. Para cualquier controversia, las partes se someten a los tribunales competentes de la Ciudad de México, sin perjuicio de tu derecho a acudir a la Procuraduría Federal del Consumidor (Profeco).'),
    ],
  ),

  // ───────────────────────────── Privacidad ─────────────────────────────
  LegalDoc(
    id: LegalDocId.privacy,
    navLabel: 'Aviso de privacidad',
    title: 'Aviso de privacidad integral',
    path: '/privacidad',
    intro: 'En Ohtli cuidamos tus datos personales. Este aviso explica qué datos tratamos, para qué, con quién los compartimos y cómo ejercer tus derechos, conforme a la Ley Federal de Protección de Datos Personales en Posesión de los Particulares.',
    summary: [
      'Usamos tus datos para darte la cuenta, las recomendaciones y las rutas; no los vendemos.',
      'Tu perfil de gustos, correo, teléfono y direcciones son privados: solo tú puedes verlos.',
      'No usamos cookies publicitarias ni de analítica de terceros.',
      'Puedes acceder, corregir, cancelar u oponerte al uso de tus datos escribiendo a $_mail.',
    ],
    sections: [
      LegalSection('1. Responsable', '$_r, con domicilio en ${LegalInfo.location}, es responsable del tratamiento de tus datos personales. Contacto para temas de privacidad: $_mail.'),
      LegalSection('2. Datos que tratamos', '• Identificación y contacto: nombre, apellidos, correo electrónico y, si decides agregarlo, número de teléfono.\n• Cuenta: fotografía de perfil, título o descripción, y la información que Google comparta si inicias sesión con esa cuenta (nombre, correo y foto).\n• Ubicación que tú proporcionas: direcciones que guardas como punto de partida. No accedemos a la ubicación GPS de tu dispositivo.\n• Preferencias: respuestas del cuestionario de gustos y el perfil cultural que generamos a partir de ellas, configuración de privacidad y notificaciones.\n• Contenido: lugares que guardas, viajes, itinerarios, crónicas, fotografías, reacciones, comentarios y sugerencias de lugares.\n• Relaciones: amistades, solicitudes y seguidores dentro de la plataforma.\n• Datos técnicos: información del navegador y señales antiabuso necesarias para proteger el servicio.\n\nNo solicitamos datos personales sensibles. Te pedimos no incluirlos en tus publicaciones.'),
      LegalSection('3. Finalidades necesarias', '• Crear y administrar tu cuenta y autenticarte.\n• Generar recomendaciones e itinerarios según tus gustos, tiempo y presupuesto.\n• Guardar y mostrar tus viajes y crónicas con la visibilidad que elijas.\n• Permitir funciones sociales como amistades, seguidores y viajes compartidos.\n• Atender solicitudes, dudas y reportes, y enviarte avisos sobre tu cuenta.\n• Proteger la seguridad del servicio y prevenir fraudes o abusos.'),
      LegalSection('4. Finalidades secundarias', '• Mejorar nuestros modelos de recomendación con información agregada o disociada.\n• Enviarte novedades y recomendaciones por correo o dentro de la app.\n\nPuedes negarte a estas finalidades en cualquier momento escribiendo a $_mail con el asunto "Finalidades secundarias". Tu negativa no afecta los servicios principales.'),
      LegalSection('5. Con quién compartimos tus datos', 'No vendemos ni rentamos tus datos personales. Los compartimos únicamente con proveedores que nos prestan servicios y que actúan por nuestra cuenta (encargados), bajo obligaciones de confidencialidad y seguridad:\n\n• Google LLC: alojamiento, base de datos, almacenamiento de fotos, autenticación, protección antiabuso (reCAPTCHA) y búsqueda de direcciones (Google Maps). Algunos de estos servicios pueden procesar datos fuera de México.\n• OpenStreetMap: mapas y cálculo de rutas; recibe tu dirección IP al cargar mapas, pero no datos de tu cuenta.\n\nLo que publicas como público (perfil social y crónicas públicas) puede verlo cualquier persona, incluso sin cuenta. Solo transferiremos datos a terceros distintos cuando la ley lo exija o lo autorice, o con tu consentimiento.'),
      LegalSection('6. Tus derechos ARCO', 'Tienes derecho a Acceder a tus datos, Rectificarlos, Cancelarlos y Oponerte a su tratamiento (derechos ARCO), así como a revocar tu consentimiento.\n\nPara ejercerlos escribe a $_mail con:\n• Tu nombre y el correo de tu cuenta.\n• Un documento que acredite tu identidad o, en su caso, la de tu representante.\n• La descripción clara del derecho que deseas ejercer y de los datos involucrados.\n\nTe responderemos en un plazo máximo de 20 días hábiles y, si procede, haremos efectiva tu solicitud dentro de los 15 días hábiles siguientes. Muchos datos puedes corregirlos o eliminarlos directamente desde la configuración de tu cuenta.'),
      LegalSection('7. Limitar el uso de tus datos', 'Desde la configuración de tu cuenta puedes cambiar la visibilidad de tu perfil y de tus viajes, desactivar notificaciones y dar de baja tu cuenta. También puedes pedirnos dejar de recibir comunicaciones promocionales.'),
      LegalSection('8. Conservación y seguridad', 'Conservamos tus datos mientras tengas una cuenta activa y durante el tiempo necesario para cumplir obligaciones legales. Al dar de baja tu cuenta los eliminamos o anonimizamos, salvo copias de respaldo temporales.\n\nAplicamos medidas de seguridad administrativas, técnicas y físicas: cifrado en tránsito (HTTPS), reglas de acceso que separan tus datos privados del perfil público y verificación contra abusos.'),
      LegalSection('9. Personas menores de edad', 'Ohtli no está dirigido a menores de 18 años. Si eres madre, padre o tutor y crees que una persona menor nos proporcionó datos sin tu autorización, escríbenos para eliminarlos.'),
      LegalSection('10. Cookies y tecnologías similares', 'Usamos almacenamiento local del navegador y cookies técnicas para mantener tu sesión, recordar tus preferencias y proteger el servicio. No usamos cookies publicitarias. Consulta los detalles en la Política de cookies.'),
      LegalSection('11. Cambios a este aviso', 'Cualquier cambio a este aviso se publicará en esta página con su fecha de actualización. Si el cambio es relevante, te lo notificaremos dentro de la app o por correo.'),
      LegalSection('12. Autoridad', 'Si consideras que tu derecho a la protección de datos personales ha sido vulnerado, puedes acudir ante la autoridad competente en materia de protección de datos personales en México (Secretaría Anticorrupción y Buen Gobierno).'),
    ],
  ),

  // ───────────────────────────── Cookies ─────────────────────────────
  LegalDoc(
    id: LegalDocId.cookies,
    navLabel: 'Política de cookies',
    title: 'Política de cookies y almacenamiento local',
    path: '/cookies',
    intro: 'Ohtli guarda una cantidad mínima de información en tu navegador para funcionar, recordar tus preferencias y protegerse contra abusos. Aquí te explicamos qué guardamos y cómo borrarlo.',
    summary: [
      'Solo usamos almacenamiento técnico, de preferencias y de rendimiento.',
      'No hay cookies de publicidad ni de analítica de terceros.',
      'Puedes borrar todo desde la configuración de tu navegador.',
    ],
    sections: [
      LegalSection('1. ¿Qué son?', 'Las cookies y el almacenamiento local son pequeños archivos o registros que un sitio guarda en tu navegador para recordar información entre visitas.'),
      LegalSection('2. Estrictamente necesarias', '• Sesión de cuenta: Firebase Authentication (Google) guarda tu sesión para que no tengas que iniciarla en cada visita.\n• Protección antiabuso: Google reCAPTCHA, a través de Firebase App Check, puede usar cookies propias para distinguir personas de programas automatizados.\n\nSin ellas el servicio no puede funcionar de forma segura.'),
      LegalSection('3. Preferencias', '• ohtli_theme_mode: tema elegido (sistema, claro u oscuro).\n• ohtli_font_size: tamaño de letra.'),
      LegalSection('4. Funcionales y de rendimiento', '• ohtli_viewed_pois: los últimos lugares que abriste, para mostrarlos en "Revisita tus lugares".\n• ohtli_cached_pois_v2: copia del catálogo público de lugares para que la sección cargue más rápido. No contiene datos personales.'),
      LegalSection('5. Lo que no usamos', 'No usamos cookies de publicidad, de redes sociales ni herramientas de analítica de terceros para rastrearte entre sitios.'),
      LegalSection('6. Cómo administrarlas', 'Puedes borrar o bloquear las cookies y el almacenamiento local desde la configuración de tu navegador. Si lo haces, se cerrará tu sesión y se perderán tus preferencias en ese dispositivo; bloquear las cookies estrictamente necesarias puede impedir iniciar sesión.'),
    ],
  ),

  // ───────────────────────────── API ─────────────────────────────
  LegalDoc(
    id: LegalDocId.api,
    navLabel: 'Términos de la API',
    title: 'Términos de uso de la API de Ohtli',
    path: '/terminos-api',
    intro: 'Estos términos aplican a empresas y equipos de desarrollo que acceden a la API de Ohtli. Si firmaste un contrato específico con nosotros, ese contrato prevalece sobre estos términos.',
    summary: [
      'El acceso es empresarial, bajo solicitud y con credenciales personales e intransferibles.',
      'Puedes integrar los datos en tu producto, pero no revender el catálogo en bruto.',
      'Debes atribuir las fuentes abiertas, como OpenStreetMap.',
      'Las credenciales pueden suspenderse ante un uso abusivo o contrario a la ley.',
    ],
    sections: [
      LegalSection('1. Acceso y credenciales', 'El acceso a la API se otorga bajo solicitud. Las credenciales que te entreguemos son confidenciales, para uso exclusivo de tu organización y no pueden compartirse ni publicarse. Eres responsable de toda la actividad realizada con ellas.'),
      LegalSection('2. Uso permitido', 'Puedes usar la API para integrar información de lugares, afinidad cultural e itinerarios en tus productos y servicios, mostrando los resultados a tus clientes o usuarios finales dentro del alcance acordado.'),
      LegalSection('3. Restricciones', '• Revender, sublicenciar o redistribuir el catálogo en bruto o crear un servicio que compita con la API.\n• Almacenar datos de forma masiva para reconstruir el catálogo.\n• Hacer ingeniería inversa de los modelos o intentar acceder a funciones no documentadas.\n• Superar los límites de uso acordados o degradar intencionalmente el servicio.\n• Usar la API para vigilar, perfilar o discriminar a personas.'),
      LegalSection('4. Datos personales', 'Si envías a la API datos de tus usuarios (por ejemplo, preferencias para calcular afinidad), lo haces como responsable de esos datos y debes contar con su consentimiento y con tu propio aviso de privacidad. $_r los tratará solo para prestarte el servicio, como encargado, y no los usará para fines propios.'),
      LegalSection('5. Atribución y propiedad', 'Los datos, modelos y documentación son propiedad de $_r o de sus licenciantes. Parte de la información proviene de OpenStreetMap: debes mostrar la atribución "© colaboradores de OpenStreetMap" cuando presentes esos datos. La marca Ohtli solo puede usarse con autorización.'),
      LegalSection('6. Disponibilidad y cambios', 'Salvo que tu contrato incluya un nivel de servicio, la API se ofrece en su estado actual. Podemos actualizar o retirar funciones avisando con anticipación razonable cuando afecten tu integración. Los productos marcados como beta o en acceso anticipado pueden cambiar sin aviso.'),
      LegalSection('7. Suspensión', 'Podemos suspender credenciales ante un uso abusivo, ilícito o que ponga en riesgo la seguridad del servicio o de terceros, notificándote cuando sea posible.'),
      LegalSection('8. Responsabilidad', 'Eres responsable del uso que tu producto haga de los resultados de la API. En la medida permitida por la ley, la responsabilidad de $_r se limita a lo establecido en tu contrato.'),
      LegalSection('9. Ley aplicable', 'Estos términos se rigen por las leyes federales de los Estados Unidos Mexicanos y cualquier controversia se resolverá ante los tribunales competentes de la Ciudad de México.'),
    ],
  ),

  // ───────────────────────────── Labs ─────────────────────────────
  LegalDoc(
    id: LegalDocId.labs,
    navLabel: 'Términos de Ohtli Labs',
    title: 'Términos de Ohtli Labs',
    path: '/labs/tyc',
    intro: 'Ohtli Labs es nuestro laboratorio de innovación. Estos términos complementan los Términos y condiciones de Ohtli y aplican cuando participas en las pruebas de funciones experimentales.',
    summary: [
      'Las funciones de Labs son experimentales y pueden cambiar o desaparecer.',
      'Labs opera en un entorno separado de producción con datos de prueba.',
      'Lo que veas en Labs es confidencial hasta su lanzamiento.',
      'Tus comentarios nos ayudan a decidir qué llega a Ohtli.quest.',
    ],
    sections: [
      LegalSection('1. Naturaleza experimental', 'Las herramientas de Labs están en desarrollo. Pueden contener errores, cambiar, reiniciar sus datos o retirarse sin aviso, y no deben usarse para planear viajes reales.'),
      LegalSection('2. Acceso', 'Para participar debes iniciar sesión con tu cuenta de Ohtli y aceptar estos términos. Podemos limitar o retirar el acceso a Labs en cualquier momento.'),
      LegalSection('3. Entorno aislado', 'Labs funciona en un entorno separado de producción y usa datos de prueba. Las acciones que realices no modifican cuentas, viajes ni información personal de otras personas en ohtli.quest.'),
      LegalSection('4. Información que registramos', 'Para evaluar los experimentos registramos los resultados de las pruebas, métricas de rendimiento y los comentarios que envíes, asociados a tu cuenta. Los tratamos conforme al Aviso de Privacidad.'),
      LegalSection('5. Confidencialidad', 'Las funciones, modelos y resultados que conozcas en Labs y que no hayan sido anunciados públicamente son confidenciales. No los compartas, publiques ni captures para difundirlos sin autorización.'),
      LegalSection('6. Comentarios', 'Al enviarnos sugerencias o reportes nos autorizas a usarlos para mejorar Ohtli sin obligación de compensación, y sin que ello implique ceder tus datos personales.'),
      LegalSection('7. Conducta', 'No intentes vulnerar la seguridad del entorno, extraer datos ni usar Labs para fines distintos a la evaluación de funciones.'),
      LegalSection('8. Sin garantías', 'Labs se ofrece en su estado actual y sin garantías de disponibilidad ni de resultados. En lo no previsto aplican los Términos y condiciones de Ohtli.'),
    ],
  ),
];

LegalDoc legalDocById(LegalDocId id) => kLegalDocs.firstWhere((d) => d.id == id);

# Ohtli Labs: estructura de investigación (v2, 16-nov-2026)

Toda la actividad de Labs cuelga de esta jerarquía. Las pruebas del TT, los experimentos, las
encuestas, los artículos del blog y las funciones en prueba de la app se acoplan a ella.

```
Proyecto (opcional; público o confidencial con nombre en clave)
 └─ Estudio (preregistrado: hipótesis, métricas y plan de análisis congelados)
     ├─ Experimentos   (biblioteca pública y reutilizable, salvo los clasificados)
     ├─ Encuestas      (las crea cualquier científico; SUS es una de ellas)
     ├─ Métricas       (lo que se mide; cada una con fórmula, unidad y umbral de éxito)
     └─ Funcionalidades (funciones de la app que solo ven los testers inscritos)
         ↓ resultados (corridas, respuestas, mediciones)
     Paper  →  revisión interna → revisión externa* → validación de participantes* → aprobado
         ↓
     Blog de noticias  (bloqueado mientras el proyecto sea confidencial)
         ↓
     Decisión de la función (admin): oficial · extender beta · retirar
```
`*` según la configuración del estudio.

Referencias de la industria que se siguen: preregistro (OSF / AsPredicted), revisión por pares
de revista (decisiones aceptar / cambios menores / cambios mayores / rechazar, revisores sin
conflicto de interés), *member checking* (validación de participantes en investigación
cualitativa), etapas de lanzamiento con feature flags (interno → beta cerrada → GA → retirada),
consentimiento informado por estudio (LFPDPPP) y paquete de reproducibilidad.

## Roles

| Rol | Qué puede |
|---|---|
| Visitante | Ver lo público: experimentos no clasificados, estudios publicados y el blog. |
| Tester | Inscribirse a estudios (consentimiento por estudio, NDA si es confidencial), usar las funciones en prueba de sus estudios, responder encuestas y validar el paper de sus estudios. Ve sus títulos y funciones en **Logros**. |
| Científico (`researcher`) | Todo lo de tester; crear proyectos, estudios, experimentos y encuestas; usar cualquier experimento público en su estudio; redactar papers; revisar papers ajenos (revisión interna). |
| Revisor invitado (`reviewer`) | Solo los estudios a los que lo invitaron, tras firmar el NDA de cada uno. Recibe el paquete de reproducibilidad y emite su dictamen. |
| Admin (superusuario) | Todo; además publicar al blog, decidir el destino de una función y **desclasificar** proyectos (nadie más puede). |

## Ciclo de vida del estudio

`borrador → preregistrado → reclutando → en curso → análisis → en revisión → publicado → archivado`
(+ `pausado` y `cancelado` desde cualquier estado antes de publicado).

- **Borrador**: se edita libremente. Se eligen experimentos, encuestas, métricas y funciones.
- **Preregistrado**: hipótesis, métricas (con umbral de éxito) y plan de análisis quedan
  congelados con fecha (`preregistration.frozenAt`). Cambiarlos después exige una **enmienda**
  registrada en la bitácora con su motivo; el paper las lista.
- **Reclutando**: aparece en "Estudios abiertos". Cupo (`capacity`) y requisitos (`eligibility`).
- **En curso**: se corren experimentos y encuestas; las funciones del estudio pasan a **beta**
  para los inscritos.
- **Análisis**: se cierran inscripciones y respuestas.
- **En revisión**: el paper recorre sus etapas (ver abajo). Si una etapa rechaza o pide cambios,
  el paper vuelve a **borrador del paper** con los comentarios y se abre una ronda nueva
  (`paper.round + 1`); el estudio sigue en revisión.
- **Publicado**: paper aprobado y, si el proyecto no es confidencial, nota en el blog.

Un estudio puede cambiar de proyecto (queda en la bitácora). Pasar de un proyecto público a uno
confidencial lo enmascara; de confidencial a público solo ocurre al desclasificar.

## Inscripción (tester)

1. Consentimiento general de Labs (una vez, ya existe).
2. Por estudio: consentimiento propio con versión (`consentVersion`); si el proyecto es
   confidencial, además el NDA del proyecto.
3. Cupo y requisitos se revisan al inscribirse.
4. Baja voluntaria en cualquier momento: la función en prueba deja de verse; sus respuestas ya
   dadas se conservan anónimas salvo que pida borrarlas ("retirar mis datos"), lo que el
   laboratorio debe atender antes del análisis.

## Funcionalidades (feature flags)

Estados: `desarrollo` (solo el laboratorio) → `beta` (laboratorio + testers inscritos a un estudio
en curso que la incluya) → `oficial` (todos) · `retirada` (nadie).

- La puerta es real: la app consulta `lab_features/{key}` y la inscripción, y las reglas de
  Firestore usan `featureOn(key)` en las colecciones de la función. El motor debe validar lo
  mismo en sus endpoints de funciones beta.
- Si el estudio termina y el admin no la vuelve oficial: sigue en beta hasta la decisión;
  si se **retira**, se apaga con aviso en Logros y los datos que generó se conservan (solo
  lectura).
- Una función puede estar en varios estudios; se ve si el tester está inscrito en cualquiera.

## Paper y validación

Etapas (`paper.stage`): `borrador → revision_interna → revision_externa* → validacion_participantes* → aprobado → publicado`.

**Revisión interna** (científicos de Ohtli): mínimo 1 revisor que no sea autor del estudio.
Dictamen: aceptar · cambios menores · cambios mayores · rechazar. Avanza con al menos un
"aceptar" o "cambios menores" (que se atienden sin nueva ronda) y ningún "rechazar".

**Revisión externa** (si `config.externalReview`): revisores invitados con NDA. Reciben el
paquete de reproducibilidad: preregistro y enmiendas, configuración exacta de cada corrida,
versión de la app/motor (commit), datos agregados y anónimos, y el procedimiento para repetirlo.
Mínimo `config.minExternalReviewers` (por defecto 2). Misma regla de dictamen.

**Validación de participantes** (si `config.participantValidation`): cada tester inscrito ve el
resumen del paper y los resultados agregados con la marca "tus respuestas están incluidas" y
responde **¿Te ves reflejado?** sí · en parte · no, con comentario opcional. Voto anónimo
(solo se guarda para evitar duplicados). Ventana de 10 días.
Se aprueba si:
- quórum: votan al menos `max(3, 30 % de los inscritos)`, y
- `(sí + 0.5·en parte) / votos ≥ 2/3`, y
- "no" < 1/3.
Si no se alcanza el quórum al cerrar la ventana, se extiende una vez 7 días; si sigue sin quórum
se registra "sin quórum" y el admin decide si avanza (queda en la bitácora y en el paper).

**Aprobado → publicado**: con todas las etapas en verde el admin publica la nota del blog
(`lab_posts`, ligada a `paperId`). Si el proyecto es confidencial, el botón está bloqueado hasta
desclasificar. Tras publicar, el admin decide el destino de cada función del estudio.

## Proyectos confidenciales

- Al crearlo se asigna un **nombre en clave único** de un banco de palabras en náhuatl
  (`lab_codenames/{palabra}` garantiza que no se repita). Ej.: "Proyecto Tecolotl".
- Todo lo que cuelga de él (estudios, experimentos, encuestas, funciones, papers) se muestra con
  el nombre en clave a quien no esté autorizado; el nombre y la descripción reales viven en un
  subdocumento `private/details` que solo leen el admin y los miembros del proyecto.
- Los experimentos clasificados no aparecen en la biblioteca pública.
- Los testers inscritos ven solo el nombre en clave y firman el NDA del proyecto.
- El blog está bloqueado. **Solo el admin desclasifica**: copia los datos reales al documento
  público, marca `declassifiedAt` y lo registra.

## Biblioteca de experimentos y encuestas

- Experimentos públicos (no clasificados) reutilizables por cualquier científico en su estudio.
  Los integrados (recolector, perfil cultural, rutas, agentes, servicios, afinidad) tienen
  pantalla propia; los creados por científicos son protocolos (procedimiento, métricas) con
  mediciones registradas por corrida.
- Encuestas: constructor con preguntas Likert 1–5, opción única, opción múltiple, número y texto.
  Una respuesta por persona y encuesta.

## Bitácora

`lab_audit`: solo se agrega (nadie edita ni borra). Registra preregistro, enmiendas, cambios de
estado o de proyecto, inscripciones (sin identidad), dictámenes, cierre de validación,
publicación, desclasificación y decisiones sobre funciones.

## Colecciones

| Colección | Contenido |
|---|---|
| `lab_projects/{id}` (+ `private/details`) | nombre o nombre en clave, confidencial, miembros, desclasificación |
| `lab_codenames/{palabra}` | reserva del nombre en clave |
| `lab_studies/{id}` (+ `private/details`) | estado, proyecto, preregistro, config, experimentos, encuestas, métricas, funciones, cupo |
| `lab_experiments/{id}` | biblioteca (integrados con `builtin`) |
| `lab_surveys/{id}`, `lab_survey_responses/{surveyId}_{uid}` | encuestas y respuestas |
| `lab_features/{key}` | funcionalidad, estado, estudios |
| `lab_enrollments/{studyId}_{uid}` | inscripción, versión del consentimiento, NDA |
| `lab_ndas/{scope}_{uid}` | NDA aceptado (proyecto o estudio para revisores) |
| `lab_papers/{id}` (+ `reviews/{uid}`, `checks/{uid}`) | paper, ronda, etapa, dictámenes, validación |
| `lab_audit/{id}` | bitácora |

Las colecciones anteriores (`lab_runs`, `lab_responses`, `lab_posts`, `lab_site`) se mantienen;
las seis pruebas del TT quedan como estudios del proyecto público "Trabajo Terminal".

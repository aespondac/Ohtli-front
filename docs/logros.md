# Logros de viajero

Los calcula y otorga el motor (`POST /v1/achievements/evaluate`, `api/achievements.py`) con datos
que la persona no puede inflar desde la app. La app los pide al abrir Logros y al terminar,
reseñar o publicar un viaje. El admin los dispara para otra persona al marcar un comentario como
"Arreglado y publicado" (`POST /v1/achievements/evaluate/{uid}`). Logros es una función en prueba
(`lab_features/logros`).

| Título | Se gana al… | Dato |
|---|---|---|
| Pochtecatl I/II/III | Completar 3, 10 o 25 viajes | `finishedAt` o `reviewedAt` |
| Recorre alcaldías | Visitar lugares en las 16 alcaldías | alcaldía del catálogo del motor |
| Ichtaca (lo escondido) | Visitar 10 lugares que casi nadie visita | `poi_feedback` (RF-12) < 3 muestras |
| De todo un poco | Lugares de 5 categorías | categoría del catálogo |
| A pie, en bici y en auto | Traslados de los tres modos | `transfer.mode` |
| Madrugador o noctámbulo | Empezar antes de las 8 o terminar después de las 22 | hora real o planeada |
| Tlapalehuiani (el que ayuda) | Calificar la accesibilidad en la reseña | `accessibilityReview` |
| Tlacuilo I/II/III | Publicar 1, 5 o 15 crónicas con fotos | `status == published` |
| Citlalli (estrella) | Aparecer en Destacados de Explorar | `app_config/explore.pinned` |
| Cencalli (familia) | Editar en vivo con otra persona | `editorIds` |
| Tlahuilli (luz) | Que alguien use tu viaje como base | `trip_inspirations` |
| Momentos | Llenar los 12 momentos | `users.moments` |
| Calpixqui | Organizar un viaje grupal que se realizó | `group_trips.hostId` + viaje completado |
| Tlahtocan (el consejo) | Tu grupo votó y completó el viaje | `group_trips.votes` |
| Tetlauhtilli (el regalo) | Un viaje sorpresa que su destinatario abrió | `surpriseOpenedBy` |
| Tlamatini II/III | 5 o 20 reportes aprobados | `place_feedback` |
| Tlapohuani (el que cuenta) | 10 lugares nuevos aprobados | `poi_suggestions` |
| Tlachixqui (el que observa) | Calificar 20 lugares recomendados por la IA | `recommendation.poi_ids` + `rating` |
| Amini (el cazador) | Un comentario convertido en arreglo publicado | `app_feedback.status == fixed` |
| Primera mano | Estudio de Labs cuya función se volvió oficial | `lab_enrollments` + `lab_features` |
| Tozquitl (la voz) | Validar resultados de un paper | `lab_papers/*/checks` |
| Insider fundador | Tester activo desde la beta hasta que fue oficial | inscripción antes de `stageChangedAt` |
| Xiuhpohualli (cuenta del año) | Viajar en las cuatro estaciones | `travelDate` |
| Cexihuitl (un año) | Un año en Ohtli con al menos un viaje | `users.createdAt` |
| Próximamente | Guía (referidos), Namictli (en pareja), Ixpopoyotl (cita a ciegas), Tlaxtlahuilli (dividir gastos) | sus funciones aún no existen |

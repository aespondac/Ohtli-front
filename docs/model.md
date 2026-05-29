# Modelo de Datos Completo (Ohtli)

La arquitectura de datos de Ohtli utiliza Cloud Firestore bajo una filosofía de optimización de lecturas. Se consolida la información frecuentemente consultada (como direcciones y configuraciones) dentro del documento raíz del usuario, y se separan estrictamente los datos pesados (contenido narrativo e imágenes de los blogs) en sub-documentos aislados para minimizar agresivamente los costos de transferencia en la nube.

## 1. Perfil y Preferencias de Usuario
**Colección:** `/users/{userId}`
- **Propósito:** Almacena la información de contacto (`phone`), la foto de perfil, configuraciones de privacidad (share, notificaciones, perfil público) y un arreglo embebido (`addresses`) que actúa como caché de direcciones físicas del usuario.
- **Sincronización:** Las direcciones físicas incrustadas incluyen campos `isDeleted`, `deletedAt` y `updatedAt` (todos en formato entero de milisegundos Unix) vitales para ejecutar y reconciliar transacciones offline consistentes entre múltiples dispositivos.

## 2. Metadatos de Viajes (Mis Viajes)
**Colección:** `/users/{userId}/trips/{tripId}`
- **Propósito:** Almacena exclusivamente los metadatos esenciales para indexar y buscar un viaje (título, descripción corta, URL de la portada y su estatus de publicación o visibilidad).
- **Acceso:** Es el documento liviano que se lee en listados masivos (como el Dashboard del usuario o el Feed Público de Viajes). Mantiene los bytes transferidos muy bajos al no descargar el contenido interior de las anécdotas.

## 3. Contenido de Viajes (Detalles Pesados)
**Sub-documento:** `/users/{userId}/trips/{tripId}/details/content`
- **Propósito:** Almacena la estructura completa, robusta y pesada de un viaje dentro de un único arreglo polimórfico `sections`. Éstas secciones son las que integran la narrativa (texto plano enriquecido, imágenes entrelazadas con layouts específicos, y lugares turísticos con ratings y librerías fotográficas propias).
- **Acceso:** Solo se consulta o factura su lectura por Firebase cuando el usuario da clic para abrir el "Editor Específico" o ingresa a leer el "Visualizador Completo" de una bitácora. 
- **Integridad:** El borrado en cascada garantiza que si se destruye el documento padre del viaje, este sub-documento también es purgado para evitar bytes huérfanos.

---

Para revisar las estructuras y llaves literales en JSON, consulta `data_contracts.md`.  
Para ver el esquema relacional lógico completo de las tablas, abre `schema.dbml`.

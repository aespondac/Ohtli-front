# Ohtli-front

Este repositorio contiene el código fuente de la **Progressive Web App (PWA)** y aplicación móvil (compilada) de **Ohtli**.

Ohtli-front actúa como el cliente principal (B2C) de la plataforma inteligente de recomendación de viajes e itinerarios altamente personalizados para la Ciudad de México (CDMX). La interfaz permite a los usuarios descubrir rutas, explorar lugares (Puntos de Interés) curados por IA y gestionar sus perfiles de viaje bajo un marco estético y narrativo inmersivo.

## 🛠️ Tecnologías Principales
- **Framework:** Flutter / Dart
- **Arquitectura de Base de Datos:** Firebase NoSQL (Cloud Firestore)
- **Autenticación:** Firebase Auth
- **Almacenamiento:** Firebase Storage

## 🎨 Sistema de Diseño (UI/UX)
El diseño visual de la interfaz fue concebido para alejarse de interfaces rígidas, apostando por un "look & feel" editorial, elegante y fuertemente inspirado en elementos orgánicos y representativos de la cultura de la CDMX.

- **Filosofía Visual:** Bordes orgánicos (`BorderRadius.circular(24)`), sombras difuminadas suaves, y gran uso del espacio en negativo para priorizar la lectura.
- **Tipografía:** *Inter* (Google Fonts) en variantes muy ligeras (w200, w300) para un estilo premium.
- **Paleta de Colores:**
  - **Stormy Teal (`#2C666E`):** Color principal.
  - **Cloud Dancer (`#F0EEE9`):** Fondo principal (blanco roto/crema).
  - **Onyx (`#0A090C`):** Textos principales.
  - **Cantera (`#D1CDC4`):** Grises cálidos para fondos secundarios o tarjetas.
  - **Xoconostle (`#6C3953`):** Rosa mexicano oscuro para acentos.
  - **Cempasúchil (`#FFB800`):** Amarillo vibrante para alertas o CTA (Call to Actions).

> Para más detalles, consulta [docs/design.md](./docs/design.md).

## 🗄️ Arquitectura de Datos (Firestore)
La aplicación fue estructurada bajo una filosofía estricta de **Optimización de Lecturas** en Firestore para reducir dramáticamente los costos operativos en la nube.

Se han separado los datos en dos conceptos:
1. **Documentos Ligeros (Metadatos):** Se usan en listados masivos (ej. Dashboard, Feed de viajes). Ejemplo: `/users/{userId}/trips/{tripId}` solo contiene título y URL de portada.
2. **Documentos Pesados (Contenidos):** Estructuras polimórficas robustas (texto, lugares, imágenes combinadas) que solo se descargan y facturan cuando el usuario abre el visor completo del viaje. Ejemplo: `/users/{userId}/trips/{tripId}/details/content`.

Adicionalmente, los perfiles de usuario integran cachés locales de direcciones y preferencias con variables offline (`isDeleted`, `updatedAt`) para asegurar resiliencia en conexiones inestables.

> Para profundizar en los esquemas y contratos de datos, consulta:
> - [Modelo de Base de Datos](./docs/model.md)
> - [Contratos JSON de Datos](./docs/data_contracts.md)
> - [Esquema Relacional DBML](./docs/schema.dbml)

## 🤖 Integración con IA
Aunque el "cerebro" inteligente reside en `Yollotl-engine` (un repositorio backend independiente), Ohtli-front está preparado para recibir y renderizar los itinerarios resueltos.
Ohtli-front actúa como el canvas de presentación donde la narrativa generada por **Gemini**, y las rutas resueltas por algoritmos de optimización matemática (Knapsack Problem & TOPTW), toman vida visualmente.

## 🚀 Correr Localmente
1. Asegúrate de tener instalado Flutter en su versión más reciente.
2. Descarga e instala dependencias:
   ```bash
   flutter pub get
   ```
3. Ejecuta el servidor de desarrollo web:
   ```bash
   ./run_local.sh
   # o alternativamente:
   # flutter run -d chrome
   ```

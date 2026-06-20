# Contratos de Datos Globales (Data Contracts)

Este documento describe la estructura exacta esperada en formato JSON/Map al leer y escribir en los documentos de Firestore de toda la aplicación Ohtli.

## `/users/{userId}` (Usuario y Preferencias)
Documento central del usuario.

```json
{
  "photoURL": "string (URL opcional)",
  "phone": "string",
  "privacy_share": "boolean",
  "privacy_notifications": "boolean",
  "privacy_public": "boolean",
  "addresses": [
    {
      "id": "string",
      "customName": "string",
      "category": "string",
      "street": "string",
      "suburb": "string",
      "zip": "string",
      "city": "string",
      "state": "string",
      "country": "string",
      "lat": "double",
      "lng": "double",
      "isDeleted": "boolean (opcional, para reconciliación offline)",
      "deletedAt": "integer (milisegundos desde la época Unix, opcional)",
      "updatedAt": "integer (milisegundos desde la época Unix)"
    }
  ],
  "updatedAt": "timestamp (Firestore Timestamp)"
}
```

## `/users/{userId}/trips/{tripId}` (Trip)
Contrato utilizado para el documento principal del viaje (lectura rápida).

```json
{
  "userId": "string",
  "title": "string",
  "description": "string",
  "coverUrl": "string (URL)",
  "status": "string ('draft' | 'published')",
  "visibility": "string ('public' | 'private')",
  "createdAt": "timestamp (Firestore Timestamp)",
  "updatedAt": "timestamp (Firestore Timestamp)"
}
```

## `/users/{userId}/trips/{tripId}/details/content` (TripContent)
Contrato utilizado para el sub-documento de carga pesada que aloja los bloques/secciones.

```json
{
  "sections": [
    {
      "id": "string (UUID v4)",
      "type": "string ('place' | 'text' | 'text_image')",
      "...": "Campos específicos dependiendo del 'type' (ver abajo)"
    }
  ]
}
```

### Contratos de Secciones (`TripSection`)

Las secciones viven dentro del array `sections` en el documento `TripContent`.

#### 1. Tipo `place` (Lugar Turístico)
```json
{
  "id": "string",
  "type": "place",
  "title": "string",
  "description": "string",
  "rating": "integer (1-5)",
  "mainPhotoUrl": "string (URL)",
  "secondaryPhotoUrls": ["string (URL)", "string (URL)"] // Max 2
}
```

#### 2. Tipo `text` (Texto / Anécdota)
```json
{
  "id": "string",
  "type": "text",
  "markdownText": "string"
}
```

#### 3. Tipo `text_image` (Texto con Imagen Lateral)
```json
{
  "id": "string",
  "type": "text_image",
  "markdownText": "string",
  "imageUrl": "string (URL)",
  "layout": "string ('left' | 'right')"
}
```

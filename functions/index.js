const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

/**
 * Helper to strip markdown characters and formatting to yield a clean description text.
 */
function stripMarkdown(text) {
  if (!text) return '';
  return text
    .replace(/(\*\*|__)(.*?)\1/g, '$2')          // bold
    .replace(/(\*|_)(.*?)\1/g, '$2')             // italics
    .replace(/~~(.*?)~~/g, '$2')                 // strikethrough
    .replace(/`{1,3}(.*?)\`{1,3}/g, '$1')        // code blocks
    .replace(/\[(.*?)\]\((.*?)\)/g, '$1')        // markdown links
    .replace(/[#*+\-`\[\]\(\){}~]/g, '')         // remaining syntax characters
    .replace(/\s+/g, ' ')                        // collapse whitespace
    .trim();
}

exports.serveTripMeta = functions.https.onRequest(async (req, res) => {
  const pathParts = req.path.split('/').filter(Boolean); // Remove empty strings
  // Expected path format: /viajes/authorId/tripId
  // pathParts will be: ['viajes', 'authorId', 'tripId']
  
  let authorId = null;
  let tripId = null;

  if (pathParts.length >= 3 && pathParts[0] === 'viajes') {
    authorId = pathParts[1];
    tripId = pathParts[2];
  }

  // If we couldn't parse the IDs, redirect humans or return simple empty response for bots
  if (!authorId || !tripId) {
    const userAgent = req.headers['user-agent'] || '';
    const isBot = /facebookexternalhit|twitterbot|whatsapp|slackbot|telegrambot|google\-structured\-data\-testing\-tool|linkedinbot|embedly|quora link preview|rogue/i.test(userAgent);
    
    if (isBot) {
      return res.status(404).send('Not Found');
    } else {
      return res.redirect(302, `https://${req.hostname}/`);
    }
  }

  const userAgent = req.headers['user-agent'] || '';
  const isBot = /facebookexternalhit|twitterbot|whatsapp|slackbot|telegrambot|google\-structured\-data\-testing\-tool|linkedinbot|embedly|quora link preview|rogue/i.test(userAgent);

  if (isBot) {
    try {
      const db = admin.firestore();
      const tripDoc = await db.collection('users').doc(authorId).collection('trips').doc(tripId).get();

      if (tripDoc.exists) {
        const tripData = tripDoc.data();
        
        // Only show previews for published public trips
        if (tripData && tripData.status === 'published' && tripData.visibility === 'public') {
          const title = tripData.title || 'Bitácora de Viaje | Ohtli';
          const rawDescription = tripData.description || 'El viaje empieza aquí. Sigue mis pasos en Ohtli.';
          const description = stripMarkdown(rawDescription);
          const coverUrl = tripData.coverUrl || `https://${req.hostname}/assets/logo.svg`;

          // Generate dynamic HTML with meta tags
          res.status(200).send(`<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>${title}</title>
    <meta name="description" content="${description}">
    
    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="website">
    <meta property="og:title" content="${title}">
    <meta property="og:description" content="${description}">
    <meta property="og:image" content="${coverUrl}">
    <meta property="og:url" content="https://${req.hostname}/viajes/${authorId}/${tripId}">
    
    <!-- Twitter -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${title}">
    <meta name="twitter:description" content="${description}">
    <meta name="twitter:image" content="${coverUrl}">
  </head>
  <body>
    <h1>${title}</h1>
    <p>${description}</p>
    <img src="${coverUrl}" alt="Cover Image" />
  </body>
</html>`);
          return;
        }
      }
      
      // If trip doesn't exist or is not public, return fallback default tags
      res.status(200).send(`<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Ohtli | El viaje empieza aquí</title>
    <meta name="description" content="Diseña tu camino, explora bitácoras y comparte aventuras con tus amigos.">
    <meta property="og:title" content="Ohtli | El viaje empieza aquí">
    <meta property="og:description" content="Diseña tu camino, explora bitácoras y comparte aventuras con tus amigos.">
  </head>
  <body>
    <h1>Ohtli</h1>
  </body>
</html>`);
    } catch (error) {
      console.error('Error serving trip meta tags:', error);
      res.status(500).send('Internal Server Error');
    }
  } else {
    // Human visitor: redirect to the SPA router on root path
    res.redirect(302, `https://${req.hostname}/?tripId=${tripId}&authorId=${authorId}`);
  }
});

exports.apiGateway = functions.https.onRequest(async (req, res) => {
  // Configuración de CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, DELETE');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Se asume que el backend Yollotl Engine está desplegado en Cloud Functions
  // con el nombre 'api' en la misma región us-central1 (proyecto yollotl-engine-api).
  const targetHost = 'https://us-central1-yollotl-engine-api.cloudfunctions.net';
  
  // Como el rewrite en Firebase Hosting incluye /api/..., usamos req.url o req.path directamente
  const targetUrl = targetHost + req.url;

  try {
    const fetchResponse = await fetch(targetUrl, {
      method: req.method,
      headers: {
        'Content-Type': req.get('Content-Type') || 'application/json',
        'Accept': req.get('Accept') || '*/*',
      },
      body: req.method !== 'GET' && req.method !== 'HEAD' ? req.rawBody : undefined
    });

    const data = await fetchResponse.text();
    
    // Copy some relevant headers back
    res.set('Content-Type', fetchResponse.headers.get('Content-Type') || 'application/json');
    res.status(fetchResponse.status).send(data);
  } catch (error) {
    console.error('API Gateway Error:', error);
    res.status(500).send({ error: 'Gateway Error', details: error.toString() });
  }
});

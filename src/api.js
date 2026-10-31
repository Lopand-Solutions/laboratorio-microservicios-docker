import http from 'node:http';
import { pool, conLimite } from './db.js';

const PUERTO = Number(process.env.PORT ?? 3000);

await pool.query(`
  CREATE TABLE IF NOT EXISTS pedidos (
    id       serial PRIMARY KEY,
    producto text NOT NULL,
    estado   text NOT NULL DEFAULT 'pendiente',
    creado   timestamptz NOT NULL DEFAULT now()
  )`);

function responder(res, codigo, cuerpo) {
  res.writeHead(codigo, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(cuerpo));
}

async function leerJson(req) {
  let texto = '';
  for await (const parte of req) texto += parte;
  return JSON.parse(texto || '{}');
}

const servidor = http.createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/health') {
      try {
        await conLimite(pool.query('SELECT 1'), 1500);
        return responder(res, 200, { status: 'ok' });
      } catch {
        // Una frase escrita a mano, nunca el error del driver.
        return responder(res, 503, { status: 'down', reason: 'no alcanzo la base de datos' });
      }
    }

    if (req.method === 'POST' && req.url === '/pedidos') {
      const { producto } = await leerJson(req);
      if (typeof producto !== 'string' || producto.trim() === '') {
        return responder(res, 400, { error: 'falta producto' });
      }
      const { rows } = await pool.query(
        'INSERT INTO pedidos (producto) VALUES ($1) RETURNING id, producto, estado',
        [producto.trim()],
      );
      return responder(res, 201, rows[0]);
    }

    const ruta = req.url.match(/^\/pedidos\/(\d+)$/);
    if (req.method === 'GET' && ruta) {
      const { rows } = await pool.query(
        'SELECT id, producto, estado FROM pedidos WHERE id = $1',
        [Number(ruta[1])],
      );
      return rows.length ? responder(res, 200, rows[0]) : responder(res, 404, { error: 'no existe' });
    }

    responder(res, 404, { error: 'ruta desconocida' });
  } catch (error) {
    console.error(error);
    responder(res, 500, { error: 'error interno' });
  }
});

servidor.listen(PUERTO, () => console.log(`api escuchando en el puerto ${PUERTO}`));

// Docker manda SIGTERM al detener el contenedor: cerramos limpio.
process.on('SIGTERM', () => {
  servidor.close(() => pool.end().then(() => process.exit(0)));
});

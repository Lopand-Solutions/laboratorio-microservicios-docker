import { writeFileSync } from 'node:fs';
import { setTimeout as esperar } from 'node:timers/promises';
import { pool } from './db.js';

const LATIDO = '/tmp/latido';
let seguir = true;

process.on('SIGTERM', () => {
  seguir = false;
});

// Toma un pedido pendiente y lo marca como procesado.
// SKIP LOCKED: si corres dos workers, nunca toman el mismo pedido.
async function procesarUno() {
  const { rows } = await pool.query(`
    UPDATE pedidos SET estado = 'procesado'
    WHERE id = (
      SELECT id FROM pedidos WHERE estado = 'pendiente'
      ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED
    )
    RETURNING id, producto`);
  if (rows.length) console.log(`pedido ${rows[0].id} procesado (${rows[0].producto})`);
  return rows.length > 0;
}

console.log('worker en marcha');
while (seguir) {
  try {
    while (seguir && (await procesarUno()));
    // El latido prueba que el ciclo sigue vivo, no solo que el proceso existe.
    writeFileSync(LATIDO, String(Date.now()));
  } catch (error) {
    console.error('no pude procesar:', error.message);
  }
  await esperar(2000);
}
await pool.end();
console.log('worker detenido');

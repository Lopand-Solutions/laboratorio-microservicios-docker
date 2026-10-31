import pg from 'pg';

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('Falta la variable DATABASE_URL');
  process.exit(1);
}

// Pocas conexiones por servicio: Postgres tiene un límite total y lo comparten todos.
export const pool = new pg.Pool({ connectionString: url, max: 5, connectionTimeoutMillis: 2000 });

// Sin esto, si la base se reinicia, una conexión inactiva que se corta tumba el proceso.
pool.on('error', (error) => console.error('se perdió una conexión con la base:', error.message));

// Corre una consulta, pero se rinde a los ms indicados.
export function conLimite(promesa, ms) {
  let timer;
  const limite = new Promise((_, rechazar) => {
    timer = setTimeout(() => rechazar(new Error('tiempo agotado')), ms);
  });
  return Promise.race([promesa, limite]).finally(() => clearTimeout(timer));
}

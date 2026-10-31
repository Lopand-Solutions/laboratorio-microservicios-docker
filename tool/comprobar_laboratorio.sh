#!/usr/bin/env bash
# Comprueba el laboratorio «Microservicios con Docker para principiantes».
# Uso: ./tool/comprobar_laboratorio.sh            (revisa archivos y levanta todo con Docker)
#      ./tool/comprobar_laboratorio.sh --sin-docker  (solo revisa archivos y el compose)
# Si los contenedores no estaban arriba, los apaga al terminar (sin borrar el volumen).
set -uo pipefail
cd "$(dirname "$0")/.."
ok=0; mal=0
bien() { echo "  ✓ $1"; ok=$((ok + 1)); }
falla() { echo "  ✗ $1"; mal=$((mal + 1)); }
CON_DOCKER=1; [ "${1:-}" = "--sin-docker" ] && CON_DOCKER=0

echo "1. Archivos"
[ -f Dockerfile ] && bien "Dockerfile existe" || falla "falta el Dockerfile"
[ -f compose.yaml ] && bien "compose.yaml existe" || falla "falta compose.yaml"
if [ -f .dockerignore ] && grep -qx "node_modules" .dockerignore && grep -qx ".env" .dockerignore; then
  bien ".dockerignore deja fuera node_modules y .env"
else
  falla ".dockerignore debe excluir node_modules y .env (la contraseña no va dentro de la imagen)"
fi
if [ -f .env ] && grep -q "^DB_PASSWORD=." .env; then bien ".env tiene DB_PASSWORD"; else falla "falta .env con DB_PASSWORD (paso 5)"; fi
grep -qx ".env" .gitignore 2>/dev/null && bien ".env está en .gitignore" || falla ".env no está en .gitignore: se subiría tu contraseña"
if git rev-parse --git-dir >/dev/null 2>&1 && git ls-files --error-unmatch .env >/dev/null 2>&1; then
  falla ".env está en git: sácalo con git rm --cached .env"
fi

echo "2. El Dockerfile"
if [ -f Dockerfile ]; then
  grep -qiE "^FROM .+ AS api$" Dockerfile && grep -qiE "^FROM .+ AS worker$" Dockerfile \
    && bien "dos imágenes de un solo Dockerfile (etapas api y worker)" || falla "faltan las etapas «AS api» y «AS worker»"
  [ "$(grep -iE '^FROM ' Dockerfile | tail -1 | awk '{print tolower($NF)}')" = "api" ] \
    && bien "la api es la última etapa: un build sin --target da la api" || falla "la última etapa debería ser la api"
  grep -qE "^USER node" Dockerfile && bien "el código no corre como root" || falla "falta USER node"
  [ "$(grep -c '^HEALTHCHECK' Dockerfile)" -ge 2 ] && bien "api y worker tienen healthcheck" || falla "cada imagen necesita su HEALTHCHECK"
  grep -q "latido" Dockerfile && bien "el healthcheck del worker mira el latido" || falla "el healthcheck del worker no revisa /tmp/latido"
fi

echo "3. El compose"
if ! command -v docker >/dev/null 2>&1; then
  falla "no encuentro docker: instálalo con el plugin de Compose"
elif ! docker compose config --quiet 2>/tmp/compose-error.txt; then
  falla "docker compose config falla: $(head -1 /tmp/compose-error.txt)"
else
  bien "docker compose config valida el archivo"
  # El compose ya resuelto (con variables) en JSON, y node para leerlo: Node 22 ya es requisito del laboratorio.
  docker compose config --format json 2>/dev/null | node -e '
    const c = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const s = c.services ?? {}, r = [];
    const db = s.db ?? {}, api = s.api ?? {}, worker = s.worker ?? {};
    const alias = Object.values(db.networks ?? {}).flatMap((n) => n?.aliases ?? []);
    const internas = Object.entries(c.networks ?? {}).filter(([, n]) => n.internal).map(([k]) => k);
    const host = (svc) => (svc.environment?.DATABASE_URL ?? "").match(/@([^:/]+)/)?.[1];
    const puertos = (svc) => svc.ports ?? [];
    r.push([!puertos(db).length, "Postgres no publica ningún puerto", "quita «ports» de db: la base no se abre afuera"]);
    r.push([Object.keys(db.networks ?? {}).every((n) => internas.includes(n)) && internas.length > 0,
      "Postgres solo vive en una red internal: true", "pon a db solo en una red con internal: true"]);
    r.push([puertos(api).length > 0 && puertos(api).every((p) => p.host_ip === "127.0.0.1"),
      "la api publica su puerto solo en 127.0.0.1", "publica la api como 127.0.0.1:3000:3000"]);
    r.push([alias.length > 0 && !alias.includes("db"), `la base tiene un alias propio (${alias.join(", ") || "ninguno"})`, "dale a db un alias con el nombre del proyecto, como mi-app-db"]);
    r.push([host(api) && alias.includes(host(api)) && host(worker) === host(api),
      "api y worker se conectan por el alias", "DATABASE_URL de api y worker debe apuntar al alias de la base, no a «db»"]);
    r.push([api.depends_on?.db?.condition === "service_healthy", "la api espera a que la base esté sana", "api: depends_on db con condition: service_healthy"]);
    r.push([worker.depends_on?.api?.condition === "service_healthy", "el worker espera a la api (ella crea la tabla)", "worker: depends_on api con condition: service_healthy"]);
    r.push([(db.volumes ?? []).some((v) => v.type === "volume"), "los datos de Postgres viven en un volumen con nombre", "monta un volumen con nombre en db"]);
    for (const [cumple, si, no] of r) console.log(cumple ? `OK ${si}` : `NO ${no}`);
  ' > /tmp/compose-revision.txt 2>&1 || true
  while IFS= read -r linea; do
    case "$linea" in OK\ *) bien "${linea#OK }";; NO\ *) falla "${linea#NO }";; *) falla "no pude leer el compose: $linea";; esac
  done < /tmp/compose-revision.txt
fi

if [ "$CON_DOCKER" -eq 1 ] && [ "$mal" -eq 0 ]; then
  echo "4. Todo junto (levanta los contenedores, puede tardar la primera vez)"
  estaban=$(docker compose ps -q 2>/dev/null | wc -l)
  url="http://127.0.0.1:3000"
  codigo() { curl -s -o /dev/null -w "%{http_code}" "$@"; }
  if docker compose up -d --build --wait >/tmp/compose-up.txt 2>&1; then
    bien "los tres servicios arrancan en orden y quedan healthy"
    [ "$(codigo "$url/health")" = "200" ] && bien "/health contesta 200 con la base arriba" || falla "/health no contesta 200"
    id=$(curl -s -X POST "$url/pedidos" -H 'Content-Type: application/json' -d '{"producto":"prueba del laboratorio"}' | node -e 'try{console.log(JSON.parse(require("fs").readFileSync(0,"utf8")).id??"")}catch{}')
    if [ -n "$id" ]; then
      estado=""
      for _ in $(seq 1 15); do
        estado=$(curl -s "$url/pedidos/$id" | node -e 'try{console.log(JSON.parse(require("fs").readFileSync(0,"utf8")).estado??"")}catch{}')
        [ "$estado" = "procesado" ] && break; sleep 1
      done
      [ "$estado" = "procesado" ] && bien "el worker procesa un pedido nuevo" || falla "el pedido $id sigue «$estado» después de 15 s: revisa docker compose logs worker"
    else
      falla "POST /pedidos no devolvió un id"
    fi
    docker compose stop db >/dev/null 2>&1
    [ "$(codigo --max-time 5 "$url/health")" = "503" ] && bien "con la base apagada, /health contesta 503 (y la api sigue viva)" || falla "con la base apagada, /health no contesta 503"
    docker compose start db >/dev/null 2>&1
    vuelve=""
    for _ in $(seq 1 30); do [ "$(codigo "$url/health")" = "200" ] && vuelve=1 && break; sleep 1; done
    [ -n "$vuelve" ] && bien "cuando la base vuelve, /health regresa a 200 sin reiniciar la api" || falla "/health no volvió a 200 en 30 s"
  else
    falla "docker compose up --wait falló: $(tail -1 /tmp/compose-up.txt)"
  fi
  [ "$estaban" -eq 0 ] && docker compose down >/dev/null 2>&1
fi

echo
if [ "$mal" -eq 0 ]; then echo "Laboratorio completo: $ok de $ok."; exit 0; fi
[ "$mal" -eq 1 ] && echo "Falta 1 cosa ($ok bien)." || echo "Faltan $mal cosas ($ok bien)."
exit 1

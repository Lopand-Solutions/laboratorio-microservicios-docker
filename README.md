# Laboratorio: microservicios con Docker

Repositorio del laboratorio de [Lopand Academy](https://academy.lopandsolutions.com/tutoriales/microservicios-docker-principiantes).
Una tienda mínima en tres contenedores: una api en Node, un worker que procesa pedidos y Postgres.

## Ramas

- **`inicio`**: el código de la api y el worker (pasos 1 a 3), sin nada de Docker. Desde aquí empiezas.
- **`main`**: la solución: `Dockerfile` multietapa, `.dockerignore` y `compose.yaml`.

```bash
git clone -b inicio https://github.com/Lopand-Solutions/laboratorio-microservicios-docker.git mi-app
cd mi-app
npm install
```

## Cómo saber si quedó

```bash
./tool/comprobar_laboratorio.sh
```

Revisa el Dockerfile y el compose (la base sin puertos y en una red interna, el alias propio, el orden de arranque),
levanta los tres servicios, crea un pedido, apaga la base para ver el 503 y la vuelve a prender.
Con `--sin-docker` solo revisa los archivos.

## Requisitos

Docker con el plugin de Compose y Node 22. La contraseña de la base va en un `.env` que no se sube a git (paso 5).

Código libre para usar y adaptar (licencia MIT).

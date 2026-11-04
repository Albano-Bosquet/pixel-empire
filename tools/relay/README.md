# Servidor online de Pixel Empire (relay)

Este servidor permite crear partidas online y unirse a ellas **sin abrir puertos ni tocar el firewall**.
Funciona también desde móviles con datos.

Todos los jugadores, anfitrión incluido, se conectan **hacia** el servidor por WebSocket
seguro (`wss://`). El servidor reenvía los paquetes dentro de cada sala y nunca lee los
datos del juego. La partida la sigue simulando el ordenador del anfitrión.

Hay dos versiones del servidor con el mismo protocolo. El juego no distingue una de otra:

| Carpeta | Dónde corre | Para qué |
|---|---|---|
| `cloudflare/` | Cloudflare Workers + Durable Objects | **Recomendado**: gratis, sin tarjeta y no se duerme |
| `server.js` | Node.js (PC, VPS, Docker) | Pruebas en local o un servidor propio |

`test.js` prueba el protocolo contra cualquiera de las dos (`npm test`).

## Opción A: Cloudflare (recomendada, 100 % gratis)

Solo hay que hacerlo una vez:

1. Crea una cuenta gratuita en <https://dash.cloudflare.com/sign-up>. No pide tarjeta.
2. En una terminal, desde la carpeta del proyecto:

   ```bash
   cd tools/relay/cloudflare
   npm install
   npx wrangler login
   npx wrangler deploy
   ```

   `wrangler login` abre el navegador para que autorices tu cuenta. La primera vez,
   Cloudflare te pide elegir un subdominio `workers.dev`.
3. `deploy` termina mostrando la dirección, por ejemplo
   `https://pixel-empire-relay.tu-usuario.workers.dev`.
4. En `assets/data/net_settings.json`, pon esa dirección en `relay_url` con `wss://`:
   `"relay_url": "wss://pixel-empire-relay.tu-usuario.workers.dev"`.

**Límites del plan gratuito:** 100.000 peticiones al día. Cloudflare cuenta 1 petición por
cada 20 mensajes que *llegan* al servidor, y los mensajes que salen no cuentan. Eso da
para unas **12 horas de partidas de 4 jugadores al día** (más de 30 h si son de 2). Si se
supera, el servidor online deja de funcionar hasta las 00:00 UTC. Sin tarjeta no se puede
cobrar nada.

Para ver el uso: panel de Cloudflare → Workers & Pages → `pixel-empire-relay`.

Para actualizar el servidor después de cambiar `cloudflare/src/index.js`, vuelve a ejecutar
`npx wrangler deploy`.

## Opción B: un servidor propio (Node.js / Docker)

```bash
docker build -t pixel-empire-relay tools/relay
docker run -d --restart=always -p 8080:8080 --name relay pixel-empire-relay
```

Para tener `wss://` hace falta un dominio y un proxy con TLS delante. Con
[Caddy](https://caddyserver.com) basta un `Caddyfile` de una línea:

```
relay.tudominio.com {
    reverse_proxy localhost:8080
}
```

Luego `"relay_url": "wss://relay.tudominio.com"`.

## Probar en local

Servidor Node:

```bash
cd tools/relay && npm install && npm test && npm start
```

Versión Cloudflare en local, con el mismo test:

```bash
cd tools/relay/cloudflare && npm install && npm run dev
```

En otra terminal:

```bash
cd tools/relay && RELAY_URL=ws://127.0.0.1:8787 node test.js
```

Partida de prueba completa del juego a través de un relay local (anfitrión, cliente y
reconexión). Usa el puerto 8080 para Node o 8787 para Cloudflare:

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . -- --mp=host --smoke=mp --online --relay=ws://127.0.0.1:8787
```

Lanza después el mismo comando con `--mp=client` y luego con `--mp=rejoin`.

## Límites del servidor

- 300 salas.
- Hasta 8 jugadores por sala.
- Paquetes de 1 MB como máximo.

Si el anfitrión se va, la sala se cierra.

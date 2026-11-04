# Servidor online de Pixel Empire (relay)

Este servidor permite crear partidas online y unirse a ellas **sin abrir puertos ni tocar el firewall**.
Funciona también desde móviles con datos.

Todos los jugadores, anfitrión incluido, se conectan **hacia** el servidor por WebSocket
seguro (`wss://`, puerto 443). El servidor reenvía los paquetes dentro de cada sala y
nunca lee los datos del juego. La partida la sigue simulando el ordenador del anfitrión.

- `server.js`: el servidor (Node.js con la librería `ws`).
- `test.js`: prueba del protocolo (`npm test`).
- `Dockerfile`: para desplegarlo en un VPS con Docker.
- `../../render.yaml`: despliegue en Render con un clic.

## Opción A: Render (gratis, sin tarjeta)

1. Crea una cuenta en <https://render.com> entrando con tu cuenta de GitHub.
2. **New → Blueprint** y elige el repositorio `pixel-empire`. Render lee `render.yaml`
   y crea el servicio `pixel-empire-relay`. Pulsa **Apply**.
3. Cuando aparezca *Live*, copia la dirección del servicio
   (por ejemplo `https://pixel-empire-relay.onrender.com`).
4. En `assets/data/net_settings.json`, pon `relay_url` con `wss://` en lugar de `https://`:
   `"relay_url": "wss://pixel-empire-relay.onrender.com"`.

En el plan gratuito, el servidor **se duerme tras 15 minutos sin uso**. La primera
conexión después de eso tarda hasta un minuto en despertarlo (el juego espera
`relay_timeout` segundos). Con el plan de pago más barato no se duerme.

## Opción B: un VPS propio (Docker)

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

```bash
cd tools/relay
npm install
npm test
npm start
```

Partida de prueba completa a través del relay local (anfitrión, cliente y reconexión):

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . -- --mp=host --smoke=mp --online --relay=ws://127.0.0.1:8080
```

Lanza después el mismo comando con `--mp=client` y luego con `--mp=rejoin`.

## Límites

Están en `server.js` y en variables de entorno:

- `MAX_ROOMS`: 300 salas.
- Hasta 8 jugadores por sala.
- Paquetes de 1 MB como máximo.

Las conexiones muertas se cierran tras unos 15–30 s sin respuesta. Si el anfitrión se
va, la sala se cierra.

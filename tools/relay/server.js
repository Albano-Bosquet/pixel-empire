// Pixel Empire relay: lets players host and join online games without opening
// ports. Everyone (host included) connects OUT to this server over WebSocket
// (wss on port 443 when behind a TLS proxy such as Render/Fly), so no router,
// firewall or mobile-carrier NAT is in the way.
//
// The server never reads game data. It keeps rooms (one host + clients) and
// forwards binary frames between them; the host still runs the whole match.
//
// Text frames (JSON) are control messages:
//   client -> server  {"op":"host","tag":T,"version":V,"name":N,"max":8}
//                     {"op":"join","code":C,"tag":T,"version":V}
//                     {"op":"list","tag":T,"version":V}
//                     {"op":"info","players":n,"open":bool}      (host)
//                     {"op":"kick","id":n}                        (host)
//   server -> client  {"op":"hosted","code":C,"id":1}
//                     {"op":"joined","id":n,"code":C}
//                     {"op":"peer_in","id":n} / {"op":"peer_out","id":n}  (host)
//                     {"op":"rooms","rooms":[{code,name,players,max,version}]}
//                     {"op":"error","reason":R} (then the socket closes)
// Binary frames carry game packets: [int32 LE peer][u8 channel][u8 mode] + payload.
// Sent: peer = target (host: 0 all, n one, -n all but n; clients always reach
// the host). Received: peer = sender id.
//
// Run:  npm install && npm start        (PORT env, default 8080)

"use strict";
const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = parseInt(process.env.PORT || "8080", 10);
const MAX_ROOMS = parseInt(process.env.MAX_ROOMS || "300", 10);
const MAX_PLAYERS = 8;
const MAX_FRAME = 1 << 20;
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I
const CODE_LEN = 5;
const HEADER = 6;

/** code -> {code, tag, version, name, max, open, host, clients: Map<id, ws>, nextId} */
const rooms = new Map();

function makeCode() {
  for (let tries = 0; tries < 100; tries++) {
    let c = "";
    for (let i = 0; i < CODE_LEN; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    if (!rooms.has(c)) return c;
  }
  return null;
}

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function fail(ws, reason) {
  send(ws, { op: "error", reason });
  ws.close(1000, "error");
}

function closeRoom(room) {
  rooms.delete(room.code);
  for (const c of room.clients.values()) c.close(1000, "host left");
  room.clients.clear();
}

function onControl(ws, msg) {
  const op = msg.op;
  if (op === "host" && !ws.room) {
    if (rooms.size >= MAX_ROOMS) return fail(ws, "The relay is full, try again later");
    const code = makeCode();
    if (!code) return fail(ws, "The relay is full, try again later");
    const room = {
      code, tag: String(msg.tag || ""), version: String(msg.version || ""),
      name: String(msg.name || "Host").slice(0, 32), max: Math.min(MAX_PLAYERS, Math.max(2, msg.max | 0 || MAX_PLAYERS)),
      open: true, players: 1, host: ws, clients: new Map(), nextId: 2,
    };
    rooms.set(code, room);
    ws.room = room; ws.peerId = 1;
    send(ws, { op: "hosted", code, id: 1 });
  } else if (op === "join" && !ws.room) {
    const room = rooms.get(String(msg.code || "").toUpperCase().trim());
    if (!room || room.tag !== String(msg.tag || "")) return fail(ws, "No game with that code");
    // The host enforces its own slots (and lets dropped players back in);
    // this cap only stops a flood of sockets on one room.
    if (room.clients.size >= MAX_PLAYERS * 2) return fail(ws, "The game is full");
    const id = room.nextId++;
    ws.room = room; ws.peerId = id;
    room.clients.set(id, ws);
    send(ws, { op: "joined", id, code: room.code });
    send(room.host, { op: "peer_in", id });
  } else if (op === "list") {
    const tag = String(msg.tag || ""), version = String(msg.version || "");
    const list = [];
    for (const r of rooms.values()) {
      if (r.tag === tag && r.version === version && r.open) list.push({ code: r.code, name: r.name, players: r.players, max: r.max, version: r.version });
      if (list.length >= 50) break;
    }
    send(ws, { op: "rooms", rooms: list });
  } else if (op === "info" && ws.room && ws.peerId === 1) {
    ws.room.players = Math.max(1, msg.players | 0);
    ws.room.open = !!msg.open;
  } else if (op === "kick" && ws.room && ws.peerId === 1) {
    const c = ws.room.clients.get(msg.id | 0);
    if (c) c.close(1000, "kicked");
  }
}

function onBinary(ws, data) {
  const room = ws.room;
  if (!room || data.length < HEADER || data.length > MAX_FRAME) return;
  const target = data.readInt32LE(0);
  const out = Buffer.from(data); // header rewritten with the sender id
  out.writeInt32LE(ws.peerId, 0);
  if (ws.peerId !== 1) {
    if (room.host.readyState === room.host.OPEN) room.host.send(out);
    return;
  }
  if (target > 0) {
    const c = room.clients.get(target);
    if (c && c.readyState === c.OPEN) c.send(out);
    return;
  }
  for (const [id, c] of room.clients) {
    if ((target === 0 || id !== -target) && c.readyState === c.OPEN) c.send(out);
  }
}

function onClose(ws) {
  const room = ws.room;
  if (!room) return;
  ws.room = null;
  if (ws.peerId === 1) {
    closeRoom(room);
  } else if (room.clients.delete(ws.peerId)) {
    send(room.host, { op: "peer_out", id: ws.peerId });
  }
}

const server = http.createServer((req, res) => {
  // Health check for hosting platforms (and a quick look in a browser).
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end(`Pixel Empire relay - ${rooms.size} games\n`);
});
const wss = new WebSocketServer({ server, maxPayload: MAX_FRAME });

wss.on("connection", (ws) => {
  ws.isAlive = true;
  ws.on("pong", () => { ws.isAlive = true; });
  ws.on("message", (data, isBinary) => {
    if (isBinary) return onBinary(ws, data);
    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return; }
    if (msg && typeof msg === "object") onControl(ws, msg);
  });
  ws.on("close", () => onClose(ws));
  ws.on("error", () => {});
});

// Drops dead connections (phones that lost signal) so their rooms close.
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 15000);
wss.on("close", () => clearInterval(heartbeat));

server.listen(PORT, () => console.log(`Pixel Empire relay on port ${PORT}`));

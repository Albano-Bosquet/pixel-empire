// Pixel Empire relay on Cloudflare Workers (free plan, no card, never sleeps).
// Same protocol as ../server.js (see the header there): the game cannot tell
// them apart. Every WebSocket goes to one Durable Object, "Relay", which keeps
// the rooms and forwards frames between a host and its clients.
//
// Hibernation: idle sockets stay open while the object is evicted from memory,
// so each socket carries its state in an attachment ({code, id, room?}) and the
// rooms are rebuilt from those attachments when the object wakes up.

const MAX_ROOMS = 300;
const MAX_PLAYERS = 8;
const MAX_FRAME = 1 << 20;
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I
const CODE_LEN = 5;
const HEADER = 6;

export default {
  async fetch(request, env) {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Pixel Empire relay\n", { headers: { "Content-Type": "text/plain" } });
    }
    const stub = env.RELAY.get(env.RELAY.idFromName("main"));
    return stub.fetch(request);
  },
};

export class Relay {
  constructor(ctx) {
    this.ctx = ctx;
    /** code -> {code, tag, version, name, max, open, players, nextId, host, clients: Map<id, ws>} */
    this.rooms = new Map();
    for (const ws of ctx.getWebSockets()) {
      const a = ws.deserializeAttachment();
      if (a && a.room) this.rooms.set(a.code, { ...a.room, code: a.code, host: ws, clients: new Map() });
    }
    for (const ws of ctx.getWebSockets()) {
      const a = ws.deserializeAttachment();
      const room = a && !a.room ? this.rooms.get(a.code) : null;
      if (room) room.clients.set(a.id, ws);
    }
  }

  async fetch() {
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    pair[1].serializeAttachment({ code: "", id: 0 });
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  info(ws) {
    return ws.deserializeAttachment() || { code: "", id: 0 };
  }

  // The host's attachment holds the room so it survives hibernation.
  saveRoom(room) {
    const { host, clients, code, ...meta } = room;
    host.serializeAttachment({ code, id: 1, room: meta });
  }

  send(ws, obj) {
    try { ws.send(JSON.stringify(obj)); } catch {}
  }

  fail(ws, reason) {
    this.send(ws, { op: "error", reason });
    try { ws.close(1000, "error"); } catch {}
  }

  makeCode() {
    for (let tries = 0; tries < 100; tries++) {
      let c = "";
      for (let i = 0; i < CODE_LEN; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
      if (!this.rooms.has(c)) return c;
    }
    return null;
  }

  async webSocketMessage(ws, data) {
    if (typeof data !== "string") return this.onBinary(ws, data);
    let msg;
    try { msg = JSON.parse(data); } catch { return; }
    if (msg && typeof msg === "object") this.onControl(ws, msg);
  }

  onControl(ws, msg) {
    const me = this.info(ws);
    const op = msg.op;
    if (op === "host" && !me.code) {
      const code = this.rooms.size < MAX_ROOMS ? this.makeCode() : null;
      if (!code) return this.fail(ws, "The relay is full, try again later");
      const room = {
        code, tag: String(msg.tag || ""), version: String(msg.version || ""),
        name: String(msg.name || "Host").slice(0, 32), max: Math.min(MAX_PLAYERS, Math.max(2, msg.max | 0 || MAX_PLAYERS)),
        open: true, players: 1, nextId: 2, host: ws, clients: new Map(),
      };
      this.rooms.set(code, room);
      this.saveRoom(room);
      this.send(ws, { op: "hosted", code, id: 1 });
    } else if (op === "join" && !me.code) {
      const room = this.rooms.get(String(msg.code || "").toUpperCase().trim());
      if (!room || room.tag !== String(msg.tag || "")) return this.fail(ws, "No game with that code");
      // The host enforces its own slots; this only stops a flood of sockets.
      if (room.clients.size >= MAX_PLAYERS * 2) return this.fail(ws, "The game is full");
      const id = room.nextId++;
      this.saveRoom(room);
      ws.serializeAttachment({ code: room.code, id });
      room.clients.set(id, ws);
      this.send(ws, { op: "joined", id, code: room.code });
      this.send(room.host, { op: "peer_in", id });
    } else if (op === "list") {
      const tag = String(msg.tag || ""), version = String(msg.version || "");
      const list = [];
      for (const r of this.rooms.values()) {
        if (r.tag === tag && r.version === version && r.open) list.push({ code: r.code, name: r.name, players: r.players, max: r.max, version: r.version });
        if (list.length >= 50) break;
      }
      this.send(ws, { op: "rooms", rooms: list });
    } else if (op === "info" && me.id === 1) {
      const room = this.rooms.get(me.code);
      if (!room) return;
      room.players = Math.max(1, msg.players | 0);
      room.open = !!msg.open;
      this.saveRoom(room);
    } else if (op === "kick" && me.id === 1) {
      const room = this.rooms.get(me.code);
      const c = room && room.clients.get(msg.id | 0);
      if (c) this.drop(c, "kicked");
    }
  }

  onBinary(ws, data) {
    const me = this.info(ws);
    const room = this.rooms.get(me.code);
    if (!room || data.byteLength < HEADER || data.byteLength > MAX_FRAME) return;
    const out = new Uint8Array(data.byteLength);
    out.set(new Uint8Array(data));
    const view = new DataView(out.buffer);
    const target = view.getInt32(0, true);
    view.setInt32(0, me.id, true); // receivers see the sender id
    if (me.id !== 1) {
      try { room.host.send(out); } catch {}
      return;
    }
    if (target > 0) {
      const c = room.clients.get(target);
      if (c) try { c.send(out); } catch {}
      return;
    }
    for (const [id, c] of room.clients) {
      if (target === 0 || id !== -target) try { c.send(out); } catch {}
    }
  }

  // A client leaves its room: the host hears about it once.
  drop(ws, reason) {
    const me = this.info(ws);
    const room = this.rooms.get(me.code);
    ws.serializeAttachment({ code: "", id: 0 });
    try { ws.close(1000, reason); } catch {}
    if (!room) return;
    if (me.id === 1) {
      this.rooms.delete(room.code);
      for (const c of room.clients.values()) {
        c.serializeAttachment({ code: "", id: 0 });
        try { c.close(1000, "host left"); } catch {}
      }
    } else if (room.clients.delete(me.id)) {
      this.send(room.host, { op: "peer_out", id: me.id });
    }
  }

  async webSocketClose(ws) {
    this.drop(ws, "closed");
  }

  async webSocketError(ws) {
    this.drop(ws, "error");
  }
}

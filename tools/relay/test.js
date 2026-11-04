// Protocol test for server.js: starts the relay on a free port and drives a
// host and two clients through hosting, listing, joining, forwarding, kicking
// and the host leaving. Run: npm test
"use strict";
const { spawn } = require("child_process");
const WebSocket = require("ws");
const assert = require("assert");

const PORT = 18000 + Math.floor(Math.random() * 1000);
const URL = `ws://127.0.0.1:${PORT}`;
const HELLO = { tag: "PixelEmpire1", version: "9.9.9" };

function open() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(URL);
    ws.inbox = [];
    ws.waiters = [];
    ws.on("message", (data, isBinary) => {
      const m = isBinary ? { bin: Buffer.from(data) } : JSON.parse(data.toString());
      const w = ws.waiters.findIndex((f) => f.match(m));
      if (w >= 0) ws.waiters.splice(w, 1)[0].resolve(m); else ws.inbox.push(m);
    });
    ws.on("open", () => resolve(ws));
    ws.on("error", reject);
  });
}

function next(ws, match, ms = 2000) {
  const i = ws.inbox.findIndex(match);
  if (i >= 0) return Promise.resolve(ws.inbox.splice(i, 1)[0]);
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error("timeout waiting for message")), ms);
    ws.waiters.push({ match, resolve: (m) => { clearTimeout(t); resolve(m); } });
  });
}

const op = (name) => (m) => m.op === name;
const bin = (m) => !!m.bin;
function frame(peer, payload) {
  const b = Buffer.alloc(6 + payload.length);
  b.writeInt32LE(peer, 0); b[4] = 0; b[5] = 2;
  Buffer.from(payload).copy(b, 6);
  return b;
}
const closed = (ws) => new Promise((r) => (ws.readyState === ws.CLOSED ? r() : ws.on("close", r)));

async function main() {
  const srv = spawn(process.execPath, [__dirname + "/server.js"], { env: { ...process.env, PORT: String(PORT) } });
  await new Promise((r) => srv.stdout.once("data", r));
  try {
    const host = await open();
    host.send(JSON.stringify({ op: "host", name: "Ana", max: 4, ...HELLO }));
    const hosted = await next(host, op("hosted"));
    assert.strictEqual(hosted.id, 1, "host is peer 1");
    assert.match(hosted.code, /^[A-Z2-9]{5}$/, "5-character room code");

    const lister = await open();
    lister.send(JSON.stringify({ op: "list", ...HELLO }));
    const rooms = await next(lister, op("rooms"));
    assert.deepStrictEqual(rooms.rooms.map((r) => r.code), [hosted.code], "the open game is listed");
    lister.send(JSON.stringify({ op: "list", tag: HELLO.tag, version: "0.0.1" }));
    assert.strictEqual((await next(lister, op("rooms"))).rooms.length, 0, "other versions see no games");

    const a = await open();
    a.send(JSON.stringify({ op: "join", code: hosted.code.toLowerCase(), ...HELLO }));
    const ja = await next(a, op("joined"));
    assert.strictEqual((await next(host, op("peer_in"))).id, ja.id, "host learns the new peer");
    const b = await open();
    b.send(JSON.stringify({ op: "join", code: hosted.code, ...HELLO }));
    const jb = await next(b, op("joined"));
    await next(host, op("peer_in"));

    a.send(frame(0, "hello host"));
    const got = await next(host, bin);
    assert.strictEqual(got.bin.readInt32LE(0), ja.id, "host sees the sender id");
    assert.strictEqual(got.bin.subarray(6).toString(), "hello host");

    host.send(frame(0, "to all"));
    assert.strictEqual((await next(a, bin)).bin.subarray(6).toString(), "to all");
    assert.strictEqual((await next(b, bin)).bin.readInt32LE(0), 1, "clients see the host as sender 1");
    host.send(frame(jb.id, "only b"));
    assert.strictEqual((await next(b, bin)).bin.subarray(6).toString(), "only b");
    host.send(frame(-jb.id, "all but b"));
    assert.strictEqual((await next(a, bin)).bin.subarray(6).toString(), "all but b");
    await new Promise((r) => setTimeout(r, 150));
    assert.ok(!b.inbox.some(bin), "excluded peer gets nothing");

    host.send(JSON.stringify({ op: "info", players: 3, open: false }));
    await new Promise((r) => setTimeout(r, 100));
    lister.send(JSON.stringify({ op: "list", ...HELLO }));
    assert.strictEqual((await next(lister, op("rooms"))).rooms.length, 0, "a started game leaves the list");

    host.send(JSON.stringify({ op: "kick", id: jb.id }));
    await closed(b);
    assert.strictEqual((await next(host, op("peer_out"))).id, jb.id, "host hears the kicked peer leave");

    const bad = await open();
    bad.send(JSON.stringify({ op: "join", code: "ZZZZZ", ...HELLO }));
    assert.strictEqual((await next(bad, op("error"))).reason, "No game with that code");

    host.close();
    await closed(a);
    lister.send(JSON.stringify({ op: "list", ...HELLO }));
    assert.strictEqual((await next(lister, op("rooms"))).rooms.length, 0, "the room is gone with its host");
    lister.close();
    console.log("RELAY TEST: PASS");
  } finally {
    srv.kill();
  }
}

main().catch((e) => { console.error("RELAY TEST: FAIL -", e.message); process.exit(1); });

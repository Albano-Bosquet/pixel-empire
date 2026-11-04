class_name Replicator
extends Node
## Match state replication for host-authoritative multiplayer (M3).
##
## Host: every 1 / snapshot_hz seconds each connected human gets a snapshot of
## what *they* may see (own entities, enemies in their vision, explored
## buildings), plus reliable events (deaths, removals, depleted nodes,
## notifications, effects, alerts, game over). Orders from clients are applied
## through OrderRouter.apply() with the sender's player id.
## Client ("replica" match): the simulation systems are off; entities are
## created, updated, interpolated and removed from snapshots; fog is computed
## locally from the player's own (replicated) entities.
## Wire format: [u32 LE raw size] + zstd(var_to_bytes of
##   {"t": float, "pl": [[id, res, age, researched, defeated]], "u": [[...]], "b": [[...]],
##    "r": [[id, amount]], "pr": [[kind, sx, sy, dx, dy]], "mp": prices})
## Unit/building types travel as indexes into the sorted id lists of GameData.

const UNIT_FIELDS := ["id", "type", "owner", "x", "y", "hp", "max_hp", "anim", "facing", "carry_t", "carry", "aboard", "ammo", "moving", "task"]

var _game: Game
var _hz := 15.0
var _timer := 0.0
var _events: Dictionary = {}   # player id -> Array of events (host)
var _unit_types: Array = []
var _bld_types: Array = []
var _ai_for: Dictionary = {}   # player id -> AIPlayer taking over a dropped human
## Times a dropped human came back (diagnostics / tests).
var returns := 0
# Client interpolation: entity_id -> {"from": Vector2, "to": Vector2, "t": float}
var _interp: Dictionary = {}
var _interval := 1.0 / 15.0
var _last_prices: Dictionary = {}
## Units missing from the latest snapshot: entity_id -> msec first missed. They
## linger briefly so a death event (reliable channel, may arrive after the
## unreliable snapshot) can still play the death animation.
var _vanish: Dictionary = {}
const VANISH_GRACE_MS := 600
## Largest snapshot a client accepts once decompressed (guards bad packets).
const MAX_SNAPSHOT := 1 << 24
## Size of the last snapshot sent: [raw bytes, wire bytes] (diagnostics / tests).
var last_snapshot_size := [0, 0]


func setup(game: Game) -> void:
	_game = game
	_hz = float(Net.settings.get("snapshot_hz", 15))
	_interval = 1.0 / maxf(1.0, _hz)
	_unit_types = GameData.units.keys()
	_unit_types.sort()
	_bld_types = GameData.buildings.keys()
	_bld_types.sort()
	Net.replicator = self
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if Net.is_host():
		EventBus.entity_killed.connect(func(e: Entity, _a: Entity) -> void: _event_all(["kill", e.entity_id]))
		EventBus.entity_removed.connect(func(e: Entity) -> void: _event_all(["remove", e.entity_id]))
		EventBus.resource_depleted.connect(func(e: Entity) -> void: _event_all(["deplete", e.entity_id]))
		EventBus.notify.connect(_on_notify)
		EventBus.under_attack.connect(func(pid: int, pos: Vector2) -> void: _event(pid, ["ping", pos]))
		EventBus.game_over.connect(func(w: Array) -> void: _event_all(["over", w]))
		_game.fx.burst_emitted.connect(func(pos: Vector2, kind: String, sound: String) -> void: _event_all(["fx", pos, kind, sound]))
		_game.wildlife.carcass_spawned.connect(func(n: ResourceNode, a: Unit) -> void:
			_event_all(["carcass", n.entity_id, a.entity_id, a.type_id, a.grid_pos, n.amount, a.facing]))
	else:
		_game.orders.remote_submit = _client_submit


func match_config() -> Dictionary:
	return _game.config


# --- Host -------------------------------------------------------------------------------------

func _remote_humans() -> Array:
	var out := []
	for i in Net.slots.size():
		var s: Dictionary = Net.slots[i]
		if not s["ai"] and s["connected"] and int(s["peer"]) > 1:
			out.append([i + 1, int(s["peer"])])
	return out


func _event(pid: int, ev: Array) -> void:
	if not _events.has(pid):
		_events[pid] = []
	_events[pid].append(ev)


func _event_all(ev: Array) -> void:
	for h in _remote_humans():
		_event(h[0], ev)


func _on_notify(pid: int, text: String) -> void:
	if pid == 0:
		_event_all(["notify", text])
	elif pid != _game.local_player:
		_event(pid, ["notify", text])


func apply_remote_order(pid: int, order: Dictionary) -> void:
	_game.orders.apply(pid, order)


## A human left mid-match: an AI keeps their civilisation going.
func player_dropped(pid: int) -> void:
	var p := _game.player(pid)
	if p == null or _ai_for.has(pid):
		return
	p.is_ai = true
	var ai := AIPlayer.new()
	ai.name = "AI_takeover_%d" % pid
	_game.systems.add_child(ai)
	ai.setup(_game, p, String(_game.config.get("difficulty", "normal")))
	_game.ai_players.append(ai)
	_ai_for[pid] = ai
	EventBus.notify.emit(0, Loc.msg("%s is now controlled by the AI", [p.name]))


func player_returned(pid: int) -> void:
	var ai: AIPlayer = _ai_for.get(pid)
	if ai != null and is_instance_valid(ai):
		_game.ai_players.erase(ai)
		ai.queue_free()
	_ai_for.erase(pid)
	returns += 1
	var p := _game.player(pid)
	if p != null:
		p.is_ai = false


func _process(delta: float) -> void:
	if Net.is_host():
		_timer -= delta
		if _timer <= 0.0:
			_timer = _interval
			for h in _remote_humans():
				var wire := encode_snapshot(build_snapshot(h[0]))
				Net.send_snapshot(h[1], wire)
				if _events.has(h[0]) and not _events[h[0]].is_empty():
					Net.send_events(h[1], _events[h[0]])
					_events[h[0]] = []
	elif Net.is_client():
		_interpolate(delta)


## Packs a snapshot for the wire: zstd keeps it small enough for the relay,
## where every byte goes through TCP and a backlog shows up as lag.
func encode_snapshot(snap: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(snap)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	last_snapshot_size = [raw.size(), out.size()]
	return out


## Unpacks encode_snapshot(); an empty dictionary when the packet is malformed.
static func decode_snapshot(data: PackedByteArray) -> Dictionary:
	if data.size() < 4:
		return {}
	var size := data.decode_u32(0)
	if size == 0 or size > MAX_SNAPSHOT:
		return {}
	var raw := data.slice(4).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size:
		return {}
	var snap: Variant = bytes_to_var(raw)
	return snap if snap is Dictionary else {}


## Everything player `pid` may know about the match right now.
func build_snapshot(pid: int) -> Dictionary:
	var fog := _game.fog
	var pl := []
	for p in _game.players:
		pl.append([p.id, p.resources, p.age, p.researched.keys(), p.defeated])
	var units := []
	var gathered := {}
	for u in _game.unit_system.units:
		if u.dead:
			continue
		var mine := u.owner_id == pid
		if not mine and (u.aboard != null or not fog.is_visible(pid, u)):
			continue
		var task := ""
		if not u.task.is_empty():
			task = "%s:%s" % [u.task.get("type", ""), u.task.get("kind", "")]
			var node: Variant = u.task.get("node")
			if is_instance_valid(node) and node is ResourceNode:
				gathered[node.entity_id] = node
		units.append([u.entity_id, _unit_types.find(u.type_id), u.owner_id, u.grid_pos.x, u.grid_pos.y, u.hp, u.max_hp,
			u._anim, u.facing, u.carry_type, u.carry_amount, 1 if u.aboard != null else 0, u.ammo,
			1 if u.state == Unit.State.MOVING else 0, task])
	var blds := []
	for b in _game.buildings.buildings:
		if b.dead:
			continue
		if b.owner_id != pid and not fog.is_explored(pid, Iso.tile_of(b.grid_pos)):
			continue
		var rp: Vector2 = b.rally_point if b.owner_id == pid else Vector2.INF
		blds.append([b.entity_id, _bld_types.find(b.type_id), b.owner_id, b.origin.x, b.origin.y, b.progress,
			b.hp, b.max_hp, b.queue if b.owner_id == pid else [], b.production_time, b.amount, rp])
	var res := []
	for id in gathered:
		res.append([id, gathered[id].amount])
	var proj := []
	for pr in _game.combat.projectiles:
		if fog.is_tile_visible(pid, Iso.tile_of(pr["pos"])):
			proj.append([pr["kind"], pr["screen"].x, pr["screen"].y, pr["screen_dir"].x, pr["screen_dir"].y])
	return {"t": _game.victory.elapsed, "pl": pl, "u": units, "b": blds, "r": res, "pr": proj, "mp": _game.market.prices}


# --- Client -----------------------------------------------------------------------------------

func _client_submit(order: Dictionary) -> void:
	Net.send_order(order)
	# Immediate feedback: units turn towards a ground order right away.
	if order.get("t", "") == "issue" and int(order.get("target", 0)) == 0:
		for id in order.get("units", []):
			var u: Unit = _game.entity(int(id)) as Unit
			if u != null and not u.dead:
				var d: Vector2 = order["grid"] - u.grid_pos
				if d.length_squared() > 0.01:
					u.face(Iso.direction_index(d))
					u.play("walk")


func receive_snapshot(data: PackedByteArray) -> void:
	var snap := decode_snapshot(data)
	if not snap.is_empty():
		apply_snapshot(snap)


## Brings the replica in line with a host snapshot.
func apply_snapshot(snap: Dictionary) -> void:
	_game.victory.elapsed = float(snap.get("t", 0.0))
	for row in snap.get("pl", []):
		_apply_player(row)
	var seen := {}
	for row in snap.get("u", []):
		seen[int(row[0])] = true
		_apply_unit(row)
	var now := Time.get_ticks_msec()
	for u in _game.unit_system.units.duplicate():
		if seen.has(u.entity_id) or u.dead:
			_vanish.erase(u.entity_id)
			continue
		if not _vanish.has(u.entity_id):
			_vanish[u.entity_id] = now
		elif now - int(_vanish[u.entity_id]) > VANISH_GRACE_MS:
			# Out of sight (or gone without a death event): the replica forgets it.
			_vanish.erase(u.entity_id)
			_game.unit_system.unregister(u)
			_interp.erase(u.entity_id)
			u.queue_free()
	var seen_b := {}
	for row in snap.get("b", []):
		seen_b[int(row[0])] = true
		_apply_building(row)
	for row in snap.get("r", []):
		var n: Entity = _game.entity(int(row[0]))
		if n is ResourceNode:
			n.amount = float(row[1])
			n.hp = ceili(n.amount)
	var proj := []
	for row in snap.get("pr", []):
		proj.append({"kind": row[0], "screen": Vector2(row[1], row[2]), "screen_dir": Vector2(row[3], row[4])})
	_game.fx.projectiles = proj
	_game.fx.queue_redraw()
	var mp: Dictionary = snap.get("mp", {})
	if mp != _last_prices:
		_last_prices = mp.duplicate()
		_game.market.prices = mp.duplicate()


func _apply_player(row: Array) -> void:
	var p := _game.player(int(row[0]))
	if p == null:
		return
	var res: Dictionary = row[1]
	if res != p.resources:
		p.resources = res.duplicate()
		EventBus.resources_changed.emit(p.id, p.resources)
	if int(row[2]) != p.age:
		p.age = int(row[2])
		EventBus.age_changed.emit(p.id, p.age)
	for t in row[3]:
		if not p.researched.has(t):
			p.researched[t] = true
			EventBus.tech_researched.emit(p.id, t)
	p.defeated = bool(row[4])


func _apply_unit(row: Array) -> void:
	var id := int(row[0])
	var u: Unit = _game.entity(id) as Unit
	var pos := Vector2(row[3], row[4])
	if u == null or u.dead:
		u = _game.spawn_replica_unit(id, _unit_types[int(row[1])], int(row[2]), pos)
		if u == null:
			return
		if u.owner_id == _game.local_player and _game.victory.elapsed > 2.0:
			EventBus.unit_trained.emit(u)
	if u.owner_id != int(row[2]):
		u.change_owner(int(row[2]), _game.color_slot_of(int(row[2])))
	u.hp = int(row[5])
	u.max_hp = int(row[6])
	var anim: String = row[7]
	if anim != u._anim:
		if anim == "attack":
			u.play_once("attack")
		else:
			u.play(anim)
	u.face(int(row[8]))
	if u.carry_amount >= 1.0 and float(row[10]) < 1.0 and u.carry_type != "":
		EventBus.sound_at.emit(String(GameData.audio.get("drop_sounds", {}).get(u.carry_type, "")), u.position)
	u.carry_type = row[9]
	u.carry_amount = float(row[10])
	var aboard := int(row[11]) == 1
	u.visible = not aboard and (u.owner_id == _game.local_player or _game.fog.is_visible(_game.local_player, u))
	u.selectable = not aboard
	u.aboard = u if aboard else null  # any non-null marks "riding"; own fog skips it
	u.ammo = int(row[12])
	u.state = Unit.State.MOVING if int(row[13]) == 1 else Unit.State.IDLE
	var task: String = row[14]
	u.task = {} if task == "" else {"type": task.get_slice(":", 0), "kind": task.get_slice(":", 1)}
	var it: Dictionary = _interp.get(id, {})
	if it.is_empty() or u.grid_pos.distance_to(pos) > 3.0:
		u.set_grid_pos(pos)
		_interp[id] = {"from": pos, "to": pos, "t": 1.0}
	else:
		_interp[id] = {"from": u.grid_pos, "to": pos, "t": 0.0}


func _apply_building(row: Array) -> void:
	var id := int(row[0])
	var b: Building = _game.entity(id) as Building
	if b == null or b.dead:
		b = _game.buildings.place(_bld_types[int(row[1])], int(row[2]), Vector2i(int(row[3]), int(row[4])), float(row[5]) >= 1.0, id)
	var progress := float(row[5])
	if not b.is_complete():
		if progress >= 1.0:
			b.add_progress(1.0)
		elif progress > b.progress:
			b.add_progress(progress - b.progress)
	b.hp = int(row[6])
	b.max_hp = int(row[7])
	var q: Array[String] = []
	for item in row[8]:
		q.append(String(item))
	if q != b.queue:
		b.queue = q
		EventBus.production_changed.emit(b)
	b.production_time = float(row[9])
	b.amount = float(row[10])
	if b.owner_id == _game.local_player:
		b.rally_point = row[11]


func receive_events(events: Array) -> void:
	for ev in events:
		match String(ev[0]):
			"kill":
				var e: Entity = _game.entity(int(ev[1]))
				# The (unreliable) snapshot may already have dropped it this frame.
				if e == null or e.is_queued_for_deletion():
					continue
				if e is Unit and not e.dead:
					_interp.erase(e.entity_id)
					# Mark it dead first: later snapshots must not free the corpse.
					e.hp = 0
					e.dead = true
					_game.kill_unit(e)
				elif e is Building and not e.dead:
					e.dead = true
					_game.fx.burst(e.position + Vector2(0, -20), "debris")
					_game.buildings.destroy(e)
			"remove":
				var b: Entity = _game.entity(int(ev[1]))
				if b is Building and not b.dead and not b.is_queued_for_deletion():
					_game.buildings.remove(b)
			"deplete":
				var n: Entity = _game.entity(int(ev[1]))
				if is_instance_valid(n) and n is ResourceNode:
					n.amount = 0.0
					n.depleted.emit(n)
			"carcass":
				var animal: Unit = _game.entity(int(ev[2])) as Unit
				var temp := false
				if animal == null:
					# The animal died out of this player's sight: build a stand-in for its sprite.
					animal = Unit.new()
					animal.setup(String(ev[3]), GameData.unit(String(ev[3])), Entity.GAIA, 0, ev[4])
					animal.facing = int(ev[6])
					temp = true
				if _game.entity(int(ev[1])) == null:
					_game.spawn_carcass(animal, float(ev[5]), int(ev[1]))
				if temp:
					animal.free()
			"notify":
				EventBus.notify.emit(_game.local_player, String(ev[1]))
			"ping":
				EventBus.under_attack.emit(_game.local_player, ev[1])
			"fx":
				_game.fx.burst(ev[1], String(ev[2]), String(ev[3]) if ev.size() > 3 else "")
			"over":
				var w: Array[int] = []
				for x in ev[1]:
					w.append(int(x))
				_game.victory.over = true
				_game.victory.winners = w
				EventBus.game_over.emit(w)


## Smooth movement between snapshots.
func _interpolate(delta: float) -> void:
	for id in _interp.keys():
		var it: Dictionary = _interp[id]
		var u: Unit = _game.entity(id) as Unit
		if u == null or u.dead:
			_interp.erase(id)
			continue
		if float(it["t"]) >= 1.0:
			u.velocity = Vector2.ZERO
			continue
		it["t"] = minf(1.0, float(it["t"]) + delta / _interval)
		var p: Vector2 = it["from"].lerp(it["to"], it["t"])
		u.velocity = (it["to"] - it["from"]) / _interval
		u.set_grid_pos(p)

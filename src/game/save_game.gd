class_name SaveGame
extends RefCounted
## Saving and loading a single-player match (Phase 4).
##
## A save holds the match config (with its resolved seed, so the map
## regenerates identically) plus every dynamic thing on top of it: players,
## remaining resource nodes and carcasses, stumps, buildings, units with
## their orders, fog exploration, market prices and trade routes, AI
## progress, Gaia animal dens, victory clocks and the camera.
## Entity references inside orders are stored as {"_ref": entity_id} and
## re-linked after every entity exists again.
## Files: user://saves/<slot>.sav (store_var of the whole dictionary) and
## <slot>.json (small header for the load list).
## Example:
##   SaveGame.write("slot_1", SaveGame.capture(game), "My village")
##   var data := SaveGame.read("slot_1")   # then Main.start_game({"save": data})

const VERSION := 1
const DIR := "user://saves/"


# --- Files ------------------------------------------------------------------------------

## Writes a save to `slot`. Returns OK or an Error.
static func write(slot: String, data: Dictionary, title: String = "") -> int:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + slot + ".sav", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(data)
	f.close()
	var meta := header(data)
	meta["title"] = title if title != "" else String(meta.get("title", slot))
	meta["slot"] = slot
	var h := FileAccess.open(DIR + slot + ".json", FileAccess.WRITE)
	if h != null:
		h.store_string(JSON.stringify(meta))
		h.close()
	return OK


## Reads a save ({} when missing, unreadable or from a newer version).
static func read(slot: String) -> Dictionary:
	var path := DIR + slot + ".sav"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = f.get_var()
	f.close()
	if not data is Dictionary or int(data.get("version", 0)) > VERSION or int(data.get("version", 0)) < 1:
		return {}
	return data


## Headers of every save, newest first.
static func list() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
			if meta is Dictionary and FileAccess.file_exists(DIR + f.get_basename() + ".sav"):
				out.append(meta)
	out.sort_custom(func(a, b): return int(a.get("time", 0)) > int(b.get("time", 0)))
	return out


static func delete(slot: String) -> void:
	for ext in [".sav", ".json"]:
		if FileAccess.file_exists(DIR + slot + ext):
			DirAccess.remove_absolute(DIR + slot + ext)


## Summary shown in the load list.
static func header(data: Dictionary) -> Dictionary:
	var names := []
	for p in data.get("players", []):
		names.append(String(p.get("name", "?")))
	var cfg: Dictionary = data.get("config", {})
	return {"time": int(data.get("saved_at", 0)), "elapsed": float(data.get("elapsed", 0.0)),
		"players": names, "map_type": cfg.get("map_type", ""), "size": cfg.get("size", ""),
		"age": int(data.get("players", [{}])[0].get("age", 0)) if not data.get("players", []).is_empty() else 0}


# --- Capture ------------------------------------------------------------------------------

## Everything needed to rebuild `game` as it is now.
static func capture(game: Game) -> Dictionary:
	var cfg := game.config.duplicate(true)
	cfg.erase("save")
	if game.tutorial != null:
		cfg["tutorial_step"] = game.tutorial.index
	var players := []
	for p in game.players:
		players.append({"name": p.name, "color_slot": p.color_slot, "is_ai": p.is_ai, "team": p.team, "age": p.age,
			"resources": p.resources.duplicate(), "modifiers": p.modifiers.duplicate(), "researched": p.researched.duplicate(),
			"defeated": p.defeated, "stats": p.stats.duplicate(true)})
	var nodes := []
	var carcasses := []
	var buildings := []
	var units := []
	for id in game._entities:
		var e: Entity = game.entity(id)
		if e == null or e.dead or e.is_queued_for_deletion():
			continue
		if e is ResourceNode:
			var n: ResourceNode = e
			if n.def.get("carcass", false):
				carcasses.append({"id": n.entity_id, "animal": n.type_id.trim_prefix("carcass_"), "pos": n.grid_pos, "amount": n.amount, "facing": n.carcass_facing})
			else:
				nodes.append({"id": n.entity_id, "type": n.type_id, "tile": n.tile(), "variant": n.variant, "amount": n.amount})
		elif e is Building:
			var b: Building = e
			buildings.append({"id": b.entity_id, "type": b.type_id, "owner": b.owner_id, "origin": b.origin, "progress": b.progress,
				"hp": b.hp, "queue": Array(b.queue), "production_time": b.production_time, "rally_point": b.rally_point,
				"rally_target": _ref(b.rally_target), "amount": b.amount, "attack_timer": b.attack_timer})
		elif e is Unit:
			var u: Unit = e
			units.append({"id": u.entity_id, "type": u.type_id, "owner": u.owner_id, "pos": u.grid_pos, "hp": u.hp,
				"facing": u.facing, "stance": u.stance, "carry_type": u.carry_type, "carry_amount": u.carry_amount,
				"task": _refs(u.task), "target": _ref(u.target), "guard_pos": u.guard_pos, "attack_move_goal": u.attack_move_goal,
				"ammo": u.ammo, "aboard": _ref(u.aboard), "dest": u.final_destination() if u.state == Unit.State.MOVING else Vector2.INF,
				"attack_timer": u.attack_timer})
	var fog := {}
	for p2 in game.players:
		fog[p2.id] = game.fog.explored_grid(p2.id).duplicate()
	var ai := {}
	for a in game.ai_players:
		ai[a.player.id] = {"elapsed": a.elapsed, "last_wave_time": a.last_wave_time, "enemy_targets": Array(a.enemy_targets), "difficulty": a.difficulty}
	return {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"config": cfg,
		"next_id": game._next_id,
		"local_player": game.local_player,
		"players": players,
		"nodes": nodes,
		"carcasses": carcasses,
		"stumps": game.stumps.duplicate(),
		"buildings": buildings,
		"units": units,
		"fog": fog,
		"market": {"prices": game.market.prices.duplicate(), "routes": _refs(game.market.routes())},
		"formations": game.commands.formations.duplicate(),
		"ai": ai,
		"wildlife_home": game.wildlife.homes(),
		"elapsed": game.victory.elapsed,
		"wonder_time": game.victory.wonder_time.duplicate(),
		"camera": {"pos": game.camera.position, "zoom": game.camera.zoom_index},
		"day_night": game.day_night.time if game.get("day_night") != null else 0.0,
	}


static func _ref(e: Variant) -> Variant:
	# Validity first: `is` on a freed instance is a script error.
	if is_instance_valid(e) and e is Entity:
		return {"_ref": (e as Entity).entity_id}
	return null


## Deep copy with every Entity replaced by {"_ref": id}.
static func _refs(v: Variant) -> Variant:
	if v is Entity:
		return _ref(v) if is_instance_valid(v) else null
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _refs(v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_refs(x))
		return a
	return v


## Inverse of _refs: {"_ref": id} -> the live entity (or null).
static func resolve(game: Game, v: Variant) -> Variant:
	if v is Dictionary:
		if v.size() == 1 and v.has("_ref"):
			return game.entity(int(v["_ref"]))
		var d := {}
		for k in v:
			d[k] = resolve(game, v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(resolve(game, x))
		return a
	return v


# --- Restore ------------------------------------------------------------------------------

## Players of a save as PlayerState objects (Game.start uses them instead of the config's).
static func make_players(data: Dictionary) -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	var list: Array = data.get("players", [])
	for i in list.size():
		var d: Dictionary = list[i]
		var p := PlayerState.new(i + 1, String(d["name"]), int(d["color_slot"]), bool(d["is_ai"]), d["resources"])
		p.team = int(d.get("team", 0))
		p.age = int(d.get("age", 0))
		p.modifiers = d.get("modifiers", {}).duplicate()
		p.researched = d.get("researched", {}).duplicate()
		p.defeated = bool(d.get("defeated", false))
		p.stats = d.get("stats", p.stats).duplicate(true)
		out.append(p)
	return out


## Rebuilds the entities of a save inside a freshly generated `game` (same map).
static func restore_world(game: Game, data: Dictionary) -> void:
	# Resource tiles that were cut or mined out become free ground again.
	var kept := {}
	for n in data.get("nodes", []):
		kept[n["tile"]] = n
	for s in game.map.resource_spawns:
		if not kept.has(s["tile"]):
			game.map.set_blocked(s["tile"], false)
			game.refresh_nav(s["tile"])
	for n2 in data.get("nodes", []):
		game.spawn_resource_node(String(n2["type"]), n2["tile"], int(n2.get("variant", 0)), float(n2["amount"]), int(n2["id"]))
	for st in data.get("stumps", []):
		game.add_stump(st)
	for b in data.get("buildings", []):
		var done := float(b["progress"]) >= 1.0
		var bl := game.buildings.place(String(b["type"]), int(b["owner"]), b["origin"], done, int(b["id"]))
		if bl == null:
			continue
		if not done and float(b["progress"]) > 0.0:
			bl.add_progress(float(b["progress"]))
		bl.hp = int(b["hp"])
		bl.update_fires()
		var q: Array[String] = []
		for item in b.get("queue", []):
			q.append(String(item))
		bl.queue = q
		bl.production_time = float(b.get("production_time", 0.0))
		bl.rally_point = b.get("rally_point", Vector2.INF)
		bl.amount = float(b.get("amount", bl.amount))
		bl.attack_timer = float(b.get("attack_timer", 0.0))
		bl.damaged.emit(bl, null, 0)  # refresh flames for damaged buildings
	for c in data.get("carcasses", []):
		var stand_in := Unit.new()
		stand_in.setup(String(c["animal"]), GameData.unit(String(c["animal"])), Entity.GAIA, 0, c["pos"])
		stand_in.facing = int(c.get("facing", 0))
		game.spawn_carcass(stand_in, float(c["amount"]), int(c["id"]))
		stand_in.free()
	for u in data.get("units", []):
		var unit := game.spawn_unit(String(u["type"]), int(u["owner"]), u["pos"], int(u["id"]))
		if unit == null:
			continue
		unit.set_grid_pos(u["pos"])
		unit.hp = mini(int(u["hp"]), unit.max_hp)
		unit.facing = int(u["facing"])
		unit.facing_target = unit.facing
		unit.stance = String(u.get("stance", "aggressive"))
		unit.carry_type = String(u.get("carry_type", ""))
		unit.carry_amount = float(u.get("carry_amount", 0.0))
		unit.guard_pos = u.get("guard_pos", Vector2.INF)
		unit.attack_move_goal = u.get("attack_move_goal", Vector2.INF)
		unit.ammo = int(u.get("ammo", unit.ammo))
		unit.attack_timer = float(u.get("attack_timer", 0.0))
	# Second pass: orders and links between entities.
	for u2 in data.get("units", []):
		var unit2: Unit = game.entity(int(u2["id"])) as Unit
		if unit2 == null:
			continue
		unit2.task = resolve(game, u2.get("task", {}))
		if unit2.task.has("type") and unit2.task.get("type") == "hunt" and unit2.task.get("animal") == null:
			unit2.task = {}
		unit2.target = resolve(game, u2.get("target"))
		var ship: Unit = resolve(game, u2.get("aboard")) as Unit
		if ship != null:
			unit2.aboard = ship
			unit2.visible = false
			unit2.selectable = false
			ship.cargo.append(unit2)
		var dest: Vector2 = u2.get("dest", Vector2.INF)
		if dest != Vector2.INF and ship == null:
			game.unit_system.request_path(unit2, dest)
	for b2 in data.get("buildings", []):
		var bl2: Building = game.entity(int(b2["id"])) as Building
		if bl2 != null:
			bl2.rally_target = resolve(game, b2.get("rally_target"))
	game.market.prices = data.get("market", {}).get("prices", game.market.prices).duplicate()
	game.market.restore_routes(resolve(game, data.get("market", {}).get("routes", {})))
	game.commands.formations = data.get("formations", {}).duplicate()
	game.wildlife.restore_homes(data.get("wildlife_home", {}))
	game.victory.elapsed = float(data.get("elapsed", 0.0))
	game.victory.wonder_time = data.get("wonder_time", {}).duplicate()
	for pid in data.get("fog", {}):
		game.fog.set_explored(int(pid), data["fog"][pid])


## Applies the saved AI progress to the freshly created AI players.
static func restore_ai(game: Game, data: Dictionary) -> void:
	var saved: Dictionary = data.get("ai", {})
	for a in game.ai_players:
		var s: Dictionary = saved.get(a.player.id, {})
		if s.is_empty():
			continue
		a.elapsed = float(s.get("elapsed", 0.0))
		a.last_wave_time = float(s.get("last_wave_time", -INF))
		var targets: Array[Vector2] = []
		for t in s.get("enemy_targets", []):
			targets.append(t)
		a.enemy_targets = targets

class_name BuildingSystem
extends Node
## Owns all buildings: placement validation and payment, footprint blocking,
## construction progress and population capacity (design/game-brief.md MVP 3).
## Data: buildings_stats.json, economy_settings.json.

signal building_completed(building: Building)

var buildings: Array[Building] = []

var _game: Game
var _econ: Dictionary
## Population limit of the match (economy_settings.json max_population unless the setup changes it).
var max_population := 200


func setup(game: Game, economy_cfg: Dictionary) -> void:
	_game = game
	_econ = economy_cfg
	max_population = int(economy_cfg.get("max_population", 200))


## Effective build-speed multiplier for `n` simultaneous builders.
## "aoe": (n + 2) / 3 → 1 builder = 1x, 4 builders = 2x (diminishing returns).
static func builder_multiplier(n: int, formula: String = "aoe") -> float:
	if n <= 0:
		return 0.0
	if formula == "linear":
		return float(n)
	return (n + 2.0) / 3.0


## Why a building can't be placed at `origin` ("" when it can).
## "placement": "shore" buildings (docks) stand on water touching land.
func placement_error(type_id: String, origin: Vector2i) -> String:
	var def := GameData.building(type_id)
	if def.is_empty():
		return "Unknown building"
	var s: int = def["size"]
	if def.get("placement", "") == "shore":
		return _shore_error(origin, s)
	for y in range(origin.y, origin.y + s):
		for x in range(origin.x, origin.x + s):
			var t := Vector2i(x, y)
			if not _game.map.in_bounds(t):
				return "Outside the map"
			if not MapData.terrain_passable(_game.map.get_terrain(t)):
				return "Cannot build on water or mountains"
			if _game.map.is_blocked(t) or _game.map.occupied[_game.map.index(t)] != 0:
				return "Something is in the way"
	return ""


func _shore_error(origin: Vector2i, s: int) -> String:
	var rect := Rect2i(origin, Vector2i(s, s))
	for y in range(origin.y, origin.y + s):
		for x in range(origin.x, origin.x + s):
			var t := Vector2i(x, y)
			if not _game.map.in_bounds(t):
				return "Outside the map"
			if not MapData.terrain_navigable(_game.map.get_terrain(t)) or _game.map.is_blocked(t) or _game.map.occupied[_game.map.index(t)] != 0:
				return "Docks must be built on open water by the shore"
	var land := false
	var water := false
	var ring := rect.grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var t2 := Vector2i(x, y)
			if rect.has_point(t2):
				continue
			if _game.map.walkable(t2):
				land = true
			elif _game.map.navigable(t2):
				water = true
	if not land:
		return "Docks must touch the shore"
	if not water:
		return "Docks need open water for ships"
	return ""


## Why `player` can't start this building ("" when they can).
func requirement_error(player: PlayerState, type_id: String) -> String:
	var def := GameData.building(type_id)
	if player.age < int(def.get("age", 0)):
		return Loc.msg("Requires %s", [Hud.AGE_NAMES[int(def.get("age", 0))]])
	if not player.can_afford(def.get("cost", {})):
		return "Not enough resources"
	return ""


## Pays for and places a foundation; assigned `builders` start building it.
## Returns null (and emits a notification) on failure.
func try_place(player: PlayerState, type_id: String, origin: Vector2i, builders: Array[Unit]) -> Building:
	var err := requirement_error(player, type_id)
	if err == "":
		err = placement_error(type_id, origin)
	if err != "":
		EventBus.notify.emit(player.id, err)
		return null
	player.spend(GameData.building(type_id).get("cost", {}))
	var b := place(type_id, player.id, origin, false)
	if not builders.is_empty():
		_game.economy.order_build(builders, b)
	return b


## Creates a building without any checks or payment (map setup, loading).
## `id` > 0 reuses the host's entity id (multiplayer replicas).
func place(type_id: String, player_id: int, origin: Vector2i, complete: bool, id: int = 0) -> Building:
	var b := Building.new()
	b.entity_id = id if id > 0 else _game.alloc_id()
	b.setup(type_id, GameData.building(type_id), player_id, _game.player(player_id).color_slot, origin, complete)
	_game.register_entity(b)
	_game.entities_root.add_child(b)
	buildings.append(b)
	b.completed.connect(_on_completed)
	# Gates are open tiles for the shared grid; Pathfinder closes them to other players.
	var gate: bool = b.def.get("gate", false)
	var walkable: bool = b.def.get("walkable", false) or gate
	for y in range(origin.y, origin.y + b.size):
		for x in range(origin.x, origin.x + b.size):
			var t := Vector2i(x, y)
			if walkable:
				_game.map.occupied[_game.map.index(t)] = 1
				if gate:
					_game.pathfinder.set_gate(t, player_id)
			else:
				_game.map.set_blocked(t, true)
				_game.refresh_nav(t)
			_game.register_static(t, b)
	if not walkable:
		_evict_units(b)
	if b.def.get("wall", false):
		refresh_wall_links(b)
	if b.is_farm():
		b.depleted.connect(_on_farm_depleted)
	_game.combat.track(b)
	_game.techs.apply_building(b)
	EventBus.entity_spawned.emit(b)
	if complete:
		EventBus.population_changed.emit(player_id)
	return b


## Units standing on a new footprint step out to the nearest free tile.
func _evict_units(b: Building) -> void:
	var rect := b.footprint()
	for u in _game.unit_system.units:
		if rect.has_point(u.tile()):
			var spot := _game.nav(u).approach(rect, u.grid_pos)
			if spot != Vector2.INF:
				u.set_grid_pos(spot)
				if u.state == Unit.State.MOVING and not u.path.is_empty():
					_game.unit_system.request_path(u, u.final_destination())


## Applies this tick's builder work, then clears the per-tick counters.
func apply_construction(delta: float) -> void:
	var formula: String = _econ.get("builder_count_formula", "aoe")
	for b in buildings:
		if b.builders_this_tick > 0 and not b.is_complete():
			var bt := maxf(1.0, float(b.def.get("build_time", 30)))
			b.add_progress(delta / bt * builder_multiplier(b.builders_this_tick, formula) * _game.player(b.owner_id).modifier("build_speed"))
		b.builders_this_tick = 0


func _process(delta: float) -> void:
	for b in buildings:
		b.animate(delta)


## Auto-reseed (economy_settings.auto_reseed_farms): pay the farm cost again
## and refill it; otherwise the exhausted field disappears.
func _on_farm_depleted(b: Building) -> void:
	var p := _game.player(b.owner_id)
	var cost: Dictionary = b.def.get("cost", {})
	if _econ.get("auto_reseed_farms", true) and p.spend(cost):
		b.amount = _game.techs.farm_food(b.owner_id, b.def)
		return
	EventBus.notify.emit(b.owner_id, "A farm is exhausted")
	remove.call_deferred(b)


func _on_completed(b: Building) -> void:
	if b.is_farm():
		b.amount = _game.techs.farm_food(b.owner_id, b.def)
	_game.techs.apply_building(b)
	_game.player(b.owner_id).stats["buildings_built"] += 1
	EventBus.notify.emit(b.owner_id, Loc.msg("%s completed", [b.display_name()]))
	EventBus.population_changed.emit(b.owner_id)
	building_completed.emit(b)


## Wall pieces (walls and gates) show connecting arms towards same-owner
## neighbours; refreshes `b` (unless it is being removed) and the eight around it.
func refresh_wall_links(b: Building, removing: bool = false) -> void:
	var around: Array[Building] = []
	if not removing:
		around.append(b)
	for key in Building.WALL_ARMS:
		var n := wall_at(b.origin + Building.WALL_ARMS[key], b.owner_id)
		if n != null and n != b:
			around.append(n)
	var skip: Building = b if removing else null
	for w in around:
		var links := {}
		for key in Building.WALL_ARMS:
			links[key] = wall_links_to(w, Building.WALL_ARMS[key], skip)
		w.set_wall_links(links)


## True if `w` joins its neighbour at offset `d`. A diagonal neighbour only
## joins when neither shared orthogonal tile holds a wall (otherwise the corner
## is already closed through that piece). `ignore` is a piece being removed.
func wall_links_to(w: Building, d: Vector2i, ignore: Building = null) -> bool:
	var n := wall_at(w.origin + d, w.owner_id)
	if n == null or n == ignore:
		return false
	if d.x == 0 or d.y == 0:
		return true
	for side in [Vector2i(d.x, 0), Vector2i(0, d.y)]:
		var o := wall_at(w.origin + side, w.owner_id)
		if o != null and o != ignore:
			return false
	return true


## The wall piece of `owner` standing on tile `t`, or null.
func wall_at(t: Vector2i, owner: int) -> Building:
	var e: Variant = _game.static_entity_at(t)
	if e is Building and is_instance_valid(e) and not e.dead and e.owner_id == owner and e.def.get("wall", false):
		return e
	return null


## Population capacity from completed buildings, capped by max_population.
func population_cap(player_id: int) -> int:
	var cap := 0
	for b in buildings:
		if b.owner_id == player_id and b.is_complete():
			cap += int(b.def.get("population", 0))
	return mini(cap, max_population)


## Nearest completed building of `player_id` accepting `resource` (grid distance).
func nearest_drop_site(player_id: int, resource: String, from: Vector2, by_ship: bool = false) -> Building:
	var best: Building = null
	var best_d := INF
	for b in buildings:
		if b.owner_id == player_id and b.accepts(resource, by_ship):
			var d := from.distance_squared_to(b.closest_point(from))
			if d < best_d:
				best_d = d
				best = b
	return best


## Destroyed building: rubble decal fades out after rubble_seconds.
func destroy(b: Building) -> void:
	var n := clampi(b.size, 1, 4)
	var r := SpriteLibrary.prop("rubble_%d" % n)
	var sp := Sprite2D.new()
	sp.texture = SpriteLibrary.props_texture()
	sp.region_enabled = true
	sp.region_rect = r["rect"]
	sp.centered = false
	sp.offset = -r["anchor"]
	sp.position = b.position
	sp.z_index = -30
	_game.world.add_child(sp)
	var tw := sp.create_tween()
	tw.tween_interval(float(GameData.combat.get("rubble_seconds", 20.0)))
	tw.tween_property(sp, "modulate:a", 0.0, 2.0)
	tw.tween_callback(sp.queue_free)
	if b.owner_id == _game.local_player:
		EventBus.notify.emit(b.owner_id, Loc.msg("%s destroyed!", [b.display_name()]))
	remove(b)


func remove(b: Building) -> void:
	buildings.erase(b)
	for y in range(b.origin.y, b.origin.y + b.size):
		for x in range(b.origin.x, b.origin.x + b.size):
			var t := Vector2i(x, y)
			_game.map.set_blocked(t, false)
			_game.map.occupied[_game.map.index(t)] = 0
			_game.pathfinder.clear_gate(t)
			_game.refresh_nav(t)
			_game.unregister_static(t)
	EventBus.entity_removed.emit(b)
	EventBus.population_changed.emit(b.owner_id)
	if b.def.get("wall", false):
		refresh_wall_links(b, true)
	_game.selection.prune.call_deferred()
	b.queue_free()

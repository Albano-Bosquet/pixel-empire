class_name NavalSystem
extends Node
## Transport ships: boarding and unloading land units (naval phase).
## Data: units_stats.json ("transport_capacity" on transports), combat_settings.json "naval".
##
## Boarding (unit entity_id -> {"unit", "ship", "repath"}):
##   walk to the shore tile nearest the ship --(within board_reach and room left)-->
##   aboard: hidden, unselectable, out of the simulation, listed in ship.cargo.
## Unloading (ship entity_id -> {"ship", "goal", "repath"}):
##   sail to the water tile nearest `goal` --(stopped within unload_reach of land)-->
##   every passenger steps onto the free land tiles around the ship.
## A sunk transport takes its passengers down with it.
## Example:
##   game.naval.order_board(selected_infantry, transport)
##   game.naval.order_unload(transport, enemy_shore_point)

var _game: Game
var _cfg: Dictionary
var _boarding: Dictionary = {}
var _unloading: Dictionary = {}


func setup(game: Game, naval_cfg: Dictionary) -> void:
	_game = game
	_cfg = naval_cfg
	EventBus.entity_killed.connect(_on_killed)


static func is_transport(u: Entity) -> bool:
	return u is Unit and int(u.def.get("transport_capacity", 0)) > 0


static func is_ship(u: Entity) -> bool:
	return u is Unit and bool(u.def.get("naval", false))


## Population slots still free on `ship`.
func room_left(ship: Unit) -> int:
	var pending := 0
	for id in _boarding:
		if _boarding[id]["ship"] == ship:
			pending += 1
	return int(ship.def.get("transport_capacity", 0)) - ship.cargo.size() - pending


func order_board(units: Array[Unit], ship: Unit) -> void:
	if not is_transport(ship) or not ship.is_alive():
		return
	for u in units:
		if is_ship(u) or u.aboard != null or not u.is_alive() or u.owner_id != ship.owner_id:
			continue
		if room_left(ship) <= 0:
			EventBus.notify.emit(u.owner_id, "The transport is full")
			break
		_game.economy.clear_task(u)
		u.target = null
		_boarding[u.entity_id] = {"unit": u, "ship": ship, "repath": 0.0}
	_meet(ship, units)


## Sends an idle transport to the water closest to the units boarding it.
func _meet(ship: Unit, units: Array[Unit]) -> void:
	if ship.state == Unit.State.MOVING or units.is_empty():
		return
	var c := Vector2.ZERO
	for u in units:
		c += u.grid_pos
	c /= units.size()
	var water := _game.naval_pathfinder.nearest_walkable(Iso.tile_of(c), 12, c)
	if water.x >= 0 and Iso.tile_center(water).distance_to(ship.grid_pos) > 1.0:
		_game.unit_system.request_path(ship, Iso.tile_center(water))


func order_unload(ship: Unit, goal: Vector2) -> void:
	if not is_transport(ship) or ship.cargo.is_empty():
		return
	_unloading[ship.entity_id] = {"ship": ship, "goal": goal, "repath": 0.0}


func cancel(u: Unit) -> void:
	_boarding.erase(u.entity_id)
	_unloading.erase(u.entity_id)


func is_unloading(ship: Unit) -> bool:
	return _unloading.has(ship.entity_id)


func _physics_process(delta: float) -> void:
	for id in _boarding.keys():
		var b: Dictionary = _boarding[id]
		var u: Unit = Iso.alive(b["unit"])
		var ship: Unit = Iso.alive(b["ship"])
		if u == null or u.dead or ship == null or ship.dead or u.aboard != null:
			_boarding.erase(id)
			continue
		if u.grid_pos.distance_to(ship.grid_pos) <= float(_cfg.get("board_reach", 1.9)):
			_boarding.erase(id)
			_board(u, ship)
			continue
		b["repath"] = float(b["repath"]) - delta
		if u.state == Unit.State.IDLE and b["repath"] <= 0.0:
			b["repath"] = 1.0
			var shore := _game.pathfinder.nearest_walkable(Iso.tile_of(ship.grid_pos), 5, u.grid_pos)
			if shore.x >= 0:
				_game.unit_system.request_path(u, Iso.tile_center(shore))
	for id in _unloading.keys():
		var r: Dictionary = _unloading[id]
		var ship2: Unit = Iso.alive(r["ship"])
		if ship2 == null or ship2.dead or ship2.cargo.is_empty():
			_unloading.erase(id)
			continue
		if ship2.state == Unit.State.MOVING:
			continue
		# Landing spot: the water closest to the goal, found once (goals are often inland).
		if not r.has("water"):
			var wt := landing_tile(r["goal"], int(_cfg.get("landing_search_radius", 40)))
			if wt.x < 0:
				_unloading.erase(id)
				EventBus.notify.emit(ship2.owner_id, "No shore to unload at")
				continue
			r["water"] = Iso.tile_center(wt)
			r["tries"] = 0
			_game.unit_system.request_path(ship2, r["water"])
			continue
		var arrived: bool = ship2.grid_pos.distance_to(r["water"]) <= float(_cfg.get("landing_arrive_radius", 1.5)) or ship2.grid_pos.distance_to(r["goal"]) <= float(_cfg.get("unload_goal_slack", 6.0))
		if arrived or int(r["tries"]) >= 3:
			_unloading.erase(id)
			if _land_near(ship2.grid_pos).x >= 0:
				unload_now(ship2)
			else:
				EventBus.notify.emit(ship2.owner_id, "No shore to unload at")
			continue
		r["repath"] = float(r["repath"]) - delta
		if r["repath"] <= 0.0:
			# Stopped short (crowded water): try again a few times, then land where it is.
			r["repath"] = 1.0
			r["tries"] = int(r["tries"]) + 1
			_game.unit_system.request_path(ship2, r["water"])


## Nearest water tile to `goal` that touches walkable land (a beach to land on),
## searched in square rings up to `radius`; (-1, -1) if none.
func landing_tile(goal: Vector2, radius: int) -> Vector2i:
	var c := Iso.tile_of(goal)
	for r in range(0, radius + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var t := c + Vector2i(dx, dy)
				if not _game.naval_pathfinder.is_walkable(t) or not _touches_land(t):
					continue
				var d := Vector2(dx, dy).length_squared()
				if d < best_d:
					best_d = d
					best = t
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _touches_land(t: Vector2i) -> bool:
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _game.pathfinder.is_walkable(t + o):
			return true
	return false


## A free land tile within unload_reach of `p`, or (-1, -1).
func _land_near(p: Vector2) -> Vector2i:
	var reach := float(_cfg.get("unload_reach", 1.9))
	var t := _game.pathfinder.nearest_walkable(Iso.tile_of(p), ceili(reach), p)
	if t.x >= 0 and Iso.tile_center(t).distance_to(p) <= reach + 0.75:
		return t
	return Vector2i(-1, -1)


func _board(u: Unit, ship: Unit) -> void:
	u.stop()
	u.target = null
	u.task = {}
	u.aboard = ship
	u.visible = false
	u.selectable = false
	u.selected = false
	ship.cargo.append(u)
	_game.selection.prune.call_deferred()
	EventBus.population_changed.emit(u.owner_id)


## Puts every passenger of `ship` on the land tiles around it.
func unload_now(ship: Unit) -> void:
	var used: Array[Vector2i] = []
	for u in ship.cargo:
		if not is_instance_valid(u):
			continue
		var spot := _free_land_spot(ship.grid_pos, used)
		if spot.x < 0:
			continue
		used.append(spot)
		u.aboard = null
		u.selectable = true
		u.visible = true
		u.set_grid_pos(Iso.tile_center(spot) + Vector2(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)))
		u.guard_pos = u.grid_pos
	ship.cargo = ship.cargo.filter(func(u): return is_instance_valid(u) and u.aboard != null)
	EventBus.population_changed.emit(ship.owner_id)


func _free_land_spot(around: Vector2, used: Array[Vector2i]) -> Vector2i:
	var c := Iso.tile_of(around)
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var t := c + Vector2i(dx, dy)
				if _game.pathfinder.is_walkable(t) and not used.has(t):
					return t
	return Vector2i(-1, -1)


func _on_killed(e: Entity, _attacker: Entity) -> void:
	if not (e is Unit):
		return
	_boarding.erase(e.entity_id)
	_unloading.erase(e.entity_id)
	for u in e.cargo:
		if is_instance_valid(u) and not u.dead:
			u.aboard = null
			u.set_grid_pos(e.grid_pos)
			u.take_damage(u.hp, null)
	e.cargo.clear()

class_name WildlifeSystem
extends Node
## Gaia animals (Phase 3; rules in Wildlife, data in wildlife_settings.json and
## units_stats.json "animal"/"food").
##
## Spawn: herdables, game and a boar near every start; wolf packs, deer herds,
##   tigers and bears out in the wild, scaled by the match's "animals" preset.
## Herding: a herdable belongs to whoever has a unit within claim_radius; the
##   current owner keeps it while one of their units is that close.
## Behaviour per animal (state lives here, keyed by entity id):
##   idle --(wander timer)--> walk to a random spot near home --> idle
##   deer damaged --> flee away from the attacker
##   boar damaged --> fights back (CombatSystem retaliation)
##   predators --> attack players' units in sight (CombatSystem auto-attack),
##                 leashed to their den by guard_pos
## Food: a killed herdable or game animal leaves a carcass (food ResourceNode);
##   villagers ordered to hunt it switch to gathering the carcass.
## AI players butcher the herdables they own with one food villager at a time.

## Emitted on the host for every carcass (the replicator mirrors it).
signal carcass_spawned(node: ResourceNode, animal: Unit)

var _game: Game
var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _ai_timer := 0.0
var _home: Dictionary = {}     # entity id -> Vector2 (grid)
var _wander: Dictionary = {}   # entity id -> seconds until next stroll
var _near: Array = []


func setup(game: Game, cfg: Dictionary) -> void:
	_game = game
	_cfg = cfg
	_rng.seed = game.map.seed * 7919 + 17
	EventBus.entity_killed.connect(_on_killed)


## Places the starting wildlife (host / single player only).
func spawn_initial(scale: float) -> void:
	if scale <= 0.0:
		return
	var spawn: Dictionary = _cfg.get("spawn", {})
	for start in _game.map.start_positions:
		for rule in spawn.get("near_start", []):
			var count := roundi(float(rule.get("count", 1)) * scale)
			_spawn_groups(String(rule["unit"]), count, int(rule.get("group", 1)), func() -> Vector2i:
				return _ring_tile(start, float(rule.get("min", 6)), float(rule.get("max", 10))))
	var side := float(_game.map.width) / 100.0
	for rule2 in spawn.get("wild_per_100_tiles_side", []):
		var count2 := roundi(float(rule2.get("count", 1.0)) * side * side * scale * maxf(1.0, _game.players.size() * 0.5))
		_spawn_groups(String(rule2["unit"]), count2, int(rule2.get("group", 1)), func() -> Vector2i:
			return _wild_tile(float(rule2.get("min_from_start", 16)), bool(rule2.get("near_forest", false))))


func _spawn_groups(unit_id: String, count: int, group: int, pick: Callable) -> void:
	var left := count
	while left > 0:
		var t: Vector2i = pick.call()
		if t.x < 0:
			return
		for i in mini(group, left):
			var at := Iso.tile_center(t) + Vector2(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-1.2, 1.2))
			var u := _game.spawn_unit(unit_id, Entity.GAIA, at)
			if u != null:
				_home[u.entity_id] = u.grid_pos
				_wander[u.entity_id] = _rng.randf_range(0.0, 6.0)
		left -= group


func _ring_tile(start: Vector2i, rmin: float, rmax: float) -> Vector2i:
	for tries in 40:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(rmin, rmax)
		var t := start + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
		if _game.pathfinder.is_walkable(t):
			return t
	return Vector2i(-1, -1)


func _wild_tile(min_from_start: float, near_forest: bool) -> Vector2i:
	var m := _game.map
	for tries in 80:
		var t := Vector2i(_rng.randi_range(3, m.width - 4), _rng.randi_range(3, m.height - 4))
		if not _game.pathfinder.is_walkable(t):
			continue
		if m.start_positions.any(func(s): return Vector2(s).distance_to(Vector2(t)) < min_from_start):
			continue
		if near_forest and not _forest_near(t):
			continue
		return t
	return Vector2i(-1, -1)


func _forest_near(t: Vector2i) -> bool:
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var n := t + Vector2i(dx, dy)
			if _game.map.in_bounds(n) and _game.map.get_terrain(n) == MapData.Terrain.FOREST:
				return true
	return false


## Home spots of the wild animals (saves).
func homes() -> Dictionary:
	return _home.duplicate()


func restore_homes(saved: Dictionary) -> void:
	for id in saved:
		_home[int(id)] = saved[id]


# --- Tick ---------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_timer -= delta
	var check := _timer <= 0.0
	if check:
		_timer = float(_cfg.get("check_interval", 0.5))
	for u in _game.unit_system.animals:
		if u.dead:
			continue
		if check and Wildlife.is_herdable(u):
			_claim(u)
		_tick_wander(u, delta)
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_timer = 5.0
		_ai_butcher()


## Herding: the nearest player's unit claims; the owner keeps it while close.
func _claim(animal: Unit) -> void:
	var radius := float(_cfg.get("claim_radius", 2.5))
	_near.clear()
	_game.unit_system.units_near(animal.grid_pos, radius, _near)
	var best: Unit = null
	var best_d := INF
	for o in _near:
		if o.dead or o.owner_id == Entity.GAIA or Wildlife.is_animal(o) or o.altitude > 0.0 or o.aboard != null:
			continue
		var d: float = o.grid_pos.distance_to(animal.grid_pos)
		if d > radius:
			continue
		if o.owner_id == animal.owner_id:
			return  # the owner is still close
		if d < best_d:
			best_d = d
			best = o
	if best != null and best.owner_id != animal.owner_id:
		var p := _game.player(best.owner_id)
		animal.change_owner(best.owner_id, p.color_slot if p != null else 0)
		_home[animal.entity_id] = animal.grid_pos
		if best.owner_id == _game.local_player:
			EventBus.sound_at.emit("herd_claim", animal.position)


func _tick_wander(u: Unit, delta: float) -> void:
	if u.state != Unit.State.IDLE or u.has_target():
		return
	# Owned herd animals stay where their owner leaves them.
	if Wildlife.is_herdable(u) and u.owner_id != Entity.GAIA:
		return
	var t := float(_wander.get(u.entity_id, 3.0)) - delta
	if t > 0.0:
		_wander[u.entity_id] = t
		return
	var span: Array = _cfg.get("wander_interval", [5.0, 14.0])
	_wander[u.entity_id] = _rng.randf_range(float(span[0]), float(span[1]))
	var r := float(_cfg.get("predator_wander_radius" if Wildlife.is_predator(u) else "wander_radius", 3.0))
	var home: Vector2 = _home.get(u.entity_id, u.grid_pos)
	var goal := home + Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r))
	if _game.pathfinder.is_walkable(Iso.tile_of(goal)):
		_game.unit_system.request_path(u, goal)
		if Wildlife.is_predator(u):
			u.guard_pos = goal


## Game that cannot fight back runs from whoever hurt it.
func on_damaged(e: Entity, attacker: Entity) -> void:
	if not (e is Unit) or e.dead or not Wildlife.is_animal(e) or attacker == null or not is_instance_valid(attacker):
		return
	var u: Unit = e
	if int(u.def.get("attack_damage", 0)) > 0:
		return
	var away := (u.grid_pos - attacker.grid_pos).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	var goal := u.grid_pos + away * float(_cfg.get("flee_distance", 4.5))
	var t := _game.pathfinder.nearest_walkable(Iso.tile_of(goal), 4, u.grid_pos)
	if t.x >= 0:
		_game.unit_system.request_path(u, Iso.tile_center(t))
		_wander[u.entity_id] = 4.0


# --- Hunting and carcasses ----------------------------------------------------------------------

## Villagers hunt an animal: they attack it, then gather its carcass.
func order_hunt(workers: Array[Unit], animal: Unit) -> void:
	_game.combat.order_attack(workers, animal)
	for w in workers:
		if w.target == animal:
			w.task = {"type": "hunt", "animal": animal, "kind": "food"}


## True while `u` was sent to slaughter `t` (lets villagers kill their own sheep).
static func is_hunting(u: Unit, t: Entity) -> bool:
	return u.task.get("type", "") == "hunt" and u.task.get("animal") == t


func _on_killed(e: Entity, _attacker: Entity) -> void:
	if not (e is Unit) or not Wildlife.is_animal(e) or int(e.def.get("food", 0)) <= 0:
		return
	var node := _game.spawn_carcass(e as Unit, float(e.def.get("food", 100)))
	if node == null:
		return
	carcass_spawned.emit(node, e)
	for u in _game.unit_system.units:
		if not u.dead and u.is_worker and is_hunting(u, e):
			u.target = null
			var one: Array[Unit] = [u]
			_game.economy.order_gather(one, node)


## AI players send one food villager to every herdable they own.
func _ai_butcher() -> void:
	for ai in _game.ai_players:
		var pid: int = ai.player.id
		var busy := false
		var flock: Array[Unit] = []
		for u in _game.unit_system.units:
			if u.dead or u.owner_id != pid:
				continue
			var node: Variant = u.task.get("node")
			if u.task.get("type", "") == "hunt" or (is_instance_valid(node) and node is ResourceNode and node.def.get("carcass", false)):
				busy = true
			if Wildlife.is_herdable(u):
				flock.append(u)
		if busy or flock.is_empty():
			continue
		var best: Unit = null
		for v in _game.unit_system.units:
			if v.owner_id == pid and v.is_worker and not v.dead and not NavalSystem.is_ship(v) and v.task.get("kind", "") == "food":
				if best == null or v.grid_pos.distance_to(flock[0].grid_pos) < best.grid_pos.distance_to(flock[0].grid_pos):
					best = v
		if best != null:
			var one: Array[Unit] = [best]
			order_hunt(one, flock[0])

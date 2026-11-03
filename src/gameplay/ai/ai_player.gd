class_name AIPlayer
extends Node
## Computer opponent (design/game-brief.md MVP item 6). Plays through the same
## systems and rules as the human (orders, costs, population, fog of war); the
## only advantage is the difficulty's gather_multiplier.
##
## Every think_interval it runs, in order:
##   economy  — idle villagers -> resource with the largest deficit vs resource_split
##   build    — houses before pop cap, mill/storehouses next to resources, farms when
##              forage runs out, military buildings by difficulty, towers on hard
##   train    — villagers up to villager_target, army from army_mix
##   age_up   — when villager thresholds and resources allow
##   scout    — explore unexplored waypoints; remember enemy buildings seen
##   naval    — a dock when there is shore nearby, fishing ships on fish, a small
##              war fleet that joins attack waves; when the enemy cannot be
##              reached by land (islands) the wave sails over in a transport:
##              boarding -> sailing (unload at the target) -> attack.
##   defend   — army attack-moves to enemies near own buildings; villagers flee
##   attack   — waves of army_attack_size from first_attack_minute on
## Data: ai_settings.json.

const ECO_RESOURCES: Array[String] = ["food", "wood", "gold", "stone"]

var player: PlayerState
var difficulty := "normal"
var diff: Dictionary
var elapsed := 0.0
var enemy_targets: Array[Vector2] = []
var wave: Array[Unit] = []
var last_wave_time := -INF
## Diagnostics: villagers moved between resources by _rebalance.
var rebalanced := 0

var _game: Game
var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _think := 0.0
var _scout_points: Array[Vector2] = []
var _villagers: Array[Unit] = []
var _army: Array[Unit] = []
var _scouts: Array[Unit] = []
var _fishers: Array[Unit] = []
var _fleet: Array[Unit] = []
var _transports: Array[Unit] = []
## Next time a dock site search may run (it is skipped when no shore is near).
var _dock_retry := 0.0
## -1 unknown, 0 enemy reachable on foot, 1 needs a transport.
var _needs_boat := -1
## Sea invasion in progress: {"phase": "boarding"|"sailing", "ship": Unit, "units": Array, "since": float}.
var _naval_op: Dictionary = {}
## Coastal scouting keeps its own waypoint list (the land scout drops the ones it cannot reach).
var _sea_points: Array[Vector2] = []
## scout entity_id -> [waypoint, position when ordered] (unreachable waypoint detection).
var _scout_last: Dictionary = {}
var _my_buildings: Array[Building] = []
var _threat := Vector2.INF


func setup(game: Game, p: PlayerState, level: String) -> void:
	_game = game
	player = p
	_rng.seed = game.map.seed * 31 + p.id
	difficulty = level if GameData.ai.get("difficulties", {}).has(level) else "normal"
	_cfg = GameData.ai
	diff = _cfg["difficulties"][difficulty]
	for r in ECO_RESOURCES:
		player.modifiers["gather_" + r] = float(diff.get("gather_multiplier", 1.0))
	var start := Vector2(game.map.start_positions[p.id - 1])
	for s in game.map.start_positions:
		if Vector2(s) != start:
			enemy_targets.append(Iso.tile_center(s))
	var w := float(game.map.width)
	for q in [Vector2(0.5, 0.5), Vector2(0.2, 0.2), Vector2(0.8, 0.2), Vector2(0.8, 0.8), Vector2(0.2, 0.8), Vector2(0.5, 0.15), Vector2(0.15, 0.5), Vector2(0.85, 0.5), Vector2(0.5, 0.85)]:
		_scout_points.append(q * w)
	_scout_points.sort_custom(func(a, b): return a.distance_to(start) < b.distance_to(start))
	_sea_points = _scout_points.duplicate()


func _physics_process(delta: float) -> void:
	elapsed += delta
	_think -= delta
	if _think > 0.0:
		return
	_think = float(_cfg.get("think_interval", 1.0))
	_refresh()
	if _villagers.is_empty() and _army.is_empty():
		return
	_economy()
	_build()
	_train()
	_age_up()
	_research()
	_scout()
	_naval()
	_defend()
	_attack()


# --- Bookkeeping ------------------------------------------------------------------

func _refresh() -> void:
	_villagers.clear()
	_army.clear()
	_scouts.clear()
	_fishers.clear()
	_fleet.clear()
	_transports.clear()
	for u in _game.unit_system.units:
		if u.owner_id != player.id or u.dead or u.aboard != null or u.def.has("animal"):
			continue
		if NavalSystem.is_ship(u):
			if u.is_worker:
				_fishers.append(u)
			elif NavalSystem.is_transport(u):
				_transports.append(u)
			else:
				_fleet.append(u)
		elif u.is_worker:
			_villagers.append(u)
		elif u.type_id == "scout":
			_scouts.append(u)
		else:
			_army.append(u)
	_my_buildings.clear()
	for b in _game.buildings.buildings:
		if b.owner_id == player.id and not b.dead:
			_my_buildings.append(b)
	wave = wave.filter(func(u): return is_instance_valid(u) and not u.dead)
	# Remember enemy buildings we have seen.
	for b in _game.buildings.buildings:
		if _is_foe(b.owner_id) and not b.dead and _game.fog.is_explored(player.id, Iso.tile_of(b.grid_pos)):
			if not enemy_targets.has(b.grid_pos):
				enemy_targets.push_front(b.grid_pos)
	enemy_targets = enemy_targets.filter(func(p): return _enemy_building_near(p) or not _game.fog.is_explored(player.id, Iso.tile_of(p)))


func _enemy_building_near(p: Vector2) -> bool:
	var e: Entity = _game.static_entity_at(Iso.tile_of(p))
	return e is Building and _is_foe(e.owner_id) and not e.dead


## Another player not allied with this AI (Gaia is nobody's target here).
func _is_foe(owner: int) -> bool:
	return owner != Entity.GAIA and not CombatSystem.are_allies(owner, player.id)


func _home() -> Vector2:
	var tc := _town_center()
	if tc:
		return tc.grid_pos
	return Iso.tile_center(_game.map.start_positions[player.id - 1])


func _town_center() -> Building:
	for b in _my_buildings:
		if b.type_id == "town_center" and b.is_complete():
			return b
	return null


func _count(type_id: String, include_unfinished: bool = true) -> int:
	var n := 0
	for b in _my_buildings:
		if b.type_id == type_id and (include_unfinished or b.is_complete()):
			n += 1
	return n


func _under_construction(type_id: String) -> bool:
	for b in _my_buildings:
		if b.type_id == type_id and not b.is_complete():
			return true
	return false


# --- Economy ------------------------------------------------------------------------

func _economy() -> void:
	var counts := {"food": 0, "wood": 0, "gold": 0, "stone": 0}
	var idle: Array[Unit] = []
	for v in _villagers:
		if v.task.is_empty():
			if v.state == Unit.State.IDLE:
				idle.append(v)
		elif v.task["type"] == "gather":
			counts[v.task["kind"]] = counts.get(v.task["kind"], 0) + 1
	var split: Dictionary = _cfg.get("resource_split", {})
	var farms_building := 0
	for b in _my_buildings:
		if b.is_farm() and not b.is_complete():
			farms_building += 1
	for v in idle:
		# Food is the bottleneck once forage runs out: build farms for it.
		var food_need: float = float(split.get("food", 0.45)) * _villagers.size() - counts["food"]
		if food_need > 0.0 and _source_for("food", v) == null:
			if farms_building < 3 and player.can_afford(GameData.building("farm")["cost"]):
				_build_farm(v)
				farms_building += 1
				counts["food"] += 1
				continue
		var best_kind := ""
		var best_need := -INF
		var needs := _needs(counts)
		for r in ECO_RESOURCES:
			var need: float = needs[r]
			if need > best_need and _source_for(r, v) != null:
				best_need = need
				best_kind = r
		if best_kind == "":
			if player.can_afford(GameData.building("farm")["cost"]):
				_build_farm(v)
			continue
		var node := _source_for(best_kind, v)
		var one: Array[Unit] = [v]
		_game.economy.order_gather(one, node)
		counts[best_kind] += 1
	_rebalance(counts)


## Desired-minus-actual gatherers per resource, biased by stockpiles: hoarded
## resources (> 800) need fewer workers, scarce ones (< 100) need more.
func _needs(counts: Dictionary) -> Dictionary:
	var split: Dictionary = _cfg.get("resource_split", {})
	var out := {}
	for r in ECO_RESOURCES:
		var need: float = float(split.get(r, 0.25)) * _villagers.size() - counts.get(r, 0)
		var stock: int = player.resources.get(r, 0)
		if stock > 800:
			need -= 3.0
		elif stock < 100:
			need += 1.0
		if r == "stone" and player.age < 1:
			need -= 2.0
		out[r] = need
	# Farms must be reseeded with wood: keep one extra lumberjack per 4 farms.
	var farms := 0
	for b in _my_buildings:
		if b.is_farm():
			farms += 1
	out["wood"] += farms / 4.0
	return out


## Moves one villager per think from the most over-supplied resource to the
## most under-supplied one that has a reachable source.
func _rebalance(counts: Dictionary) -> void:
	var needs := _needs(counts)
	var want := ""
	var give := ""
	for r in ECO_RESOURCES:
		if needs[r] >= 1.5 and (want == "" or needs[r] > needs[want]):
			want = r
		if needs[r] <= -1.0 and (give == "" or needs[r] < needs[give]):
			give = r
	if want == "" or give == "":
		return
	for v in _villagers:
		if v.task.get("type", "") == "gather" and v.task.get("kind", "") == give and v.carry_amount < 3.0:
			var node := _source_for(want, v)
			if node == null:
				if want == "food" and player.can_afford(GameData.building("farm")["cost"]):
					_game.economy.clear_task(v)
					_build_farm(v)
				return
			var one: Array[Unit] = [v]
			_game.economy.order_gather(one, node)
			rebalanced += 1
			return


func _source_for(kind: String, v: Unit) -> Entity:
	var home := _home()
	var node := _game.economy.find_node(kind, home, 16, player.id)
	if node == null:
		node = _game.economy.find_node(kind, v.grid_pos, 24, player.id)
	return node


func _build_farm(builder: Unit) -> void:
	# Ring the Town Center (a drop site) so farmers walk as little as possible.
	_place("farm", _home(), 3, 9, [builder])


# --- Construction -------------------------------------------------------------------

func _build() -> void:
	if _villagers.is_empty():
		return
	# Islands: the dock comes before any other building (wood is saved for it).
	if _enemy_needs_boat() and _count("dock") == 0 and _villagers.size() >= int(_cfg.get("dock_min_villagers_islands", 6)):
		_try_dock()
		return
	var pop := _game.population(player.id)
	var cap := _game.population_cap(player.id)
	if cap < _game.buildings.max_population and cap - pop <= 3 and not _under_construction("house"):
		_place("house", _home(), 4, 12, _builders(1))
		return
	if _count("mill") == 0 and _villagers.size() >= 5:
		var berries := _game.economy.find_node("food", _home(), 14, player.id)
		if berries is ResourceNode:
			_place("mill", berries.grid_pos, 2, 5, _builders(1))
			return
	if _villagers.size() >= 6:
		for r in ["wood", "gold", "stone"]:
			if r == "stone" and player.age < 1:
				continue
			var node := _game.economy.find_node(r, _home(), 22, player.id)
			if node == null:
				continue
			var drop := _game.buildings.nearest_drop_site(player.id, r, node.grid_pos)
			if (drop == null or drop.closest_point(node.grid_pos).distance_to(node.grid_pos) > 7.0) and not _under_construction("storehouse"):
				_place("storehouse", node.grid_pos, 2, 6, _builders(1))
				return
	var mil_wanted := int(diff.get("military_buildings", 1))
	var order: Array[String] = ["barracks", "archery_range", "stable"]
	var have := 0
	for t in order:
		have += _count(t)
	if have < mil_wanted and _villagers.size() >= 9:
		for t in order:
			if _count(t) == 0 and player.age >= int(GameData.building(t).get("age", 0)):
				_place(t, _home(), 5, 14, _builders(2))
				return
	if difficulty != "easy" and player.age >= 1 and _count("blacksmith") == 0 and _villagers.size() >= 14:
		_place("blacksmith", _home(), 5, 13, _builders(1))
		return
	if difficulty != "easy" and player.age >= int(GameData.ai.get("siege_workshop_from_age", 2)) and _count("siege_workshop") == 0 and _villagers.size() >= 18:
		_place("siege_workshop", _home(), 5, 14, _builders(2))
		return
	# Gunpowder/Industrial ages: one of each modern production building (normal/hard).
	if difficulty != "easy":
		for mid in GameData.ai.get("modern_buildings", []):
			if player.age >= int(GameData.building(mid).get("age", 99)) and _count(mid) == 0 and _villagers.size() >= 20:
				if _place(mid, _home(), 5, 15, _builders(2)) != null:
					return
	if difficulty == "hard" and player.age >= 1 and _count("tower") < 2 and player.resources["stone"] >= 150:
		_place("tower", _home(), 5, 9, _builders(1))


## Picks builders: idle first, then wood gatherers.
func _builders(n: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for v in _villagers:
		if v.task.is_empty():
			out.append(v)
	for v in _villagers:
		if out.size() >= n:
			break
		if not out.has(v) and v.task.get("kind", "") == "wood":
			out.append(v)
	for v in _villagers:
		if out.size() >= n:
			break
		if not out.has(v) and v.task.get("type", "") == "gather":
			out.append(v)
	return out.slice(0, n)


## Finds a free spot (with a 1-tile walkable margin so bases never wall in)
## between min_d and max_d tiles of `near` and places the building.
func _place(type_id: String, near: Vector2, min_d: int, max_d: int, builders: Array[Unit]) -> Building:
	if _game.buildings.requirement_error(player, type_id) != "" or builders.is_empty():
		return null
	var s: int = GameData.building(type_id)["size"]
	var c := Iso.tile_of(near)
	var candidates: Array[Vector2i] = []
	for dy in range(-max_d, max_d + 1):
		for dx in range(-max_d, max_d + 1):
			var d := Vector2(dx, dy).length()
			if d >= min_d and d <= max_d:
				candidates.append(c + Vector2i(dx, dy) - Vector2i(s / 2, s / 2))
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	# Shore sites are rare: docks check every candidate.
	var shore: bool = GameData.building(type_id).get("placement", "") == "shore"
	for o in (candidates if shore else candidates.slice(0, 160)):
		if _game.buildings.placement_error(type_id, o) != "":
			continue
		if type_id != "farm" and GameData.building(type_id).get("placement", "") != "shore" and not _margin_free(o, s):
			continue
		return _game.buildings.try_place(player, type_id, o, builders)
	return null


func _margin_free(o: Vector2i, s: int) -> bool:
	var ring := Rect2i(o, Vector2i(s, s)).grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var t := Vector2i(x, y)
			if Rect2i(o, Vector2i(s, s)).has_point(t):
				continue
			if not _game.pathfinder.is_walkable(t):
				return false
	return true


# --- Production ---------------------------------------------------------------------

func _train() -> void:
	var tc := _town_center()
	var saving_for_age := _ready_for_age() and not player.can_afford(_next_age_cost())
	# Classic "click up": once the villager threshold for the next age is met,
	# pause villagers and army until the age research can be queued.
	if tc and _villagers.size() < int(diff.get("villager_target", 20)) and tc.queue.size() < 1 and not saving_for_age:
		if _game.production.enqueue_error(tc, "villager") == "":
			_game.production.enqueue(tc, "villager")
	if _villagers.size() < 7:
		return
	var army_size := _army.size()
	for b in _my_buildings:
		if b.type_id == "dock" and b.is_complete() and b.queue.size() < 2:
			_train_dock(b)
			continue
		if not b.is_complete() or b.queue.size() >= 2 or b.def.get("trains", []).is_empty() or b.type_id == "town_center" or b.type_id == "dock":
			continue
		if b.type_id == "stable" and _scouts.is_empty() and _game.production.enqueue_error(b, "scout") == "":
			_game.production.enqueue(b, "scout")
			continue
		# Saving for an age only pauses the army once a minimal force exists.
		if army_size >= int(diff.get("max_army", 20)) or (saving_for_age and army_size >= int(diff.get("army_attack_size", 4))):
			continue
		var pick := _pick_unit(b)
		if pick != "":
			_game.production.enqueue(b, pick)
			army_size += 1


func _pick_unit(b: Building) -> String:
	var mix: Dictionary = diff.get("army_mix", {})
	var options: Array[String] = []
	var weights: Array[float] = []
	for id in b.def.get("trains", []):
		if mix.has(id) and _game.production.enqueue_error(b, id) == "":
			options.append(id)
			weights.append(float(mix[id]))
	if options.is_empty():
		return ""
	var total := 0.0
	for w in weights:
		total += w
	var r := _rng.randf() * total
	for i in options.size():
		r -= weights[i]
		if r <= 0.0:
			return options[i]
	return options[0]


func _next_age_id() -> String:
	for id in GameData.ages:
		if int(GameData.ages[id].get("sets_age", 0)) == player.age + 1:
			return id
	return ""


func _next_age_cost() -> Dictionary:
	var id := _next_age_id()
	return GameData.ages[id].get("cost", {}) if id != "" else {}


func _ready_for_age() -> bool:
	var thresholds: Array = diff.get("age_up_villagers", [99, 99, 99])
	return _next_age_id() != "" and player.age < thresholds.size() and _villagers.size() >= int(thresholds[player.age])


func _age_up() -> void:
	if not _ready_for_age():
		return
	var tc := _town_center()
	var id := _next_age_id()
	if tc and _game.production.enqueue_error(tc, id) == "":
		_game.production.enqueue(tc, id)


## Researches technologies in tech_priority order, one per building at a time,
## never while saving for the next age, up to the difficulty's max_techs.
func _research() -> void:
	if player.researched.size() >= int(diff.get("max_techs", 0)) or _ready_for_age() or _villagers.size() < 10:
		return
	for id in _cfg.get("tech_priority", []):
		var t: Dictionary = GameData.techs.get(id, {})
		if t.is_empty() or player.researched.has(id):
			continue
		for b in _my_buildings:
			if b.type_id == t.get("building", "") and b.is_complete() and b.queue.is_empty() and _game.production.enqueue_error(b, id) == "":
				_game.production.enqueue(b, id)
				return


# --- Military -------------------------------------------------------------------------

func _scout() -> void:
	for s in _scouts:
		if s.has_target() or s.state == Unit.State.MOVING:
			continue
		while not _scout_points.is_empty() and _game.fog.is_explored(player.id, Iso.tile_of(_scout_points[0])):
			_scout_points.pop_front()
		if _scout_points.is_empty():
			return
		# An idle scout still standing where the last order left it could not reach
		# that waypoint (water, cliffs): skip it instead of re-ordering forever.
		var last: Array = _scout_last.get(s.entity_id, [])
		if not last.is_empty() and last[0] == _scout_points[0] and s.grid_pos.distance_to(last[1]) < 0.3:
			_scout_points.pop_front()
			if _scout_points.is_empty():
				return
		_scout_last[s.entity_id] = [_scout_points[0], s.grid_pos]
		var one: Array[Unit] = [s]
		_game.commands.move_group(one, _scout_points[0])


func _defend() -> void:
	_threat = Vector2.INF
	var radius := float(diff.get("reaction_radius", 12))
	var near: Array = []
	var sum := Vector2.ZERO
	var n := 0
	for b in _my_buildings:
		near.clear()
		_game.unit_system.units_near(b.grid_pos, radius, near)
		for o in near:
			if not o.dead and CombatSystem.is_enemy(b, o) and _game.fog.is_visible(player.id, o) and o.grid_pos.distance_to(b.grid_pos) <= radius and _threatens(o):
				sum += o.grid_pos
				n += 1
		if n > 0:
			break
	if n == 0:
		_rally_idle_army()
		return
	_threat = sum / n
	var defenders: Array[Unit] = []
	for u in _army:
		if not u.has_target() and not wave.has(u):
			defenders.append(u)
	if not defenders.is_empty():
		_game.commands.attack_move(defenders, _threat)
	# Villagers next to the fight run home.
	var home := _home()
	for v in _villagers:
		if v.grid_pos.distance_to(_threat) < 4.0 and v.grid_pos.distance_to(home) > 3.0:
			var one: Array[Unit] = [v]
			_game.economy.clear_task(v)
			_game.commands.move_group(one, home)


## Enemy players' units always threaten the base; wild animals only while
## they are attacking this AI (deer and boar grazing nearby are no raid).
func _threatens(o: Unit) -> bool:
	if not Wildlife.is_animal(o):
		return true
	return o.has_target() and o.target.owner_id == player.id


func _rally_idle_army() -> void:
	var home := _home()
	var center := Vector2(_game.map.width, _game.map.height) * 0.5
	var rally := home + (center - home).normalized() * 6.0
	var idle: Array[Unit] = []
	for u in _army:
		if not u.has_target() and u.state == Unit.State.IDLE and not wave.has(u) and not _naval_op.get("units", []).has(u) and u.grid_pos.distance_to(rally) > 5.0:
			idle.append(u)
	if not idle.is_empty():
		_game.commands.move_group(idle, rally)


func _attack() -> void:
	if elapsed < float(diff.get("first_attack_minute", 10)) * 60.0:
		return
	if not _naval_op.is_empty():
		_run_naval_op()
		return
	if not wave.is_empty():
		# Keep an active wave pushing to the next known target.
		var arrived := wave.all(func(u): return not u.has_target() and u.state == Unit.State.IDLE)
		if arrived and not enemy_targets.is_empty():
			_game.commands.attack_move(wave, enemy_targets[0])
		return
	if elapsed - last_wave_time < 90.0 or _threat != Vector2.INF:
		return
	var ready: Array[Unit] = []
	for u in _army:
		if not u.has_target():
			ready.append(u)
	if ready.size() < int(diff.get("army_attack_size", 8)) or enemy_targets.is_empty():
		return
	last_wave_time = elapsed
	if not _fleet.is_empty():
		_game.commands.attack_move(_fleet, enemy_targets[0])
	if _enemy_needs_boat():
		if _transports.is_empty():
			return
		var ship: Unit = _transports[0]
		var riders: Array[Unit] = []
		for u in ready:
			if riders.size() < int(ship.def.get("transport_capacity", 10)):
				riders.append(u)
		ship.stop()  # it may be out exploring the coast
		_game.naval.order_board(riders, ship)
		_naval_op = {"phase": "boarding", "ship": ship, "units": riders, "since": elapsed}
		return
	wave = ready
	_game.commands.attack_move(wave, enemy_targets[0])


## True when no land path leads from home to the first enemy target (cached).
func _enemy_needs_boat() -> bool:
	if _needs_boat < 0 and not enemy_targets.is_empty():
		var path := _game.pathfinder.find_path(_home(), enemy_targets[0], player.id)
		_needs_boat = 1 if path.is_empty() or path[path.size() - 1].distance_to(enemy_targets[0]) > 8.0 else 0
	return _needs_boat == 1


func _run_naval_op() -> void:
	var ship: Unit = Iso.alive(_naval_op.get("ship"))
	if ship == null or ship.dead:
		_naval_op = {}
		return
	var riders: Array = _naval_op["units"].filter(func(u): return is_instance_valid(u) and not u.dead)
	match String(_naval_op["phase"]):
		"boarding":
			var aboard := riders.filter(func(u): return u.aboard == ship)
			var timeout := elapsed - float(_naval_op["since"]) > float(_cfg.get("naval_boarding_timeout", 45.0))
			if (aboard.size() == riders.size() or timeout) and not ship.cargo.is_empty() and not enemy_targets.is_empty():
				_game.naval.order_unload(ship, enemy_targets[0])
				_naval_op["phase"] = "sailing"
				_naval_op["since"] = elapsed
			elif timeout:
				_naval_op = {}
		"sailing":
			if ship.cargo.is_empty():
				var landed: Array[Unit] = []
				for u in riders:
					if u.aboard == null:
						landed.append(u)
				wave = landed
				if not enemy_targets.is_empty():
					_game.commands.attack_move(wave, enemy_targets[0])
				_naval_op = {}
			elif not _game.naval.is_unloading(ship) and not enemy_targets.is_empty():
				_game.naval.order_unload(ship, enemy_targets[0])


# --- Naval ---------------------------------------------------------------------------

func _naval() -> void:
	# Dock: once, if a shore site exists near home.
	_try_dock()
	# Idle fishing ships go to the nearest shoal.
	for f in _fishers:
		if f.task.is_empty() and f.state == Unit.State.IDLE:
			var fish := _game.economy.find_node("food", f.grid_pos, 30, -1, true)
			if fish != null:
				var one: Array[Unit] = [f]
				_game.economy.order_gather(one, fish)
	# An idle transport (no invasion under way) explores the coasts.
	if _naval_op.is_empty():
		for tr_ship in _transports:
			if tr_ship.state != Unit.State.IDLE or not tr_ship.cargo.is_empty():
				continue
			while not _sea_points.is_empty() and _game.fog.is_explored(player.id, Iso.tile_of(_sea_points[0])):
				_sea_points.pop_front()
			if _sea_points.is_empty():
				break
			var last: Array = _scout_last.get(tr_ship.entity_id, [])
			if not last.is_empty() and last[0] == _sea_points[0] and tr_ship.grid_pos.distance_to(last[1]) < 0.3:
				_sea_points.pop_front()
				continue
			var water := _game.naval_pathfinder.nearest_walkable(Iso.tile_of(_sea_points.front()), 12, tr_ship.grid_pos)
			if water.x >= 0:
				_scout_last[tr_ship.entity_id] = [_sea_points[0], tr_ship.grid_pos]
				var one2: Array[Unit] = [tr_ship]
				_game.commands.move_group(one2, Iso.tile_center(water))
			break
	# Idle warships guard the water near the dock.
	var dock: Building = null
	for b in _my_buildings:
		if b.type_id == "dock" and b.is_complete():
			dock = b
	if dock != null:
		var idle: Array[Unit] = []
		for s in _fleet:
			if not s.has_target() and s.state == Unit.State.IDLE and s.grid_pos.distance_to(dock.grid_pos) > 10.0:
				idle.append(s)
		if not idle.is_empty():
			_game.commands.move_group(idle, dock.grid_pos)


## Places the first dock once enough villagers exist. Without the money it
## retries soon; without any shore site it waits a minute.
func _try_dock() -> bool:
	var min_vil := int(_cfg.get("dock_min_villagers_islands", 6)) if _enemy_needs_boat() else int(_cfg.get("dock_min_villagers", 10))
	if _count("dock") > 0 or _villagers.size() < min_vil or elapsed < _dock_retry:
		return false
	if _game.buildings.requirement_error(player, "dock") != "":
		_dock_retry = elapsed + 5.0
		return false
	_dock_retry = elapsed + 60.0
	return _place("dock", _home(), 6, int(_cfg.get("dock_search_radius", 24)), _builders(1)) != null


func _train_dock(b: Building) -> void:
	var want_fish := int(diff.get("fishing_ships", 3))
	if _fishers.size() + b.queue.count("fishing_ship") < want_fish and _game.production.enqueue_error(b, "fishing_ship") == "":
		_game.production.enqueue(b, "fishing_ship")
		return
	if _enemy_needs_boat() and _transports.is_empty() and not b.queue.has("transport_ship") and _game.production.enqueue_error(b, "transport_ship") == "":
		_game.production.enqueue(b, "transport_ship")
		return
	if _fleet.size() >= int(diff.get("max_fleet", 4)):
		return
	var mix: Dictionary = diff.get("fleet_mix", {})
	var options: Array[String] = []
	for id in mix:
		for k in int(mix[id]):
			if _game.production.enqueue_error(b, id) == "":
				options.append(id)
	if not options.is_empty():
		_game.production.enqueue(b, options[_rng.randi() % options.size()])

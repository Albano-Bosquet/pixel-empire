class_name EconomySystem
extends Node
## Villager work tasks (design/game-brief.md MVP item 2).
##
## Task state table (unit.task["type"] / ["phase"]):
##   gather: to_node --(in reach)--> work --(full or node gone)--> to_drop
##           to_drop --(in reach of drop site, deposit)--> to_node (same node,
##           else nearest same resource within search_radius, else none)
##   build:  to_site --(in reach)--> work --(building complete)--> auto-gather if
##           it is a drop site, else none
##   repair: to_site --> work --(full hp or can't afford)--> none
##   drop:   to_site --(deposit)--> none
## A plain move order clears the task. Arrival is detected when locomotion is
## IDLE or the unit is within `work_reach` of the target's footprint.
## Data: economy_settings.json.

const MAX_RETRIES := 3

var _game: Game
var _cfg: Dictionary
var _reach := 0.75
var _gather_reach := 0.12
var _capacity := 10.0


func setup(game: Game, economy_cfg: Dictionary) -> void:
	_game = game
	_cfg = economy_cfg
	_reach = float(_cfg.get("work_reach", 0.75))
	_gather_reach = float(_cfg.get("gather_reach", 0.12))
	_capacity = float(_cfg.get("carry_capacity", 10))


# --- Orders -------------------------------------------------------------------

func order_gather(units: Array[Unit], node: Entity) -> void:
	for u in _workers(units):
		if can_gather(u, node):
			_set_task(u, {"type": "gather", "node": node, "phase": "to_node", "kind": node.resource_type, "retries": 0})


## Ships ("naval") only harvest water nodes (fish); land workers never do.
static func can_gather(u: Unit, node: Entity) -> bool:
	var water_node: bool = node is ResourceNode and bool(node.def.get("naval", false))
	return water_node == bool(u.def.get("naval", false))


func order_build(units: Array[Unit], b: Building) -> void:
	var type := "build" if not b.is_complete() else "repair"
	for u in _workers(units):
		if u.def.get("builds", true):
			_set_task(u, {"type": type, "building": b, "phase": "to_site", "retries": 0})


func order_drop(units: Array[Unit], b: Building) -> void:
	for u in _workers(units):
		if u.carry_amount >= 1.0 and b.accepts(u.carry_type, u.def.get("naval", false)):
			_set_task(u, {"type": "drop", "building": b, "phase": "to_site", "retries": 0})


func clear_task(u: Unit) -> void:
	u.task = {}
	u.work_anim = ""


func _workers(units: Array[Unit]) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if is_instance_valid(u) and u.is_worker:
			out.append(u)
	return out


func _set_task(u: Unit, t: Dictionary) -> void:
	u.task = t
	u.work_anim = ""
	_move_to_target(u)


# --- Tick ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	for u in _game.unit_system.units:
		if not u.task.is_empty() and not u.dead:
			_tick(u, delta)
	_game.buildings.apply_construction(delta)


func _tick(u: Unit, delta: float) -> void:
	match u.task["type"]:
		"gather":
			_tick_gather(u, delta)
		"build", "repair":
			_tick_build(u, delta)
		"drop":
			_tick_drop(u)


func _tick_gather(u: Unit, delta: float) -> void:
	var t := u.task
	var node: Entity = Iso.alive(t.get("node"))
	match t["phase"]:
		"to_node":
			if not _valid_node(node):
				node = _find_node(t["kind"], u.grid_pos, u.grid_pos, -1, u.owner_id, u.def.get("naval", false))
				if node == null:
					clear_task(u)
					return
				t["node"] = node
				_move_to_target(u)
				return
			if _at_node(u, node):
				u.stop()
				t["phase"] = "work"
				if u.carry_type != node.resource_type:
					u.carry_type = node.resource_type
					u.carry_amount = 0.0
			elif u.state == Unit.State.IDLE:
				_retry(u)
		"work":
			if not _valid_node(node):
				t["phase"] = "to_drop" if u.carry_amount >= 1.0 else "to_node"
				u.work_anim = ""
				_move_to_target(u)
				return
			var anims: Dictionary = _cfg.get("gather_animations", {})
			if node is Building:
				_farm_work(u, node, delta, anims)
			else:
				u.work_anim = String(anims.get(node.resource_type, "forage"))
				_face(u, node.grid_pos)
			# Units may override the per-resource rate (fishing ships: "gather_rate").
			var rate := float(u.def.get("gather_rate", _cfg.get("gather_rates", {}).get(node.resource_type, 0.3))) * _game.gather_multiplier(u.owner_id, node.resource_type)
			var cap := capacity(u.owner_id)
			u.carry_amount += node.take(minf(rate * delta, cap - u.carry_amount))
			if u.carry_amount >= cap - 0.001:
				t["phase"] = "to_drop"
				u.work_anim = ""
				_move_to_target(u)
		"to_drop":
			var drop: Building = Iso.alive(t.get("drop"))
			if drop == null or not is_instance_valid(drop) or not drop.accepts(u.carry_type, u.def.get("naval", false)):
				drop = _game.buildings.nearest_drop_site(u.owner_id, u.carry_type, u.grid_pos, u.def.get("naval", false))
				t["drop"] = drop
				if drop == null:
					EventBus.notify.emit(u.owner_id, Loc.msg("No drop-off building for %s", [u.carry_type]))
					clear_task(u)
					return
				_move_to_target(u)
				return
			if _in_reach(u, drop.footprint()):
				_deposit(u)
				t["drop"] = null
				t["phase"] = "to_node"
				t["retries"] = 0
				if not _valid_node(node):
					t["node"] = _find_node(t["kind"], node_pos(t, u), u.grid_pos, -1, u.owner_id, u.def.get("naval", false))
					if t["node"] == null:
						clear_task(u)
						return
				_move_to_target(u)
			elif u.state == Unit.State.IDLE:
				_retry(u)


## Public search used by the AI and rally logic.
func find_node(kind: String, around: Vector2, radius: int, owner_id: int, naval: bool = false) -> Entity:
	return _find_node(kind, around, around, radius, owner_id, naval)


## Villagers currently assigned to gather `node`.
func farmers(node: Entity) -> int:
	var n := 0
	for u in _game.unit_system.units:
		if not u.task.is_empty() and u.task.get("node") == node:
			n += 1
	return n


## Carry capacity of a player's villagers (carry_capacity modifier).
func capacity(pid: int) -> float:
	return _capacity * _game.player(pid).modifier("carry_capacity")


func node_pos(t: Dictionary, u: Unit) -> Vector2:
	return t.get("last_node_pos", u.grid_pos)


func _tick_build(u: Unit, delta: float) -> void:
	var t := u.task
	var b: Building = Iso.alive(t.get("building"))
	if b == null or not is_instance_valid(b):
		clear_task(u)
		return
	if t["type"] == "build" and b.is_complete():
		_after_build(u, b)
		return
	if t["type"] == "repair" and b.hp >= b.max_hp:
		clear_task(u)
		return
	match t["phase"]:
		"to_site":
			if _in_reach(u, b.footprint()):
				u.stop()
				t["phase"] = "work"
			elif u.state == Unit.State.IDLE:
				_retry(u)
		"work":
			u.work_anim = "build"
			_face(u, b.grid_pos)
			if t["type"] == "build":
				b.builders_this_tick += 1
			elif not _repair(u, b, delta):
				clear_task(u)


func _tick_drop(u: Unit) -> void:
	var b: Building = Iso.alive(u.task.get("building"))
	if b == null or not is_instance_valid(b):
		clear_task(u)
		return
	if _in_reach(u, b.footprint()):
		_deposit(u)
		clear_task(u)
	elif u.state == Unit.State.IDLE:
		_retry(u)


## Repairs `b` for one tick; pays repair_cost_fraction of the build cost per full
## HP bar, charged in whole resource units. Returns false when it cannot continue.
func _repair(u: Unit, b: Building, delta: float) -> bool:
	var player := _game.player(u.owner_id)
	var hp_gain := float(_cfg.get("repair_rate_hp_per_second", 25)) * delta
	var t := u.task
	var debt: Dictionary = t.get("debt", {})
	var cost: Dictionary = b.def.get("cost", {})
	var frac := float(_cfg.get("repair_cost_fraction", 0.5))
	for k in cost:
		debt[k] = float(debt.get(k, 0.0)) + float(cost[k]) * frac * hp_gain / b.max_hp
	var due := {}
	for k in debt:
		if debt[k] >= 1.0:
			due[k] = floori(debt[k])
	if not due.is_empty():
		if not player.spend(due):
			EventBus.notify.emit(u.owner_id, "Not enough resources to repair")
			return false
		for k in due:
			debt[k] -= due[k]
	t["debt"] = debt
	t["hp_frac"] = float(t.get("hp_frac", 0.0)) + hp_gain
	var whole := floori(t["hp_frac"])
	t["hp_frac"] -= whole
	b.hp = mini(b.max_hp, b.hp + whole)
	return true


func _after_build(u: Unit, b: Building) -> void:
	clear_task(u)
	if b.def.get("line_build", false) or b.def.get("wall", false):
		# Wall lines: move on to the nearest unfinished piece of the same owner.
		var next: Building = null
		var best := float(_cfg.get("wall_chain_radius", 4.0))
		for o in _game.buildings.buildings:
			if o != b and o.owner_id == u.owner_id and not o.is_complete() and not o.dead and o.def.get("wall", false):
				var d := o.grid_pos.distance_to(b.grid_pos)
				if d <= best:
					best = d
					next = o
		if next != null:
			var me2: Array[Unit] = [u]
			order_build(me2, next)
		return
	if b.is_farm():
		var me: Array[Unit] = [u]
		order_gather(me, b)
		return
	var drops: Array = b.def.get("drop_off", [])
	if drops.is_empty() or b.type_id == "town_center":
		return
	var best: Entity = null
	for kind in drops:
		var n := _find_node(kind, b.grid_pos, u.grid_pos, -1, u.owner_id, u.def.get("naval", false))
		if n != null and (best == null or n.grid_pos.distance_squared_to(b.grid_pos) < best.grid_pos.distance_squared_to(b.grid_pos)):
			best = n
	if best != null:
		var one: Array[Unit] = [u]
		order_gather(one, best)


# --- Helpers ------------------------------------------------------------------

func _valid_node(n: Entity) -> bool:
	return n != null and is_instance_valid(n) and not n.dead and not n.is_depleted()


func _node_rect(n: Entity) -> Rect2i:
	return n.footprint() if n is Building else Rect2i(n.tile(), Vector2i.ONE)


func _deposit(u: Unit) -> void:
	var amount := floori(u.carry_amount)
	if amount > 0:
		var p := _game.player(u.owner_id)
		p.add(u.carry_type, amount)
		p.stats["gathered"][u.carry_type] = int(p.stats["gathered"].get(u.carry_type, 0)) + amount
		EventBus.sound_at.emit(String(GameData.audio.get("drop_sounds", {}).get(u.carry_type, "")), u.position)
	u.carry_amount = 0.0


## In reach of a footprint. A unit that has stopped (crowd-blocked near its
## goal) gets extra slack so busy drop sites never deadlock their workers.
func _in_reach(u: Unit, rect: Rect2i, reach: float = -1.0, allow_slack: bool = true) -> bool:
	var closest := Vector2(clampf(u.grid_pos.x, rect.position.x, rect.end.x), clampf(u.grid_pos.y, rect.position.y, rect.end.y))
	var slack := 0.6 if allow_slack and u.state == Unit.State.IDLE else 0.0
	return u.grid_pos.distance_to(closest) <= (_reach if reach < 0.0 else reach) + u.radius + slack


## Arrived at a gather node: farmers must stand inside the field; other nodes
## need the tight gather reach (crowd slack only once an approach has failed).
func _at_node(u: Unit, node: Entity) -> bool:
	var rect := _node_rect(node)
	var retried := int(u.task.get("retries", 0)) > 0
	if node is Building:
		return Rect2(rect).grow(-0.1).has_point(u.grid_pos) or (retried and u.state == Unit.State.IDLE and _in_reach(u, rect))
	return _in_reach(u, rect, _gather_reach, retried)


## Farmer work: walks the field in a serpentine along `farm_rows` rows while
## hoeing (AoE-style), instead of standing still at its edge.
## Farming cycle: hoe while walking the furrows for `farm_hoe_seconds`, then
## stand still filling a basket for `farm_basket_seconds`, forever. Food is
## gathered at the same rate in both halves (economy_settings.json).
func _farm_work(u: Unit, farm: Building, delta: float, anims: Dictionary) -> void:
	var cycle := farm_cycle()
	var t := u.task
	t["farm_t"] = farm_clock(float(t.get("farm_t", 0.0)), delta, cycle)
	if is_hoeing(u):
		u.work_anim = String(anims.get("farm", "farm"))
		_farm_walk(u, farm, delta)
	else:
		u.work_anim = String(anims.get("farm_basket", "forage"))
		# Kneel facing the camera so the basket is in view.
		u.face(Iso.direction_index(Vector2(1, 1)))


## (hoe seconds, basket seconds) of the farming cycle.
func farm_cycle() -> Vector2:
	return Vector2(maxf(0.0, float(_cfg.get("farm_hoe_seconds", 8.0))), maxf(0.0, float(_cfg.get("farm_basket_seconds", 8.0))))


## Whether a farmer is in the hoeing half of the farming cycle.
func is_hoeing(u: Unit) -> bool:
	return farm_hoeing(float(u.task.get("farm_t", 0.0)), farm_cycle())


## Farming clock `t` advanced by `delta`, wrapping at hoe + basket seconds.
## Example: farm_clock(15.5, 1.0, Vector2(8, 8)) == 0.5 (back to hoeing).
static func farm_clock(t: float, delta: float, cycle: Vector2) -> float:
	return fmod(t + delta, maxf(cycle.x + cycle.y, 0.001))


## Whether clock `t` falls in the hoeing part of `cycle` (hoe, basket seconds).
## Example: farm_hoeing(9.0, Vector2(8, 8)) == false (filling the basket).
static func farm_hoeing(t: float, cycle: Vector2) -> bool:
	return t < cycle.x


func _farm_walk(u: Unit, farm: Building, delta: float) -> void:
	var t := u.task
	var r := Rect2(farm.footprint()).grow(-float(_cfg.get("farm_inset", 0.3)))
	var rows := maxi(1, int(_cfg.get("farm_rows", 3)))
	var k := int(t.get("farm_k", 0))
	var row := ((k + 1) / 2) % rows
	var gx := r.end.x if (k / 2) % 2 == 0 else r.position.x
	var goal := Vector2(gx, r.position.y + (row + 0.5) * r.size.y / rows)
	var to := goal - u.grid_pos
	var dist := to.length()
	if dist < 0.04:
		t["farm_k"] = k + 1
		return
	var step := minf(dist, float(_cfg.get("farm_walk_speed", 0.32)) * delta)
	u.set_grid_pos(u.grid_pos + to / dist * step)
	u.face(Iso.direction_index(to))


func _target_rect(u: Unit) -> Rect2i:
	var t := u.task
	match t["type"]:
		"gather":
			if t["phase"] == "to_drop" and t.get("drop") != null and is_instance_valid(t["drop"]):
				return t["drop"].footprint()
			if t.get("node") != null and is_instance_valid(t["node"]):
				t["last_node_pos"] = t["node"].grid_pos
				return _node_rect(t["node"])
		"build", "repair", "drop":
			if is_instance_valid(t["building"]):
				return t["building"].footprint()
	return Rect2i()


func _move_to_target(u: Unit, spread: float = 0.0) -> void:
	if u.task.is_empty():
		return
	var t := u.task
	if t["type"] == "gather" and t["phase"] == "to_drop" and t.get("drop") == null:
		t["drop"] = _game.buildings.nearest_drop_site(u.owner_id, u.carry_type, u.grid_pos, u.def.get("naval", false))
	var rect := _target_rect(u)
	if rect.size == Vector2i.ZERO:
		return
	var node: Variant = t.get("node")
	var to_node: bool = t["type"] == "gather" and t["phase"] == "to_node" and node is Entity
	if (_at_node(u, node) if to_node else _in_reach(u, rect)):
		u.stop()
		return
	if to_node and node is Building:
		# Farms are walkable: work standing on the field.
		_game.unit_system.request_path(u, node.grid_pos + Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6)))
		return
	var pull := float(_cfg.get("gather_approach_pull", 0.55)) if to_node else 0.25
	var spot := _game.nav(u).approach(rect, u.grid_pos, spread, pull)
	if spot == Vector2.INF:
		clear_task(u)
		return
	_game.unit_system.request_path(u, spot)


## Arrived without reaching the target: try another approach spot. Gather
## trips to a drop site never give up (the worker would strand its load).
func _retry(u: Unit) -> void:
	u.task["retries"] = int(u.task.get("retries", 0)) + 1
	var dropping: bool = u.task["type"] == "gather" and u.task["phase"] == "to_drop"
	if u.task["retries"] > MAX_RETRIES and not dropping:
		clear_task(u)
		return
	if dropping and u.task["retries"] > MAX_RETRIES * 2:
		u.task["drop"] = null
		u.task["retries"] = 0
	_move_to_target(u, 2.5)


func _face(u: Unit, target: Vector2) -> void:
	var d := target - u.grid_pos
	if d.length_squared() > 0.0001:
		u.face(Iso.direction_index(d))


## Nearest non-depleted node of resource `kind` around `around` (search_radius).
## Food also includes the gatherer's own unworked farms.
func _find_node(kind: String, around: Vector2, from: Vector2, radius: int = -1, owner_id: int = -1, naval: bool = false) -> Entity:
	var r := radius if radius > 0 else int(_cfg.get("search_radius", 10))
	var c := Iso.tile_of(around)
	var best: Entity = null
	var best_d := INF
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var e: Entity = _game.static_entity_at(c + Vector2i(dx, dy))
			if e is Building and not naval and e.is_farm() and kind == "food" and not e.is_depleted() and (owner_id < 0 or e.owner_id == owner_id) and farmers(e) == 0:
				var df: float = e.grid_pos.distance_squared_to(around)
				if df < best_d:
					best_d = df
					best = e
			elif e is ResourceNode and e.resource_type == kind and not e.is_depleted() and bool(e.def.get("naval", false)) == naval:
				var d: float = e.grid_pos.distance_squared_to(around) + e.grid_pos.distance_squared_to(from) * 0.25
				if d < best_d:
					best_d = d
					best = e
	return best

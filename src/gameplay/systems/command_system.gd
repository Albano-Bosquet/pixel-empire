class_name CommandSystem
extends Node
## Right-click orders, resolved by what was clicked:
##   own units + resource          -> workers gather, others move next to it
##   own units + own unfinished bld -> workers build;  damaged -> workers repair
##   own units + own drop site      -> carrying workers drop off, others move
##   own units + ground             -> formation move (clears tasks)
##   own building(s) selected only  -> set rally point (on a resource: rally gather)
##   own units + visible enemy        -> attack it
##   trade carts + own market        -> trade route (MarketSystem)
##   monks + visible enemy unit      -> convert it (MonkSystem)
##   land units + own transport      -> board it; loaded transport + land -> unload there
## Formations: "box" (melee in front rows, ranged behind) or "line" (one wide row).

## Formation per player id ("box" default).
var formations: Dictionary = {}
## Shift+right-click waypoints still to walk: unit entity id -> Array[Vector2].
var waypoints: Dictionary = {}
var _game: Game
var _spacing := 0.62


func setup(game: Game, movement_cfg: Dictionary) -> void:
	_game = game
	_spacing = float(movement_cfg.get("formation_spacing", 0.62))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if order_at(event.position, event.shift_pressed):
			get_viewport().set_input_as_handled()


## The local player's contextual order at `screen_pos` (right click, or a tap on
## touch screens) for the current selection. Returns false when nothing is selected.
## Example: commands.order_at(tap_position, false)
func order_at(screen_pos: Vector2, queue: bool) -> bool:
	var world := _game.world_from_screen(screen_pos)
	var target := _game.selection.pick(screen_pos)
	var units := _game.selection.own_units()
	var blds := _game.selection.own_buildings()
	if units.is_empty() and blds.is_empty():
		return false
	_game.orders.submit({"t": "issue", "units": OrderRouter.ids(units), "buildings": OrderRouter.ids(blds),
		"grid": Iso.world_to_grid(world), "target": target.entity_id if target != null else 0, "queue": queue})
	if target != null and target.visible:
		_game.ground_fx.add_target_marker(target, _hostile_to(target))
	else:
		_game.ground_fx.add_move_marker(world)
	EventBus.local_order.emit(units)
	if units.is_empty():
		EventBus.ui_sound.emit("rally")  # only buildings selected: a new rally point
	return true


## Whether a right-clicked target is something the local player fights (red ring).
func _hostile_to(target: Entity) -> bool:
	if Wildlife.is_hostile_animal(target):
		return true
	if target.owner_id == Entity.GAIA:
		return false
	return not CombatSystem.are_allies(_game.local_player, target.owner_id)


## Formation used for `pid`'s group moves.
func formation_of(pid: int) -> String:
	return String(formations.get(pid, "box"))


func set_formation(pid: int, f: String) -> void:
	formations[pid] = f


## Whether `pid` can currently target `target`. Uses `pid`'s own fog, not the node's
## `visible` flag: that one follows the local player, so on the host it would drop
## orders from a network client aimed at things only the client sees. Buildings
## on explored ground stay targetable from memory.
func _sees(pid: int, target: Entity) -> bool:
	if target is Unit and (target as Unit).aboard != null:
		return false
	if target is Building:
		var r: Rect2i = (target as Building).footprint()
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if _game.fog.is_explored(pid, Vector2i(x, y)):
					return true
	return _game.fog.is_visible(pid, target)


## Applies the contextual right-click order. Returns true if anything was ordered.
## `pid` is the commanding player (defaults to the owner of the selection).
## `queue` (Shift): a ground move is appended as a waypoint instead of replacing the orders.
func issue(units: Array[Unit], buildings: Array[Building], grid: Vector2, target: Entity, pid: int = -1, queue: bool = false) -> bool:
	if pid < 0:
		pid = units[0].owner_id if not units.is_empty() else (buildings[0].owner_id if not buildings.is_empty() else _game.local_player)
	if queue and target == null and not units.is_empty():
		queue_waypoint(units, grid)
		return true
	for u in units:
		waypoints.erase(u.entity_id)
	if units.is_empty():
		if buildings.is_empty():
			return false
		for b in buildings:
			b.rally_point = target.grid_pos if target != null else grid
			b.rally_target = target if target is ResourceNode else null
			b.queue_redraw()
		return true
	if target != null and NavalSystem.is_transport(target) and target.owner_id == pid:
		var riders: Array[Unit] = []
		for u in units:
			if not NavalSystem.is_ship(u):
				riders.append(u)
		if not riders.is_empty():
			_game.naval.order_board(riders, target)
			return true
	if target == null and _game.pathfinder.is_walkable(Iso.tile_of(grid)):
		var loaded := units.filter(func(u): return NavalSystem.is_transport(u) and not u.cargo.is_empty())
		if not loaded.is_empty() and loaded.size() == units.size():
			for ship in loaded:
				_game.naval.order_unload(ship, grid)
			return true
	if target is Unit and Wildlife.is_animal(target) and _sees(pid, target) and (target.owner_id == pid or Wildlife.is_hostile_animal(target) or CombatSystem.is_enemy(units[0], target)):
		var hunters: Array[Unit] = []
		var fighters: Array[Unit] = []
		for u in units:
			if u.is_worker:
				hunters.append(u)
			elif not Wildlife.is_animal(u):
				fighters.append(u)
		if not hunters.is_empty() and Wildlife.kind(target) != "predator":
			_game.wildlife.order_hunt(hunters, target)
		else:
			fighters.append_array(hunters)
		if not fighters.is_empty():
			if CombatSystem.is_enemy(fighters[0], target):
				_game.combat.order_attack(fighters, target)
			else:
				move_group(fighters, target.grid_pos)
		return true
	if target != null and _sees(pid, target) and CombatSystem.is_enemy(units[0], target):
		_game.combat.order_attack(units, target)
		var monks: Array[Unit] = []
		for u in units:
			if MonkSystem.is_monk(u):
				monks.append(u)
		if not monks.is_empty():
			_game.monks.order_convert(monks, target)
		return true
	var workers: Array[Unit] = []
	var others: Array[Unit] = []
	for u in units:
		if u.is_worker:
			workers.append(u)
		else:
			others.append(u)
	if target is ResourceNode:
		_game.economy.order_gather(workers, target)
		if not others.is_empty():
			move_group(others, target.grid_pos)
		return true
	if target is Building and target.owner_id == pid and target.is_farm() and target.is_complete():
		_game.economy.order_gather(workers, target)
		return true
	if target is Building and target.owner_id == pid and target.def.get("exchange", false) and target.is_complete():
		var carts: Array[Unit] = []
		for o in others:
			if _game.market.is_trader(o):
				carts.append(o)
		if not carts.is_empty():
			_game.market.order_trade(carts, target)
			if carts.size() == units.size():
				return true
			for cu in carts:
				others.erase(cu)
	if target is Building and target.owner_id == pid:
		var b: Building = target
		if not b.is_complete() or b.hp < b.max_hp:
			_game.economy.order_build(workers, b)
			if not others.is_empty():
				move_group(others, b.closest_point(_centroid(others)))
			return true
		var carriers: Array[Unit] = []
		for w in workers:
			if w.carry_amount >= 1.0 and b.accepts(w.carry_type, w.def.get("naval", false)):
				carriers.append(w)
		if not carriers.is_empty():
			_game.economy.order_drop(carriers, b)
			for c in carriers:
				workers.erase(c)
		var rest: Array[Unit] = []
		rest.append_array(workers)
		rest.append_array(others)
		if not rest.is_empty():
			var spot := _game.nav(rest[0]).approach(b.footprint(), _centroid(rest))
			if spot != Vector2.INF:
				move_group(rest, spot)
		return true
	for u in units:
		_game.economy.clear_task(u)
	move_group(units, grid)
	return true


## Adds a formation waypoint after the units' current orders.
func queue_waypoint(units: Array[Unit], grid: Vector2) -> void:
	var slots := formation_slots(units, grid)
	var ordered := _assign(units, grid)
	for i in ordered.size():
		var u: Unit = ordered[i]
		if not waypoints.has(u.entity_id):
			waypoints[u.entity_id] = []
		waypoints[u.entity_id].append(slots[i])


## Walks queued waypoints once a unit has finished what it was doing.
func _physics_process(_delta: float) -> void:
	if waypoints.is_empty():
		return
	for id in waypoints.keys():
		var u: Unit = _game.entity(id) as Unit
		if u == null or u.dead or waypoints[id].is_empty():
			waypoints.erase(id)
			continue
		if u.state == Unit.State.IDLE and not u.path_pending and not u.has_target() and u.task.is_empty():
			var wp: Vector2 = waypoints[id].pop_front()
			_game.combat.on_move_ordered(u, wp)
			_game.unit_system.request_path(u, wp)


## Orders `units` to `target` (grid space) in formation. Returns the slots used.
func move_group(units: Array[Unit], target: Vector2) -> Array[Vector2]:
	var slots := formation_slots(units, target)
	var ordered := _assign(units, target)
	for i in ordered.size():
		var u: Unit = ordered[i]
		_game.combat.on_move_ordered(u, slots[i])
		_game.market.cancel(u)
		_game.monks.cancel(u)
		_game.naval.cancel(u)
		_game.unit_system.request_path(u, slots[i])
	EventBus.move_ordered.emit(target, units)
	return slots


## Grid positions for a block formation centred on `target`, front row first.
func formation_slots(units: Array[Unit], target: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := units.size()
	if n == 1:
		out.append(target)
		return out
	var centroid := _centroid(units)
	var dir := _travel_dir(centroid, target)
	var perp := Vector2(-dir.y, dir.x)
	var f := formation_of(units[0].owner_id) if not units.is_empty() else "box"
	var cols := _columns(n, f)
	var rows := ceili(float(n) / cols)
	var spacing := _spacing * (1.15 if f == "line" else 1.0)
	for k in n:
		var r := k / cols
		var c := k % cols
		var in_row := mini(cols, n - r * cols)
		var off := perp * (c - (in_row - 1) * 0.5) * spacing - dir * (r - (rows - 1) * 0.5) * spacing
		var slot := target + off
		var t := Iso.tile_of(slot)
		var pf := _game.nav(units[0])
		if units[0].altitude <= 0.0 and not pf.is_walkable(t):
			var w := pf.nearest_walkable(t, 6, centroid)
			if w.x >= 0:
				slot = Iso.tile_center(w) + Vector2(fmod(k * 0.37, 0.5) - 0.25, fmod(k * 0.61, 0.5) - 0.25)
		out.append(slot)
	return out


## Orders units to match slots while preserving their relative layout:
## front-most units take the front row, then left-to-right within each row.
func _assign(units: Array[Unit], target: Vector2) -> Array[Unit]:
	var n := units.size()
	if n <= 1:
		return units.duplicate()
	var dir := _travel_dir(_centroid(units), target)
	var perp := Vector2(-dir.y, dir.x)
	var cols := _columns(n, formation_of(units[0].owner_id) if not units.is_empty() else "box")
	var by_front := units.duplicate()
	# Melee first (front rows), then ranged; within a class keep spatial order.
	by_front.sort_custom(func(a, b):
		var ra: float = a.attack_range()
		var rb: float = b.attack_range()
		if absf(ra - rb) > 0.5:
			return ra < rb
		return a.grid_pos.dot(dir) > b.grid_pos.dot(dir))
	var out: Array[Unit] = []
	var i := 0
	while i < n:
		var row: Array = by_front.slice(i, mini(i + cols, n))
		row.sort_custom(func(a, b): return a.grid_pos.dot(perp) < b.grid_pos.dot(perp))
		for u in row:
			out.append(u)
		i += cols
	return out


func _columns(n: int, f: String = "box") -> int:
	if f == "line":
		return mini(n, 24)
	return ceili(sqrt(n * 1.5))


## Moves `units` to `goal` engaging every enemy met on the way.
func attack_move(units: Array[Unit], goal: Vector2) -> void:
	_game.combat.order_attack_move(units, goal)


## Halts units: clears tasks, targets and paths; they guard where they stand.
func stop(units: Array[Unit]) -> void:
	for u in units:
		waypoints.erase(u.entity_id)
		_game.economy.clear_task(u)
		_game.combat.on_move_ordered(u, u.grid_pos)
		u.stop()


func set_stance(units: Array[Unit], stance: String) -> void:
	for u in units:
		u.stance = stance


func _centroid(units: Array[Unit]) -> Vector2:
	var c := Vector2.ZERO
	for u in units:
		c += u.grid_pos
	return c / units.size()


func _travel_dir(centroid: Vector2, target: Vector2) -> Vector2:
	var dir := (target - centroid).normalized()
	return dir if dir != Vector2.ZERO else Vector2(1, 1).normalized()

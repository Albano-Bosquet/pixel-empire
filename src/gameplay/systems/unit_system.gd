class_name UnitSystem
extends Node
## Ticks every unit: path following, separation steering, wall sliding,
## facing and animation. Units have no per-node process callbacks (D6).
## Tuning: units_movement.json.

var units: Array[Unit] = []
## Dead units still animating/lying on the ground: [{"unit": Unit, "time": float}].
var corpses: Array[Dictionary] = []
var spatial: SpatialHash
## False on multiplayer clients: positions come from host snapshots.
var simulate := true

var _map: MapData
var _pathfinder: Pathfinder
var _naval: Pathfinder
var _cfg: Dictionary
var _neighbors: Array = []
## Pending path requests: [{"unit": Unit, "dest": Vector2}], served FIFO
## within a per-frame time budget so big group orders never spike a frame.
var _path_queue: Array[Dictionary] = []
var _path_budget_usec := 3000


func setup(map: MapData, pathfinder: Pathfinder, movement_cfg: Dictionary, naval_pathfinder: Pathfinder = null) -> void:
	_map = map
	_pathfinder = pathfinder
	_naval = naval_pathfinder if naval_pathfinder != null else pathfinder
	_cfg = movement_cfg
	spatial = SpatialHash.new(map.width, map.height, 2.0)
	_path_budget_usec = int(float(movement_cfg.get("path_budget_ms", 3.0)) * 1000.0)


func register(u: Unit) -> void:
	units.append(u)


func unregister(u: Unit) -> void:
	units.erase(u)


## Removes a dead unit from the simulation (deferred, so it is safe to call
## while systems iterate `units`). The body lies for `hold_seconds`, then fades
## out gradually over `fade_seconds` and is freed (combat_settings.json
## corpse_seconds / corpse_fade_seconds).
func retire(u: Unit, hold_seconds: float, fade_seconds: float = 0.0) -> void:
	corpses.append({"unit": u, "time": hold_seconds + fade_seconds, "fade": fade_seconds})
	unregister.call_deferred(u)


## Opacity of a corpse with `time_left` seconds to go: 1 while it lies, then an
## eased ramp to 0 across the last `fade` seconds.
static func corpse_alpha(time_left: float, fade: float) -> float:
	if fade <= 0.0:
		return 1.0 if time_left > 0.0 else 0.0
	return smoothstep(0.0, 1.0, clampf(time_left / fade, 0.0, 1.0))


## Queues a path search; the unit is MOVING (waiting) until it is served.
func request_path(u: Unit, dest: Vector2) -> void:
	for r in _path_queue:
		if r["unit"] == u:
			r["dest"] = dest
			u.await_path()
			return
	_path_queue.append({"unit": u, "dest": dest})
	u.await_path()


func pending_paths() -> int:
	return _path_queue.size()


func _serve_paths() -> void:
	var t0 := Time.get_ticks_usec()
	while not _path_queue.is_empty() and Time.get_ticks_usec() - t0 < _path_budget_usec:
		var r: Dictionary = _path_queue.pop_front()
		var u: Unit = r["unit"]
		if is_instance_valid(u) and u.path_pending:
			if u.altitude > 0.0:
				# Aircraft fly straight over everything (kept inside the map).
				u.order_path(PackedVector2Array([_clamp_to_map(r["dest"])]))
			else:
				u.order_path(_pf(u).find_path(u.grid_pos, r["dest"], u.owner_id))


## Units whose grid position is within `radius` of `pos`.
func units_near(pos: Vector2, radius: float, out: Array) -> void:
	spatial.query(pos, radius, out)


func _physics_process(delta: float) -> void:
	if simulate:
		_serve_paths()
	spatial.clear()
	for u in units:
		if not u.dead and u.aboard == null:
			spatial.insert(u, u.grid_pos)
	if not simulate:
		return
	for u in units:
		if not u.dead and u.aboard == null:
			_step(u, delta)


func _process(delta: float) -> void:
	for u in units:
		u.animate(delta)
	for c in corpses:
		if not is_instance_valid(c["unit"]):
			c["time"] = 0.0
			continue
		var cu: Unit = c["unit"]
		cu.animate(delta)
		c["time"] -= delta
		cu.modulate.a = corpse_alpha(c["time"], c.get("fade", 1.0))
		if c["time"] <= 0.0:
			cu.queue_free()
	corpses = corpses.filter(func(c): return c["time"] > 0.0 and is_instance_valid(c["unit"]))


func _step(u: Unit, delta: float) -> void:
	var desired := Vector2.ZERO
	if u.state == Unit.State.MOVING and not u.path_pending:
		desired = _follow_path(u, delta)

	# Separation: push overlapping units apart; moving units yield less.
	var push := Vector2.ZERO
	_neighbors.clear()
	spatial.query(u.grid_pos, 0.8, _neighbors)
	for o in _neighbors:
		if o == u or (o.altitude > 0.0) != (u.altitude > 0.0):
			continue  # air and ground never push each other
		var d: Vector2 = u.grid_pos - o.grid_pos
		var min_d: float = u.radius + o.radius
		var l2 := d.length_squared()
		if l2 >= min_d * min_d:
			continue
		var l := sqrt(l2)
		if l < 0.0001:
			d = Vector2.RIGHT.rotated(float(u.entity_id) * 2.399)
			l = 1.0
		push += d / l * (min_d - l)
	var sep_gain: float = _cfg.get("separation_strength", 5.0)
	if u.state == Unit.State.MOVING:
		sep_gain *= float(_cfg.get("moving_separation_factor", 0.45))
	var vel := desired + push * sep_gain
	u.velocity = vel
	if vel.length_squared() > 0.000001:
		if u.altitude > 0.0:
			u.set_grid_pos(_clamp_to_map(u.grid_pos + vel * delta))
		else:
			u.set_grid_pos(_slide(u.grid_pos, u.grid_pos + vel * delta, u.owner_id, _pf(u)))
	if desired.length_squared() > 0.0001 and u.anim_lock <= 0.0:
		u.face(Iso.direction_index(desired))
	u.play(_pick_anim(u))


func _follow_path(u: Unit, delta: float) -> Vector2:
	var last := u.path_index >= u.path.size() - 1
	var target := u.path[u.path_index]
	var to := target - u.grid_pos
	var dist := to.length()
	var reach: float = _cfg.get("arrive_radius", 0.08) if last else _cfg.get("waypoint_radius", 0.35)
	if dist <= reach:
		u.path_index += 1
		if u.path_index >= u.path.size():
			u.stop()
			return Vector2.ZERO
		target = u.path[u.path_index]
		to = target - u.grid_pos
		dist = to.length()
		last = u.path_index >= u.path.size() - 1
	# Progress tracking towards the final destination for crowd/stuck handling.
	var final_dist := u.grid_pos.distance_to(u.final_destination())
	if final_dist < u.last_progress_dist - 0.03:
		u.last_progress_dist = final_dist
		u.stuck_time = 0.0
	else:
		u.stuck_time += delta
	if u.stuck_time > float(_cfg.get("crowd_stuck_time", 0.6)) and final_dist < float(_cfg.get("crowd_arrive_distance", 1.1)):
		u.stop()
		return Vector2.ZERO
	if u.stuck_time > float(_cfg.get("repath_stuck_time", 2.5)):
		request_path(u, u.final_destination())
		return Vector2.ZERO
	var spd := u.speed
	var slow: float = _cfg.get("slowdown_distance", 0.35)
	if last and dist < slow:
		spd *= maxf(0.35, dist / slow)
	return to / maxf(dist, 0.0001) * spd


## Moves towards `to` but never into an unwalkable tile (slides along walls).
func _clamp_to_map(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.5, _map.width - 0.5), clampf(p.y, 0.5, _map.height - 0.5))


func _pf(u: Unit) -> Pathfinder:
	return _naval if u.def.get("naval", false) else _pathfinder


func _slide(from: Vector2, to: Vector2, owner: int = -1, pf: Pathfinder = null) -> Vector2:
	if pf == null:
		pf = _pathfinder
	if pf.is_walkable(Iso.tile_of(to), owner):
		return to
	var x_only := Vector2(to.x, from.y)
	if pf.is_walkable(Iso.tile_of(x_only), owner):
		return x_only
	var y_only := Vector2(from.x, to.y)
	if pf.is_walkable(Iso.tile_of(y_only), owner):
		return y_only
	return from


func _pick_anim(u: Unit) -> String:
	if u.anim_lock > 0.0:
		return u._anim
	if u.state == Unit.State.MOVING:
		if u.carry_amount >= 1.0 and u.has_anim("carry_" + u.carry_type):
			return "carry_" + u.carry_type
		return "walk"
	if u.work_anim != "" and u.has_anim(u.work_anim):
		return u.work_anim
	return "idle"

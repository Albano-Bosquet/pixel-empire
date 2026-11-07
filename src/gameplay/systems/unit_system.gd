class_name UnitSystem
extends Node
## Ticks every unit: path following, separation steering, wall sliding,
## facing and animation. Units have no per-node process callbacks (D6).
## The simulation ticks at physics_ticks_per_second (project.godot), below the
## screen's rate; Unit.glide_to keeps the drawn movement smooth between ticks.
## Tuning: units_movement.json.

## Sprites this many world pixels off screen still animate (tall and flying ones).
const VIEW_MARGIN := 160.0
const SEPARATION_CELL := 1.0

var units: Array[Unit] = []
## Subsets of `units`, for systems that only care about these.
var animals: Array[Unit] = []
var loiterers: Array[Unit] = []
## Dead units still animating/lying on the ground: [{"unit": Unit, "time": float}].
var corpses: Array[Dictionary] = []
var spatial: SpatialHash
## False on multiplayer clients: positions come from host snapshots.
var simulate := true

var _map: MapData
var _pathfinder: Pathfinder
var _naval: Pathfinder
var _cfg: Dictionary
# Separation grid, rebuilt each tick as linked lists in packed arrays: the
# neighbour loop is the hottest code in the game and reading a property of
# another object costs far more than reading these.
var _active: Array[Unit] = []
var _sep_head := PackedInt32Array()
var _sep_next := PackedInt32Array()
var _sep_pos := PackedVector2Array()
var _sep_radius := PackedFloat32Array()
var _sep_air := PackedByteArray()
var _sep_cols := 0
var _sep_rows := 0
var _sep_max_radius := 0.0
## False once units may have moved since `spatial` was last filled.
var _spatial_fresh := false
# Tuning, read once from units_movement.json.
var _separation_gain := 5.0
var _moving_separation := 0.45
var _rest_ticks := 2
var _waypoint_radius := 0.35
var _arrive_radius := 0.08
var _slowdown_distance := 0.35
var _crowd_stuck_time := 0.6
var _crowd_arrive_distance := 1.1
var _repath_stuck_time := 2.5
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
	_separation_gain = float(_cfg.get("separation_strength", 5.0))
	_moving_separation = float(_cfg.get("moving_separation_factor", 0.45))
	_rest_ticks = int(_cfg.get("rest_ticks", 2))
	_waypoint_radius = float(_cfg.get("waypoint_radius", 0.35))
	_arrive_radius = float(_cfg.get("arrive_radius", 0.08))
	_slowdown_distance = float(_cfg.get("slowdown_distance", 0.35))
	_crowd_stuck_time = float(_cfg.get("crowd_stuck_time", 0.6))
	_crowd_arrive_distance = float(_cfg.get("crowd_arrive_distance", 1.1))
	_repath_stuck_time = float(_cfg.get("repath_stuck_time", 2.5))
	_sep_cols = ceili(map.width / SEPARATION_CELL) + 1
	_sep_rows = ceili(map.height / SEPARATION_CELL) + 1
	_sep_head.resize(_sep_cols * _sep_rows)


func register(u: Unit) -> void:
	units.append(u)
	if u.def.has("animal"):
		animals.append(u)
	if u.loiter:
		loiterers.append(u)
	_spatial_fresh = false


func unregister(u: Unit) -> void:
	units.erase(u)
	if u.def.has("animal"):
		animals.erase(u)
	if u.loiter:
		loiterers.erase(u)
	_spatial_fresh = false


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
				u.order_path(PackedVector2Array([clamp_to_map(r["dest"])]))
			else:
				u.order_path(_pf(u).find_path(u.grid_pos, r["dest"], u.owner_id))


## Units whose grid position is within `radius` of `pos`.
func units_near(pos: Vector2, radius: float, out: Array) -> void:
	if not _spatial_fresh:
		_spatial_fresh = true
		spatial.clear()
		for u in units:
			if not u.dead and u.aboard == null:
				spatial.insert(u, u.grid_pos)
	spatial.query(pos, radius, out)


func _physics_process(delta: float) -> void:
	_spatial_fresh = false  # refilled by the first query of this tick
	if not simulate:
		return
	_serve_paths()
	_build_separation()
	for i in _active.size():
		_step(_active[i], i, delta)


## Fills the separation grid with every unit on the map.
func _build_separation() -> void:
	_active.clear()
	var n := units.size()
	if _sep_next.size() < n:
		_sep_next.resize(n)
		_sep_pos.resize(n)
		_sep_radius.resize(n)
		_sep_air.resize(n)
	_sep_head.fill(-1)
	_sep_max_radius = 0.0
	var i := 0
	for u in units:
		if u.dead or u.aboard != null:
			continue
		var g := u.grid_pos
		var r := u.radius
		_active.append(u)
		_sep_pos[i] = g
		_sep_radius[i] = r
		_sep_air[i] = 1 if u.altitude > 0.0 else 0
		_sep_max_radius = maxf(_sep_max_radius, r)
		var cell := clampi(floori(g.y / SEPARATION_CELL), 0, _sep_rows - 1) * _sep_cols + clampi(floori(g.x / SEPARATION_CELL), 0, _sep_cols - 1)
		_sep_next[i] = _sep_head[cell]
		_sep_head[cell] = i
		i += 1


## Push away from every overlapping unit; air and ground never push each other.
func _separation(i: int, entity_id: int) -> Vector2:
	var pos := _sep_pos
	var radius := _sep_radius
	var air := _sep_air
	var head := _sep_head
	var next := _sep_next
	var p := pos[i]
	var r := radius[i]
	var layer := air[i]
	var reach := r + _sep_max_radius
	var x0 := clampi(floori((p.x - reach) / SEPARATION_CELL), 0, _sep_cols - 1)
	var x1 := clampi(floori((p.x + reach) / SEPARATION_CELL), 0, _sep_cols - 1)
	var y0 := clampi(floori((p.y - reach) / SEPARATION_CELL), 0, _sep_rows - 1)
	var y1 := clampi(floori((p.y + reach) / SEPARATION_CELL), 0, _sep_rows - 1)
	var push := Vector2.ZERO
	for y in range(y0, y1 + 1):
		var row := y * _sep_cols
		for x in range(x0, x1 + 1):
			var j := head[row + x]
			while j >= 0:
				if j != i and air[j] == layer:
					var d := p - pos[j]
					var min_d := r + radius[j]
					var l2 := d.length_squared()
					if l2 < min_d * min_d:
						var l := sqrt(l2)
						if l < 0.0001:
							d = Vector2.RIGHT.rotated(float(entity_id) * 2.399)
							l = 1.0
						push += d / l * (min_d - l)
				j = next[j]
	return push


func _process(delta: float) -> void:
	var view := _view_rect()
	for u in units:
		u.animate(delta, u.visible and view.has_point(u.position))
	if corpses.is_empty():
		return
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


## The visible world, plus a margin for sprites whose feet are just outside it.
func _view_rect() -> Rect2:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var a: Vector2 = inv * Vector2.ZERO
	var c: Vector2 = inv * get_viewport().get_visible_rect().size
	return Rect2(a, c - a).grow(VIEW_MARGIN)


func _step(u: Unit, i: int, delta: float) -> void:
	if u.rest_ticks > 0 and u.state == Unit.State.IDLE:
		# Standing with nobody touching it: it looks again every few ticks.
		u.rest_ticks -= 1
		u.play(_pick_anim(u))
		return
	var desired := Vector2.ZERO
	if u.state == Unit.State.MOVING and not u.path_pending:
		desired = _follow_path(u, delta)
	if u.loiter and u.altitude > 0.0:
		# Planes never hang still: between two legs they hold their last heading.
		if desired == Vector2.ZERO:
			desired = u.cruise
		else:
			u.cruise = desired

	# Separation: push overlapping units apart; moving units yield less.
	var push := _separation(i, u.entity_id)
	var sep_gain := _separation_gain
	if u.state == Unit.State.MOVING:
		sep_gain *= _moving_separation
	var vel := desired + push * sep_gain
	u.velocity = vel
	if vel.length_squared() > 0.000001:
		if u.altitude > 0.0:
			u.glide_to(clamp_to_map(u.grid_pos + vel * delta))
		else:
			u.glide_to(_slide(u.grid_pos, u.grid_pos + vel * delta, u.owner_id, _pf(u)))
		_sep_pos[i] = u.grid_pos
	elif u.state == Unit.State.IDLE:
		u.rest_ticks = _rest_ticks + u.entity_id % (_rest_ticks + 1)
	# Aircraft always nose along their flight line, even mid-attack.
	if desired.length_squared() > 0.0001 and (u.anim_lock <= 0.0 or u.altitude > 0.0):
		u.face(Iso.direction_index(desired))
	u.play(_pick_anim(u))


func _follow_path(u: Unit, delta: float) -> Vector2:
	var last := u.path_index >= u.path.size() - 1
	var target := u.path[u.path_index]
	var to := target - u.grid_pos
	var dist := to.length()
	var reach := _arrive_radius if last and u.altitude <= 0.0 else _waypoint_radius
	if dist <= reach:
		u.path_index += 1
		if u.path_index >= u.path.size():
			u.stop()
			return Vector2.ZERO
		target = u.path[u.path_index]
		to = target - u.grid_pos
		dist = to.length()
		last = u.path_index >= u.path.size() - 1
	if u.altitude > 0.0:
		# Aircraft never get stuck and keep full speed into the next leg.
		return to / maxf(dist, 0.0001) * u.speed * u.air_speed_factor
	# Progress tracking towards the final destination for crowd/stuck handling.
	var final_dist := u.grid_pos.distance_to(u.final_destination())
	if final_dist < u.last_progress_dist - 0.03:
		u.last_progress_dist = final_dist
		u.stuck_time = 0.0
	else:
		u.stuck_time += delta
	if u.stuck_time > _crowd_stuck_time and final_dist < _crowd_arrive_distance:
		u.stop()
		return Vector2.ZERO
	if u.stuck_time > _repath_stuck_time:
		request_path(u, u.final_destination())
		return Vector2.ZERO
	var spd := u.speed
	if last and dist < _slowdown_distance:
		spd *= maxf(0.35, dist / _slowdown_distance)
	return to / maxf(dist, 0.0001) * spd


## Moves towards `to` but never into an unwalkable tile (slides along walls).
func clamp_to_map(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.5, _map.width - 0.5), clampf(p.y, 0.5, _map.height - 0.5))


func _pf(u: Unit) -> Pathfinder:
	return _naval if u.naval else _pathfinder


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

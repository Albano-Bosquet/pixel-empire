class_name AirSystem
extends Node
## Aircraft (Industrial Age): ammunition, rearming, attack runs and loitering.
## Flight itself is handled by UnitSystem (aircraft get straight paths and
## ignore terrain); CombatSystem spends ammo and keeps melee off aircraft.
## Data: units_stats.json ("air", "altitude", "ammo", "rearm_seconds", "loiter"),
## buildings_stats.json ("rearms_air"), combat_settings.json "air".
##
## Plane state (entity_id -> {"plane", "phase", "timer", "post"}):
##   armed --(ammo reaches 0)--> to_base: fly to the nearest own airfield
##   to_base --(within rearm_reach)--> rearming: circle the field rearm_seconds
##   rearming --> armed (full ammo), fly back to the post it left
##   (no airfield: the plane circles where it is, unable to attack, until one exists)
##
## Planes with "loiter" never hang still. Idle ones circle their post. Engaged
## ones fly attack runs (entity_id -> {"phase", "point", "radius", "ordered"}):
##   dive --(passes over the target)--> lap: climb away on a circle that
##     comes back over the target --(back over it)--> lap again
##   lap --(target moved off the circle)--> dive straight at it again
## The sprite drops towards its shadow and speeds up as it closes on the target
## (the dive) and climbs back to cruise altitude on the far side of the lap.
## Example:
##   game.air.out_of_ammo(plane)   # called by CombatSystem after the last shot
##   game.air.attack_run(plane, target_point, plane.attack_range())  # every tick

var _game: Game
var _cfg: Dictionary
var _state: Dictionary = {}
var _loiter: Dictionary = {}  # entity_id -> Vector2 circle centre
var _runs: Dictionary = {}  # entity_id -> attack run (see header)


func setup(game: Game, air_cfg: Dictionary) -> void:
	_game = game
	_cfg = air_cfg


static func is_air(e: Entity) -> bool:
	return e is Unit and bool(e.def.get("air", false))


## True while `u` has shots left (units without "ammo" always do).
static func armed(u: Unit) -> bool:
	return u.ammo != 0


func out_of_ammo(u: Unit) -> void:
	var post := u.guard_pos if u.guard_pos != Vector2.INF else u.grid_pos
	_state[u.entity_id] = {"plane": u, "phase": "to_base", "timer": 0.0, "post": post}
	u.target = null
	_head_home(u)


func phase(u: Unit) -> String:
	return String(_state.get(u.entity_id, {}).get("phase", "armed"))


## Current attack-run phase of `u` ("dive", "lap", or "" when not attacking).
func run_phase(u: Unit) -> String:
	return String(_runs.get(u.entity_id, {}).get("phase", ""))


func _airfield(pid: int, from: Vector2) -> Building:
	var best: Building = null
	var best_d := INF
	for b in _game.buildings.buildings:
		if b.owner_id == pid and b.is_complete() and not b.dead and b.def.get("rearms_air", false):
			var d := b.grid_pos.distance_to(from)
			if d < best_d:
				best_d = d
				best = b
	return best


func _head_home(u: Unit) -> void:
	var base := _airfield(u.owner_id, u.grid_pos)
	if base != null:
		_game.unit_system.request_path(u, base.grid_pos)


func _physics_process(delta: float) -> void:
	var circle := float(_cfg.get("loiter_radius", 1.1))
	for id in _state.keys():
		var s: Dictionary = _state[id]
		var u: Unit = Iso.alive(s["plane"])
		if u == null or u.dead:
			_state.erase(id)
			continue
		match String(s["phase"]):
			"to_base":
				var base := _airfield(u.owner_id, u.grid_pos)
				if base == null:
					if u.state == Unit.State.IDLE:
						if not s.has("hold"):
							s["hold"] = u.grid_pos
						orbit(u, s["hold"], circle)
					continue
				if u.grid_pos.distance_to(base.grid_pos) <= float(_cfg.get("rearm_reach", 1.6)) + base.size * 0.5:
					s["phase"] = "rearming"
					s["timer"] = float(u.def.get("rearm_seconds", 8.0))
					s["base"] = base.grid_pos
					orbit(u, base.grid_pos, circle)
				elif u.state == Unit.State.IDLE:
					_game.unit_system.request_path(u, base.grid_pos)
			"rearming":
				if u.state == Unit.State.IDLE:
					orbit(u, s["base"], circle)
				s["timer"] = float(s["timer"]) - delta
				if s["timer"] <= 0.0:
					u.ammo = int(u.def.get("ammo", -1))
					_state.erase(id)
					u.guard_pos = s["post"]
					_game.unit_system.request_path(u, s["post"])
	_loiter_idle()
	_shape_flight(delta)


## Idle armed planes fly small circles around where they stopped.
func _loiter_idle() -> void:
	for u in _game.unit_system.loiterers:
		if u.dead or _state.has(u.entity_id) or u.has_target():
			continue
		if u.state != Unit.State.IDLE:
			continue
		var r := float(_cfg.get("loiter_radius", 1.1))
		var post: Vector2 = _loiter.get(u.entity_id, Vector2.INF)
		if post == Vector2.INF or post.distance_to(u.grid_pos) > r * 2.5:
			post = u.grid_pos
			_loiter[u.entity_id] = post
		orbit(u, post, r)


## Flies `u` round `center` at `radius` (counter-clockwise), continuing from
## where it is now: one full loop of waypoints so it never slows mid-circle.
func orbit(u: Unit, center: Vector2, radius: float) -> void:
	var angle := (u.grid_pos - center).angle() if u.grid_pos.distance_to(center) > 0.05 else 0.0
	u.order_path(_circle(center, radius, angle))


## Keeps an engaged plane on its attack runs over `point` (see header); called
## by CombatSystem every tick while `u` fights. `attack_range` sizes the lap.
func attack_run(u: Unit, point: Vector2, attack_range: float) -> void:
	var radius := lap_radius(attack_range)
	var run: Dictionary = _runs.get(u.entity_id, {})
	if run.is_empty():
		run = {"phase": "dive", "point": point, "radius": radius, "ordered": Vector2.INF}
		_runs[u.entity_id] = run
	run["radius"] = radius
	var pass_r := float(_cfg.get("pass_radius", 0.45))
	if run["phase"] == "lap":
		if run["point"].distance_to(point) > radius * 0.5:
			run["phase"] = "dive"
			run["ordered"] = Vector2.INF
		elif u.state != Unit.State.MOVING:
			if u.grid_pos.distance_to(point) <= pass_r * 2.0:
				_start_lap(u, run, point)
			else:
				run["phase"] = "dive"
				run["ordered"] = Vector2.INF
	if run["phase"] == "dive":
		run["point"] = point
		if u.grid_pos.distance_to(point) <= pass_r:
			_start_lap(u, run, point)
		elif u.state != Unit.State.MOVING or run["ordered"].distance_to(point) > 0.3:
			# Straight at the target and on past it, so the plane never brakes.
			var dir := (point - u.grid_pos).normalized()
			run["ordered"] = point
			u.order_path(PackedVector2Array([point, _game.unit_system.clamp_to_map(point + dir * radius)]))


## True when the plane's nose points at `point` (or it is right over it):
## planes only fire forwards, on the diving half of a run.
func nose_on(u: Unit, point: Vector2) -> bool:
	var to := point - u.grid_pos
	if to.length() <= float(_cfg.get("overhead_radius", 0.6)) or u.velocity.length_squared() < 0.0001:
		return true
	return u.velocity.normalized().dot(to.normalized()) >= float(_cfg.get("fire_cone_cos", 0.5))


## Radius of the climbing lap for a plane attacking from `attack_range`.
func lap_radius(attack_range: float) -> float:
	return clampf(attack_range * float(_cfg.get("lap_radius_factor", 0.8)),
			float(_cfg.get("lap_radius_min", 1.6)), float(_cfg.get("lap_radius_max", 3.0)))


## A full circle that starts over `point` along the current heading and comes
## back over it: the climb out of the dive and the turn into the next pass.
func _start_lap(u: Unit, run: Dictionary, point: Vector2) -> void:
	var dir := u.velocity.normalized() if u.velocity.length_squared() > 0.0001 else (point - u.grid_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var radius: float = run["radius"]
	var n := Vector2(dir.y, -dir.x)  # centre -> point; the circle's tangent there is `dir`
	run["phase"] = "lap"
	run["point"] = point
	u.order_path(_circle(point - n * radius, radius, n.angle()))


## Waypoints of one full counter-clockwise loop that ends back at `start_angle`.
func _circle(center: Vector2, radius: float, start_angle: float) -> PackedVector2Array:
	var steps := maxi(3, int(_cfg.get("orbit_waypoints", 12)))
	var path := PackedVector2Array()
	var angle := start_angle
	for k in steps:
		angle += TAU / steps
		path.append(_game.unit_system.clamp_to_map(center + Vector2(cos(angle), sin(angle)) * radius))
	return path


## Dive and climb: engaged planes drop towards their shadow and speed up as
## they close on the target, then climb back slower on the far side of the lap.
func _shape_flight(delta: float) -> void:
	var depth := float(_cfg.get("dive_depth", 0.45))
	var rate := float(_cfg.get("dive_rate", 40.0))
	for u in _game.unit_system.loiterers:
		if u.dead or u.altitude <= 0.0:
			continue
		if _runs.has(u.entity_id) and (not u.has_target() or _state.has(u.entity_id)):
			_runs.erase(u.entity_id)
		var want_dip := 0.0
		var want_speed := 1.0
		var run: Dictionary = _runs.get(u.entity_id, {})
		if not run.is_empty():
			var to: Vector2 = run["point"] - u.grid_pos
			var reach := float(run["radius"]) * float(_cfg.get("dive_reach_factor", 1.3))
			var near := 1.0 - smoothstep(0.0, reach, to.length())
			want_dip = u.altitude * depth * near
			if near > 0.0 and u.velocity.length_squared() > 0.0001 and to.length_squared() > 0.0001:
				var closing := u.velocity.normalized().dot(to.normalized()) > 0.0
				want_speed = lerpf(1.0, float(_cfg.get("dive_speed" if closing else "climb_speed", 1.0)), near)
		u.flight_dip = move_toward(u.flight_dip, want_dip, rate * delta)
		u.air_speed_factor = move_toward(u.air_speed_factor, want_speed, delta)

class_name AirSystem
extends Node
## Aircraft (Industrial Age): ammunition, rearming and loitering.
## Flight itself is handled by UnitSystem (aircraft get straight paths and
## ignore terrain); CombatSystem spends ammo and keeps melee off aircraft.
## Data: units_stats.json ("air", "altitude", "ammo", "rearm_seconds", "loiter"),
## buildings_stats.json ("rearms_air"), combat_settings.json "air".
##
## Plane state (entity_id -> {"plane", "phase", "timer", "post"}):
##   armed --(ammo reaches 0)--> to_base: fly to the nearest own airfield
##   to_base --(within rearm_reach)--> rearming: wait rearm_seconds
##   rearming --> armed (full ammo), fly back to the post it left
##   (no airfield: the plane stays where it is, unable to attack, until one exists)
## Idle armed planes with "loiter" circle their post so they never hang still.
## Example:
##   game.air.out_of_ammo(plane)   # called by CombatSystem after the last shot

var _game: Game
var _cfg: Dictionary
var _state: Dictionary = {}
var _loiter: Dictionary = {}


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
					continue
				if u.grid_pos.distance_to(base.grid_pos) <= float(_cfg.get("rearm_reach", 1.6)) + base.size * 0.5:
					u.stop()
					s["phase"] = "rearming"
					s["timer"] = float(u.def.get("rearm_seconds", 8.0))
				elif u.state == Unit.State.IDLE:
					_game.unit_system.request_path(u, base.grid_pos)
			"rearming":
				s["timer"] = float(s["timer"]) - delta
				if s["timer"] <= 0.0:
					u.ammo = int(u.def.get("ammo", -1))
					_state.erase(id)
					u.guard_pos = s["post"]
					_game.unit_system.request_path(u, s["post"])
	_loiter_idle(delta)


## Idle armed planes fly small circles around where they stopped.
func _loiter_idle(delta: float) -> void:
	for u in _game.unit_system.units:
		if u.dead or not u.def.get("loiter", false) or _state.has(u.entity_id) or u.has_target():
			continue
		if u.state != Unit.State.IDLE:
			continue
		var l: Dictionary = _loiter.get(u.entity_id, {})
		if l.is_empty() or l["post"].distance_to(u.grid_pos) > float(_cfg.get("loiter_radius", 1.1)) * 2.5:
			l = {"post": u.grid_pos, "angle": 0.0}
		l["angle"] = float(l["angle"]) + float(_cfg.get("loiter_step", 0.9))
		_loiter[u.entity_id] = l
		var r := float(_cfg.get("loiter_radius", 1.1))
		var p: Vector2 = l["post"] + Vector2(cos(l["angle"]), sin(l["angle"])) * r
		u.order_path(PackedVector2Array([p]))

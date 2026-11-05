class_name AmbientLife
extends Node2D
## Cosmetic life over the map (Phase 6; ambience_settings.json): bird flocks
## crossing the sky with their shadows on the ground (gulls over water),
## drifting cloud shadows and butterflies by day, fireflies near trees at
## night. Everything is drawn here as simple shapes, only around the camera,
## and only on tiles the local player can see.

var _game: Game
var _cfg: Dictionary
var _day_night: DayNight
var _rng := RandomNumberGenerator.new()
var _flocks: Array[Dictionary] = []
var _flock_timer := 3.0
var _clouds: Array[Dictionary] = []
var _flies: Array[Dictionary] = []     # butterflies (day) and fireflies (night)
var _t := 0.0


func setup(game: Game, cfg: Dictionary, day_night: DayNight) -> void:
	_game = game
	_cfg = cfg
	_day_night = day_night
	_rng.seed = game.map.seed + 991
	z_index = 60
	var c: Dictionary = cfg.get("clouds", {})
	for i in int(c.get("count", 5)):
		_clouds.append(_new_cloud(true))


func _view() -> Rect2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)


func _new_cloud(anywhere: bool) -> Dictionary:
	var c: Dictionary = _cfg.get("clouds", {})
	var size: Array = c.get("size", [120.0, 260.0])
	var r := _view()
	var p := r.position + Vector2(_rng.randf() * r.size.x, _rng.randf() * r.size.y)
	if not anywhere:
		p.x = r.position.x - float(size[1])
	return {"p": p, "w": _rng.randf_range(float(size[0]), float(size[1])), "k": _rng.randf_range(0.4, 0.7)}


func _process(delta: float) -> void:
	if _game == null:
		return
	_t += delta
	var night := _day_night.night_amount() if _day_night != null else 0.0
	var view := _view()
	# Birds.
	var b: Dictionary = _cfg.get("birds", {})
	_flock_timer -= delta
	if _flock_timer <= 0.0 and night < 0.5:
		var span: Array = b.get("flock_interval", [8.0, 20.0])
		_flock_timer = _rng.randf_range(float(span[0]), float(span[1]))
		if _flocks.size() < int(b.get("max_flocks", 3)):
			_flocks.append(_new_flock(view, b))
	for f in _flocks:
		f["p"] += f["v"] * delta
	_flocks = _flocks.filter(func(f): return view.grow(400.0).has_point(f["p"]))
	# Clouds drift with the wind and wrap around the view.
	var cs := float(_cfg.get("clouds", {}).get("speed", 8.0))
	for i in _clouds.size():
		_clouds[i]["p"] += Vector2(cs, cs * 0.25) * delta
		if not view.grow(320.0).has_point(_clouds[i]["p"]):
			_clouds[i] = _new_cloud(false)
	_update_flies(view, night, delta)
	queue_redraw()


func _new_flock(view: Rect2, b: Dictionary) -> Dictionary:
	var from_left := _rng.randf() < 0.5
	var y := view.position.y + _rng.randf_range(0.1, 0.9) * view.size.y
	var start := Vector2(view.position.x - 80.0 if from_left else view.end.x + 80.0, y)
	var speed := _rng.randf_range(float(b.get("speed", [38.0, 60.0])[0]), float(b.get("speed", [38.0, 60.0])[1]))
	var dir := Vector2(1.0 if from_left else -1.0, _rng.randf_range(-0.25, 0.25)).normalized()
	var size: Array = b.get("flock_size", [3, 9])
	var n := _rng.randi_range(int(size[0]), int(size[1]))
	var members := []
	for i in n:
		var row := (i + 1) / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		members.append({"o": -dir * row * 9.0 + Vector2(-dir.y, dir.x) * side * row * 7.0 + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2)), "ph": _rng.randf() * TAU})
	var t := Iso.tile_of(Iso.world_to_grid(start + dir * view.size.x * 0.5))
	var gull := _game.map.in_bounds(t) and _game.map.get_terrain(t) in [MapData.Terrain.WATER, MapData.Terrain.DEEP_WATER]
	var alt: Array = b.get("altitude", [40.0, 70.0])
	return {"p": start, "v": dir * speed, "m": members, "alt": _rng.randf_range(float(alt[0]), float(alt[1])), "gull": gull}


func _update_flies(view: Rect2, night: float, delta: float) -> void:
	var want_fire := night > 0.5
	var target := int(_cfg.get("fireflies", {}).get("count", 26)) if want_fire else int(_cfg.get("butterflies", {}).get("count", 10))
	_flies = _flies.filter(func(f): return f["fire"] == want_fire and view.grow(60.0).has_point(f["p"]))
	var tries := 0
	while _flies.size() < target and tries < 30:
		tries += 1
		var p := view.position + Vector2(_rng.randf() * view.size.x, _rng.randf() * view.size.y)
		var t := Iso.tile_of(Iso.world_to_grid(p))
		if not _game.map.in_bounds(t) or not _game.fog.is_tile_visible(_game.local_player, t):
			continue
		var ter := _game.map.get_terrain(t)
		if want_fire and not (ter == MapData.Terrain.FOREST or _game.static_entity_at(t) is ResourceNode):
			continue
		if not want_fire and not ter in [MapData.Terrain.GRASS, MapData.Terrain.MEADOW]:
			continue
		var cols := [Color("#f5e05a"), Color("#f08ac0"), Color("#9ad0ff"), Color("#ffffff")]
		_flies.append({"p": p, "home": p, "ph": _rng.randf() * TAU, "fire": want_fire, "c": cols[_rng.randi() % cols.size()]})
	var sp := float(_cfg.get("butterflies", {}).get("speed", 14.0))
	for f in _flies:
		f["ph"] += delta * (1.3 if f["fire"] else 2.0)
		f["p"] = f["home"] + Vector2(sin(f["ph"] * 0.7) * 14.0, cos(f["ph"] * 0.9) * 8.0) + Vector2(sin(_t * 0.3 + f["ph"]) * sp, 0.0)


func _draw() -> void:
	var night := _day_night.night_amount() if _day_night != null else 0.0
	var day := 1.0 - night
	# Cloud shadows (soft, layered ellipses).
	var ca := float(_cfg.get("clouds", {}).get("alpha", 0.1)) * day
	if ca > 0.005:
		for c in _clouds:
			for k in 3:
				var w: float = c["w"] * (1.0 - k * 0.22)
				_ellipse(c["p"] + Vector2(k * 14.0, k * 3.0), w * 0.5, w * 0.5 * float(c["k"]) * 0.5, Color(0.05, 0.08, 0.12, ca * 0.45))
	# Butterflies / fireflies.
	for f in _flies:
		var p: Vector2 = f["p"]
		if not _seen(p):
			continue
		if f["fire"]:
			var glow := (0.5 + 0.5 * sin(f["ph"] * 3.0)) * night
			draw_circle(p, 2.5, Color(1.0, 0.95, 0.4, 0.18 * glow))
			draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(1.0, 1.0, 0.6, glow))
		else:
			var flap := absf(sin(f["ph"] * 9.0))
			var col: Color = f["c"]
			draw_rect(Rect2(p.round() + Vector2(-1.0 - flap, 0), Vector2(1, 1)), col)
			draw_rect(Rect2(p.round() + Vector2(1.0 + flap, 0), Vector2(1, 1)), col)
	# Birds and their ground shadows.
	for fl in _flocks:
		for m in fl["m"]:
			var bp: Vector2 = fl["p"] + m["o"]
			var shadow := bp + Vector2(fl["alt"] * 0.25, fl["alt"])
			if _seen(shadow):
				_ellipse(shadow, 2.5, 1.0, Color(0, 0, 0, 0.18 * day))
			if not _seen(bp):
				continue
			var wing := sin(_t * 9.0 + float(m["ph"])) * 2.0
			var col2 := Color("#f4f4f0") if fl["gull"] else Color("#2a2622")
			draw_line(bp + Vector2(-4, wing), bp, col2, 1.0)
			draw_line(bp, bp + Vector2(4, wing), col2, 1.0)


## Whether the local player sees the map at world point `p`. This layer is drawn
## above the fog, so anything it draws elsewhere would show over the dark.
func _seen(p: Vector2) -> bool:
	return _game.fog.is_tile_visible(_game.local_player, Iso.tile_of(Iso.world_to_grid(p)))


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * i / 18.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

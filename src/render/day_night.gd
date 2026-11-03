class_name DayNight
extends Node
## Day/night cycle (Phase 6; ambience_settings.json). Purely cosmetic: it
## tints the world with a CanvasModulate following `tint_keys`, and at night
## lights windows and torches of the buildings the local player can see on a
## glow layer drawn above the world (additive, untouched by the tint).
## GameAudio reads night_amount() for crickets, owls and the dawn bell.
## `time` is the fraction of the day (0 = midnight, 0.5 = noon).

var time := 0.3
var enabled := true

var _game: Game
var _cfg: Dictionary
var _modulate: CanvasModulate
var _glow_layer: CanvasLayer
var _glow: GlowDraw


func setup(game: Game, cfg: Dictionary, on: bool) -> void:
	_game = game
	_cfg = cfg
	enabled = on
	time = float(cfg.get("start_time", 0.3))
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_modulate = CanvasModulate.new()
	_modulate.name = "DayTint"
	game.add_child(_modulate)
	_glow_layer = CanvasLayer.new()
	_glow_layer.name = "Glow"
	_glow_layer.layer = 1
	_glow_layer.follow_viewport_enabled = true
	game.add_child(_glow_layer)
	_glow = GlowDraw.new()
	_glow.game = game
	_glow.lights = cfg.get("lights", {})
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow_layer.add_child(_glow)
	_apply()


func _process(delta: float) -> void:
	if not enabled:
		return
	time = fmod(time + delta / maxf(1.0, float(_cfg.get("day_minutes", 12.0)) * 60.0), 1.0)
	_apply()


## Darkness 0 (day) .. 1 (deep night), with soft edges at dusk and dawn.
func night_amount() -> float:
	if not enabled:
		return 0.0
	return night_at(time, _cfg)


## Night amount at a time of day (static so tests can check the curve).
static func night_at(t: float, cfg: Dictionary) -> float:
	var fade := float(cfg.get("night_fade", 0.04))
	var best := 0.0
	for r in cfg.get("night_ranges", []):
		var a := float(r[0])
		var b := float(r[1])
		var v := 0.0
		if t >= a and t <= b:
			v = 1.0
			if a > 0.0:
				v = minf(v, (t - a) / fade)
			if b < 1.0:
				v = minf(v, (b - t) / fade)
		best = maxf(best, clampf(v, 0.0, 1.0))
	return best


## World tint at a time of day (keys are [time, "#hex"], interpolated).
static func tint_at(t: float, cfg: Dictionary) -> Color:
	var keys: Array = cfg.get("tint_keys", [[0.0, "#ffffff"], [1.0, "#ffffff"]])
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var f := (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return Color(String(a[1])).lerp(Color(String(b[1])), f)
	return Color(String(keys[-1][1]))


func _apply() -> void:
	_modulate.color = tint_at(time, _cfg) if enabled else Color.WHITE
	_glow.night = night_amount()
	_glow.queue_redraw()


## Additive light pools for buildings at night.
class GlowDraw:
	extends Node2D
	var game: Game
	var lights: Dictionary = {}
	var night := 0.0
	var _t := 0.0
	var _soft: GradientTexture2D


	func _ready() -> void:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.35))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64


	## Soft light pool: a radial gradient squashed to the isometric ground plane.
	func _pool(c: Vector2, r: float, col: Color, flat: float = 0.5) -> void:
		draw_texture_rect(_soft, Rect2(c - Vector2(r, r * flat), Vector2(r * 2.0, r * 2.0 * flat)), false, col)

	func _process(delta: float) -> void:
		_t += delta
		if night > 0.01:
			queue_redraw()

	func _draw() -> void:
		if night <= 0.01 or game == null:
			return
		var vp := get_viewport()
		var view := vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
		view = view.grow(80.0)
		var def: Dictionary = lights.get("default", {})
		var by: Dictionary = lights.get("by_building", {})
		for b in game.buildings.buildings:
			if b.dead or not b.visible or not b.is_complete() or not view.has_point(b.position):
				continue
			var l: Dictionary = def.duplicate()
			l.merge(by.get(b.type_id, {}), true)
			var r := float(l.get("radius", 24))
			if r <= 0.0:
				continue
			var flicker := 0.93 + 0.07 * sin(_t * 6.0 + b.entity_id) * sin(_t * 2.3 + b.entity_id * 0.7)
			var col := Color(String(l.get("color", "#ffb45a")))
			var e := float(l.get("energy", 0.5)) * night * flicker
			# Warm pool on the ground in front of the doors and a faint haze on the walls.
			_pool(b.position + Vector2(0, b.size * 6.0), r * 1.1, Color(col, e * 0.55), 0.5)
			_pool(b.position + Vector2(0, b.visual_top() * 0.25), r * 0.55, Color(col, e * 0.35), 0.8)
			if b.is_burning():
				_pool(b.position + Vector2(0, b.visual_top() * 0.4), r, Color(1.0, 0.45, 0.15, 0.45 * night), 0.8)
		# Villagers carry a small lantern.
		for u in game.unit_system.units:
			if u.owner_id == game.local_player and not u.dead and u.visible and view.has_point(u.position) and u.is_worker:
				_pool(u.position + Vector2(0, -4), 14.0, Color(1.0, 0.75, 0.4, 0.22 * night), 0.6)

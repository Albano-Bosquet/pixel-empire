class_name OcclusionXray
extends Node
## Shows units, dying bodies and carcasses hidden behind buildings as flat
## team-coloured silhouettes drawn over the building that covers them (only
## where it covers them: Building.set_xray clips to the building sprite).
## Config: render_sprites.json "xray" {alpha, lighten, neutral_color}.

const SHADER := preload("res://assets/shaders/xray.gdshader")
## World pixels from a body's feet to the far edge of its sprite, with room to spare.
const REACH := 160.0

var _game: Game
var _cfg: Dictionary
var _material := ShaderMaterial.new()
## Buildings that showed silhouettes last frame (cleared when nothing is behind them).
var _shown: Dictionary = {}
## Base tint per colour slot (-1 = neutral), parsed once.
var _tints: Dictionary = {}
## On-screen building sprites, grown by REACH: bodies elsewhere are skipped cheaply.
var _covers: Array[Rect2] = []


func setup(game: Game, cfg: Dictionary) -> void:
	_game = game
	_cfg = cfg
	_material.shader = SHADER


func _process(_delta: float) -> void:
	var view := _view_rect()
	_covers.clear()
	for b in _game.buildings.buildings:
		var cover := b.body_rect()
		if cover.size != Vector2.ZERO and view.intersects(cover):
			_covers.append(cover.grow(REACH))
	var bodies := _bodies(view)
	var now: Dictionary = {}
	if not bodies.is_empty():
		for b in _game.buildings.buildings:
			if b.dead or b.z_index != 0 or not b.is_visible_in_tree():
				continue
			var rect := b.body_rect()
			if rect.size == Vector2.ZERO or not view.intersects(rect):
				continue
			var items := []
			for body in bodies:
				# Drawn before the building (y-sort) and overlapping its sprite.
				if body["y"] < b.position.y and rect.intersects(body["rect"]):
					if not body.has("tint"):
						body["tint"] = _tint(body["entity"])
					items.append(body)
			if not items.is_empty():
				b.set_xray(items, _material)
				now[b] = true
	for b in _shown:
		if not now.has(b) and is_instance_valid(b):
			b.set_xray([], _material)
	_shown = now


func _view_rect() -> Rect2:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var size := get_viewport().get_visible_rect().size
	var a: Vector2 = inv * Vector2.ZERO
	var c: Vector2 = inv * size
	return Rect2(a, c - a)


## Every visible ground body on screen: {"sprite", "at", "entity", "y", "rect"};
## "tint" is added when a building turns out to cover it.
func _bodies(view: Rect2) -> Array:
	var out := []
	for u in _game.unit_system.units:
		if not u.dead and u.aboard == null and u.altitude <= 0.0:
			_add(out, u, view)
	for c in _game.unit_system.corpses:
		var cu: Variant = c["unit"]
		if is_instance_valid(cu) and (cu as Unit).z_index == 0:
			_add(out, cu, view)
	_game.carcasses = _game.carcasses.filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
	for n in _game.carcasses:
		_add(out, n, view)
	return out


func _add(out: Array, e: Entity, view: Rect2) -> void:
	var feet := e.position
	var covered := false
	for cover in _covers:
		if cover.has_point(feet):
			covered = true
			break
	if not covered or not e.visible or e.modulate.a < 0.05:
		return
	var sp: Sprite2D = e.body_sprite()
	var rect := Rect2(e.position + sp.position + sp.offset, _frame_size(sp))
	if not view.intersects(rect):
		return
	out.append({"sprite": sp, "at": e.position, "entity": e, "y": e.position.y, "rect": rect})


static func _frame_size(sp: Sprite2D) -> Vector2:
	if sp.region_enabled:
		return sp.region_rect.size
	return sp.texture.get_size() / Vector2(maxi(1, sp.hframes), maxi(1, sp.vframes))


func _tint(e: Entity) -> Color:
	var slot: int = e.color_slot if e is Unit and e.owner_id != Entity.GAIA and not e.def.has("animal") else -1
	if not _tints.has(slot):
		var hex := String(_cfg.get("neutral_color", "#f2e3a0"))
		if slot >= 0:
			hex = String(GameData.player_color(slot).get("primary", "#ffffff"))
		_tints[slot] = Color(hex).lightened(float(_cfg.get("lighten", 0.2)))
	var col: Color = _tints[slot]
	col.a = float(_cfg.get("alpha", 0.6)) * e.modulate.a
	return col

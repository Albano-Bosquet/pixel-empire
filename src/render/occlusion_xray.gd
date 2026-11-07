class_name OcclusionXray
extends Node
## Shows units, dying bodies and carcasses hidden behind buildings, trees and
## rocks as flat team-coloured silhouettes drawn over what covers them (only
## where it covers them). Buildings clip with clip_children (Building.set_xray);
## props are far more numerous, so their silhouettes clip themselves in a shader
## and a per-tile index finds the props in front of a body without a search.
## Config: render_sprites.json "xray" {alpha, lighten, neutral_color, min_prop_height}.

const SHADER := preload("res://assets/shaders/xray.gdshader")
const PROP_SHADER := preload("res://assets/shaders/xray_prop.gdshader")
## World pixels a body's sprite can reach sideways from its feet.
const BODY_HALF_WIDTH := 32.0
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
## Per map tile: props that can cover a body standing there, or null.
var _tile_props: Array = []
## Prop sprite -> Node2D holding its silhouettes.
var _holders: Dictionary = {}
## Prop sprites that showed silhouettes last frame.
var _props_shown: Dictionary = {}


func setup(game: Game, cfg: Dictionary) -> void:
	_game = game
	_cfg = cfg
	_material.shader = SHADER


func _process(_delta: float) -> void:
	if _tile_props.is_empty():
		_index_props()
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
	_update_props(bodies)


## Finds every tall tree, rock and decor sprite once, and lists each under the
## tiles where a body's feet would put it behind that sprite.
func _index_props() -> void:
	_tile_props.resize(_game.map.width * _game.map.height)
	var min_height := float(_cfg.get("min_prop_height", 24.0))
	for c in _game.entities_root.get_children():
		var sp: Sprite2D = null
		if c is ResourceNode:
			if not c.def.get("carcass", false):
				sp = c.body_sprite()
		elif c is Sprite2D:
			sp = c
		if sp != null and sp.region_enabled and sp.region_rect.size.y >= min_height:
			_index_prop(sp, c.position)


func _index_prop(sp: Sprite2D, feet: Vector2) -> void:
	var rect := Rect2(feet + sp.offset, sp.region_rect.size)
	var prop := {"sprite": sp, "feet": feet, "rect": rect}
	# Bodies stand behind the prop's feet and can reach it from a little to each side.
	var area := Rect2(rect.position.x - BODY_HALF_WIDTH, rect.position.y, rect.size.x + BODY_HALF_WIDTH * 2.0, feet.y - rect.position.y)
	var corners := [Iso.world_to_grid(area.position), Iso.world_to_grid(area.end),
		Iso.world_to_grid(Vector2(area.end.x, area.position.y)), Iso.world_to_grid(Vector2(area.position.x, area.end.y))]
	var lo: Vector2 = corners[0]
	var hi: Vector2 = corners[0]
	for g in corners:
		lo = lo.min(g)
		hi = hi.max(g)
	var map: MapData = _game.map
	for y in range(maxi(0, floori(lo.y)), mini(map.height - 1, floori(hi.y)) + 1):
		for x in range(maxi(0, floori(lo.x)), mini(map.width - 1, floori(hi.x)) + 1):
			if not area.grow(Iso.HALF_W).has_point(Iso.grid_to_world(Vector2(x + 0.5, y + 0.5))):
				continue
			var i := y * map.width + x
			if _tile_props[i] == null:
				_tile_props[i] = []
			_tile_props[i].append(prop)


## Silhouettes over the props in front of `bodies`; props left bare are cleared.
func _update_props(bodies: Array) -> void:
	var now: Dictionary = {}
	for body in bodies:
		var props: Variant = body["props"]
		if props == null:
			continue
		# One silhouette per body, over the prop hiding most of it: in a forest a
		# body touches several, and each extra silhouette is one more draw call.
		var hit: Rect2 = body["entity"].global_pick_rect()
		var best: Dictionary = {}
		var best_area := 0.0
		for prop in props:
			if not is_instance_valid(prop["sprite"]) or body["y"] >= prop["feet"].y:
				continue
			var area: float = prop["rect"].intersection(hit).get_area()
			if area > best_area:
				best_area = area
				best = prop
		if best.is_empty():
			continue
		if not body.has("tint"):
			body["tint"] = _tint(body["entity"])
		var sp: Sprite2D = best["sprite"]
		if not now.has(sp):
			now[sp] = {"prop": best, "items": []}
		now[sp]["items"].append(body)
	for sp in now:
		_show_over_prop(sp, now[sp]["prop"], now[sp]["items"])
	for sp in _props_shown:
		if not now.has(sp) and is_instance_valid(sp):
			_holders[sp].visible = false
	_props_shown = now


func _show_over_prop(prop_sprite: Sprite2D, prop: Dictionary, items: Array) -> void:
	var holder: Node2D = _holders.get(prop_sprite)
	if holder == null:
		holder = Node2D.new()
		prop_sprite.add_child(holder)
		_holders[prop_sprite] = holder
	holder.visible = true
	var pool := holder.get_children()
	for i in items.size():
		var sp: Sprite2D
		if i < pool.size():
			sp = pool[i]
		else:
			sp = Sprite2D.new()
			sp.centered = false
			var mat := ShaderMaterial.new()
			mat.shader = PROP_SHADER
			mat.set_shader_parameter("mask_tex", prop_sprite.texture)
			var region := prop_sprite.region_rect
			mat.set_shader_parameter("mask_rect", Vector4(region.position.x, region.position.y, region.size.x, region.size.y))
			sp.material = mat
			holder.add_child(sp)
		var src: Sprite2D = items[i]["sprite"]
		if sp.texture != src.texture:
			sp.texture = src.texture
			sp.region_enabled = src.region_enabled
			sp.region_rect = src.region_rect
			sp.hframes = src.hframes
			sp.vframes = src.vframes
		sp.frame = src.frame
		sp.flip_h = src.flip_h
		sp.offset = src.offset
		sp.position = items[i]["at"] + src.position - prop["feet"]
		sp.modulate = items[i]["tint"]
		sp.visible = true
		sp.material.set_shader_parameter("shift", sp.position - prop_sprite.offset)
	for i in range(items.size(), pool.size()):
		pool[i].visible = false


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
	var tile := e.tile()
	var map: MapData = _game.map
	var props: Variant = _tile_props[tile.y * map.width + tile.x] if map.in_bounds(tile) else null
	var covered := props != null
	if not covered:
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
	out.append({"sprite": sp, "at": e.position, "entity": e, "y": e.position.y, "rect": rect, "props": props})


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

class_name Minimap
extends Control
## Isometric minimap (design/game-brief.md MVP item 1 / UI). One texel per tile,
## drawn through an iso transform so it matches the world's diamond. Terrain
## colours are averaged from the terrain atlas, so they follow the art.
## Shows fog of war, resources, buildings and units (player colours), the
## camera view and flashing "under attack" pings.
## Left click/drag: move the camera. Right click: order selected units there.

const UPDATE_HZ := 4.0
const PING_SECONDS := 3.0
const RESOURCE_COLORS := {"wood": Color("#2c5222"), "gold": Color("#e8c13a"), "stone": Color("#b8bec6"), "food": Color("#c9405a")}

var _game: Game
var _w := 0
var _h := 0
var _base: PackedByteArray  # RGB per tile: terrain + static resources
var _img: Image
var _tex: ImageTexture
var _timer := 0.0
var _pings: Array[Dictionary] = []
var _dragging := false
var _palette: Array[Color] = []


func setup(game: Game) -> void:
	_game = game
	_w = game.map.width
	_h = game.map.height
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_base()
	_img = Image.create_from_data(_w, _h, false, Image.FORMAT_RGB8, _base)
	_tex = ImageTexture.create_from_image(_img)
	EventBus.under_attack.connect(func(pid: int, where: Vector2) -> void:
		if pid == _game.local_player and (_pings.is_empty() or _pings[-1]["pos"].distance_to(where) > 6.0 or _pings[-1]["t"] < PING_SECONDS - 1.0):
			_pings.append({"pos": where, "t": PING_SECONDS}))
	EventBus.entity_removed.connect(func(e: Node) -> void:
		if e is ResourceNode:
			clear_tile(e.tile()))
	_refresh()


## Average colour of each terrain texture in the atlas.
func _terrain_palette() -> Array[Color]:
	var atlas: Image = (load(SpriteLibrary.TERRAIN_ATLAS) as Texture2D).get_image()
	var n: int = GameData.sprites["terrain"]["order"].size()
	var size: int = GameData.sprites["terrain"]["tile_texture_size"]
	var out: Array[Color] = []
	for i in n:
		var acc := Color(0, 0, 0)
		for y in range(0, size, 4):
			for x in range(0, size, 4):
				acc += atlas.get_pixel(i * size + x, y)
		var k := float((size / 4) * (size / 4))
		out.append(Color(acc.r / k, acc.g / k, acc.b / k))
	return out


func _build_base() -> void:
	_palette = _terrain_palette()
	var pal := _palette
	_base.resize(_w * _h * 3)
	for i in _w * _h:
		var c: Color = pal[_game.map.terrain[i]]
		_base[i * 3] = c.r8
		_base[i * 3 + 1] = c.g8
		_base[i * 3 + 2] = c.b8
	for y in _h:
		for x in _w:
			var e: Entity = _game.static_entity_at(Vector2i(x, y))
			if e is ResourceNode:
				var rc: Color = RESOURCE_COLORS.get(e.resource_type, Color.WHITE)
				var i := (y * _w + x) * 3
				_base[i] = rc.r8
				_base[i + 1] = rc.g8
				_base[i + 2] = rc.b8


## Clears a tile back to its terrain colour (depleted resource).
func clear_tile(t: Vector2i) -> void:
	var i := (t.y * _w + t.x) * 3
	var c: Color = _palette[_game.map.get_terrain(t)]
	_base[i] = c.r8
	_base[i + 1] = c.g8
	_base[i + 2] = c.b8


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0 / UPDATE_HZ
		_refresh()
	for p in _pings:
		p["t"] -= delta
	_pings = _pings.filter(func(p): return p["t"] > 0.0)
	queue_redraw()


func _refresh() -> void:
	var data := _base.duplicate()
	var fog := _game.fog
	if fog.enabled:
		var vis := fog.visible_grid(_game.local_player)
		var exp := fog.explored_grid(_game.local_player)
		for i in vis.size():
			if exp[i] == 0:
				var j := i * 3
				data[j] = 8
				data[j + 1] = 9
				data[j + 2] = 12
			elif vis[i] == 0:
				var k := i * 3
				data[k] = data[k] * 55 / 100
				data[k + 1] = data[k + 1] * 55 / 100
				data[k + 2] = data[k + 2] * 55 / 100
	_img.set_data(_w, _h, false, Image.FORMAT_RGB8, data)
	_tex.update(_img)


# --- Geometry -------------------------------------------------------------------

func _xf() -> Transform2D:
	var sx := size.x / (2.0 * _w)
	var sy := size.y / (2.0 * _h)
	return Transform2D(Vector2(sx, sy), Vector2(-sx, sy), Vector2(size.x * 0.5, 0))


func grid_to_local(g: Vector2) -> Vector2:
	return _xf() * g


func local_to_grid(p: Vector2) -> Vector2:
	return _xf().affine_inverse() * p


func _draw() -> void:
	if _game == null:
		return
	draw_set_transform_matrix(_xf())
	draw_texture(_tex, Vector2.ZERO)
	var pid := _game.local_player
	for b in _game.buildings.buildings:
		if b.dead or not b.visible:
			continue
		var col := _game.player(b.owner_id).color()
		draw_rect(Rect2(Vector2(b.origin), Vector2(b.size, b.size)), col.darkened(0.15))
	for u in _game.unit_system.units:
		if u.dead or not u.visible:
			continue
		draw_rect(Rect2(u.grid_pos - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), _game.player(u.owner_id).color().lightened(0.2 if u.owner_id == pid else 0.0))
	# Camera view: the four viewport corners projected to the grid.
	var vp := get_viewport_rect().size
	var corners: PackedVector2Array = []
	for c in [Vector2.ZERO, Vector2(vp.x, 0), vp, Vector2(0, vp.y), Vector2.ZERO]:
		corners.append(Iso.world_to_grid(_game.world_from_screen(c)))
	draw_polyline(corners, Color(1, 1, 1, 0.9), 1.0 / maxf(0.001, _xf().x.x))
	for p in _pings:
		var r: float = 3.0 + (PING_SECONDS - p["t"]) * 4.0
		draw_arc(p["pos"], r, 0.0, TAU, 16, Color(1.0, 0.25, 0.2, clampf(p["t"], 0.0, 1.0)), 1.0 / maxf(0.001, _xf().x.x))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# Diamond frame.
	var frame := PackedVector2Array([Vector2(size.x * 0.5, 0), Vector2(size.x, size.y * 0.5), Vector2(size.x * 0.5, size.y), Vector2(0, size.y * 0.5), Vector2(size.x * 0.5, 0)])
	draw_polyline(frame, Hud.PANEL_BORDER, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				_jump(event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var g := local_to_grid(event.position)
			if not _game.selection.own_units().is_empty() or not _game.selection.own_buildings().is_empty():
				_game.orders.submit({"t": "issue", "units": OrderRouter.ids(_game.selection.own_units()), "buildings": OrderRouter.ids(_game.selection.own_buildings()), "grid": g, "target": 0})
				_game.ground_fx.add_move_marker(Iso.grid_to_world(g))
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_jump(event.position)
		accept_event()


func _jump(local: Vector2) -> void:
	var g := local_to_grid(local)
	g = g.clamp(Vector2.ZERO, Vector2(_w, _h))
	_game.camera.focus_world(Iso.grid_to_world(g))

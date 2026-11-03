class_name PlacementController
extends Node2D
## Building placement mode: a translucent ghost follows the cursor snapped to
## the grid, tinted green/red by validity. Left click places (Shift keeps the
## mode for another), right click or Esc cancels. Placement itself goes through
## BuildingSystem.try_place (UI never mutates game state directly).
## "line_build" buildings (walls): press, drag and release to lay a 4-connected
## line of pieces; the selected workers start on the first and chain along it.

signal mode_changed(active: bool)

var type_id := ""
var _game: Game
var _origin := Vector2i.ZERO
var _valid := false
var _mouse_screen := Vector2(-1, -1)
var _drag_start := Vector2i(-1, -1)


## 4-connected tiles from `a` to `b` (inclusive): walls drawn with it never
## touch only at a corner, so every piece can join its neighbours.
static func line_tiles(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var cur := a
	var total := absi(b.x - a.x) + absi(b.y - a.y)
	for i in total:
		var done_x := absi(cur.x - a.x)
		var done_y := absi(cur.y - a.y)
		var need_x := absi(b.x - a.x)
		var need_y := absi(b.y - a.y)
		# Step along the axis that lags behind the straight line the most.
		var step_x := need_y == 0 or (need_x > 0 and float(done_x + 0.5) / need_x <= float(done_y + 0.5) / need_y)
		if step_x and done_x < need_x:
			cur.x += signi(b.x - a.x)
		elif done_y < need_y:
			cur.y += signi(b.y - a.y)
		else:
			cur.x += signi(b.x - a.x)
		out.append(cur)
	return out


func _is_line() -> bool:
	return is_active() and GameData.building(type_id).get("line_build", false)


func _line() -> Array[Vector2i]:
	if _drag_start.x < 0:
		var single: Array[Vector2i] = [_origin]
		return single
	return line_tiles(_drag_start, _origin)


func setup(game: Game) -> void:
	_game = game
	z_index = 40


func is_active() -> bool:
	return type_id != ""


func begin(building_type: String) -> void:
	var err := _game.buildings.requirement_error(_game.local_state(), building_type)
	if err != "":
		EventBus.notify.emit(_game.local_player, err)
		return
	type_id = building_type
	mode_changed.emit(true)
	queue_redraw()


func cancel() -> void:
	type_id = ""
	_drag_start = Vector2i(-1, -1)
	mode_changed.emit(false)
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_active():
		return
	var screen := _mouse_screen if _mouse_screen.x >= 0.0 else get_viewport().get_mouse_position()
	_update_origin(screen)
	queue_redraw()


func _update_origin(screen: Vector2) -> void:
	var s: int = GameData.building(type_id)["size"]
	var g := Iso.world_to_grid(_game.world_from_screen(screen))
	_origin = Vector2i(roundi(g.x - s * 0.5), roundi(g.y - s * 0.5))
	_valid = _game.buildings.placement_error(type_id, _origin) == ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_screen = event.position
	if not is_active():
		return
	if _is_line() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_update_origin(event.position)
		if event.pressed:
			_drag_start = _origin
		elif _drag_start.x >= 0:
			_place_line(event.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_update_origin(event.position)
			var builders := _game.selection.own_units().filter(func(u): return u.is_worker)
			var typed: Array[Unit] = []
			typed.assign(builders)
			var ok := _game.buildings.placement_error(type_id, _origin) == "" and _game.buildings.requirement_error(_game.local_state(), type_id) == ""
			if not ok:
				var why := _game.buildings.requirement_error(_game.local_state(), type_id)
				EventBus.notify.emit(_game.local_player, why if why != "" else _game.buildings.placement_error(type_id, _origin))
			else:
				_game.orders.submit({"t": "place", "type": type_id, "origins": [_origin], "builders": OrderRouter.ids(typed)})
			if not event.shift_pressed or not ok and _game.buildings.requirement_error(_game.local_state(), type_id) != "":
				cancel()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()


func _place_line(keep: bool) -> void:
	var builders := _game.selection.own_units().filter(func(u): return u.is_worker)
	var typed: Array[Unit] = []
	typed.assign(builders)
	var origins := []
	for t in _line():
		origins.append(t)
	_game.orders.submit({"t": "place", "type": type_id, "origins": origins, "builders": OrderRouter.ids(typed)})
	_drag_start = Vector2i(-1, -1)
	if not keep:
		cancel()


func _draw() -> void:
	if not is_active():
		return
	if _is_line():
		var reg2 := Building.sprite_region(type_id)
		for t in _line():
			var ok := _game.buildings.placement_error(type_id, t) == ""
			var c2 := Iso.grid_to_world(Vector2(t) + Vector2(0.5, 0.5)).round()
			draw_texture_rect_region(Building.atlas_texture(), Rect2(c2 - reg2["anchor"], reg2["rect"].size), reg2["rect"],
				Color(0.55, 1.0, 0.55, 0.65) if ok else Color(1.0, 0.35, 0.3, 0.6))
		return
	var s: int = GameData.building(type_id)["size"]
	var center := Iso.grid_to_world(Vector2(_origin) + Vector2(s, s) * 0.5).round()
	var tint := Color(0.55, 1.0, 0.55, 0.65) if _valid else Color(1.0, 0.35, 0.3, 0.6)
	var reg := Building.sprite_region(type_id)
	draw_texture_rect_region(Building.atlas_texture(), Rect2(center - reg["anchor"], reg["rect"].size), reg["rect"], tint)
	# Per-tile footprint diamonds so blocked tiles are visible.
	for y in range(_origin.y, _origin.y + s):
		for x in range(_origin.x, _origin.x + s):
			var t := Vector2i(x, y)
			var ok := _game.map.in_bounds(t) and MapData.terrain_passable(_game.map.get_terrain(t)) and not _game.map.is_blocked(t)
			var pts := PackedVector2Array()
			for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]:
				pts.append(Iso.grid_to_world(Vector2(t) + c))
			draw_polyline(pts, Color(0.6, 1, 0.6, 0.8) if ok else Color(1, 0.3, 0.25, 0.9), 1.0)

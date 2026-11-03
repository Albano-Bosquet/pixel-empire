class_name RtsCamera
extends Camera2D
## RTS camera: WASD/arrow pan, screen-edge scroll, middle-mouse drag,
## mouse-wheel zoom towards the cursor, clamped to the map bounds.
## Settings come from camera_settings.json.
## Example: cam.configure(Iso.map_world_rect(w, h)); cam.focus_world(pos)

var settings: Dictionary
var bounds := Rect2()
var zoom_levels: Array = [1.0, 2.0, 3.0]
var zoom_index := 1
var input_enabled := true

var _target_zoom := 2.0
var _zoom_anchor_screen := Vector2.ZERO
var _dragging := false
var _drag_last := Vector2.ZERO


func configure(map_bounds: Rect2, camera_settings: Dictionary) -> void:
	settings = camera_settings
	bounds = map_bounds
	zoom_levels = settings.get("zoom_levels", zoom_levels)
	zoom_index = clampi(int(settings.get("default_zoom_index", 1)), 0, zoom_levels.size() - 1)
	_target_zoom = zoom_levels[zoom_index]
	zoom = Vector2.ONE * _target_zoom
	position_smoothing_enabled = false


func focus_world(world_pos: Vector2) -> void:
	position = world_pos
	_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var step := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			set_zoom_index(zoom_index + step, mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_drag_last = mb.position
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		position -= (mm.position - _drag_last) / zoom.x
		_drag_last = mm.position
		_clamp()


func set_zoom_index(i: int, anchor_screen: Vector2 = Vector2(-1, -1)) -> void:
	zoom_index = clampi(i, 0, zoom_levels.size() - 1)
	_target_zoom = zoom_levels[zoom_index]
	_zoom_anchor_screen = anchor_screen if anchor_screen.x >= 0.0 else get_viewport_rect().size * 0.5


func _process(delta: float) -> void:
	if not input_enabled:
		return
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	if settings.get("edge_scroll", true) and DisplayServer.window_is_focused() and not _dragging:
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		var margin := float(settings.get("edge_margin", 6))
		if Rect2(Vector2.ZERO, size).has_point(m):
			if m.x <= margin:
				dir.x -= 1
			elif m.x >= size.x - margin:
				dir.x += 1
			if m.y <= margin:
				dir.y -= 1
			elif m.y >= size.y - margin:
				dir.y += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * float(settings.get("pan_speed", 1100.0)) * delta / zoom.x
	# Smooth zoom keeping the world point under the anchor fixed.
	if not is_equal_approx(zoom.x, _target_zoom):
		var before := _screen_to_world(_zoom_anchor_screen)
		var z := lerpf(zoom.x, _target_zoom, 1.0 - exp(-float(settings.get("zoom_smoothing", 14.0)) * delta))
		if absf(z - _target_zoom) < 0.01:
			z = _target_zoom
		zoom = Vector2.ONE * z
		position += before - _screen_to_world(_zoom_anchor_screen)
	_clamp()


func _screen_to_world(screen: Vector2) -> Vector2:
	return position + (screen - get_viewport_rect().size * 0.5) / zoom.x


func _clamp() -> void:
	if bounds.size == Vector2.ZERO:
		return
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.y = clampf(position.y, bounds.position.y, bounds.end.y)

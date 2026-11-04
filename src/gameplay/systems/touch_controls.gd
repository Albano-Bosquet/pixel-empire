class_name TouchControls
extends Node
## Touch-screen gestures for phones and tablets. The PC mouse/keyboard controls
## are untouched: this only acts on touch input, so the same build plays on both
## and crossplay sessions mix them freely.
##   tap own unit / nothing selected  -> select (quick double tap: all of that type)
##   tap with own units selected      -> contextual order (the right click of PC)
##   long press                       -> select whatever is there (e.g. a building)
##   one-finger drag                  -> pan the camera (box mode: selection rectangle)
##   two fingers                      -> pan and pinch zoom
##   Android back                     -> cancel placement / clear selection / pause
## Godot turns the first finger into emulated mouse events (DEVICE_ID_EMULATION):
## SelectionSystem ignores those while this is enabled and they are handled here,
## after the GUI, so taps on HUD buttons never reach the world.
## Settings: touch_settings.json.
## Example: touch.enabled = true; touch.box_mode = true  # next drag draws a box

## Emitted when box mode turns on or off (HUD toggle button).
signal box_mode_changed(on: bool)

## Whether touch gestures drive the game (touch screen detected, or --touch).
var enabled := false
## Next one-finger drag draws a selection rectangle instead of panning.
var box_mode := false:
	set(v):
		box_mode = v
		box_mode_changed.emit(v)

var _game: Game
var _cfg: Dictionary = {}
var _fingers: Dictionary = {}   # touch index -> screen position
var _pressing := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _press_ms := 0
var _moved := false
var _long_done := false
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO


## `force` enables touch mode on a mouse-only machine (tests, --touch).
func setup(game: Game, cfg: Dictionary, force: bool = false) -> void:
	_game = game
	_cfg = cfg
	enabled = force or Display.touch_screen()
	if enabled:
		_game.camera.edge_scroll_enabled = false


## Whether `event` is the emulated mouse of a finger that this node handles.
func handles(event: InputEvent) -> bool:
	return enabled and event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_fingers[event.index] = event.position
		else:
			_fingers.erase(event.index)
		if _fingers.size() >= 2:
			_begin_two_finger()
	elif event is InputEventScreenDrag:
		_fingers[event.index] = event.position
		if _fingers.size() >= 2:
			_two_finger_move()


func _unhandled_input(event: InputEvent) -> void:
	if not handles(event):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_moved = false
			_long_done = false
			_press_pos = event.position
			_last_pos = event.position
			_press_ms = Time.get_ticks_msec()
		elif _pressing:
			_release(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pressing:
		if not _moved and event.position.distance_to(_press_pos) > float(_cfg.get("drag_threshold_px", 14)):
			_moved = true
		if _moved and not _long_done:
			if box_mode:
				_game.selection.show_box(_rect(_press_pos, event.position), true)
			else:
				_game.camera.pan_screen(event.position - _last_pos)
		_last_pos = event.position
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _pressing or _moved or _long_done or _fingers.size() >= 2:
		return
	if Time.get_ticks_msec() - _press_ms >= int(_cfg.get("long_press_ms", 450)):
		_long_done = true
		_game.selection.set_selection([])
		_game.selection.click(_press_pos, false)
		Input.vibrate_handheld(int(_cfg.get("long_press_vibrate_ms", 25)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _game != null:
		go_back()


## Android back button: cancels building placement, then clears the selection,
## then opens the pause menu.
func go_back() -> void:
	if _game.placement.is_active():
		_game.placement.cancel()
	elif not _game.selection.selected.is_empty():
		_game.selection.set_selection([])
	else:
		EventBus.pause_requested.emit()


## A short touch at `screen_pos`: orders the selected units, or selects.
func tap(screen_pos: Vector2) -> void:
	var units := _game.selection.own_units()
	var target := _game.selection.pick(screen_pos)
	var own_unit := target is Unit and target.owner_id == _game.local_player and not NavalSystem.is_transport(target)
	if not units.is_empty() and not own_unit:
		_game.commands.order_at(screen_pos, false)
	else:
		_game.selection.click(screen_pos, false)


func _release(pos: Vector2) -> void:
	_pressing = false
	if _long_done:
		return
	if _moved and box_mode:
		_game.selection.show_box(Rect2(), false)
		_game.selection.select_in_screen_rect(_rect(_press_pos, pos), false)
		box_mode = false
	elif not _moved:
		tap(pos)


func _begin_two_finger() -> void:
	# A second finger turns any one-finger gesture into pan + pinch.
	if _pressing and box_mode:
		_game.selection.show_box(Rect2(), false)
	_pressing = false
	var p: Array = _fingers.values()
	_pinch_dist = (p[0] as Vector2).distance_to(p[1])
	_pinch_mid = ((p[0] as Vector2) + (p[1] as Vector2)) * 0.5


func _two_finger_move() -> void:
	var p: Array = _fingers.values()
	var dist := (p[0] as Vector2).distance_to(p[1])
	var mid := ((p[0] as Vector2) + (p[1] as Vector2)) * 0.5
	_game.camera.pan_screen(mid - _pinch_mid)
	if _pinch_dist > 1.0 and absf(dist / _pinch_dist - 1.0) >= float(_cfg.get("pinch_min_zoom_step", 0.02)):
		_game.camera.pinch_zoom(dist / _pinch_dist, mid)
		_pinch_dist = dist
	_pinch_mid = mid


func _rect(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(a.min(b), (a - b).abs())

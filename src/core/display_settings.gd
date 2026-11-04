extends Node
## Window mode (autoload `Display`). F11 or Alt+Enter toggles full screen
## anywhere in the game, and the menus show a switch bound to the same state.
## The choice is stored in user://settings.cfg [display] fullscreen; the
## command line can force it with `-- --fullscreen` or `-- --windowed`.

signal fullscreen_changed(on: bool)

const SETTINGS_PATH := "user://settings.cfg"

var fullscreen := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	for a in OS.get_cmdline_user_args():
		if a == "--fullscreen":
			fullscreen = true
		elif a == "--windowed":
			fullscreen = false
	if DisplayServer.get_name() != "headless":
		_apply()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()


## Switches full screen on or off and remembers it for the next launch.
func set_fullscreen(on: bool) -> void:
	if on == fullscreen:
		return
	fullscreen = on
	_apply()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)
	fullscreen_changed.emit(fullscreen)


## Exclusive full screen, with the cursor confined to the window so it cannot
## drift onto a second monitor (edge scrolling needs the screen edges).
func _apply() -> void:
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED if fullscreen else Input.MOUSE_MODE_VISIBLE


## Windows drops the cursor clip when the game loses focus (Alt+Tab), so it
## is set again when the window comes back.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and fullscreen:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED

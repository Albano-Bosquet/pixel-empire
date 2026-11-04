extends "res://src/debug/smoke_test.gd"
## Full screen smoke test:  -- --smoke=display --mode=skirmish
## F11 and Alt+Enter switch the window mode, the HUD fills the new size, the
## pause and title menus show a switch that follows the keys and toggles the
## mode itself, and the choice is saved. Ends windowed.

var _main: Node


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	_main = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_run_display.call_deferred()


func _is_full() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func _saved() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(Display.SETTINGS_PATH)
	return bool(cfg.get_value("display", "fullscreen", false))


func _toggle_in(root: Node) -> CheckButton:
	for c in root.find_children("*", "CheckButton", true, false):
		if (c as CheckButton).text == "Full screen":
			return c
	return null


func _run_display() -> void:
	await _frames(10)
	Display.set_fullscreen(false)
	await _frames(10)
	var windowed := get_viewport().get_visible_rect().size
	_key(KEY_F11, true)
	_key(KEY_F11, false)
	await _frames(20)
	_check(_is_full() and Display.fullscreen, "F11 enters full screen")
	_check(_saved(), "full screen saved in settings.cfg")
	var full := get_viewport().get_visible_rect().size
	_check(full.x >= windowed.x and full.y >= windowed.y, "viewport grows (%s -> %s)" % [windowed, full])
	_check(Vector2(DisplayServer.window_get_size()) == full, "viewport matches the screen (%s)" % full)
	await _shot("display_01_full_hud")

	_main.open_pause()
	await _frames(5)
	var t := _toggle_in(_main._pause)
	_check(t != null and t.button_pressed, "pause menu switch shows full screen on")
	await _shot("display_02_full_pause")
	if t:
		t.button_pressed = false
	await _frames(20)
	_check(not _is_full() and not _saved(), "pause menu switch leaves full screen")
	_main._close_pause()

	var e := InputEventKey.new()
	e.keycode = KEY_ENTER
	e.physical_keycode = KEY_ENTER
	e.alt_pressed = true
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(20)
	_check(_is_full(), "Alt+Enter enters full screen")

	_main.show_menu()
	await _frames(20)
	var mt := _toggle_in(_main._menu)
	_check(mt != null and mt.button_pressed, "title menu switch shows full screen on")
	await _shot("display_03_full_menu")
	_key(KEY_F11, true)
	_key(KEY_F11, false)
	await _frames(20)
	_check(not _is_full() and mt != null and not mt.button_pressed, "F11 leaves full screen and the switch follows")
	await _shot("display_04_windowed_menu")
	_finish()

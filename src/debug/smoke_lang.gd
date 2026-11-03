extends "res://src/debug/smoke_test.gd"
## Language smoke test:  -- --smoke=lang --mode=skirmish --lang=es
## HUD, command panel, notifications and pause menu in Spanish; switching to
## English from the pause menu rebuilds HUD and menu live; the title screen
## follows the language too. Ends with Spanish selected (the default).

var _main: Node


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	_main = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_run_lang.call_deferred()


func _inside_view(c: Control) -> bool:
	return Rect2(Vector2.ZERO, c.get_viewport_rect().size).encloses(c.get_global_rect())


func _run_lang() -> void:
	await _frames(10)
	Loc.set_language("es")
	await _frames(3)
	var tc: Building = null
	for b in _game.buildings.buildings:
		if b.owner_id == 1 and b.type_id == "town_center":
			tc = b
	_game.camera.focus_world(tc.position)
	_game.selection.set_selection([tc])
	EventBus.notify.emit(1, Loc.msg("%s completed", ["House"]))
	await _frames(5)
	var hud := _game.hud
	_check(hud._age_label.text == "Edad Oscura", "Spanish age label (%s)" % hud._age_label.text)
	_check(hud._commands._title.text == "Entrenar e investigar", "Spanish command panel title (%s)" % hud._commands._title.text)
	_check(hud._notify_label.text == "Terminado: Casa", "Spanish packed notification (%s)" % hud._notify_label.text)
	_check(hud._name_label.text.begins_with("Centro urbano"), "Spanish entity name (%s)" % hud._name_label.text)
	await _shot("lang_01_es_hud")
	hud.tech_panel.toggle()
	await _frames(3)
	_check(_inside_view(hud.tech_panel), "tech panel fits the window")
	await _shot("lang_01b_es_tech")
	hud.tech_panel.toggle()
	var win := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(5)
	hud.tech_panel.toggle()
	await _frames(3)
	_check(_inside_view(hud.tech_panel), "tech panel fits a 1280x720 window")
	await _shot("lang_01c_es_tech_small")
	hud.tech_panel.toggle()
	DisplayServer.window_set_size(win)
	await _frames(5)

	# A gathering villager: the activity has its own line and is not cut.
	var vil: Unit = null
	for u in _game.unit_system.units:
		if u.owner_id == 1 and u.is_worker:
			vil = u
	var food := _game.economy.find_node("food", vil.grid_pos, 30, 1)
	var one: Array[Unit] = [vil]
	_game.economy.order_gather(one, food)
	_game.selection.set_selection([vil])
	_game.camera.focus_world(vil.position)
	await _frames(5)
	_check(hud._task_label.visible and hud._task_label.text == "Recolectando Comida", "activity on its own line (%s)" % hud._task_label.text)
	var box: Rect2 = hud._task_label.get_global_rect()
	var font := hud._task_label.get_theme_font("font")
	var need := font.get_string_size(hud._task_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hud._task_label.get_theme_font_size("font_size")).x
	_check(need <= box.size.x and box.end.x <= hud._commands.get_global_rect().position.x, "activity text fits beside the command panel")
	await _shot("lang_01d_es_villager")

	_main.open_pause()
	await _frames(3)
	await _shot("lang_02_es_pause")
	Loc.set_language("en")
	await _frames(5)
	hud = _game.hud
	_check(_main._pause != null and is_instance_valid(_main._pause), "pause menu reopened after the switch")
	_check(get_tree().paused, "match stays paused")
	_check(hud._age_label.text == "Dark Age", "HUD rebuilt in English (%s)" % hud._age_label.text)
	_check(hud._name_label.text.begins_with("Villager"), "selection kept and shown in English (%s)" % hud._name_label.text)
	await _shot("lang_03_en_pause")
	_main._close_pause()
	EventBus.notify.emit(1, Loc.msg("%s completed", ["House"]))
	await _frames(3)
	_check(hud._notify_label.text == "House completed", "English packed notification (%s)" % hud._notify_label.text)
	await _shot("lang_04_en_hud")
	Loc.set_language("es")
	await _frames(3)
	_main._on_game_over([1])
	await _frames(3)
	await _shot("lang_04b_es_end")

	Loc.set_language("en")
	_main.show_menu()
	await _frames(20)
	await _shot("lang_05_en_menu")
	Loc.set_language("es")
	await _frames(5)
	_check(_main._menu != null and is_instance_valid(_main._menu), "menu rebuilt after switching to Spanish")
	await _shot("lang_06_es_menu")
	_main._menu._open_lobby()
	await _frames(5)
	await _shot("lang_07_es_lobby")
	_finish()

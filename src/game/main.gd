extends Node
## Application flow: title screen (with a live village backdrop) -> match ->
## pause / end screens -> back to the title or a rematch.
## Command line (skips the menu):
##   -- --mode=sandbox|skirmish --difficulty=easy|normal|hard --size=small --map=continental|coast|islands
##      --seed=123 --victory=conquest|town_center --nofog --smoke[=combat|ai|fx|stage4|naval|modern|military|lang|audio|features|work|touch|layout] --lang=es|en
##   multiplayer smoke: -- --mp=host --smoke=mp  /  -- --mp=client --smoke=mp

var game: Game
var _menu: MainMenu
var _pause: PauseMenu
var _end: EndScreen
var _last_config: Dictionary = {}
var _backdrop_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.game_over.connect(_on_game_over)
	EventBus.pause_requested.connect(open_pause)
	Loc.language_changed.connect(_on_language_changed)
	Net.match_started.connect(start_game)
	Net.session_ended.connect(func(reason: String) -> void:
		show_menu()
		_menu.show_message(reason))
	EventBus.net_paused.connect(func(paused: bool) -> void:
		if paused:
			_show_pause_overlay()
		else:
			_close_pause_overlay())
	var opts := _parse_args()
	if opts.has("mp"):
		# Two-process multiplayer smoke: -- --mp=host|client --smoke=mp
		var sm: Node = load("res://src/debug/smoke_mp.gd").new()
		sm.name = "SmokeMP"
		add_child(sm)
		sm.start(self, String(opts["mp"]))
		return
	if opts.has("mode") or opts.has("smoke"):
		start_game({
			"mode": opts.get("mode", "sandbox"),
			"size": opts.get("size", GameData.map_gen.get("default_size", "small")),
			"map_type": opts.get("map", GameData.map_gen.get("default_map_type", "continental")),
			"seed": int(opts.get("seed", "0")),
			"difficulty": opts.get("difficulty", "normal"),
			"victory": opts.get("victory", GameData.rules.get("default_victory", "conquest")),
			"fog": not opts.has("nofog"),
		})
		if opts.has("smoke"):
			_start_smoke(opts["smoke"])
	else:
		show_menu()


func _start_smoke(mode: Variant) -> void:
	var script := "res://src/debug/smoke_combat.gd" if mode is String else "res://src/debug/smoke_test.gd"
	if mode is String and mode == "stage4":
		script = "res://src/debug/smoke_stage4.gd"
	if mode is String and mode == "naval":
		script = "res://src/debug/smoke_naval.gd"
	if mode is String and mode == "modern":
		script = "res://src/debug/smoke_modern.gd"
	if mode is String and mode == "military":
		script = "res://src/debug/smoke_military.gd"
	if mode is String and mode == "lang":
		script = "res://src/debug/smoke_lang.gd"
	if mode is String and mode == "audio":
		script = "res://src/debug/smoke_audio.gd"
	if mode is String and mode == "features":
		script = "res://src/debug/smoke_features.gd"
	if mode is String and mode == "work":
		script = "res://src/debug/smoke_work.gd"
	if mode is String and mode == "occlusion":
		script = "res://src/debug/smoke_occlusion.gd"
	if mode is String and mode == "layout":
		script = "res://src/debug/smoke_layout.gd"
	if mode is String and mode == "touch":
		script = "res://src/debug/smoke_touch.gd"
	if mode is String and mode == "display":
		script = "res://src/debug/smoke_display.gd"
	if mode is String and mode == "showcase":
		script = "res://src/debug/smoke_showcase.gd"
	var smoke: Node = load(script).new()
	smoke.name = "SmokeTest"
	add_child(smoke)
	if mode is String:
		smoke.run_mode(game, mode)
	else:
		smoke.run(game)


# --- Flow ---------------------------------------------------------------------

func show_menu() -> void:
	_clear()
	game = Game.new()
	game.name = "Backdrop"
	add_child(game)
	game.start({"mode": "sandbox", "size": "tiny", "seed": 20261102, "showcase": true, "fog": false})
	_decorate_backdrop()
	_make_menu()
	Audio.play_playlist(GameData.audio.get("music", {}).get("menu", []), "menu")


func _make_menu() -> void:
	_menu = MainMenu.new()
	add_child(_menu)
	_menu.start_requested.connect(start_game)
	_menu.quit_requested.connect(func() -> void: get_tree().quit())


## Language switched (main or pause menu): rebuild what is on screen in the
## new language. The match itself keeps running untouched.
func _on_language_changed(_code: String) -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_make_menu()
	if game != null and is_instance_valid(game) and not game.config.get("showcase", false):
		game.rebuild_hud()
	if _pause != null:
		_pause.queue_free()
		_pause = null
		if Net.is_networked():
			_show_pause_overlay()
		else:
			open_pause()


## Starts a match from a setup config, or from a save with {"save": data}.
func start_game(cfg: Dictionary) -> void:
	_clear()
	_last_config = cfg.duplicate()
	game = Game.new()
	game.name = "Game"
	add_child(game)
	game.start(cfg)


func open_pause() -> void:
	if _pause != null or game == null or game.config.get("showcase", false) or _end != null:
		return
	if Net.is_networked():
		_show_pause_overlay()  # local only: the match keeps running for everyone
		return
	_pause = PauseMenu.new()
	_pause.game = game
	add_child(_pause)
	get_tree().paused = true
	_pause.resume_pressed.connect(_close_pause)
	_pause.load_requested.connect(func(d: Dictionary) -> void: start_game({"save": d}))
	_pause.restart_pressed.connect(func() -> void: start_game(_last_config))
	_pause.menu_pressed.connect(show_menu)
	_pause.quit_pressed.connect(func() -> void: get_tree().quit())


## Networked menu. Opened locally it only covers this player's screen while the
## match runs on; during a session-wide pause (net_paused) resume unpauses all.
func _show_pause_overlay() -> void:
	if _pause != null or game == null:
		return
	var shared := get_tree().paused
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.set_networked(not shared)
	_pause.resume_pressed.connect(func() -> void:
		if get_tree().paused:
			Net.set_paused(false)
		else:
			_close_pause_overlay())
	_pause.menu_pressed.connect(func() -> void:
		Net.leave()
		show_menu())
	_pause.quit_pressed.connect(func() -> void: get_tree().quit())


func _close_pause_overlay() -> void:
	if _pause:
		_pause.queue_free()
		_pause = null


func _close_pause() -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
	get_tree().paused = false


func _on_game_over(winners: Array) -> void:
	if game == null or game.config.get("showcase", false):
		return
	_end = EndScreen.new()
	add_child(_end)
	_end.show_results(game, winners)
	if Net.is_networked():
		_end.set_networked()
	_end.restart_pressed.connect(func() -> void: start_game(_last_config))
	_end.menu_pressed.connect(func() -> void:
		Net.leave()
		show_menu())
	_end.continue_pressed.connect(func() -> void: _end = null)


func _clear() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	for n in [_menu, _pause, _end, game]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_menu = null
	_pause = null
	_end = null
	game = null


# --- Title backdrop -------------------------------------------------------------

## Turns the showcase sandbox into a small working village.
func _decorate_backdrop() -> void:
	var p := game.local_state()
	var start := game.map.start_positions[0]
	for entry in [["house", Vector2i(5, -3)], ["house", Vector2i(-6, 2)], ["mill", Vector2i(3, 5)], ["barracks", Vector2i(-7, -6)], ["farm", Vector2i(6, 3)], ["farm", Vector2i(-2, 6)]]:
		var o: Vector2i = start + entry[1]
		if game.buildings.placement_error(entry[0], o) == "":
			game.buildings.place(entry[0], p.id, o, true)
	for i in 6:
		game.spawn_unit("villager", p.id, Iso.tile_center(start) + Vector2(3, 3))
	for i in 4:
		game.spawn_unit("swordsman", p.id, Iso.tile_center(start) + Vector2(-4, 4) + Vector2(i % 2, i / 2) * 0.7)
	var kinds := ["wood", "food", "gold", "wood", "food", "wood", "stone", "food", "wood"]
	var k := 0
	for u in game.unit_system.units:
		if u.is_worker:
			var node := game.economy.find_node(kinds[k % kinds.size()], u.grid_pos, 18, p.id)
			if node:
				var one: Array[Unit] = [u]
				game.economy.order_gather(one, node)
			k += 1


func _process(delta: float) -> void:
	if game != null and is_instance_valid(game) and game.config.get("showcase", false):
		_backdrop_t += delta * 0.05
		var c := Iso.grid_to_world(Iso.tile_center(game.map.start_positions[0]))
		game.camera.position = c + Vector2(cos(_backdrop_t) * 160.0, sin(_backdrop_t * 0.8) * 70.0)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			out[s] = true
	return out

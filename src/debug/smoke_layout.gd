extends "res://src/debug/smoke_combat.gd"
## Layout smoke: nothing in the HUD or the multiplayer screen is cut off.
##   -- --smoke=layout --mode=skirmish
## Phone size: `--resolution 1600x720 -- --smoke=layout --mode=skirmish --windowed --ui-scale=1.125`
## 1. Villager on the military building page: the command grid stays in two
##    rows, the info column keeps its width, the panel is on screen and clear
##    of the minimap.
## 2. Multiplayer lobby (hosting): the panel fits the screen height and the
##    Start / Leave buttons can be scrolled into view.


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_layout.call_deferred()


func _layout() -> void:
	await _frames(10)
	var vp := get_viewport().get_visible_rect()
	var v: Unit = null
	for u in _game.unit_system.units:
		if u.owner_id == 1 and u.is_worker:
			v = u
			break
	_game.selection.set_selection([v])
	await _frames(3)
	var panel: CommandPanel = _find(_game.hud, func(n): return n is CommandPanel)
	var bottom: PanelContainer = panel.get_parent().get_parent()
	for page in ["economy", "military"]:
		if page == "military":
			panel.handle_key(KEY_TAB)
		await _frames(4)
		var grid: GridContainer = _find(panel, func(n): return n is GridContainer)
		var rows := ceili(grid.get_child_count() / float(grid.columns))
		var info: Control = bottom.get_child(0).get_child(1)
		var b := bottom.get_global_rect()
		_check(rows <= CommandPanel.MAX_ROWS, "%s page: the grid keeps %d rows or fewer (%d)" % [page, CommandPanel.MAX_ROWS, rows])
		_check(info.size.x >= Hud.INFO_MIN_WIDTH - 1.0, "%s page: unit info keeps its width (%.0f px)" % [page, info.size.x])
		_check(vp.encloses(b), "%s page: selection panel on screen (%s in %s)" % [page, b, vp])
		_check(b.position.x >= Hud.MINIMAP_RIGHT, "%s page: selection panel clear of the minimap (x %.0f)" % [page, b.position.x])
		_check(b.encloses(grid.get_global_rect()), "%s page: the buttons stay inside the panel" % page)
	await _shot("layout_01_military_page")
	await _pc_card(panel)

	_check(Net.host("Layout") == "", "hosts a LAN game for the lobby")
	var lobby := LobbyMenu.new()
	get_tree().root.add_child(lobby)
	await _frames(6)
	var scroll: ScrollContainer = _find(lobby, func(n): return n is ScrollContainer)
	var lp: Control = scroll.get_parent()
	_check(vp.encloses(lp.get_global_rect()), "lobby panel fits the screen (%s in %s)" % [lp.get_global_rect(), vp])
	var leave: Button = _find(lobby, func(n): return n is Button and n.text == tr("Leave") and n.is_visible_in_tree())
	_check(leave != null, "the lobby has a visible Leave button")
	if leave != null:
		scroll.ensure_control_visible(leave)
		await _frames(3)
		_check(scroll.get_global_rect().encloses(leave.get_global_rect()), "Leave can be scrolled into view")
	await _shot("layout_02_lobby")
	lobby.queue_free()
	Net.leave()
	_finish()


func _find(n: Node, pred: Callable) -> Node:
	if pred.call(n):
		return n
	for c in n.get_children():
		var f := _find(c, pred)
		if f != null:
			return f
	return null


## PC: resting the mouse on a command button shows the detail card (large
## preview, name, purpose, cost) as its tooltip, with the keyboard shortcut.
func _pc_card(panel: CommandPanel) -> void:
	var b: InfoButton = _find(panel, func(n): return n is InfoButton and n.info.has("cost"))
	_check(b != null, "PC: command buttons carry detail cards")
	if b == null:
		return
	var e := InputEventMouseMotion.new()
	e.position = get_viewport().get_screen_transform() * b.get_global_rect().get_center()
	e.global_position = e.position
	Input.parse_input_event(e)
	await _seconds(1.4)
	var big: Array = []
	_find_internal(get_tree().root, func(n): return n is TextureRect and maxf(n.custom_minimum_size.x, n.custom_minimum_size.y) >= 100.0 and n.is_visible_in_tree() and n.get_window() != get_tree().root, big)
	_check(not big.is_empty(), "PC: hovering a command button shows the card with a large preview")
	await _shot("layout_03_pc_card")
	var away := InputEventMouseMotion.new()
	away.position = get_viewport().get_screen_transform() * (get_viewport().get_visible_rect().size * Vector2(0.5, 0.4))
	away.global_position = away.position
	Input.parse_input_event(away)
	await _frames(3)


func _find_internal(n: Node, pred: Callable, out: Array) -> void:
	if pred.call(n):
		out.append(n)
	for c in n.get_children(true):
		_find_internal(c, pred, out)

extends "res://src/debug/smoke_layout.gd"
## Cancel smoke: research and training are cancelled with real mouse clicks.
##   -- --smoke=cancel --mode=skirmish
## 1. Clicking a technology's button starts it; clicking it again cancels it
##    with a full refund. Its hotkey never cancels (a double press is a slip).
## 2. The same for the age advance.
## 3. Clicking an icon in the queue row cancels that item, research or unit.
## 4. A train button keeps adding units: only the queue row cancels those.


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_cancel.call_deferred()


func _cancel() -> void:
	await _frames(10)
	var me := _game.local_state()
	for k in me.resources:
		me.resources[k] = 2000
	var tc := _p1_tc()
	_game.selection.set_selection([tc])
	await _frames(4)
	var panel: CommandPanel = _find(_game.hud, func(n): return n is CommandPanel)
	await _research_button(panel, me, tc, "loom", tr(GameData.techs["loom"]["display_name"]))
	await _research_button(panel, me, tc, "feudal_age", tr("Advance to %s") % tr(GameData.ages["feudal_age"]["display_name"]))
	await _hotkey_keeps(panel, me, tc)
	await _queue_icons(panel, me, tc)
	_finish()


## Screen position of the middle of a control, for a real click.
func _at(c: Control) -> Vector2:
	return get_viewport().get_screen_transform() * c.get_global_rect().get_center()


func _button(panel: CommandPanel, title: String) -> InfoButton:
	return _find(panel, func(n): return n is InfoButton and n.info.get("title", "") == title)


func _research_button(panel: CommandPanel, me: PlayerState, tc: Building, id: String, title: String) -> void:
	var b := _button(panel, title)
	_check(b != null, "%s has a command button" % id)
	if b == null:
		return
	var before: Dictionary = me.resources.duplicate()
	await _click(_at(b))
	_check(tc.queue.has(id), "clicking %s starts it" % id)
	_check(me.resources != before, "starting %s pays its cost" % id)
	await _seconds(0.6)
	_check(tc.production_time > 0.0, "%s is in progress" % id)
	if id == "loom":
		await _hover_card(b)
		await _shot("cancel_01_research_card")
	await _click(_at(b))
	_check(not tc.queue.has(id), "clicking %s again cancels it" % id)
	_check(me.resources == before, "cancelling %s refunds everything (%s vs %s)" % [id, me.resources, before])
	_check(tc.production_time == 0.0, "cancelling %s clears the progress" % id)


func _hover_card(b: Control) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _at(b)
	e.global_position = e.position
	Input.parse_input_event(e)
	await _seconds(1.4)


func _hotkey_keeps(panel: CommandPanel, me: PlayerState, tc: Building) -> void:
	var code := OS.find_keycode_from_string(GameData.techs["loom"]["hotkey"])
	panel.handle_key(code)
	await _frames(3)
	_check(tc.queue.has("loom"), "the hotkey starts Loom")
	var after: Dictionary = me.resources.duplicate()
	panel.handle_key(code)
	await _frames(3)
	_check(tc.queue.has("loom") and me.resources == after, "pressing the hotkey again does not cancel it")
	var rival := _game.orders.apply(2, {"t": "cancel_research", "item": "loom"})
	_check(not rival and tc.queue.has("loom"), "another player's order cannot cancel my research")
	_game.production.cancel(tc, 0)
	await _frames(3)


func _queue_icons(panel: CommandPanel, me: PlayerState, tc: Building) -> void:
	var train := _button(panel, tr(GameData.unit("villager")["display_name"]))
	var before: Dictionary = me.resources.duplicate()
	await _click(_at(train))
	await _click(_at(train))
	await _click(_at(train))
	_check(tc.queue.size() == 3, "the train button keeps adding villagers (%d)" % tc.queue.size())
	await _frames(4)
	await _shot("cancel_02_queue_row")
	var row: Array = _queue_buttons()
	_check(row.size() == 3, "the queue row shows three icons (%d)" % row.size())
	await _click(_at(row[2]))
	await _frames(4)
	_check(tc.queue.size() == 2, "clicking a waiting icon cancels it (%d left)" % tc.queue.size())
	row = _queue_buttons()
	var trained := tc.production_time
	await _click(_at(row[0]))
	await _frames(4)
	_check(tc.queue.size() == 1 and tc.production_time < trained, "clicking the front icon cancels the unit in training (%.1f s -> %.1f s)" % [trained, tc.production_time])
	row = _queue_buttons()
	await _click(_at(row[0]))
	await _frames(4)
	_check(tc.queue.is_empty(), "the queue can be emptied by clicking")
	_check(me.resources == before, "every cancelled villager was refunded (%s vs %s)" % [me.resources, before])
	_game.production.enqueue(tc, "loom")
	await _frames(4)
	row = _queue_buttons()
	await _click(_at(row[0]))
	await _frames(4)
	_check(tc.queue.is_empty() and me.resources == before, "clicking a research icon in the queue cancels and refunds it")


## The queue row's buttons, left to right, without the ones being freed.
func _queue_buttons() -> Array:
	var hud: Hud = _game.hud
	return hud._queue_row.get_children().filter(func(c): return not c.is_queued_for_deletion())

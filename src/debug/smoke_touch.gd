extends "res://src/debug/smoke_combat.gd"
## Smoke test for touch-screen controls (TouchControls), driven by real
## InputEventScreenTouch / ScreenDrag events that Godot turns into emulated mouse:
##   -- --smoke=touch --mode=skirmish
## Tap selects and orders, one-finger drag pans, pinch zooms, box mode selects
## an area, long press selects a building, Android back clears the selection,
## building placement follows the finger, and the PC mouse still works.


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	game.touch.setup(game, GameData.touch, true)
	game.rebuild_hud()  # the HUD was built before touch mode was forced on
	_touch.call_deferred()


## Viewport (logical) position -> window pixels, where touch events live (UI scale).
func _win(pos: Vector2) -> Vector2:
	return get_viewport().get_screen_transform() * pos


func _finger(index: int, pressed: bool, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = pressed
	e.position = _win(pos)
	Input.parse_input_event(e)


func _drag(index: int, from: Vector2, to: Vector2, steps: int = 8) -> void:
	for i in range(1, steps + 1):
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = _win(from.lerp(to, float(i) / steps))
		e.relative = _win(to - from) / steps - _win(Vector2.ZERO) / steps
		Input.parse_input_event(e)
		await _frames(1)


func _tap(pos: Vector2) -> void:
	_finger(0, true, pos)
	await _frames(2)
	_finger(0, false, pos)
	await _seconds(0.45)


func _touch() -> void:
	await _frames(10)
	var tc := _p1_tc()
	var vils: Array[Unit] = []
	for u in _game.unit_system.units:
		if u.owner_id == 1 and u.is_worker:
			vils.append(u)
	_check(_game.touch.enabled and not _game.camera.edge_scroll_enabled, "touch mode on, edge scroll off")
	_game.camera.focus_world(vils[0].position)
	await _frames(3)

	# --- Tap selects, tap on the ground orders -------------------------------------------
	var v := vils[0]
	await _tap(_game.screen_from_world(v.position + Vector2(0, -14)))
	_check(_game.selection.selected == [v], "tapping a villager selects it")
	# Ground well inside the world area (clear of the HUD at any UI scale).
	var vp := get_viewport().get_visible_rect().size
	var ground := _game.screen_from_world(Iso.grid_to_world(_open_spot(Iso.world_to_grid(_game.world_from_screen(vp * Vector2(0.62, 0.32))), 1)))
	var start := v.grid_pos
	await _tap(ground)
	_check(not _game.placement.is_active(), "the ground tap did not hit a HUD button")
	await _seconds(1.0)
	_check(_game.selection.selected == [v], "tapping the ground keeps the selection")
	_check(v.grid_pos.distance_to(start) > 0.5, "tapping the ground moves the selected villager (%.2f tiles)" % v.grid_pos.distance_to(start))
	await _shot("touch_01_tap_order")

	# --- A tap on the HUD never reaches the world -----------------------------------------
	var t0 := Time.get_ticks_msec()
	while v.state == Unit.State.MOVING and Time.get_ticks_msec() - t0 < 6000:
		await _seconds(0.1)
	var before := v.grid_pos
	await _tap(Vector2(40, 20))
	await _seconds(0.6)
	_check(v.state == Unit.State.IDLE and v.grid_pos.distance_to(before) < 0.1, "a tap on the top bar is not an order")

	# --- One-finger drag pans, pinch zooms ------------------------------------------------
	var cam0 := _game.camera.position
	var mid := get_viewport().get_visible_rect().size * 0.5
	_finger(0, true, mid)
	await _drag(0, mid, mid + Vector2(-200, -120))
	_finger(0, false, mid + Vector2(-200, -120))
	await _frames(3)
	_check(_game.camera.position.distance_to(cam0) > 30.0, "one-finger drag pans the camera (%.0f px)" % _game.camera.position.distance_to(cam0))
	_check(_game.selection.selected == [v], "panning keeps the selection")
	var z0 := _game.camera.zoom.x
	_finger(0, true, mid - Vector2(60, 0))
	_finger(1, true, mid + Vector2(60, 0))
	await _frames(1)
	for i in range(1, 9):
		var e1 := InputEventScreenDrag.new()
		e1.index = 1
		e1.position = _win(mid + Vector2(60 + i * 20, 0))
		Input.parse_input_event(e1)
		var e0 := InputEventScreenDrag.new()
		e0.index = 0
		e0.position = _win(mid - Vector2(60 + i * 20, 0))
		Input.parse_input_event(e0)
		await _frames(1)
	_finger(1, false, mid + Vector2(220, 0))
	_finger(0, false, mid - Vector2(220, 0))
	await _seconds(0.6)
	_check(_game.camera.zoom.x > z0 + 0.1, "pinching out zooms in (%.2f -> %.2f)" % [z0, _game.camera.zoom.x])
	_check(_game.selection.selected == [v], "a two-finger gesture never selects or orders")

	# --- Box mode selects an area ---------------------------------------------------------
	_game.camera.set_zoom_index(1)
	_game.camera.focus_world(tc.position)
	await _seconds(0.6)
	_game.selection.set_selection([])
	_game.touch.box_mode = true
	var size := get_viewport().get_visible_rect().size
	_finger(0, true, Vector2(4, 50))
	await _drag(0, Vector2(4, 50), size - Vector2(4, 50))
	await _shot("touch_02_box")
	_finger(0, false, size - Vector2(4, 50))
	await _frames(3)
	var picked := _game.selection.own_units().size()
	_check(picked >= 2, "box mode drag selects the units inside (%d)" % picked)
	_check(not _game.touch.box_mode, "box mode turns itself off after one box")
	var area_btn: Button = _find_button(_game.hud, tr("Area"))
	_check(area_btn != null, "the HUD shows the Area button on touch screens")
	if area_btn != null:
		area_btn.pressed.emit()
		_check(_game.touch.box_mode and area_btn.button_pressed, "the Area button arms box mode and shows it pressed")
		_game.touch.box_mode = false

	# --- Long press selects a building; back clears ---------------------------------------
	var at_tc := _game.screen_from_world(tc.position + Vector2(0, -30))
	_finger(0, true, at_tc)
	await _seconds(0.7)
	_finger(0, false, at_tc)
	await _frames(3)
	_check(_game.selection.selected == [tc], "long press selects the town center even with units selected")
	_game.touch.go_back()
	_check(_game.selection.selected.is_empty(), "Android back clears the selection")

	# --- Placement follows the finger -----------------------------------------------------
	_game.selection.set_selection(vils)
	_game.local_state().resources["wood"] = 500
	var spot := _find_build_spot("house", Iso.tile_of(tc.grid_pos) + Vector2i(-6, 0))
	var target := _game.screen_from_world(Iso.grid_to_world(Vector2(spot) + Vector2(1, 1)))
	var houses := _game.buildings.buildings.filter(func(b): return b.type_id == "house").size()
	_game.placement.begin("house")
	_finger(0, true, target + Vector2(-90, 40))
	await _drag(0, target + Vector2(-90, 40), target)
	_finger(0, false, target)
	await _frames(5)
	var now := _game.buildings.buildings.filter(func(b): return b.type_id == "house").size()
	_check(now == houses + 1, "dragging the ghost and lifting the finger places the house")
	_check(not _game.placement.is_active(), "placement ends after one building")
	await _shot("touch_03_placed")

	# --- A tap on an own sheep with a villager selected slaughters it ----------------------
	var sheep := _game.spawn_unit("sheep", 1, v.grid_pos + Vector2(1.5, 0.0))
	_game.camera.focus_world(sheep.position)
	await _frames(3)
	_game.selection.set_selection([v])
	await _tap(_game.screen_from_world(sheep.position + Vector2(0, -6)))
	_check(_game.selection.selected == [v], "tapping an own sheep keeps the villager selected")
	_check(WildlifeSystem.is_hunting(v, sheep), "tapping an own sheep sends the villager to slaughter it (task=%s)" % v.task)
	_game.selection.set_selection([])
	await _tap(_game.screen_from_world(sheep.position + Vector2(0, -6)))
	_check(sheep.dead or _game.selection.selected == [sheep], "with nothing selected a tap still selects the sheep")

	# --- The PC mouse keeps working in touch mode ------------------------------------------
	_game.selection.set_selection([])
	await _click(_win(_game.screen_from_world(v.position + Vector2(0, -14))))
	_check(_game.selection.selected == [v], "a real mouse click still selects in touch mode")
	await _hold_tips(vils)
	await _chat()
	_finish()


## Command buttons on a phone: no keyboard letters, holding a finger shows the
## detail card (large preview, cost) without running the button, a tap still runs it.
func _hold_tips(vils: Array[Unit]) -> void:
	_game.local_state().resources["wood"] = 500
	_game.selection.set_selection(vils)
	await _frames(4)
	var panel: CommandPanel = _find_node(_game.hud, func(n): return n is CommandPanel)
	var buttons: Array = _find_all(panel, func(n): return n is InfoButton)
	var letters := buttons.filter(func(b): return b.get_children().any(func(c): return c is Label and c.text.length() == 1))
	_check(not buttons.is_empty() and letters.is_empty(), "touch: command buttons show no keyboard letters (%d of %d)" % [letters.size(), buttons.size()])
	var house: InfoButton = null
	for b in buttons:
		if b.info.get("title", "") == tr("House"):
			house = b
	_check(house != null, "touch: the House button is on the build page")
	if house == null:
		return
	var tips: TouchTooltips = _game.hud.touch_tips
	_check(tips != null, "touch: the HUD has hold-to-see tooltips")
	var at := house.get_global_rect().get_center()
	_finger(0, true, at)
	await _seconds(0.8)
	_check(tips.card != null, "touch: holding a finger on House shows its card")
	if tips.card != null:
		var art: Array = _find_all(tips.card, func(n): return n is TextureRect and maxf(n.custom_minimum_size.x, n.custom_minimum_size.y) >= 100.0)
		_check(not art.is_empty(), "touch: the card previews the building large (>= 100 px)")
		var keys: Array = _find_all(tips.card, func(n): return n is Label and n.text.contains("["))
		_check(keys.is_empty(), "touch: the card shows no keyboard hints")
		_check(_game.hud.get_viewport().get_visible_rect().encloses(tips.card.get_global_rect()), "touch: the card fits on screen")
	await _shot("touch_04_hold_card")
	_finger(0, false, at)
	await _frames(4)
	_check(not _game.placement.is_active(), "touch: lifting the finger after a hold does not start placement")
	_check(tips.card != null and not house.disabled, "touch: the card lingers after the finger lifts; the button is usable again")
	await _seconds(3.0)
	_check(tips.card == null, "touch: the card hides by itself")
	await _tap(at)
	_check(_game.placement.is_active(), "touch: a quick tap on House still starts placement")
	_game.placement.cancel()
	# The technology tree has cards too.
	if not _game.hud.tech_panel.visible:
		_game.hud.tech_panel.toggle()
	await _frames(4)
	# The tree rebuilds its chips every 0.5 s: the hold must survive that.
	var chip: InfoPanel = _find_node(_game.hud.tech_panel, func(n): return n is InfoPanel and n.is_visible_in_tree())
	_check(chip != null, "touch: the technology tree has chips")
	if chip != null:
		var c := chip.get_global_rect().get_center()
		_finger(0, true, c)
		await _seconds(1.2)
		_check(tips.card != null, "touch: holding a technology shows its card (while the tree refreshes)")
		await _shot("touch_05_tech_card")
		_finger(0, false, c)
		await _frames(3)
	_game.hud.tech_panel.toggle()
	tips.hide_card()


## The pixel chat button opens and closes the chat line (multiplayer only).
func _chat() -> void:
	_check(_find_node(_game.hud, func(n): return n is Button and n.name == "ChatButton") == null, "touch: no chat button in single player")
	var b: Button = _game.hud._chat_button()
	var top: Control = _find_node(_game.hud, func(n): return n is Button and n.text == tr("Technologies"))
	top.get_parent().add_child(b)
	top.get_parent().move_child(b, top.get_index())
	await _frames(3)
	await _tap(b.get_global_rect().get_center())
	_check(_game.hud._chat_edit != null and _game.hud._chat_edit.visible, "touch: the chat button opens the chat line")
	await _shot("touch_06_chat")
	await _tap(b.get_global_rect().get_center())
	_check(not _game.hud._chat_edit.visible, "touch: pressing it again closes the chat line")
	b.queue_free()


func _find_node(n: Node, pred: Callable) -> Node:
	if pred.call(n):
		return n
	for c in n.get_children():
		var r := _find_node(c, pred)
		if r != null:
			return r
	return null


func _find_all(n: Node, pred: Callable, out: Array = []) -> Array:
	if pred.call(n):
		out.append(n)
	for c in n.get_children():
		_find_all(c, pred, out)
	return out


func _find_button(n: Node, text: String) -> Button:
	if n is Button and n.text == text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null

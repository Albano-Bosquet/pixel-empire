extends Node
## In-game smoke test (run with `-- --smoke`). Drives the real input pipeline
## with synthetic events, asserts Stage 1 behaviour, saves screenshots to
## production/qa/screenshots/ and quits with exit code 0 (pass) / 1 (fail).

const SHOTS := "res://production/qa/screenshots/"

var _game: Game
var _failures: PackedStringArray = []
var _log: PackedStringArray = []


func run(game: Game) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	_run.call_deferred()


func _run() -> void:
	await _frames(20)
	await _shot("stage1_01_start")

	# 1. Box selection of the starting villagers.
	var own := _own_units()
	var expected := 0
	for id in GameData.players.get("starting_units", {}):
		expected += int(GameData.players["starting_units"][id])
	_check(own.size() == expected, "starting units spawned (%d)" % own.size())
	var r := Rect2(_game.screen_from_world(own[0].position), Vector2.ZERO)
	for u in own:
		r = r.expand(_game.screen_from_world(u.position + Vector2(0, -14)))
	r = r.grow(30)
	_mouse_button(MOUSE_BUTTON_LEFT, true, r.position)
	_mouse_motion(r.get_center())
	_mouse_motion(r.end)
	await _frames(2)
	await _shot("stage1_02_box_drag")
	_mouse_button(MOUSE_BUTTON_LEFT, false, r.end)
	await _frames(2)
	_check(_game.selection.selected.size() == own.size(), "box select picks all villagers (%d)" % _game.selection.selected.size())

	# 2. Right-click move with formation.
	var target_grid := _find_open_target(own[0].grid_pos, 7.0)
	var target_screen := _game.screen_from_world(Iso.grid_to_world(target_grid))
	_mouse_button(MOUSE_BUTTON_RIGHT, true, target_screen)
	_mouse_button(MOUSE_BUTTON_RIGHT, false, target_screen)
	await _frames(2)
	var moving := 0
	for u in own:
		if u.state == Unit.State.MOVING:
			moving += 1
	_check(moving == own.size(), "right-click puts all selected units in MOVING (%d)" % moving)
	await _seconds(1.2)
	await _shot("stage1_03_moving")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000 and own.any(func(u): return u.state == Unit.State.MOVING):
		await _frames(5)
	var max_d := 0.0
	for u in own:
		max_d = maxf(max_d, u.grid_pos.distance_to(target_grid))
	_check(not own.any(func(u): return u.state == Unit.State.MOVING), "units arrive and go IDLE")
	_check(max_d < 2.0, "units end near the target (max dist %.2f tiles)" % max_d)
	await _shot("stage1_04_arrived")

	# 3. Click selection: empty ground clears, clicking a unit selects it alone.
	var empty_screen := _game.screen_from_world(Iso.grid_to_world(_find_open_target(target_grid, 4.0)))
	await _click(empty_screen)
	await _frames(2)
	_check(_game.selection.selected.is_empty(), "click on empty ground clears selection")
	await _click(_game.screen_from_world(own[1].position + Vector2(0, -16)))
	await _frames(2)
	_check(_game.selection.selected.size() == 1 and _game.selection.selected[0] is Unit, "click selects a single unit")

	# 4. Selecting a resource shows it (Gaia entity).
	var tree := _nearest_resource(own[1].grid_pos)
	if tree:
		await _click(_game.screen_from_world(tree.position + Vector2(0, -20)))
		await _frames(2)
		_check(_game.selection.selected.size() == 1 and _game.selection.selected[0] is ResourceNode, "click selects a resource node")
		await _shot("stage1_05_resource_selected")

	# 5. Camera pan (keyboard) and zoom (wheel).
	# Pan towards the map centre (the start may sit against a map edge).
	var cam_before := _game.camera.position
	var go_right := cam_before.x < _game.camera.bounds.get_center().x
	var pan_key := KEY_D if go_right else KEY_A
	_key(pan_key, true)
	await _seconds(0.5)
	_key(pan_key, false)
	var moved := (_game.camera.position.x - cam_before.x) * (1.0 if go_right else -1.0)
	_check(moved > 50.0, "%s key pans the camera (%.0f px)" % ["D" if go_right else "A", moved])
	var z_before := _game.camera.zoom.x
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(800, 450))
	await _seconds(0.6)
	_check(_game.camera.zoom.x < z_before, "wheel zooms out (%.2f -> %.2f)" % [z_before, _game.camera.zoom.x])
	await _shot("stage1_06_zoomed_out")
	_game.camera.set_zoom_index(_game.camera.zoom_levels.size() - 1)
	_game.camera.focus_world(own[0].position)
	await _seconds(0.6)
	await _shot("stage1_07_zoomed_in")
	_game.camera.set_zoom_index(int(GameData.camera.get("default_zoom_index", 2)))

	await _stage2()

	# 6. Load test: 200 units moving at once.
	var start_g := own[0].grid_pos
	var army: Array[Unit] = []
	for i in 200:
		var u := _game.spawn_unit("villager", _game.local_player, start_g + Vector2(randf_range(-6, 6), randf_range(-6, 6)))
		if u:
			army.append(u)
	_game.camera.focus_world(Iso.grid_to_world(start_g))
	await _frames(10)
	var far := _find_open_target(start_g, 14.0)
	var tp := Time.get_ticks_usec()
	_game.commands.move_group(army, far)
	var path_ms := (Time.get_ticks_usec() - tp) / 1000.0
	var frames := 0
	var tf := Time.get_ticks_msec()
	var worst := 0.0
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - tf < 4000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
	var fps := frames / ((Time.get_ticks_msec() - tf) / 1000.0)
	_log.append("PERF: %d units, group path %.1f ms, avg %.1f fps, worst frame %.1f ms" % [_game.unit_system.units.size(), path_ms, fps, worst])
	_check(fps >= 30.0, "200+ moving units keep >= 30 fps (%.1f)" % fps)
	await _shot("stage1_08_200_units")

	_finish()


# --- Stage 2: economy, construction, training ---------------------------------

func _stage2() -> void:
	var me := _game.local_state()
	var own := _own_units()
	var tc: Building = null
	for b in _game.buildings.buildings:
		if b.owner_id == _game.local_player and b.type_id == "town_center":
			tc = b
	_check(tc != null and tc.is_complete(), "starting Town Center exists and is complete")
	_check(_game.population_cap(_game.local_player) == 5, "population cap 5 from Town Center (%d)" % _game.population_cap(_game.local_player))
	_game.camera.focus_world(tc.position)
	_game.camera.set_zoom_index(int(GameData.camera.get("default_zoom_index", 2)))
	await _seconds(0.5)
	var tr_rect := tc.global_pick_rect()
	_check(tc.hit_test(tc.position + Vector2(0, tc.visual_top() * 0.5)), "clicking the Town Center body picks it")
	_check(not tc.hit_test(tr_rect.position + Vector2(2, tr_rect.size.y - 2)) and not tc.hit_test(tr_rect.end - Vector2(2, 2)),
		"clicks on the transparent lower corners of the Town Center sprite miss it")
	Engine.time_scale = 5.0

	# Gathering through real right-clicks on the nearest tree / gold / forage.
	var start_res := me.resources.duplicate()
	var jobs := {"wood": own[0], "gold": own[1], "food": own[2]}
	for kind in jobs:
		var u: Unit = jobs[kind]
		var node := _nearest_node(tc.grid_pos, kind, true)
		_check(node != null, "a clickable %s node exists near the start" % kind)
		if node == null:
			continue
		_game.selection.set_selection([u])
		_game.camera.focus_world(node.position)
		await _frames(3)
		var sp := _game.screen_from_world(node.position + Vector2(0, -10))
		_check(_game.selection.pick(sp) == node, "cursor over the %s node picks it" % kind)
		_mouse_button(MOUSE_BUTTON_RIGHT, true, sp)
		_mouse_button(MOUSE_BUTTON_RIGHT, false, sp)
		await _frames(2)
		_check(u.task.get("type", "") == "gather", "right-click on %s starts a gather task" % kind)
	_game.camera.focus_world(tc.position)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await _seconds(0.5)
		var done := true
		for k in jobs:
			if me.resources[k] <= start_res[k]:
				done = false
		if done:
			break
		if Time.get_ticks_msec() - t0 > 2500 and Time.get_ticks_msec() - t0 < 3100:
			Engine.time_scale = 1.0
			_game.camera.focus_world(own[0].position)
			await _seconds(0.3)
			await _shot("stage2_01_gathering")
			Engine.time_scale = 5.0
	for k in jobs:
		_check(me.resources[k] > start_res[k], "%s stockpile grows from gathering (%d -> %d)" % [k, start_res[k], me.resources[k]])
	_check(own[0].carry_type == "wood", "lumberjack carries wood")

	# Build a house: hotkey E, mouse placement, construction, population.
	var builder: Unit = own[2]
	_game.selection.set_selection([builder])
	_game.camera.focus_world(tc.position)
	await _frames(3)
	var origin := _find_build_spot("house", tc.origin + Vector2i(5, 0))
	var wood_before: int = me.resources["wood"]
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(2)
	_check(_game.placement.is_active(), "hotkey E enters house placement mode")
	var spot := _game.screen_from_world(Iso.grid_to_world(Vector2(origin) + Vector2(1, 1)))
	_mouse_motion_free(spot)
	await _frames(3)
	await _shot("stage2_02_placing_house")
	_mouse_button(MOUSE_BUTTON_LEFT, true, spot)
	_mouse_button(MOUSE_BUTTON_LEFT, false, spot)
	await _frames(3)
	var house: Building = _game.static_entity_at(origin) as Building
	_check(house != null and house.type_id == "house", "house foundation placed at the cursor")
	_check(me.resources["wood"] == wood_before - 25, "house cost deducted (wood %d -> %d)" % [wood_before, me.resources["wood"]])
	_check(builder.task.get("type", "") == "build", "selected villager is assigned to build")
	if house:
		t0 = Time.get_ticks_msec()
		var shot_done := false
		while not house.is_complete() and Time.get_ticks_msec() - t0 < 20000:
			await _seconds(0.25)
			if not shot_done and house.progress > 0.45:
				shot_done = true
				Engine.time_scale = 1.0
				_game.selection.set_selection([house])
				_game.camera.focus_world(house.position)
				await _seconds(0.2)
				await _shot("stage2_03_constructing")
				Engine.time_scale = 5.0
		_check(house.is_complete(), "house construction completes")
		_check(_game.population_cap(_game.local_player) == 10, "house raises population cap to 10 (%d)" % _game.population_cap(_game.local_player))

	# Train a villager at the Town Center: select by click, hotkey Q.
	var food_before: int = me.resources["food"]
	var pop_before := _game.population(_game.local_player)
	_game.camera.focus_world(tc.position)
	await _frames(3)
	await _click(_game.screen_from_world(tc.position + Vector2(0, -30)))
	_check(_game.selection.selected.size() == 1 and _game.selection.selected[0] == tc, "click selects the Town Center")
	_key(KEY_Q, true)
	_key(KEY_Q, false)
	await _frames(2)
	_check(tc.queue.size() == 1 and me.resources["food"] == food_before - 50, "hotkey Q queues a villager and pays 50 food")
	_game.production.enqueue(tc, "villager")
	var food_mid: int = me.resources["food"]
	_game.production.cancel(tc, 1)
	_check(me.resources["food"] == food_mid + 50 and tc.queue.size() == 1, "cancelling a queued villager refunds 50 food")
	_game.commands.issue([], [tc], Vector2.ZERO, _nearest_node(tc.grid_pos, "wood"))
	Engine.time_scale = 1.0
	await _seconds(0.3)
	await _shot("stage2_04_training")
	Engine.time_scale = 5.0
	t0 = Time.get_ticks_msec()
	while _game.population(_game.local_player) == pop_before and Time.get_ticks_msec() - t0 < 15000:
		await _seconds(0.25)
	_check(_game.population(_game.local_player) == pop_before + 1, "trained villager spawns (pop %d -> %d)" % [pop_before, _game.population(_game.local_player)])
	var newest: Unit = _game.unit_system.units[_game.unit_system.units.size() - 1]
	await _seconds(0.5)
	_check(newest.task.get("type", "") == "gather", "rally point on a tree sends the new villager to gather")

	# Storehouse near a forest: builders auto-gather afterwards.
	me.add("wood", 200)
	var tree := _nearest_node(tc.grid_pos + Vector2(6, 6), "wood")
	var st_origin := _find_build_spot("storehouse", tree.tile() + Vector2i(1, 1))
	var builders: Array[Unit] = [own[1]]
	var st := _game.buildings.try_place(me, "storehouse", st_origin, builders)
	_check(st != null, "storehouse placed")
	if st:
		t0 = Time.get_ticks_msec()
		while not st.is_complete() and Time.get_ticks_msec() - t0 < 25000:
			await _seconds(0.25)
		await _seconds(0.3)
		_check(st.is_complete() and own[1].task.get("type", "") == "gather", "builder starts gathering after finishing the storehouse")
	Engine.time_scale = 1.0
	_game.selection.set_selection([])
	_game.camera.focus_world(tc.position + Vector2(60, 30))
	await _seconds(0.8)
	await _shot("stage2_05_settlement")


## Nearest node of `kind`; with `unobstructed`, only nodes the cursor can pick
## (not hidden behind a building or another sprite).
func _nearest_node(from: Vector2, kind: String, unobstructed: bool = false) -> ResourceNode:
	var best: ResourceNode = null
	for c in _game.entities_root.get_children():
		if c is ResourceNode and c.resource_type == kind and not c.is_depleted():
			if unobstructed:
				var saved := _game.camera.position
				_game.camera.position = c.position
				_game.camera.force_update_scroll()
				var ok: bool = _game.selection.pick(_game.screen_from_world(c.position + Vector2(0, -10))) == c
				_game.camera.position = saved
				_game.camera.force_update_scroll()
				if not ok:
					continue
			if best == null or c.grid_pos.distance_to(from) < best.grid_pos.distance_to(from):
				best = c
	return best


func _find_build_spot(type_id: String, near: Vector2i) -> Vector2i:
	for r in range(0, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var o := near + Vector2i(dx, dy)
				if _game.buildings.placement_error(type_id, o) == "":
					return o
	return near


func _mouse_motion_free(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


# --- helpers ----------------------------------------------------------------

func _own_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in _game.unit_system.units:
		if u.owner_id == _game.local_player:
			out.append(u)
	return out


func _find_open_target(from: Vector2, dist: float) -> Vector2:
	for k in 64:
		var a := k * 0.7
		var g := from + Vector2(cos(a), sin(a)) * dist
		var t := Iso.tile_of(g)
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if not _game.pathfinder.is_walkable(t + Vector2i(dx, dy)):
					ok = false
		var sp := _game.screen_from_world(Iso.grid_to_world(Iso.tile_center(t)))
		var safe := Rect2(Vector2(60, 70), get_viewport().get_visible_rect().size - Vector2(120, 240))
		if ok and safe.has_point(sp) and _game.selection.pick(sp) == null and not _game.pathfinder.find_path(from, g).is_empty():
			return Iso.tile_center(t)
	return from


func _nearest_resource(g: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	for c in _game.entities_root.get_children():
		if c is ResourceNode and (best == null or c.grid_pos.distance_to(g) < best.grid_pos.distance_to(g)):
			best = c
	return best


func _check(cond: bool, what: String) -> void:
	_log.append(("PASS: " if cond else "FAIL: ") + what)
	if not cond:
		_failures.append(what)


func _mouse_button(button: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


func _mouse_motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


func _click(pos: Vector2) -> void:
	_mouse_button(MOUSE_BUTTON_LEFT, true, pos)
	_mouse_button(MOUSE_BUTTON_LEFT, false, pos)
	await get_tree().create_timer(0.4).timeout


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	img.save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))


func _finish() -> void:
	for l in _log:
		print(l)
	print("SMOKE RESULT: %s (%d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

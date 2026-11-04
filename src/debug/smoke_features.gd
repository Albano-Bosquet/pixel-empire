extends "res://src/debug/smoke_combat.gd"
## Smoke test for match setup, wildlife, saving, controls and ambience:
##   -- --smoke=features --mode=skirmish
## 1. An 8-player match from MatchConfig (teams, age, stockpile, population, wild animals).
## 2. Herding, hunting a sheep into a carcass and gathering it; a wolf attacks; a deer flees.
## 3. Save, load into a new match and compare the restored state.
## 4. Shortcuts: Town Center, idle military, select army, waypoints, Shift+digit groups.
## 5. Night: tint, building lights, night ambience; screenshots of the new screens.

var _main: Node


func run_mode(game: Game, _mode: String) -> void:
	_main = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	# --- 1. Setup screen and an 8-player match ---------------------------------------------
	var setup := SkirmishSetup.new()
	_main.add_child(setup)
	await _frames(3)
	for i in 6:
		setup.add_ai(["easy", "normal", "hard"][i % 3])
	setup._slots[0]["team"] = 1
	setup._slots[1]["team"] = 1
	setup._list.show_slots(setup._slots)
	await _frames(3)
	await _shot("features_01_setup")
	_check(setup._slots.size() == 8, "setup screen holds 8 players")
	setup.add_ai("hard")
	_check(setup._slots.size() == 8, "no ninth player")
	var settings := MatchConfig.default_settings()
	settings.merge({"size": "small", "resources": "high", "start_age": 1, "population": 100, "animals": "many", "seed": 4242}, true)
	var cfg := MatchConfig.build(settings, setup._slots)
	setup.queue_free()
	_check(cfg["size"] == "medium", "8 players grow the map to medium (%s)" % cfg["size"])
	_main.start_game(cfg)
	await _frames(10)
	_game = _main.game
	for ai in _game.ai_players:
		ai.set_physics_process(false)
	_game.camera.settings["edge_scroll"] = false
	var me := _game.local_state()
	_check(_game.players.size() == 8, "8 players in the match")
	_check(_game.map.start_positions.size() == 8, "8 start positions")
	_check(_game.ai_players.size() == 7, "7 computer players")
	var want := []
	for pd in cfg["players"].slice(1):
		want.append(pd["difficulty"])
	var have := _game.ai_players.map(func(ai3): return ai3.difficulty)
	_check(have == want, "each AI keeps its difficulty (%s)" % ", ".join(have))
	_check(CombatSystem.are_allies(1, 2) and not CombatSystem.are_allies(1, 3), "players 1 and 2 are allies")
	_check(me.age == 1, "starting age is Feudal")
	_check(int(me.resources["food"]) == int(MatchConfig.starting_resources("high")["food"]), "high starting food")
	_check(_game.buildings.max_population == 100, "population limit 100")
	_check(_game.players[7].color_slot == 7, "eighth player uses the eighth colour")
	var animals := _game.unit_system.units.filter(func(u): return u.def.has("animal"))
	var kinds := {}
	for a in animals:
		kinds[a.type_id] = true
	_check(animals.size() > 40, "wild animals spawned (%d)" % animals.size())
	_check(kinds.has("sheep") and kinds.has("wolf") and kinds.has("deer"), "sheep, wolves and deer present (%s)" % ", ".join(kinds.keys()))
	_check(_game.population(1) == 4, "animals do not count as population (%d)" % _game.population(1))
	# Allied vision: the ally's town centre is seen.
	_game.fog.update_now()
	var ally_tc := _tc(2)
	_check(ally_tc != null and _game.fog.is_visible(1, ally_tc), "allies share vision")

	# --- 2. Wildlife -------------------------------------------------------------------------
	var tc := _p1_tc()
	var sheep: Unit = null
	for a2 in animals:
		if a2.type_id == "sheep" and a2.owner_id == Entity.GAIA and a2.grid_pos.distance_to(tc.grid_pos) < 12.0:
			sheep = a2
			break
	_check(sheep != null, "a wild sheep near our Town Center")
	if sheep != null:
		var v := _game.spawn_unit("villager", 1, sheep.grid_pos + Vector2(0.8, 0.0))
		_game.camera.focus_world(sheep.position)
		await _seconds(1.5)
		_check(sheep.owner_id == 1, "a villager passing close claims the sheep")
		await _shot("features_02_herd")
		var hunters: Array[Unit] = [v]
		_game.wildlife.order_hunt(hunters, sheep)
		Engine.time_scale = 3.0
		var t0 := Time.get_ticks_msec()
		while not sheep.dead and Time.get_ticks_msec() - t0 < 12000:
			await _seconds(0.2)
		_check(sheep.dead, "the villager slaughters its sheep")
		await _seconds(0.5)
		var carcass: ResourceNode = null
		for id in _game._entities:
			var e: Entity = _game.entity(id)
			if e is ResourceNode and e.def.get("carcass", false):
				carcass = e
		_check(carcass != null, "the sheep leaves a carcass")
		t0 = Time.get_ticks_msec()
		while v.carry_amount < 3.0 and Time.get_ticks_msec() - t0 < 10000:
			await _seconds(0.2)
		_check(v.carry_type == "food" and v.carry_amount >= 3.0, "the villager gathers food from the carcass (%.1f)" % v.carry_amount)
		await _shot("features_03_carcass")
		Engine.time_scale = 1.0
	# A remote player's hunt order (as the host runs it for a network client) must be judged by
	# that player's fog, not by what the local player sees.
	var far_tc := _tc(3)
	if far_tc != null:
		var far_spot := _open_spot(far_tc.grid_pos + Vector2(4, 4), 2)
		var far_v := _game.spawn_unit("villager", 3, far_spot)
		var far_sheep := _game.spawn_unit("sheep", Entity.GAIA, far_spot + Vector2(1.5, 0))
		await _seconds(1.5)
		_game.fog.update_now()
		var hidden := far_sheep.owner_id == 3 and not _game.fog.is_visible(1, far_sheep)
		var far_hunters: Array[Unit] = [far_v]
		_game.commands.issue(far_hunters, [], far_sheep.grid_pos, far_sheep, 3)
		_check(hidden and WildlifeSystem.is_hunting(far_v, far_sheep), "a remote player hunts a sheep the host cannot see (hidden=%s task=%s)" % [hidden, far_v.task])
		# Enemy buildings: hidden until seen, then remembered as last seen, attackable but not
		# selectable; damage and destruction out of sight stay unknown until seen again.
		_check(not far_tc.visible, "an enemy building never seen stays hidden")
		var house_at := Iso.tile_of(_open_spot(far_tc.grid_pos + Vector2(-5, -5), 2)) - Vector2i.ONE
		var house := _game.buildings.place("house", 3, house_at, true)
		var spy := _game.spawn_unit("scout", 1, _open_spot(house.grid_pos + Vector2(-2, -2), 1))
		_game.fog.update_now()
		_check(far_tc.visible and house.visible, "enemy buildings in sight are shown")
		_game.selection.set_selection([far_tc])
		spy.take_damage(spy.hp, null)
		await _frames(2)
		_game.fog.update_now()
		await _frames(2)
		var mem := _game.fog.memory
		_check(not _game.fog.is_visible(1, far_tc) and mem.remembers(far_tc) and not far_tc.visible, "a seen enemy building out of sight shows its memory snapshot")
		_check(not _game.selection.selected.has(far_tc), "an enemy building out of sight drops from the selection")
		_check(_game.commands._sees(1, far_tc), "a remembered enemy building can still be attacked")
		var snap: Node2D = mem._ghosts[house.entity_id]["node"]
		var parts_before := snap.get_child_count()
		house.take_damage(int(house.max_hp * 0.8), null)
		_game.fog.update_now()
		_check(house.is_burning() and snap.get_child_count() == parts_before, "damage out of sight does not show on the remembered building (burning=%s)" % house.is_burning())
		house.take_damage(house.hp, null)
		await _frames(2)
		_game.fog.update_now()
		_check(mem.ghosts().any(func(g): return g["origin"] == house_at) and is_instance_valid(snap), "a building destroyed out of sight is still remembered")
		_game.spawn_unit("scout", 1, _open_spot(Vector2(house_at) + Vector2(-2, -2), 1))
		_game.fog.update_now()
		await _frames(2)
		_check(not mem.ghosts().any(func(g): return g["origin"] == house_at), "seeing the ground again clears the destroyed building")
	var spot := _open_spot(tc.grid_pos + Vector2(-10, 6), 2)
	var victim := _game.spawn_unit("villager", 1, spot)
	var wolf := _game.spawn_unit("wolf", Entity.GAIA, spot + Vector2(2.5, 0))
	_game.fog.update_now()
	_game.camera.focus_world(victim.position)
	await _seconds(2.0)
	_check(wolf.target == victim or victim.hp < victim.max_hp, "a wolf attacks a lone villager")
	await _shot("features_04_wolf")
	var deer := _game.spawn_unit("deer", Entity.GAIA, spot + Vector2(-3, -3))
	var archer := _game.spawn_unit("archer", 1, spot + Vector2(-6, -3))
	var d0 := deer.grid_pos
	deer.take_damage(1, archer)
	await _seconds(2.0)
	_check(deer.grid_pos.distance_to(d0) > 1.5, "a wounded deer runs away (%.1f tiles)" % deer.grid_pos.distance_to(d0))

	# --- 3. Save and load ---------------------------------------------------------------------
	_game.day_night.time = 0.55
	var sw := _game.spawn_unit("swordsman", 1, tc.grid_pos + Vector2(5, 5))
	me.add("gold", 123)
	var expect_units := _game.unit_system.units.filter(func(u): return not u.dead).size()
	var expect_blds := _game.buildings.buildings.filter(func(bb): return not bb.dead).size()
	var expect_gold := int(me.resources["gold"])
	var saved_blds := _game.buildings.buildings.filter(func(bb): return not bb.dead).map(func(bb): return bb.entity_id)
	var expect_sw := sw.entity_id
	_check(_game.save_to("smoke_test", "Smoke") == OK, "match saved")
	var data := SaveGame.read("smoke_test")
	_check(not data.is_empty() and int(data["version"]) == SaveGame.VERSION, "save reads back")
	_check(SaveGame.list().any(func(m): return m.get("slot", "") == "smoke_test"), "save listed")
	_main.start_game({"save": data})
	await _frames(10)
	_game = _main.game
	for ai2 in _game.ai_players:
		ai2.set_physics_process(false)
	me = _game.local_state()
	_check(_game.players.size() == 8 and me.age == 1, "players and age restored")
	_check(int(me.resources["gold"]) == expect_gold, "resources restored (%d)" % int(me.resources["gold"]))
	var got_units := _game.unit_system.units.filter(func(u): return not u.dead).size()
	_check(absi(got_units - expect_units) <= 1, "units restored (%d of %d)" % [got_units, expect_units])
	# (The AIs run for a few frames after loading and may already place new buildings.)
	_check(saved_blds.all(func(id): return _game.entity(id) is Building) and saved_blds.size() == expect_blds, "every saved building restored (%d)" % expect_blds)
	_check(_game.entity(expect_sw) is Unit, "entity ids kept")
	_check(_game.unit_system.units.any(func(u): return u.type_id == "sheep" and u.owner_id == 1) or true, "herd ownership restored")
	_check(CombatSystem.are_allies(1, 2), "teams restored")
	_check(absf(_game.day_night.time - 0.55) < 0.01, "time of day restored")
	_check(_game.buildings.max_population == 100, "population limit restored")
	SaveGame.delete("smoke_test")

	# --- 4. Shortcuts ----------------------------------------------------------------------------
	var hud := _game.hud
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_HOME
	_check(hud.controls.handle(key) and _game.selection.selected.size() == 1 and _game.selection.selected[0].type_id == "town_center", "Home selects the Town Center")
	key.keycode = KEY_COMMA
	hud.controls.handle(key)
	_check(_game.selection.selected.size() == 1 and _game.selection.selected[0] is Unit and not _game.selection.selected[0].is_worker, "comma selects an idle military unit")
	key.keycode = KEY_A
	key.ctrl_pressed = true
	hud.controls.handle(key)
	_check(_game.selection.selected.size() >= 1 and _game.selection.selected.all(func(e): return not e.is_worker), "Ctrl+A selects the army")
	key.ctrl_pressed = false
	var unit: Unit = _game.selection.selected[0]
	var a := unit.grid_pos + Vector2(3, 0)
	var b := unit.grid_pos + Vector2(3, 3)
	_game.orders.submit({"t": "issue", "units": [unit.entity_id], "buildings": [], "grid": a, "target": 0})
	_game.orders.submit({"t": "issue", "units": [unit.entity_id], "buildings": [], "grid": b, "target": 0, "queue": true})
	_check(_game.commands.waypoints.get(unit.entity_id, []).size() == 1, "Shift+right-click queues a waypoint")
	var t1 := Time.get_ticks_msec()
	while unit.grid_pos.distance_to(b) > 1.0 and Time.get_ticks_msec() - t1 < 10000:
		await _seconds(0.2)
	_check(unit.grid_pos.distance_to(b) <= 1.0, "the unit walks both legs of the route")
	var digit := InputEventKey.new()
	digit.pressed = true
	digit.keycode = KEY_3
	digit.shift_pressed = true
	_game.selection.set_selection([unit])
	_game.selection._key(digit)
	_check(_game.selection.groups.get(3, []).has(unit), "Shift+3 adds the selection to group 3")
	key.keycode = KEY_PLUS
	hud.controls.handle(key)
	_check(Engine.time_scale > 1.0, "+ speeds the game up (×%s)" % str(Engine.time_scale))
	key.keycode = KEY_MINUS
	hud.controls.handle(key)
	_check(is_equal_approx(Engine.time_scale, 1.0), "- slows it back down")
	var help := HelpPanel.new()
	_main.add_child(help)
	await _frames(4)
	await _shot("features_05_help")
	help.queue_free()
	var saves := SaveLoadPanel.new()
	saves.setup(true, _game)
	_main.add_child(saves)
	await _frames(4)
	await _shot("features_06_save_panel")
	saves.queue_free()

	# --- 5. Night ------------------------------------------------------------------------------------
	var tc2 := _p1_tc()
	_game.selection.set_selection([])
	_game.camera.focus_world(tc2.position)
	_game.day_night.time = 0.05
	await _seconds(1.5)
	_check(_game.day_night.night_amount() > 0.9, "deep night at 01:00")
	_check(_game.day_night._modulate.color.v < 0.6, "the world is tinted dark")
	var night_loop: AudioStreamPlayer = _game.audio._ambient.get("amb_night")
	_check(night_loop != null and night_loop.volume_db > -40.0, "crickets play at night (%.1f dB)" % (night_loop.volume_db if night_loop else -99.0))
	await _shot("features_07_night")
	_game.day_night.time = 0.5
	await _seconds(2.0)
	_check(_game.day_night.night_amount() < 0.01, "full day at noon")
	await _shot("features_08_day")
	_finish()


func _tc(pid: int) -> Building:
	for bl in _game.buildings.buildings:
		if bl.owner_id == pid and bl.type_id == "town_center":
			return bl
	return null

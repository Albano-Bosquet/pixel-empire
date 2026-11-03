extends "res://src/debug/smoke_test.gd"
## Stage 4 smoke test:  -- --smoke=stage4 --mode=skirmish --victory=conquest
## Technologies through the UI, tech panel, minimap, pause menu, conquest
## victory + end screen, a rematch lost by Town Center destruction, and the
## title screen starting a match with a real click.

var _main: Node


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	_main = get_parent()
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_run4.call_deferred()


func _tc(owner: int) -> Building:
	for b in _game.buildings.buildings:
		if b.owner_id == owner and b.type_id == "town_center" and not b.dead:
			return b
	return null


func _run4() -> void:
	await _frames(10)
	var me := _game.local_state()
	var tc := _tc(1)
	for k in ["food", "wood", "gold", "stone"]:
		me.add(k, 3000)

	# 1. Technologies through the building's command panel.
	me.age = 1
	var bs := _game.buildings.place("blacksmith", 1, _find_build_spot("blacksmith", Iso.tile_of(tc.grid_pos) + Vector2i(6, -2)), true)
	var sw := _game.spawn_unit("swordsman", 1, bs.grid_pos + Vector2(3, 3))
	_game.camera.focus_world(bs.position)
	await _frames(3)
	await _click(_game.screen_from_world(bs.position + Vector2(0, -30)))
	_check(_game.selection.selected.size() == 1 and _game.selection.selected[0] == bs, "click selects the blacksmith")
	await _frames(3)
	await _shot("stage4_01_blacksmith_panel")

	# 1b. Phase B1 roster: every new unit spawns and renders; the stable lists its line.
	me.age = 3
	var st := _game.buildings.place("stable", 1, _find_build_spot("stable", Iso.tile_of(tc.grid_pos) + Vector2i(-7, 3)), true)
	var roster := ["militia", "pikeman", "greatsword", "skirmisher", "crossbowman", "hand_cannoneer",
		"cavalry_archer", "light_cavalry", "cavalier", "camel_rider",
		"battering_ram", "mangonel", "scorpion", "bombard_cannon", "trebuchet", "petard"]
	var shown: Array[Unit] = []
	for i in roster.size():
		shown.append(_game.spawn_unit(roster[i], 1, st.grid_pos + Vector2(2.5 + (i % 5) * 1.1, -1.5 + (i / 5) * 1.2)))
	_check(shown.all(func(u): return is_instance_valid(u) and u.is_alive()), "all %d new unit types spawn" % roster.size())
	var ws := _game.buildings.place("siege_workshop", 1, _find_build_spot("siege_workshop", Iso.tile_of(tc.grid_pos) + Vector2i(-7, -5)), true)
	_check(_game.production.enqueue_error(ws, "bombard_cannon") == "", "siege workshop can build bombard cannons in the Imperial Age")
	var ram_list: Array[Unit] = [shown[10]]
	var foe := _game.spawn_unit("swordsman", 2, shown[10].grid_pos + Vector2(1.5, 0))
	_game.combat.order_attack(ram_list, foe)
	_check(shown[10].target == null, "a ram refuses an order to attack infantry")
	_game.kill_unit(foe)
	_game.camera.focus_world(st.position + Vector2(40, 0))
	_game.selection.set_selection([st])
	await _frames(6)
	_check(_game.production.enqueue_error(st, "cavalier") == "", "stable can train cavaliers in the Imperial Age")
	await _shot("stageB1_01_new_units_stable_panel")
	for u in shown:
		_game.kill_unit(u)
	await _frames(2)
	# Petard: walks to an enemy house, explodes (house damaged, sapper dead).
	var house := _game.buildings.place("house", 2, _find_build_spot("house", Iso.tile_of(ws.grid_pos) + Vector2i(-4, 0)), true)
	var sapper := _game.spawn_unit("petard", 1, house.grid_pos + Vector2(2.5, 0))
	var sapper_list: Array[Unit] = [sapper]
	_game.combat.order_attack(sapper_list, house)
	var t1 := Time.get_ticks_msec()
	while sapper.is_alive() and Time.get_ticks_msec() - t1 < 8000:
		await _seconds(0.1)
	_check(not sapper.is_alive(), "petard blows itself up")
	_check(not is_instance_valid(house) or house.dead or house.hp < house.max_hp - 300, "petard blast wrecks the house")
	# Scorpion bolt passes through a line of enemies.
	var sc := _game.spawn_unit("scorpion", 1, ws.grid_pos + Vector2(0, 3.5))
	var line_a := _game.spawn_unit("militia", 2, sc.grid_pos + Vector2(3.0, 0))
	var line_b := _game.spawn_unit("militia", 2, sc.grid_pos + Vector2(4.2, 0))
	for m in [line_a, line_b]:
		m.stance = "stand"
	var sc_list: Array[Unit] = [sc]
	_game.combat.order_attack(sc_list, line_a)
	var t2 := Time.get_ticks_msec()
	while line_b.hp == line_b.max_hp and Time.get_ticks_msec() - t2 < 8000:
		await _seconds(0.1)
	_check(line_b.hp < line_b.max_hp, "scorpion bolt also hits the enemy behind its target")
	for m in [line_a, line_b]:
		if m.is_alive():
			_game.kill_unit(m)
	_game.kill_unit(sc)
	await _run_b3(me, tc)
	await _run_b4(me, tc)
	me.age = 1
	_game.selection.set_selection([bs])
	await _frames(3)
	_key(KEY_F, true)
	_key(KEY_F, false)
	await _frames(2)
	_check(bs.queue.has("forging"), "hotkey F queues Forging at the blacksmith")
	Engine.time_scale = 10.0
	var t0 := Time.get_ticks_msec()
	while not me.researched.has("forging") and Time.get_ticks_msec() - t0 < 15000:
		await _seconds(0.2)
	Engine.time_scale = 1.0
	_check(me.researched.has("forging"), "Forging completes")
	_check(sw.attack_bonus == 1, "existing swordsman gets +1 attack (%d)" % sw.attack_bonus)
	var sw2 := _game.spawn_unit("swordsman", 1, bs.grid_pos + Vector2(3, 4))
	_check(sw2.attack_bonus == 1, "newly trained swordsman also gets +1 attack")
	_check(_game.production.enqueue_error(bs, "forging") == "Already researched", "researched tech cannot be queued again")
	_check(_game.production.enqueue_error(bs, "iron_casting").begins_with("Requires"), "Iron Casting locked until Castle Age")

	var villager: Unit = null
	for u in _game.unit_system.units:
		if u.owner_id == 1 and u.is_worker:
			villager = u
			break
	var hp0 := villager.max_hp
	_check(_game.production.enqueue(tc, "loom") and _game.production.enqueue(tc, "wheelbarrow"), "Loom and Wheelbarrow queued at the Town Center")
	Engine.time_scale = 12.0
	t0 = Time.get_ticks_msec()
	while not me.researched.has("wheelbarrow") and Time.get_ticks_msec() - t0 < 20000:
		await _seconds(0.2)
	Engine.time_scale = 1.0
	_check(villager.max_hp == hp0 + 15, "Loom: villagers +15 HP (%d -> %d)" % [hp0, villager.max_hp])
	_check(is_equal_approx(_game.economy.capacity(1), 12.5), "Wheelbarrow: carry capacity 12.5 (%.2f)" % _game.economy.capacity(1))

	# 2. Technology panel.
	_key(KEY_F2, true)
	_key(KEY_F2, false)
	await _seconds(0.3)
	_check(_game.hud.tech_panel.visible, "F2 opens the technology panel")
	await _shot("stage4_02_tech_panel")
	_key(KEY_F2, true)
	_key(KEY_F2, false)
	await _frames(2)
	_check(not _game.hud.tech_panel.visible, "F2 closes it again")

	# 3. Minimap: left click jumps the camera, right click orders units.
	var mm := _game.hud.minimap
	var cam0 := _game.camera.position
	var target_grid := Vector2(_game.map.width * 0.5, _game.map.height * 0.5)
	var local := mm.grid_to_local(target_grid)
	var screen := mm.get_global_transform_with_canvas() * local
	_mouse_button(MOUSE_BUTTON_LEFT, true, screen)
	_mouse_button(MOUSE_BUTTON_LEFT, false, screen)
	await _frames(3)
	_check(_game.camera.position.distance_to(Iso.grid_to_world(target_grid)) < 40.0 and _game.camera.position != cam0, "minimap click centres the camera")
	_game.camera.focus_world(tc.position)
	_game.selection.set_selection([sw])
	var near := mm.get_global_transform_with_canvas() * mm.grid_to_local(sw.grid_pos + Vector2(6, 0))
	_mouse_button(MOUSE_BUTTON_RIGHT, true, near)
	_mouse_button(MOUSE_BUTTON_RIGHT, false, near)
	await _frames(3)
	_check(sw.state == Unit.State.MOVING, "minimap right-click moves the selected unit")
	await _seconds(0.5)
	await _shot("stage4_03_hud_minimap")

	# 4. Pause menu.
	_game.selection.set_selection([])
	_key(KEY_F10, true)
	_key(KEY_F10, false)
	await _frames(3)
	_check(get_tree().paused, "F10 pauses the game")
	await _shot("stage4_04_pause")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check(not get_tree().paused, "Esc resumes")

	# 5. Conquest victory: wipe out player 2.
	for u in _game.unit_system.units.duplicate():
		if u.owner_id == 2 and not u.dead:
			u.take_damage(u.hp, sw)
	for b in _game.buildings.buildings.duplicate():
		if b.owner_id == 2 and not b.dead:
			b.take_damage(b.hp, sw)
	await _seconds(1.5)
	_check(_game.victory.over and _game.victory.winners == [1], "destroying every enemy entity wins by conquest")
	_check(_main._end != null, "end screen shows")
	await _seconds(0.3)
	await _shot("stage4_05_victory")

	# 6. Rematch (Town Center rule) and defeat.
	var cfg: Dictionary = _main._last_config.duplicate()
	cfg["victory"] = "town_center"
	_main.start_game(cfg)
	await _frames(10)
	_game = _main.game
	for ai in _game.ai_players:
		ai.set_physics_process(false)
	_check(_game.victory.condition == "town_center", "rematch uses the Town Center rule")
	var my_tc := _tc(1)
	my_tc.take_damage(my_tc.hp, null)
	await _seconds(1.5)
	_check(_game.victory.over and not _game.victory.winners.has(1) and _game.local_state().defeated, "losing the Town Center is a defeat")
	await _shot("stage4_06_defeat")

	# 7. Title screen and starting a match from it with a real click.
	_main.show_menu()
	await _seconds(1.0)
	await _shot("stage4_07_main_menu")
	var start_btn: Button = _main._menu._start
	var c := start_btn.get_global_rect().get_center()
	_mouse_button(MOUSE_BUTTON_LEFT, true, c)
	_mouse_button(MOUSE_BUTTON_LEFT, false, c)
	await _frames(10)
	_check(_main.game != null and _main.game.name == "Game" and _main.game.config.get("mode") == "skirmish", "Start game button launches a skirmish")
	_check(_main.game.ai_players.size() == 1, "skirmish has an AI opponent")
	_finish()


## Phase B3: every new building places and renders, the market exchange moves
## prices, a trade cart earns gold between two markets, the bombard tower fires.
func _run_b3(me: PlayerState, tc: Building) -> void:
	var base := Iso.tile_of(tc.grid_pos)
	var placed := {}
	for item in [["lumber_camp", Vector2i(6, 6)], ["mining_camp", Vector2i(9, 6)], ["university", Vector2i(6, 10)],
			["outpost", Vector2i(10, 10)], ["bombard_tower", Vector2i(12, 8)], ["market", Vector2i(-2, 9)]]:
		placed[item[0]] = _game.buildings.place(item[0], 1, _find_build_spot(item[0], base + item[1]), true)
	_check(placed.values().all(func(b): return b != null and b.is_complete()), "all 6 new building types place")
	var m1: Building = placed["market"]
	var gold0 := int(me.resources["gold"])
	var food_price := _game.market.buy_cost("food")
	_check(_game.market.buy(me, "food"), "market buys 100 food")
	_check(int(me.resources["gold"]) == gold0 - food_price, "buying costs the quoted %d gold" % food_price)
	_check(_game.market.buy_cost("food") > food_price, "buying raises the food price")
	_check(_game.market.sell(me, "wood"), "market sells 100 wood")
	_game.camera.focus_world(placed["university"].position + Vector2(-60, 0))
	_game.selection.set_selection([m1])
	await _frames(6)
	await _shot("stageB3_01_new_buildings_market_panel")
	# Trade: a second market far away, a cart from the first one.
	var m2 := _game.buildings.place("market", 1, _find_build_spot("market", base + Vector2i(-6, -20)), true)
	_check(m2 != null, "second market placed")
	var cart := _game.spawn_unit("trade_cart", 1, m1.grid_pos + Vector2(2.5, 2.5))
	var carts: Array[Unit] = [cart]
	_game.market.order_trade(carts, m2)
	_check(not _game.market.route_of(cart).is_empty(), "trade cart gets a route")
	var gold1 := int(me.resources["gold"])
	Engine.time_scale = 8.0
	var t0 := Time.get_ticks_msec()
	while int(me.resources["gold"]) <= gold1 and Time.get_ticks_msec() - t0 < 20000:
		await _seconds(0.2)
	Engine.time_scale = 1.0
	_check(int(me.resources["gold"]) > gold1, "trade cart delivers and earns gold (+%d)" % (int(me.resources["gold"]) - gold1))
	_game.kill_unit(cart)
	# Bombard tower shoots an enemy in range.
	var bt: Building = placed["bombard_tower"]
	var foe := _game.spawn_unit("knight", 2, bt.grid_pos + Vector2(4, 0))
	foe.stance = "stand"
	var t1 := Time.get_ticks_msec()
	while foe.is_alive() and foe.hp == foe.max_hp and Time.get_ticks_msec() - t1 < 8000:
		await _seconds(0.1)
	_check(not foe.is_alive() or foe.hp < foe.max_hp, "bombard tower hits the enemy knight")
	if foe.is_alive():
		_game.kill_unit(foe)


## Phase B4: wall pieces join up, a gate lets only its owner through, monks heal
## and convert, a standing Wonder starts the victory countdown.
func _run_b4(me: PlayerState, tc: Building) -> void:
	var base := Iso.tile_of(tc.grid_pos) + Vector2i(-12, 6)
	var start := _find_build_spot("wonder", base) + Vector2i(0, 2)
	var pieces: Array[Building] = []
	for i in 5:
		var t := start + Vector2i(i, 0)
		if _game.buildings.placement_error("stone_wall", t) == "":
			pieces.append(_game.buildings.place("gate" if i == 2 else "stone_wall", 1, t, true))
	_check(pieces.size() == 5, "a line of 5 wall pieces places (%d)" % pieces.size())
	_check(pieces.size() >= 2 and pieces[0]._arms.has("px") and pieces[1]._arms.has("nx"), "neighbouring wall pieces connect with arms")
	if pieces.size() == 5:
		var g := pieces[2].origin
		_check(_game.pathfinder.is_walkable(g, 1) and not _game.pathfinder.is_walkable(g, 2), "gate opens for its owner only")
	var mon := _game.buildings.place("monastery", 1, _find_build_spot("monastery", base + Vector2i(1, 4)), true)
	_check(_game.production.enqueue_error(mon, "monk") == "", "monastery trains monks in the Castle Age")
	# Heal.
	var monk := _game.spawn_unit("monk", 1, mon.grid_pos + Vector2(3, 2))
	var hurt := _game.spawn_unit("swordsman", 1, monk.grid_pos + Vector2(1.2, 0))
	hurt.hp = 20
	var t0 := Time.get_ticks_msec()
	while hurt.hp <= 20 and Time.get_ticks_msec() - t0 < 6000:
		await _seconds(0.2)
	_check(hurt.hp > 20, "monk heals a wounded ally (%d hp)" % hurt.hp)
	_game.kill_unit(hurt)
	# Convert.
	var foe := _game.spawn_unit("militia", 2, monk.grid_pos + Vector2(3, 0))
	foe.stance = "stand"
	var monks: Array[Unit] = [monk]
	_game.monks.order_convert(monks, foe)
	Engine.time_scale = 4.0
	var t1 := Time.get_ticks_msec()
	while foe.is_alive() and foe.owner_id != 1 and Time.get_ticks_msec() - t1 < 8000:
		await _seconds(0.1)
	Engine.time_scale = 1.0
	_check(foe.is_alive() and foe.owner_id == 1, "monk converts the enemy militia")
	_game.camera.focus_world(mon.position + Vector2(-40, -10))
	_game.selection.set_selection([monk])
	await _frames(6)
	await _shot("stageB4_01_walls_gate_monastery_monk")
	for u in [monk, foe]:
		if u.is_alive():
			_game.kill_unit(u)
	# Wonder countdown (removed again so the smoke continues).
	var w := _game.buildings.place("wonder", 1, _find_build_spot("wonder", Iso.tile_of(tc.grid_pos) + Vector2i(10, -12)), true)
	await _seconds(1.5)
	var left := _game.victory.wonder_remaining(1)
	_check(left < float(GameData.rules.get("wonder_victory_seconds", 300)) and left > 0.0, "a standing Wonder starts the victory countdown (%.0f s left)" % left)
	_game.camera.focus_world(w.position + Vector2(0, -60))
	_game.selection.set_selection([w])
	await _frames(6)
	await _shot("stageB4_02_wonder")
	_game.selection.set_selection([])
	_game.buildings.remove(w)
	for p in pieces:
		_game.buildings.remove(p)
	_game.buildings.remove(mon)
	await _frames(3)
	_check(_game.victory.wonder_remaining(1) == INF, "countdown stops when the Wonder is gone")

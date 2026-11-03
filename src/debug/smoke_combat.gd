extends "res://src/debug/smoke_test.gd"
## Stage 3 smoke tests. Run:
##   -- --smoke=combat --mode=skirmish   (AI frozen; scripted fights)
##   -- --smoke=ai --mode=skirmish --difficulty=hard   (AI plays; observed)


func run_mode(game: Game, mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	if mode == "fx":
		_fx_check.call_deferred()
	elif mode == "ai":
		_ai.call_deferred()
	else:
		for ai in game.ai_players:
			ai.set_physics_process(false)
		_combat.call_deferred()


func _p1_tc() -> Building:
	for b in _game.buildings.buildings:
		if b.owner_id == 1 and b.type_id == "town_center":
			return b
	return null


func _spawn_group(id: String, owner: int, at: Vector2, n: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for i in n:
		var u := _game.spawn_unit(id, owner, at + Vector2(i % 3, i / 3) * 0.6)
		if u:
			out.append(u)
	return out


func _alive(list: Array) -> int:
	return list.filter(func(u): return is_instance_valid(u) and not u.dead).size()


func _open_spot(near: Vector2, clearance: int = 3) -> Vector2:
	for r in range(0, 20):
		for k in 16:
			var a := k * TAU / 16.0
			var g := near + Vector2(cos(a), sin(a)) * r
			var t := Iso.tile_of(g)
			var ok := true
			for dy in range(-clearance, clearance + 1):
				for dx in range(-clearance, clearance + 1):
					if not _game.pathfinder.is_walkable(t + Vector2i(dx, dy)):
						ok = false
			if ok:
				return Iso.tile_center(t)
	return near


func _combat() -> void:
	await _frames(10)
	var tc := _p1_tc()
	var me := _game.local_state()
	Engine.physics_ticks_per_second = 120

	# 1. Melee auto-engage: 4 swordsmen vs 2 enemy swordsmen.
	var arena := _open_spot(tc.grid_pos + Vector2(9, 0))
	var mine := _spawn_group("swordsman", 1, arena, 4)
	var theirs := _spawn_group("swordsman", 2, arena + Vector2(3.0, 0.5), 2)
	_game.fog.update_now()
	_check(theirs.all(func(u): return u.visible), "enemies inside our sight are visible")
	_game.camera.focus_world(Iso.grid_to_world(arena + Vector2(1.5, 0)))
	await _seconds(1.6)
	_check(mine.any(func(u): return u.target != null), "idle soldiers auto-acquire visible enemies")
	await _shot("stage3_01_melee")
	Engine.time_scale = 3.0
	var t0 := Time.get_ticks_msec()
	while _alive(theirs) > 0 and Time.get_ticks_msec() - t0 < 15000:
		await _seconds(0.2)
	_check(_alive(theirs) == 0, "enemy swordsmen killed by the larger group")
	_check(_alive(mine) >= 2, "most of our swordsmen survive (%d/4)" % _alive(mine))
	await _seconds(2.0)
	var max_d := 0.0
	for u in mine:
		if is_instance_valid(u) and not u.dead:
			max_d = maxf(max_d, u.grid_pos.distance_to(arena))
	_check(max_d < 5.0, "soldiers return to their post after the fight (max %.1f tiles)" % max_d)
	Engine.time_scale = 1.0

	# 2. Archers shoot visible arrows at spearmen.
	var a_spot := _open_spot(tc.grid_pos + Vector2(0, 10))
	var archers := _spawn_group("archer", 1, a_spot, 4)
	var spears := _spawn_group("spearman", 2, a_spot + Vector2(4.0, 0.0), 2)
	_game.camera.focus_world(Iso.grid_to_world(a_spot + Vector2(2, 0)))
	var saw_arrows := false
	t0 = Time.get_ticks_msec()
	var shot_taken := false
	while _alive(spears) > 0 and Time.get_ticks_msec() - t0 < 20000:
		await _frames(2)
		if not _game.combat.projectiles.is_empty():
			saw_arrows = true
			if not shot_taken and _game.combat.projectiles.any(func(p): return p["t"] > 0.4):
				shot_taken = true
				await _shot("stage3_02_arrows")
	_check(saw_arrows, "archers fire visible projectiles")
	_check(_alive(spears) == 0, "archers kill the spearmen")
	_check(_alive(archers) >= 1, "archers survive (%d/4)" % _alive(archers))

	# 3. Damage formula sanity on live entities.
	var sw := _spawn_group("swordsman", 2, _open_spot(tc.grid_pos + Vector2(-9, 0)), 1)[0]
	var kn := _spawn_group("knight", 1, sw.grid_pos + Vector2(3.5, 0), 1)[0]
	kn.stance = "stand"  # do not auto-engage: the right-click must start the fight
	_game.fog.update_now()
	_check(CombatSystem.compute_damage(3, "melee", {"cavalry": 15}, kn) == 16, "spearman vs knight: max(1, 3 - 2 armor) + 15 bonus = 16")
	_check(CombatSystem.compute_damage(4, "pierce", {}, kn) == 2, "knight pierce armor reduces arrows to 2")

	# 4. Right-click attack order (knight hunts the swordsman).
	_game.selection.set_selection([kn])
	_game.camera.focus_world(sw.position)
	await _frames(3)
	var sp_screen := _game.screen_from_world(sw.position + Vector2(0, -16))
	_mouse_button(MOUSE_BUTTON_RIGHT, true, sp_screen)
	_mouse_button(MOUSE_BUTTON_RIGHT, false, sp_screen)
	await _frames(3)
	_check(kn.target == sw, "right-click on an enemy orders an attack")
	Engine.time_scale = 3.0
	t0 = Time.get_ticks_msec()
	while is_instance_valid(sw) and not sw.dead and Time.get_ticks_msec() - t0 < 15000:
		await _seconds(0.2)
	_check(not is_instance_valid(sw) or sw.dead, "ordered attack kills the target")
	Engine.time_scale = 1.0

	# 5. Catapult vs an enemy house: area damage, fire, destruction, rubble.
	var h_origin := _find_build_spot("house", Iso.tile_of(tc.grid_pos) + Vector2i(-12, 8))
	var house := _game.buildings.place("house", 2, h_origin, true)
	var cat := _spawn_group("catapult", 1, house.grid_pos + Vector2(5.5, 0), 1)[0]
	_game.fog.update_now()
	var cats: Array[Unit] = [cat]
	_game.combat.order_attack(cats, house)
	_game.camera.focus_world(house.position + Vector2(40, 0))
	Engine.time_scale = 3.0
	t0 = Time.get_ticks_msec()
	var burn_shot := false
	while is_instance_valid(house) and not house.dead and Time.get_ticks_msec() - t0 < 25000:
		await _seconds(0.1)
		if not burn_shot and is_instance_valid(house) and house.hp < house.max_hp * 0.45:
			burn_shot = true
			Engine.time_scale = 1.0
			await _seconds(0.6)
			await _shot("stage3_03_catapult_burning")
			Engine.time_scale = 3.0
	Engine.time_scale = 1.0
	_check(not is_instance_valid(house) or house.dead, "catapult destroys the house")
	_check(_game.static_entity_at(h_origin) == null, "destroyed house frees its tiles")
	await _seconds(0.5)
	await _shot("stage3_04_rubble")

	# 6. Our watch tower shoots an intruder.
	me.age = 1
	var t_origin := _find_build_spot("tower", Iso.tile_of(tc.grid_pos) + Vector2i(0, -9))
	var tower := _game.buildings.place("tower", 1, t_origin, true)
	var intruder := _spawn_group("spearman", 2, tower.grid_pos + Vector2(4, 0), 1)[0]
	intruder.stance = "stand"
	var hp0 := intruder.hp
	await _seconds(3.0)
	_check(not is_instance_valid(intruder) or intruder.dead or intruder.hp < hp0, "watch tower damages enemies in range")

	# 7. Fog of war hides far enemies; scouting reveals them.
	var far := _game.map.start_positions[1]
	var enemy_tc_tile := Vector2i(far)
	var far_unit := _spawn_group("swordsman", 2, Iso.tile_center(far) + Vector2(3, 3), 1)[0]
	_game.fog.update_now()
	_check(not far_unit.visible, "enemy unit in unexplored fog is hidden")
	_check(not _game.fog.is_explored(1, enemy_tc_tile), "enemy base starts unexplored")
	var scout := _spawn_group("scout", 1, Iso.tile_center(far) + Vector2(-2, -2), 1)[0]
	_game.fog.update_now()
	_check(far_unit.visible, "a nearby scout reveals the enemy unit")
	_game.camera.focus_world(Iso.grid_to_world(tc.grid_pos + Vector2(6, 6)))
	await _seconds(0.4)
	await _shot("stage3_05_fog")

	# 8. Advancing to the Feudal Age through the Town Center.
	me.age = 0
	me.add("food", 600)
	var food0: int = me.resources["food"]
	_check(_game.production.enqueue(tc, "feudal_age"), "Feudal Age research queued")
	_check(me.resources["food"] == food0 - 500, "Feudal Age costs 500 food")
	Engine.time_scale = 12.0
	t0 = Time.get_ticks_msec()
	while me.age < 1 and Time.get_ticks_msec() - t0 < 20000:
		await _seconds(0.25)
	Engine.time_scale = 1.0
	_check(me.age == 1, "player reaches the Feudal Age")
	_check(_game.buildings.requirement_error(me, "archery_range") != Loc.msg("Requires %s", ["Feudal Age"]), "Feudal buildings unlock")
	Engine.physics_ticks_per_second = 60
	_finish()


# --- AI observation -------------------------------------------------------------

func _ai() -> void:
	await _frames(10)
	var ai: AIPlayer = _game.ai_players[0]
	var tc := _p1_tc()
	var p1_hp0 := 0
	for b in _game.buildings.buildings:
		if b.owner_id == 1:
			p1_hp0 += b.hp
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 8.0
	var attacked := false
	var hit_at := [Vector2.INF]
	EventBus.under_attack.connect(func(pid: int, where: Vector2) -> void:
		if pid == 1:
			hit_at[0] = where)
	var t0 := Time.get_ticks_msec()
	var game_minutes := float(ai.diff.get("first_attack_minute", 7)) + 6.0
	var shot_base := false
	while ai.elapsed < game_minutes * 60.0 and Time.get_ticks_msec() - t0 < 240000:
		await _seconds(1.0)
		for u in _game.unit_system.units:
			if u.owner_id == 2 and ai.wave.has(u) and u.grid_pos.distance_to(tc.grid_pos) < 14.0:
				attacked = true
		if not shot_base and ai.elapsed > game_minutes * 60.0 * 0.6:
			shot_base = true
			Engine.time_scale = 1.0
			_game.fog.set_enabled(false)
			var home := ai._home()
			_game.camera.focus_world(Iso.grid_to_world(home))
			await _seconds(0.6)
			await _shot("stage3_06_ai_base")
			_game.fog.set_enabled(true)
			Engine.time_scale = 8.0
		if attacked:
			break
	Engine.time_scale = 1.0
	var vill := 0
	var mil := 0
	for u in _game.unit_system.units:
		if u.owner_id == 2:
			if u.is_worker:
				vill += 1
			else:
				mil += 1
	var types := {}
	for b in _game.buildings.buildings:
		if b.owner_id == 2:
			types[b.type_id] = types.get(b.type_id, 0) + 1
	_log.append("AI after %.1f game min: villagers %d, military %d, age %d, buildings %s, explored %.0f%%, resources %s" % [ai.elapsed / 60.0, vill, mil, ai.player.age, str(types), _game.fog.explored_fraction(2) * 100.0, str(ai.player.resources)])
	var farms_done := 0
	for b in _game.buildings.buildings:
		if b.owner_id == 2 and b.is_farm() and b.is_complete():
			farms_done += 1
	var tasks := {}
	for u in _game.unit_system.units:
		if u.owner_id == 2 and u.is_worker:
			var key: String = "idle" if u.task.is_empty() else "%s:%s:%s" % [u.task["type"], u.task.get("kind", ""), u.task.get("phase", "")]
			tasks[key] = tasks.get(key, 0) + 1
	_log.append("AI farms complete %d, rebalanced %d, villager tasks %s, gathered %s" % [farms_done, ai.rebalanced, str(tasks), str(ai.player.stats["gathered"])])
	_check(vill >= 12, "AI grows its economy (%d villagers)" % vill)
	_check(types.get("house", 0) >= 2, "AI builds houses (%d)" % types.get("house", 0))
	_check(types.has("barracks") or types.has("archery_range") or types.has("stable"), "AI builds military buildings")
	_check(types.has("mill") or types.has("storehouse"), "AI builds drop sites next to resources")
	_check(mil >= 3 or attacked, "AI trains an army (%d)" % mil)
	_check(_game.fog.explored_fraction(2) > 0.15, "AI scouts the map (%.0f%%)" % (_game.fog.explored_fraction(2) * 100.0))
	_check(attacked, "AI sends an attack to the player's base")
	if attacked:
		# Follow the wave until it actually hurts the player's base.
		Engine.time_scale = 4.0
		var hurt := false
		t0 = Time.get_ticks_msec()
		var shot_done := false
		while not hurt and Time.get_ticks_msec() - t0 < 60000:
			await _seconds(0.05)
			if not shot_done and hit_at[0] != Vector2.INF:
				shot_done = true
				Engine.time_scale = 1.0
				_game.camera.focus_world(Iso.grid_to_world(hit_at[0]))
				await _seconds(0.5)
				await _shot("stage3_07_ai_attack")
				Engine.time_scale = 4.0
			var hp_now := 0
			for b in _game.buildings.buildings:
				if b.owner_id == 1:
					hp_now += b.hp
			var lost: int = _game.local_state().stats["units_lost"]
			hurt = hp_now < p1_hp0 or lost > 0 or _game.population(1) < 4
		Engine.time_scale = 1.0
		_check(hurt, "the AI wave damages the player's base")
		var fighter: Unit = null
		for u in ai.wave:
			if is_instance_valid(u) and not u.dead:
				fighter = u

	Engine.physics_ticks_per_second = 60
	_finish()


func _fx_check() -> void:
	await _frames(5)
	var tc := _p1_tc()
	var h := _game.buildings.place("house", 1, _find_build_spot("house", Iso.tile_of(tc.grid_pos) + Vector2i(5, 0)), true)
	h.take_damage(int(h.max_hp * 0.7), null)
	_game.camera.set_zoom_index(_game.camera.zoom_levels.size() - 1)
	_game.camera.focus_world(h.position + Vector2(0, -30))
	await _seconds(1.5)
	await _shot("fx_fire")
	_log.append("fires: %s" % str(h._fires.map(func(f): return [f.emitting, f.global_position, f.visible, f.is_visible_in_tree()])))
	_finish()

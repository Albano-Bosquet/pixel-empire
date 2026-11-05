extends "res://src/debug/smoke_test.gd"
## Modern eras smoke test:  -- --smoke=modern --mode=skirmish --seed=4242
## Gunpowder and Industrial age research, the new buildings, every new unit,
## blunderbuss spread, aircraft flight / ammo / rearming / bombing, flak fire.

func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_run.call_deferred()


func _tc(owner: int) -> Building:
	for b in _game.buildings.buildings:
		if b.owner_id == owner and b.type_id == "town_center" and not b.dead:
			return b
	return null


func _run() -> void:
	await _frames(10)
	var me := _game.local_state()
	for k in ["food", "wood", "gold", "stone"]:
		me.add(k, 9000)
	var tc := _tc(1)
	var base := Iso.tile_of(tc.grid_pos)

	# 1. Age research through the town center.
	me.age = 3
	for age_id in ["gunpowder_age", "industrial_age"]:
		_check(_game.production.enqueue_error(tc, age_id) == "", "%s can be researched" % age_id)
		_game.production.enqueue(tc, age_id)
		Engine.time_scale = 16.0
		var t0 := Time.get_ticks_msec()
		var want := int(GameData.ages[age_id]["sets_age"])
		while me.age < want and Time.get_ticks_msec() - t0 < 30000:
			await _seconds(0.2)
		Engine.time_scale = 1.0
		_check(me.age == want, "reached %s" % Hud.AGE_NAMES[want])

	# 2. New buildings.
	var placed := {}
	for item in [["foundry", Vector2i(7, 5)], ["airfield", Vector2i(-9, 6)], ["flak_fort", Vector2i(6, -8)]]:
		placed[item[0]] = _game.buildings.place(item[0], 1, _find_build_spot(item[0], base + item[1]), true)
	_check(placed.values().all(func(b): return b != null and b.is_complete()), "foundry, airfield and flak fort place")
	_check(_game.production.enqueue_error(placed["airfield"], "biplane_bomber") == "", "airfield builds bombers")
	_check(_game.production.enqueue_error(placed["foundry"], "mortar") == "", "foundry casts mortars")

	# 3. Every new unit spawns.
	var roster := ["blunderbussier", "musketeer", "grenadier", "rifleman", "dragoon", "field_cannon", "mortar",
		"biplane_fighter", "biplane_bomber", "observation_balloon"]
	var shown: Array[Unit] = []
	var field: Building = placed["airfield"]
	for i in roster.size():
		shown.append(_game.spawn_unit(roster[i], 1, field.grid_pos + Vector2(3.0 + (i % 5) * 1.1, -2.0 + (i / 5) * 1.3)))
	_check(shown.all(func(u): return is_instance_valid(u) and u.is_alive()), "all %d modern unit types spawn" % roster.size())
	_game.camera.focus_world(field.position + Vector2(60, -20))
	await _frames(20)
	await _shot("modern_01_units_airfield")
	for u in shown:
		_game.kill_unit(u)
	await _frames(2)

	# 4. Blunderbuss spread hits two enemies at once.
	var spot := Iso.tile_center(_find_build_spot("house", base + Vector2i(-4, -12)))
	var bb := _game.spawn_unit("blunderbussier", 1, spot)
	var m1 := _game.spawn_unit("militia", 2, spot + Vector2(2.0, 0.0))
	var m2 := _game.spawn_unit("militia", 2, spot + Vector2(2.3, 0.35))
	for m in [m1, m2]:
		m.stance = "stand"
	var bl: Array[Unit] = [bb]
	_game.combat.order_attack(bl, m1)
	var t1 := Time.get_ticks_msec()
	while (m1.hp == m1.max_hp or m2.hp == m2.max_hp) and Time.get_ticks_msec() - t1 < 8000:
		await _seconds(0.1)
	_check(m1.hp < m1.max_hp and m2.hp < m2.max_hp, "one blunderbuss blast wounds both militia")
	for u in [bb, m1, m2]:
		if u.is_alive():
			_game.kill_unit(u)

	# 5. Fighter: melee cannot answer, it shoots, runs dry, rearms at the airfield.
	var fighter := _game.spawn_unit("biplane_fighter", 1, field.grid_pos + Vector2(4, 0))
	var foe := _game.spawn_unit("swordsman", 2, fighter.grid_pos + Vector2(2.5, 0))
	var fl: Array[Unit] = [foe]
	_game.combat.order_attack(fl, fighter)
	_check(foe.target == null, "a swordsman cannot attack an aircraft")
	foe.max_hp = 2000
	foe.hp = 2000
	var fgl: Array[Unit] = [fighter]
	_game.combat.order_attack(fgl, foe)
	Engine.time_scale = 6.0
	var t2 := Time.get_ticks_msec()
	var samples := 0
	var moving := 0
	var attack_frames := 0
	var facings := {}
	var phases := {}
	var low := INF
	var high := 0.0
	var dive_shot := false
	var climb_shot := false
	while fighter.ammo != 0 and Time.get_ticks_msec() - t2 < 45000:
		await _seconds(0.1)
		if samples > 0 or fighter.velocity.length() > 0.5:  # count from take-off
			samples += 1
			if fighter.velocity.length() > 0.5:
				moving += 1
		if fighter._anim == "attack":
			attack_frames += 1
		facings[fighter.facing] = true
		phases[_game.air.run_phase(fighter)] = true
		low = minf(low, fighter.flight_height())
		high = maxf(high, fighter.flight_height())
		var d := fighter.grid_pos.distance_to(foe.grid_pos)
		if (not dive_shot and fighter.flight_height() < fighter.altitude * 0.65 and d < 1.0) or (dive_shot and not climb_shot and d > 2.5 and fighter.ammo < 25):
			Engine.time_scale = 1.0
			_game.camera.position = foe.position
			await _shot("modern_03_fighter_dive" if not dive_shot else "modern_04_fighter_climb")
			if dive_shot:
				climb_shot = true
			dive_shot = true
			Engine.time_scale = 6.0
	_check(moving == samples, "the engaged fighter never hangs still (%d/%d samples moving)" % [moving, samples])
	_check(phases.has("dive") and phases.has("lap"), "it alternates dives and climbing laps")
	_check(low < fighter.altitude * 0.7 and high > fighter.altitude * 0.95, "it drops towards the target and climbs back (%.0f..%.0f px)" % [low, high])
	_check(facings.size() >= 6, "it turns right round between passes")
	_check(attack_frames >= 5, "it plays its attack animation on the passes")
	_check(foe.hp < 2000, "the fighter strafes the swordsman")
	_check(fighter.ammo == 0, "the fighter runs out of ammunition")
	var t3 := Time.get_ticks_msec()
	var rearm_samples := 0
	var rearm_moving := 0
	while fighter.ammo == 0 and Time.get_ticks_msec() - t3 < 45000:
		await _seconds(0.1)
		if _game.air.phase(fighter) == "rearming":
			rearm_samples += 1
			if fighter.velocity.length() > 0.5:
				rearm_moving += 1
	Engine.time_scale = 1.0
	_check(rearm_samples > 0 and rearm_moving == rearm_samples, "it circles the airfield while rearming (%d/%d)" % [rearm_moving, rearm_samples])
	_check(fighter.ammo == int(GameData.unit("biplane_fighter")["ammo"]), "it rearms at the airfield")
	_game.kill_unit(foe)
	# Flies straight over obstacles to a far point.
	var far := Iso.tile_center(base + Vector2i(18, 18))
	_game.commands.move_group(fgl, far)
	Engine.time_scale = 6.0
	var t4 := Time.get_ticks_msec()
	while fighter.grid_pos.distance_to(far) > 2.5 and Time.get_ticks_msec() - t4 < 15000:
		await _seconds(0.1)
	Engine.time_scale = 1.0
	_check(fighter.grid_pos.distance_to(far) <= 2.5, "the fighter flies straight to a far point")
	var idle_moving := 0
	for i in 10:
		await _seconds(0.2)
		if fighter.velocity.length() > 0.5:
			idle_moving += 1
	_check(idle_moving == 10, "with nothing to do it keeps circling (%d/10)" % idle_moving)
	_game.kill_unit(fighter)

	# 6. Bomber hits an enemy house.
	var house := _game.buildings.place("house", 2, _find_build_spot("house", base + Vector2i(10, 12)), true)
	var bomber := _game.spawn_unit("biplane_bomber", 1, house.grid_pos + Vector2(-6, 0))
	var bml: Array[Unit] = [bomber]
	_game.combat.order_attack(bml, house)
	Engine.time_scale = 4.0
	var t5 := Time.get_ticks_msec()
	while is_instance_valid(house) and not house.dead and house.hp == house.max_hp and Time.get_ticks_msec() - t5 < 15000:
		await _seconds(0.1)
	Engine.time_scale = 1.0
	_check(not is_instance_valid(house) or house.dead or house.hp < house.max_hp, "the bomber damages the house")
	_game.kill_unit(bomber)

	# 7. Flak shoots down an enemy plane; ground units are ignored.
	var flak: Building = placed["flak_fort"]
	var raider := _game.spawn_unit("biplane_fighter", 2, flak.grid_pos + Vector2(4, 0))
	raider.stance = "stand"
	# Out of reach of the town center's arrows, inside the flak's range.
	var away := (flak.grid_pos - tc.grid_pos).normalized()
	var walker := _game.spawn_unit("militia", 2, flak.grid_pos + away * 4.0)
	walker.stance = "stand"
	flak.turret_goal = PI * 0.75
	flak.turret_angle = PI * 0.75
	var t6 := Time.get_ticks_msec()
	var aimed := INF
	var shot_taken := false
	_game.camera.focus_world(flak.position + Vector2(40, -30))
	while raider.is_alive() and Time.get_ticks_msec() - t6 < 10000:
		await _seconds(0.1)
		var seen_at := Iso.world_to_grid(raider.position - Vector2(0, raider.flight_height()))
		aimed = minf(aimed, absf(wrapf(flak.turret_angle - (seen_at - flak.grid_pos).angle(), -PI, PI)))
		if aimed < 0.4 and not shot_taken:
			shot_taken = true
			await _shot("modern_02a_flak_aiming")
	_check(not raider.is_alive(), "the flak fort shoots down the enemy fighter")
	_check(aimed < 0.4, "the flak guns turn towards the plane (off by %.2f rad)" % aimed)
	_check(walker.hp == walker.max_hp, "flak ignores ground troops")
	await _seconds(0.4)
	await _shot("modern_02_flak_crash")
	_finish()

extends "res://src/debug/smoke_modern.gd"
## Military Age smoke test:  -- --smoke=military --mode=skirmish --seed=4242
## Military Age research, the three new buildings, every new unit, bazooka vs
## tank, tanks vs aircraft, jet rearming at the air base, the Delete key and a
## fresh construction site starting from its bare foundation.


func _run() -> void:
	await _frames(10)
	var me := _game.local_state()
	for k in ["food", "wood", "gold", "stone"]:
		me.add(k, 20000)
	var tc := _tc(1)
	var base := Iso.tile_of(tc.grid_pos)

	# 1. Military Age through the town center.
	me.age = 5
	_check(_game.production.enqueue_error(tc, "military_age") == "", "military_age can be researched")
	_game.production.enqueue(tc, "military_age")
	Engine.time_scale = 16.0
	var t0 := Time.get_ticks_msec()
	while me.age < 6 and Time.get_ticks_msec() - t0 < 30000:
		await _seconds(0.2)
	Engine.time_scale = 1.0
	_check(me.age == 6, "reached %s" % Hud.AGE_NAMES[6])

	# 2. New buildings.
	var placed := {}
	for item in [["military_base", Vector2i(7, 5)], ["tank_factory", Vector2i(-10, 6)], ["air_base", Vector2i(6, -10)]]:
		placed[item[0]] = _game.buildings.place(item[0], 1, _find_build_spot(item[0], base + item[1]), true)
	_check(placed.values().all(func(b): return b != null and b.is_complete()), "military base, tank factory and air base place")
	_check(_game.production.enqueue_error(placed["tank_factory"], "heavy_tank") == "", "the tank factory builds heavy tanks")
	_check(_game.production.enqueue_error(placed["military_base"], "bazooka_trooper") == "", "the military base trains bazookas")
	_check(_game.production.enqueue_error(placed["air_base"], "jet_fighter") == "", "the air base builds jets")

	# 3. Every new unit spawns (screenshot next to the tank factory).
	var roster := ["infantryman", "machine_gunner", "bazooka_trooper", "light_tank", "heavy_tank", "self_propelled_gun",
		"jet_fighter", "jet_bomber"]
	var shown: Array[Unit] = []
	var factory: Building = placed["tank_factory"]
	for i in roster.size():
		shown.append(_game.spawn_unit(roster[i], 1, factory.grid_pos + Vector2(3.5 + (i % 4) * 1.4, -2.5 + (i / 4) * 1.8)))
	_check(shown.all(func(u): return is_instance_valid(u) and u.is_alive()), "all %d military unit types spawn" % roster.size())
	_game.camera.focus_world(factory.position + Vector2(90, -10))
	await _frames(20)
	await _shot("military_01_roster")
	for u in shown:
		_game.kill_unit(u)
	await _frames(2)

	# 4. Bazookas destroy a light tank; the tank cannot fire at a jet overhead.
	var spot := Iso.tile_center(_find_build_spot("house", base + Vector2i(-6, -14)))
	var tank := _game.spawn_unit("light_tank", 2, spot + Vector2(3.0, 0.0))
	tank.stance = "stand"
	var jet := _game.spawn_unit("jet_fighter", 1, tank.grid_pos + Vector2(1.0, 0.0))
	jet.stance = "stand"
	var tl: Array[Unit] = [tank]
	_game.combat.order_attack(tl, jet)
	_check(tank.target == null, "a tank cannot attack an aircraft")
	_game.kill_unit(jet)
	var squad: Array[Unit] = []
	for k in 3:
		squad.append(_game.spawn_unit("bazooka_trooper", 1, spot + Vector2(-1.5, -0.8 + k * 0.8)))
	_game.combat.order_attack(squad, tank)
	_game.camera.focus_world(Iso.grid_to_world(spot + Vector2(1.0, 0.0)))
	var t1 := Time.get_ticks_msec()
	var shot_taken := false
	while tank.is_alive() and Time.get_ticks_msec() - t1 < 15000:
		await _seconds(0.1)
		if not shot_taken and tank.hp < tank.max_hp:
			shot_taken = true
			await _shot("military_02_bazookas")
	_check(not tank.is_alive(), "bazookas destroy the light tank")
	await _seconds(0.6)
	await _shot("military_03_wreck")
	for u in squad:
		if u.is_alive():
			_game.kill_unit(u)

	# 5. Heavy tank shells an enemy house.
	var house := _game.buildings.place("house", 2, _find_build_spot("house", base + Vector2i(12, 12)), true)
	var heavy := _game.spawn_unit("heavy_tank", 1, house.grid_pos + Vector2(-5, 0))
	var hl: Array[Unit] = [heavy]
	_game.combat.order_attack(hl, house)
	Engine.time_scale = 4.0
	var t2 := Time.get_ticks_msec()
	while is_instance_valid(house) and not house.dead and house.hp == house.max_hp and Time.get_ticks_msec() - t2 < 15000:
		await _seconds(0.1)
	Engine.time_scale = 1.0
	_check(not is_instance_valid(house) or house.dead or house.hp < house.max_hp, "the heavy tank damages the house")
	_game.kill_unit(heavy)

	# 6. A jet out of ammunition rearms at the air base.
	var ab: Building = placed["air_base"]
	var fighter := _game.spawn_unit("jet_fighter", 1, ab.grid_pos + Vector2(6, 0))
	fighter.ammo = 0
	_game.air.out_of_ammo(fighter)
	Engine.time_scale = 6.0
	var t3 := Time.get_ticks_msec()
	while fighter.ammo == 0 and Time.get_ticks_msec() - t3 < 30000:
		await _seconds(0.1)
	Engine.time_scale = 1.0
	_check(fighter.ammo == int(GameData.unit("jet_fighter")["ammo"]), "the jet rearms at the air base")
	_game.kill_unit(fighter)

	# 7. Delete key: the selected own unit dies and the selected own building falls.
	var victim := _game.spawn_unit("infantryman", 1, Iso.tile_center(_find_build_spot("house", base + Vector2i(-4, 9))))
	var shed := _game.buildings.place("house", 1, _find_build_spot("house", base + Vector2i(4, 10)), true)
	var enemy := _game.spawn_unit("infantryman", 2, Iso.tile_center(_find_build_spot("house", base + Vector2i(14, -14))))
	enemy.stance = "stand"
	await _frames(2)
	_game.selection.set_selection([victim, shed, enemy])
	_key(KEY_DELETE, true)
	_key(KEY_DELETE, false)
	await _frames(4)
	_check(not victim.is_alive(), "Delete kills the selected unit")
	_check(not is_instance_valid(shed) or shed.dead, "Delete destroys the selected building")
	_check(enemy.is_alive(), "Delete never touches enemy units")
	_game.kill_unit(enemy)

	# 8. A new construction site shows its bare foundation, not the finished building.
	var site := _game.buildings.place("military_base", 1, _find_build_spot("military_base", base + Vector2i(-8, -6)), false)
	site.add_progress(0.01)
	_check(site.state == Building.State.CONSTRUCTING and not site._body.visible, "a fresh site starts from its foundation")
	_game.camera.focus_world(site.position)
	await _frames(6)
	await _shot("military_04_new_site")
	_finish()

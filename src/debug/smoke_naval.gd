extends "res://src/debug/smoke_test.gd"
## Naval smoke test:  -- --smoke=naval --mode=skirmish --map=islands --seed=4242
## Islands map layout and fish, dock on the shore, fishing income, transport
## boarding and a landing on the enemy island, ship-to-ship combat, sinking.

func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_run.call_deferred()


func _run() -> void:
	await _frames(10)
	var me := _game.local_state()
	for k in ["food", "wood", "gold", "stone"]:
		me.add(k, 3000)
	me.age = 3
	var home := _game.map.start_positions[0]
	var enemy := _game.map.start_positions[1]

	# 1. Map: separate islands, fish in the sea.
	var walk := _game.pathfinder.find_path(Iso.tile_center(home), Iso.tile_center(enemy), 1)
	_check(walk.is_empty() or walk[walk.size() - 1].distance_to(Iso.tile_center(enemy)) > 8.0, "islands: no land route between the starts")
	var fish := 0
	for s in _game.map.resource_spawns:
		if s["type"] == "fish":
			fish += 1
	_check(fish >= 6, "islands map has fish shoals (%d)" % fish)

	# 2. Dock on the shore nearest home.
	var spot := _shore_spot(home)
	_check(spot.x >= 0, "a valid shore site exists near home")
	if spot.x < 0:
		_finish()
		return
	var dock := _game.buildings.place("dock", 1, spot, true)
	_check(dock != null and dock.is_complete(), "dock placed on the water")
	_check(_game.buildings.placement_error("dock", home) != "", "a dock cannot be placed on dry land")

	# 3. Fishing.
	var food0 := int(me.stats["gathered"]["food"])
	var boat := _spawn_ship("fishing_ship", 1, dock)
	var shoal := _game.economy.find_node("food", boat.grid_pos, 40, -1, true)
	_check(shoal != null, "the fishing ship finds a shoal")
	var vil := _game.spawn_unit("villager", 1, Iso.tile_center(home) + Vector2(2, 2))
	var vlist: Array[Unit] = [vil]
	if shoal != null:
		_game.economy.order_gather(vlist, shoal)
		_check(vil.task.is_empty(), "villagers cannot gather fish")
		var blist: Array[Unit] = [boat]
		_game.economy.order_gather(blist, shoal)
	Engine.time_scale = 8.0
	var t0 := Time.get_ticks_msec()
	while int(me.stats["gathered"]["food"]) <= food0 and Time.get_ticks_msec() - t0 < 45000:
		await _seconds(0.25)
	Engine.time_scale = 1.0
	_check(int(me.stats["gathered"]["food"]) > food0, "fishing ship delivers fish to the dock (+%d food)" % (int(me.stats["gathered"]["food"]) - food0))

	# 4. Transport: board three soldiers, land them on the enemy island.
	var ship := _spawn_ship("transport_ship", 1, dock)
	var squad: Array[Unit] = []
	for i in 3:
		squad.append(_game.spawn_unit("swordsman", 1, dock.grid_pos + Vector2(-2.5 + i * 0.6, -2.5)))
	_game.naval.order_board(squad, ship)
	Engine.time_scale = 4.0
	var t1 := Time.get_ticks_msec()
	while ship.cargo.size() < 3 and Time.get_ticks_msec() - t1 < 20000:
		await _seconds(0.2)
	Engine.time_scale = 1.0
	_check(ship.cargo.size() == 3 and squad.all(func(u): return not u.visible), "three swordsmen board the transport")
	_game.naval.order_unload(ship, Iso.tile_center(enemy))
	Engine.time_scale = 8.0
	var t2 := Time.get_ticks_msec()
	while not ship.cargo.is_empty() and Time.get_ticks_msec() - t2 < 40000:
		await _seconds(0.25)
	Engine.time_scale = 1.0
	_check(ship.cargo.is_empty(), "the transport unloads")
	var landed := squad.filter(func(u): return u.is_alive() and u.aboard == null and _game.pathfinder.is_walkable(u.tile()))
	_check(landed.size() == 3, "all three are back on land (%d)" % landed.size())
	var enemy_side := landed.filter(func(u): return u.grid_pos.distance_to(Iso.tile_center(enemy)) < u.grid_pos.distance_to(Iso.tile_center(home)))
	_check(enemy_side.size() == 3, "they landed on the enemy island")

	# 5. Combat on the water, and melee cannot reach ships.
	var galley := _spawn_ship("war_galley", 1, dock)
	var foe := _spawn_ship("war_galley", 2, dock)
	foe.set_grid_pos(_water_near(galley.grid_pos, 4))
	foe.stance = "stand"
	_check(not CombatSystem.can_target(GameData.unit("swordsman"), foe), "a swordsman cannot attack a ship")
	_check(CombatSystem.can_target(GameData.unit("archer"), foe), "an archer can shoot a ship")
	var glist: Array[Unit] = [galley]
	_game.combat.order_attack(glist, foe)
	var t3 := Time.get_ticks_msec()
	while foe.is_alive() and foe.hp == foe.max_hp and Time.get_ticks_msec() - t3 < 10000:
		await _seconds(0.1)
	_check(not foe.is_alive() or foe.hp < foe.max_hp, "the war galley damages the enemy ship")
	_game.camera.focus_world(dock.position)
	_game.selection.set_selection([ship, galley])
	await _frames(8)
	await _shot("naval_01_dock_ships")
	# 6. A sunk transport takes its passengers down.
	var rider := _game.spawn_unit("militia", 1, ship.grid_pos)
	var rl: Array[Unit] = [rider]
	_game.naval.order_board(rl, ship)
	var t4 := Time.get_ticks_msec()
	while rider.aboard == null and Time.get_ticks_msec() - t4 < 10000:
		await _seconds(0.1)
	ship.take_damage(ship.hp, null)
	await _frames(3)
	_check(rider.dead, "passengers die when their transport sinks")
	await _seconds(0.6)
	await _shot("naval_02_sinking")
	await _ai_invasion(home, enemy)
	_finish()


## 7. The AI (player 2) ships an army over to the player's island.
func _ai_invasion(home: Vector2i, enemy: Vector2i) -> void:
	# Clear the player's units from the AI island first (the AI would rightly defend instead).
	for u in _game.unit_system.units.duplicate():
		if u.owner_id == 1 and not u.dead:
			_game.kill_unit(u)
	await _seconds(0.5)
	var ai: AIPlayer = _game.ai_players[0]
	var p2 := ai.player
	for k in ["food", "wood", "gold", "stone"]:
		p2.add(k, 4000)
	p2.age = 1
	var spot := _shore_spot(enemy)
	_check(spot.x >= 0, "the AI island has a shore site")
	if spot.x < 0:
		return
	var dock2 := _game.buildings.place("dock", 2, spot, true)
	_spawn_ship("transport_ship", 2, dock2)
	for i in 6:
		_game.spawn_unit("swordsman", 2, Iso.tile_center(enemy) + Vector2(2.0 + (i % 3) * 0.7, 2.0 + (i / 3) * 0.7))
	ai.elapsed = float(ai.diff.get("first_attack_minute", 8)) * 60.0 + 1.0
	ai.last_wave_time = -INF
	ai.set_physics_process(true)
	Engine.time_scale = 6.0
	var t0 := Time.get_ticks_msec()
	var landed := false
	while not landed and Time.get_ticks_msec() - t0 < 60000:
		await _seconds(0.5)
		for u in _game.unit_system.units:
			if u.owner_id == 2 and not u.dead and u.aboard == null and not NavalSystem.is_ship(u) and u.grid_pos.distance_to(Iso.tile_center(home)) < u.grid_pos.distance_to(Iso.tile_center(enemy)):
				landed = true
	Engine.time_scale = 1.0
	ai.set_physics_process(false)
	_check(landed, "the AI ferries soldiers to the player's island")


func _spawn_ship(id: String, owner: int, dock: Building) -> Unit:
	var at := _game.naval_pathfinder.approach(dock.footprint(), dock.grid_pos + Vector2(3, 3))
	return _game.spawn_unit(id, owner, at)


func _water_near(p: Vector2, r: int) -> Vector2:
	var t := _game.naval_pathfinder.nearest_walkable(Iso.tile_of(p + Vector2(r, 0)), 8, p)
	return Iso.tile_center(t)


## Nearest valid 3x3 dock origin to `home` (ring search).
func _shore_spot(home: Vector2i) -> Vector2i:
	for r in range(4, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var o := home + Vector2i(dx, dy)
				if _game.buildings.placement_error("dock", o) == "":
					return o
	return Vector2i(-1, -1)

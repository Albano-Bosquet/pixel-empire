extends "res://src/debug/smoke_combat.gd"
## Smoke test for villager work placement and order feedback:
##   -- --smoke=work --mode=skirmish
## 1. A farmer works standing inside the field and walks along it while hoeing.
## 2. A woodcutter works right against the tree (gather_reach), not a tile away.
## 3. Right-clicking a target blinks a ring under it (green for work, red for enemies).


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_work.call_deferred()


func _work() -> void:
	await _frames(5)
	var tc := _p1_tc()
	var econ: Dictionary = GameData.economy

	# --- 1. Farmer walks on the field ------------------------------------------------------
	var f_origin := _find_build_spot("farm", Iso.tile_of(tc.grid_pos) + Vector2i(5, 0))
	var farm := _game.buildings.place("farm", 1, f_origin, true)
	var farmer := _spawn_group("villager", 1, farm.grid_pos + Vector2(-2.5, 0), 1)[0]
	var farmers: Array[Unit] = [farmer]
	_game.economy.order_gather(farmers, farm)
	var field := Rect2(farm.footprint())
	var t0 := Time.get_ticks_msec()
	while farmer.task.get("phase", "") != "work" and Time.get_ticks_msec() - t0 < 8000:
		await _seconds(0.1)
	_check(farmer.task.get("phase", "") == "work", "farmer reaches the farm and starts working")
	_check(field.has_point(farmer.grid_pos), "farmer works standing inside the field (%s in %s)" % [farmer.grid_pos, field])
	var seen: Array[Vector2] = []
	var inside := true
	for i in 30:
		await _seconds(0.2)
		seen.append(farmer.grid_pos)
		inside = inside and field.grow(0.05).has_point(farmer.grid_pos)
	var span := 0.0
	for p in seen:
		span = maxf(span, p.distance_to(seen[0]))
	_check(span > 0.6, "farmer walks along the field while farming (%.2f tiles)" % span)
	_check(inside, "farmer never leaves the field while working")
	_check(farmer.work_anim == "build" and farmer.state == Unit.State.IDLE, "farmer plays the hoeing animation, not walk")
	_check(farmer.carry_amount > 0.0, "farmer gathers food while walking (%.1f)" % farmer.carry_amount)
	_game.camera.focus_world(farm.position)
	await _frames(3)
	await _shot("work_01_farmer")

	# --- 2. Woodcutter stands against the tree ---------------------------------------------
	var spot := _open_spot(tc.grid_pos + Vector2(-7, 4), 2)
	var tree_tile := Iso.tile_of(spot)
	var tree := _game.spawn_resource_node("tree_oak", tree_tile, 0)
	# Map-generated trees block their tile; do the same for this hand-placed one.
	_game.map.set_blocked(tree_tile, true)
	_game.pathfinder.refresh_tile(tree_tile)
	var cutter := _spawn_group("villager", 1, spot + Vector2(3.0, 0.5), 1)[0]
	var cutters: Array[Unit] = [cutter]
	_game.economy.order_gather(cutters, tree)
	t0 = Time.get_ticks_msec()
	while cutter.task.get("phase", "") != "work" and Time.get_ticks_msec() - t0 < 8000:
		await _seconds(0.1)
	var tr := Rect2(Rect2i(tree_tile, Vector2i.ONE))
	var closest := Vector2(clampf(cutter.grid_pos.x, tr.position.x, tr.end.x), clampf(cutter.grid_pos.y, tr.position.y, tr.end.y))
	var gap := cutter.grid_pos.distance_to(closest)
	var limit := float(econ.get("gather_reach", 0.12)) + cutter.radius + 0.02
	_check(cutter.task.get("phase", "") == "work", "woodcutter starts chopping")
	_check(gap <= limit, "woodcutter stands against the tree (%.2f <= %.2f tiles from its tile)" % [gap, limit])
	await _seconds(0.6)
	_check(cutter.work_anim == "chop", "woodcutter plays the chop animation")

	# --- 3. Blinking target ring on right-click --------------------------------------------
	_game.selection.set_selection([cutter])
	_game.camera.focus_world(tree.position)
	await _frames(3)
	var at := _game.screen_from_world(tree.position + Vector2(0, -20))
	_mouse_button(MOUSE_BUTTON_RIGHT, true, at)
	_mouse_button(MOUSE_BUTTON_RIGHT, false, at)
	await _frames(2)
	var rings: Array = _game.ground_fx._targets
	_check(rings.size() == 1 and rings[0]["e"] == tree, "right-click on a tree blinks a ring under it")
	_check(rings.size() == 1 and rings[0]["col"] == GroundFx.TARGET_FRIENDLY, "work target ring is green")
	await _shot("work_02_tree_ring")
	var off := false
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 500:
		await _frames(1)
		if not _game.ground_fx._targets.is_empty() and fmod(_game.ground_fx._targets[0]["t"] * GroundFx.TARGET_BLINKS / GroundFx.TARGET_TIME, 1.0) > 0.55:
			off = true
	_check(off, "the ring blinks (has off phases)")
	await _seconds(GroundFx.TARGET_TIME)
	_check(_game.ground_fx._targets.is_empty(), "the ring disappears after %.1f s" % GroundFx.TARGET_TIME)

	var enemy := _spawn_group("swordsman", 2, _open_spot(tc.grid_pos + Vector2(0, -8), 2), 1)[0]
	enemy.stance = "stand"
	var sw := _spawn_group("swordsman", 1, enemy.grid_pos + Vector2(3.0, 0), 1)[0]
	sw.stance = "stand"
	_game.fog.update_now()
	_game.selection.set_selection([sw])
	_game.camera.focus_world(enemy.position)
	await _frames(3)
	at = _game.screen_from_world(enemy.position + Vector2(0, -16))
	_mouse_button(MOUSE_BUTTON_RIGHT, true, at)
	_mouse_button(MOUSE_BUTTON_RIGHT, false, at)
	await _frames(2)
	rings = _game.ground_fx._targets
	_check(rings.size() == 1 and rings[0]["e"] == enemy and rings[0]["col"] == GroundFx.TARGET_HOSTILE, "attack target ring is red")
	_check(sw.target == enemy, "the right-click still orders the attack")
	await _shot("work_03_attack_ring")
	_finish()

extends "res://src/debug/smoke_combat.gd"
## Sound smoke test:  -- --smoke=audio --mode=skirmish
## Villagers chop / mine / build on screen, a fight with archers, a catapult
## and swordsmen happens in view, a unit is trained, an age is reached; the
## GameAudio and Audio play counters must show each of those sounds, the
## ambience loops must be running and the age playlist playing. Ends with
## a screenshot of the sound options panel.


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_audio.call_deferred()


func _audio() -> void:
	await _frames(10)
	var tc := _p1_tc()
	var me := _game.local_state()
	var ga := _game.audio
	_game.camera.focus_world(tc.position)
	_check(Audio.playlist_id() == "age_0", "Dark Age playlist on match start (%s)" % Audio.playlist_id())
	_check(Audio._music[Audio._music_active].playing, "a music track is playing")

	# Economy: villagers work next to the Town Centre.
	var vils := _spawn_group("villager", 1, tc.grid_pos + Vector2(3, 3), 6)
	var wood := _game.economy.find_node("wood", tc.grid_pos, 14, 1)
	var gold := _game.economy.find_node("gold", tc.grid_pos, 16, 1)
	_game.economy.order_gather(vils.slice(0, 3), wood)
	if gold:
		_game.economy.order_gather(vils.slice(3, 5), gold)
	me.add("wood", 500)
	var spot := _open_spot(tc.grid_pos + Vector2(-5, 2), 2)
	var house := _game.buildings.try_place(me, "house", Iso.tile_of(spot), vils.slice(5, 6))
	_check(house != null, "house placed for the builder")
	if wood:
		_game.camera.focus_world(Iso.grid_to_world((wood.grid_pos + tc.grid_pos) * 0.5))
	Engine.time_scale = 2.0
	await _seconds(12.0)
	for key in ["chop", "build"]:
		_check(int(ga.played.get(key, 0)) > 0, "work sound '%s' played (%d)" % [key, int(ga.played.get(key, 0))])
	var t_drop := Time.get_ticks_msec()
	while int(ga.played.get("drop_wood", 0)) + int(ga.played.get("drop_gold", 0)) == 0 and Time.get_ticks_msec() - t_drop < 20000:
		await _seconds(0.3)
	_check(int(ga.played.get("drop_wood", 0)) + int(ga.played.get("drop_gold", 0)) > 0, "drop-off sound played")

	# Selection and orders.
	_game.selection.set_selection([vils[0]])
	await _frames(3)
	_check(int(Audio.ui_played.get("sel_villager", 0)) > 0 or _any_prefix(Audio.ui_played, "sel_villager"), "villager selection voice")
	await _seconds(0.6)  # selection voices never stack (0.2 s real time; the match runs at 2x)
	_game.selection.set_selection([tc])
	await _frames(3)
	_check(int(Audio.ui_played.get("bld_town_center", 0)) > 0, "Town Center selection bell")

	# Training a unit (houses first: the extra villagers fill the Town Center's room).
	for k in 3:
		var hs := _open_spot(tc.grid_pos + Vector2(-8, -4 + k * 3), 1)
		_game.buildings.place("house", 1, Iso.tile_of(hs), true)
	me.add("food", 200)
	_game.production.enqueue(tc, "villager")
	var t0 := Time.get_ticks_msec()
	while int(Audio.ui_played.get("unit_ready", 0)) == 0 and Time.get_ticks_msec() - t0 < 20000:
		await _seconds(0.3)
	_check(int(Audio.ui_played.get("unit_ready", 0)) > 0, "unit-ready horn when a villager is trained")

	# A battle in view.
	var arena := _open_spot(tc.grid_pos + Vector2(10, 0))
	_spawn_group("swordsman", 1, arena, 5)
	_spawn_group("archer", 1, arena - Vector2(2, 0), 4)
	_spawn_group("catapult", 1, arena - Vector2(3, 2), 1)
	_spawn_group("swordsman", 2, arena + Vector2(3, 0), 6)
	_game.fog.update_now()
	_game.camera.focus_world(Iso.grid_to_world(arena + Vector2(1, 0)))
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 14000 and int(ga.played.get("death", 0)) < 3:
		await _seconds(0.25)
	await _shot("audio_01_battle")
	for key in ["swing", "bow", "arrow_hit", "death"]:
		_check(int(ga.played.get(key, 0)) > 0, "combat sound '%s' played (%d)" % [key, int(ga.played.get(key, 0))])
	_check(int(ga.played.get("hit_sword", 0)) + int(ga.played.get("hit_flesh", 0)) > 0, "melee impact sound played")
	_check(Audio.playlist_id() == "battle" or ga._battle_hits.size() > 0, "battle intensity tracked (%s, %d hits)" % [Audio.playlist_id(), ga._battle_hits.size()])

	# Fog: a sound behind the fog of war stays silent.
	var hidden := Vector2.INF
	for y in _game.map.height:
		for x in _game.map.width:
			if not _game.fog.is_tile_visible(1, Vector2i(x, y)):
				hidden = Iso.grid_to_world(Iso.tile_center(Vector2i(x, y)))
				break
		if hidden != Vector2.INF:
			break
	_game.camera.focus_world(hidden)
	await _frames(3)
	var before := int(ga.played.get("cannon", 0))
	EventBus.sound_at.emit("cannon", hidden)
	_check(int(ga.played.get("cannon", 0)) == before, "no sound from inside the fog")

	# Building placement: placing thuds, backing out cancels, a building's right click plants a rally flag.
	_game.camera.focus_world(tc.position)
	await _frames(3)
	var canvas := get_viewport().get_canvas_transform()
	me.add("wood", 200)
	_game.selection.set_selection([vils[5]])
	_game.placement.begin("house")
	_game.placement._update_origin(canvas * Iso.grid_to_world(_open_spot(tc.grid_pos + Vector2(6, -6), 2)))
	_game.placement._place_single(false)
	await _frames(2)
	_check(int(Audio.ui_played.get("ui_place", 0)) > 0, "placing a foundation thuds")
	_game.placement.begin("house")
	_game.placement.abort()
	await _frames(2)
	_check(int(Audio.ui_played.get("ui_cancel", 0)) > 0, "backing out of placement sounds")
	_game.selection.set_selection([tc])
	_game.commands.order_at(canvas * Iso.grid_to_world(tc.grid_pos + Vector2(4, 4)), false)
	await _frames(2)
	_check(int(Audio.ui_played.get("rally", 0)) > 0, "setting a rally point plants a flag")

	# Hunting a boar: it strikes back, but that is no "under attack" alert.
	var hunt_at := _open_spot(tc.grid_pos + Vector2(-4, 6))
	var hunter: Unit = _spawn_group("villager", 1, hunt_at, 1)[0]
	var boar: Unit = _spawn_group("boar", Entity.GAIA, hunt_at + Vector2(1.5, 0), 1)[0]
	var bitten := [false]
	hunter.damaged.connect(func(_e, attacker, _a) -> void: bitten[0] = bitten[0] or attacker == boar)
	_game.combat._attack_notice.erase(1)
	var alerts := int(Audio.ui_played.get("under_attack", 0))
	var hunters: Array[Unit] = [hunter]
	_game.wildlife.order_hunt(hunters, boar)
	t0 = Time.get_ticks_msec()
	while not bitten[0] and Time.get_ticks_msec() - t0 < 15000:
		await _seconds(0.25)
	_check(bitten[0], "the hunted boar fought back")
	_check(int(Audio.ui_played.get("under_attack", 0)) == alerts, "no under-attack alert while hunting")

	# Ambience loops run.
	var running := 0
	for key in ga._ambient:
		if ga._ambient[key].playing:
			running += 1
	_check(running >= 4, "ambience loops running (%d)" % running)

	# Age up switches the music.
	me.age = 3
	EventBus.age_changed.emit(1, 3)
	await _frames(3)
	_check(int(Audio.ui_played.get("age_up", 0)) > 0, "age-up fanfare")
	_check(Audio.playlist_id() == "age_3" or Audio.playlist_id() == "battle", "age playlist follows the age (%s)" % Audio.playlist_id())
	Engine.time_scale = 1.0

	# Sound options panel.
	var panel := AudioPanel.new()
	add_child(panel)
	await _frames(5)
	await _shot("audio_02_panel")
	panel.queue_free()
	print("GameAudio played: ", ga.played)
	print("Audio.ui played: ", Audio.ui_played)
	_finish()


func _any_prefix(d: Dictionary, prefix: String) -> bool:
	for k in d:
		if String(k).begins_with(prefix):
			return true
	return false

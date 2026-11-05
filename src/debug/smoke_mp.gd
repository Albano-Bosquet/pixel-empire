extends Node
## Two-process multiplayer smoke test (same PC, loopback):
##   host:   -- --mp=host --smoke=mp
##   client: -- --mp=client --smoke=mp      (start after the host)
##   rejoin: -- --mp=rejoin --smoke=mp      (after the client quit: takes player 2 back)
## Add `--online --relay=ws://127.0.0.1:8080` to all three to go through the relay
## server instead (tools/relay: `npm start`): room code, online list, join by code.
## Lobby join + ready + start, replicated starting state, client orders
## (move, build a house, train a villager) applied by the host and seen by the
## client, chat both ways, and the AI taking over when the client leaves.
## Each process prints PASS/FAIL lines and exits 0 (pass) / 1 (fail).

const SHOTS := "res://production/qa/screenshots/"
const CODE_FILE := "user://smoke_online_code.txt"

var role := "host"
var _main: Node
var _failures: Array[String] = []
var _chat_seen := ""
var online := OS.get_cmdline_user_args().has("--online")


func start(main: Node, as_role: String) -> void:
	_main = main
	role = as_role
	Net.chat_received.connect(func(from: String, text: String) -> void:
		if from != "":
			_chat_seen = text)
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("PASS: " if cond else "FAIL: ") + "[%s] %s" % [role, what])
	if not cond:
		_failures.append(what)


func _wait(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < seconds * 1000.0:
		await get_tree().create_timer(0.1, true, false, true).timeout
	return cond.call()


func _finish() -> void:
	print("SMOKE RESULT: %s (%d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	await get_tree().create_timer(0.5, true, false, true).timeout
	Net.leave()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	img.save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))


func _game() -> Game:
	return _main.game


func _run() -> void:
	if role == "host":
		await _host()
	elif role == "rejoin":
		await _rejoin()
	else:
		await _client()
	_finish()


# --- Host -------------------------------------------------------------------------------------

func _host() -> void:
	if online:
		_check(Net.host_online("Host") == "", "asks the relay for an online game")
		var opened := await _wait(func(): return Net.online_code != "" and Net.is_host(), 15.0)
		_check(opened, "the relay gives a room code (%s)" % Net.online_code)
		if not opened:
			return
		var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
		f.store_string(Net.online_code)
		f.close()
	else:
		_check(Net.host("Host") == "", "opens the game on the default port")
		_check(not Net.local_ips().is_empty(), "lists this machine's addresses for sharing")
	Net.host_set_settings({"map_type": "continental", "size": "tiny", "seed": 4242, "victory": "conquest", "fog": true})
	var lobby := LobbyMenu.new()
	_main.add_child(lobby)
	var joined := await _wait(func(): return Net.slots.size() >= 2, 40.0)
	_check(joined, "the client joins the lobby")
	if not joined:
		return
	await get_tree().create_timer(1.0, true, false, true).timeout
	await _shot("mp_00_lobby")
	_check(await _wait(func(): return Net.all_ready(), 15.0), "the client marks itself ready")
	_check(Net.host_start() == "", "the host starts the match")
	await _wait(func(): return _game() != null and is_instance_valid(_game()) and _game().replicator != null, 10.0)
	var g := _game()
	var p2 := g.player(2)
	var wood0 := int(p2.resources["wood"])
	# The client builds a house, trains a villager and chats.
	var built := await _wait(func(): return g.buildings.buildings.any(func(b): return b.owner_id == 2 and b.type_id == "house"), 40.0)
	_check(built, "a house ordered by the client exists on the host")
	_check(int(p2.resources["wood"]) <= wood0 - 25, "the client's player paid for it on the host")
	var tc2: Building = null
	for b in g.buildings.buildings:
		if b.owner_id == 2 and b.type_id == "town_center":
			tc2 = b
	_check(await _wait(func(): return tc2 != null and (tc2.queue.has("villager") or g.unit_system.units.filter(func(u): return u.owner_id == 2 and u.type_id == "villager").size() > 3), 20.0), "the client's villager order reached the town center")
	_check(await _wait(func(): return _chat_seen == "hola desde el cliente", 15.0), "chat from the client arrives")
	Net.send_chat("hola desde el host")
	# Combat across the network: archers of player 1 attack a villager of player 2.
	# A fresh villager of player 2 a little away from its base (no helpers nearby).
	var tc_p2: Building = null
	for b in g.buildings.buildings:
		if b.owner_id == 2 and b.type_id == "town_center":
			tc_p2 = b
	# Out of the Town Center's arrow range, so it is the archers' fight alone.
	var tc_range := float(GameData.building("town_center").get("attack", {}).get("range", 7)) + 3.0
	var away := (Vector2(g.map.width, g.map.height) * 0.5 - tc_p2.grid_pos).normalized() if tc_p2 != null else Vector2.RIGHT
	var victim: Unit = g.spawn_unit("villager", 2, tc_p2.grid_pos + away * tc_range) if tc_p2 != null else null
	if victim != null:
		victim.stance = "stand"
		var squad: Array[Unit] = []
		for i in 3:
			squad.append(g.spawn_unit("archer", 1, victim.grid_pos + away * 3.0 + Vector2(-away.y, away.x) * 0.5 * i))
		g.combat.order_attack(squad, victim)
		_check(await _wait(func(): return victim.dead, 30.0), "host-side archers kill a villager of the client")
	await get_tree().create_timer(2.0, true, false, true).timeout
	await _shot("mp_01_host_view")
	var sz: Array = g.replicator.last_snapshot_size
	print("INFO: [host] snapshot %d bytes raw -> %d on the wire" % [sz[0], sz[1]])
	_check(sz[1] > 0 and sz[1] < sz[0], "snapshots go compressed")
	# The client leaves: its civilisation keeps playing under AI control.
	_check(await _wait(func(): return g.replicator._ai_for.has(2), 40.0), "the AI takes over the disconnected player")
	_check(g.player(2).is_ai, "player 2 is now marked as AI")
	# The same player connects again and takes their civilisation back.
	_check(await _wait(func(): return g.replicator.returns > 0, 90.0), "the returning player gets player 2 back from the AI")


# --- Client -----------------------------------------------------------------------------------

func _client() -> void:
	await get_tree().create_timer(1.0, true, false, true).timeout
	if online:
		var rooms: Array = []
		Net.online_games_found.connect(func(l: Array) -> void: rooms.append_array(l), CONNECT_ONE_SHOT)
		Net.browse_online()
		await _wait(func(): return not rooms.is_empty(), 10.0)
		var code := FileAccess.get_file_as_string(CODE_FILE)
		_check(rooms.any(func(g): return g.get("code", "") == code), "the host's game is in the online list")
		_check(Net.join_online("Cliente", code) == "", "joins the online game by its code")
	else:
		_check(Net.join("Cliente", "127.0.0.1") == "", "connects to 127.0.0.1")
	var in_lobby := await _wait(func(): return Net.slots.size() >= 2, 20.0)
	_check(in_lobby, "receives the lobby")
	if not in_lobby:
		return
	Net.set_ready(true)
	var started := await _wait(func(): return _game() != null and is_instance_valid(_game()) and _game().config.get("replica", false), 30.0)
	_check(started, "the match starts on the client as a replica")
	if not started:
		return
	var g := _game()
	_check(g.local_player == 2, "the client plays as player 2")
	var mine := func(): return g.unit_system.units.filter(func(u): return u.owner_id == 2 and not u.dead)
	_check(await _wait(func(): return mine.call().size() >= 3, 10.0), "own starting units arrive in snapshots (%d)" % mine.call().size())
	# (Lambdas capture by value: look the town center up outside the wait condition.)
	await _wait(func(): return g.buildings.buildings.any(func(b): return b.owner_id == 2 and b.type_id == "town_center"), 10.0)
	var tc: Building = null
	for b in g.buildings.buildings:
		if b.owner_id == 2 and b.type_id == "town_center":
			tc = b
	_check(tc != null and tc.is_complete(), "own town center is replicated")
	if tc == null:
		return
	_check(int(g.local_state().resources.get("wood", 0)) == int(GameData.players["starting_resources"]["wood"]), "starting wood matches the host")
	# Move order: a villager walks (positions arrive from the host).
	var vills: Array = mine.call().filter(func(u): return u.type_id == "villager")
	var v: Unit = vills[0]
	var start_pos := v.grid_pos
	var goal := start_pos + Vector2(4, 0)
	g.orders.submit({"t": "issue", "units": [v.entity_id], "buildings": [], "grid": goal, "target": 0})
	_check(g.replicator.is_predicting(v), "the replica predicts its own move order")
	await get_tree().create_timer(0.15, true, false, true).timeout
	_check(v.grid_pos.distance_to(start_pos) > 0.1, "the villager starts walking before the host answers (%.2f tiles)" % v.grid_pos.distance_to(start_pos))
	_check(await _wait(func(): return v.grid_pos.distance_to(start_pos) > 1.5, 10.0), "the villager moves after a move order")
	_check(await _wait(func(): return not g.replicator.is_predicting(v), 5.0), "the prediction hands back to host positions")
	await _wait(func(): return v.state == Unit.State.IDLE, 8.0)
	_check(v.grid_pos.distance_to(goal) < 1.0, "the predicted villager ends where the host put it (%.2f from the goal)" % v.grid_pos.distance_to(goal))
	# Build a house with the other villagers.
	var spot := _house_spot(g, tc)
	var builders := OrderRouter.ids(vills.slice(1))
	g.orders.submit({"t": "place", "type": "house", "origins": [spot], "builders": builders})
	_check(await _wait(func(): return g.buildings.buildings.any(func(b): return b.owner_id == 2 and b.type_id == "house"), 10.0), "the new house appears on the client")
	_check(await _wait(func(): return int(g.local_state().resources["wood"]) < int(GameData.players["starting_resources"]["wood"]), 5.0), "the wood counter drops")
	g.orders.submit({"t": "enqueue", "b": tc.entity_id, "item": "villager"})
	_check(await _wait(func(): return tc.queue.has("villager") or mine.call().size() > 3, 10.0), "the town center shows the villager in training")
	Net.send_chat("hola desde el cliente")
	_check(await _wait(func(): return _chat_seen == "hola desde el host", 15.0), "chat from the host arrives")
	_check(g.fog.is_explored(2, Iso.tile_of(tc.grid_pos)), "the client's fog is explored around its base")
	# The host's archers show up, their arrows fly and a villager falls.
	_check(await _wait(func(): return g.unit_system.units.any(func(u): return u.owner_id == 1 and u.type_id == "archer"), 20.0), "enemy archers appear when in sight")
	var saw_arrows := [false]
	var watch := func(): 
		if not g.fx.projectiles.is_empty():
			saw_arrows[0] = true
		return saw_arrows[0]
	_check(await _wait(watch, 15.0), "their arrows are drawn on the client")
	var deaths := [0]
	EventBus.entity_killed.connect(func(_e, _a): deaths[0] += 1)
	_check(await _wait(func(): return g.unit_system.corpses.size() > 0, 30.0), "the villager's death plays on the client")
	# Shared pause: the client asks, the host pauses everyone.
	Net.set_paused(true)
	_check(await _wait(func(): return get_tree().paused, 10.0), "pausing from the client pauses the match")
	Net.set_paused(false)
	_check(await _wait(func(): return not get_tree().paused, 10.0), "and resuming works too")
	# The in-game menu opens for this player only: the match keeps running.
	_main.open_pause()
	var menu: PauseMenu = _main._pause
	_check(menu != null and not get_tree().paused, "the menu opens without pausing the match")
	var walker: Unit = mine.call()[0]  # the first villager may have fallen to the archers
	var from := walker.grid_pos
	g.orders.submit({"t": "issue", "units": [walker.entity_id], "buildings": [], "grid": from + Vector2(-4, 0), "target": 0})
	_check(await _wait(func(): return walker.grid_pos.distance_to(from) > 1.5, 10.0), "units keep moving behind the menu")
	await _shot("mp_02b_client_menu")
	if menu:
		menu.resume_pressed.emit()
	_check(_main._pause == null, "resume closes the menu")
	# Give the replica a couple of snapshots after the pause: units that just left
	# our sight linger for VANISH_GRACE_MS before the client forgets them.
	var hidden_enemies := func() -> Array: return g.unit_system.units.filter(func(u): return u.owner_id == 1 and not g.fog.is_visible(2, u))
	await _wait(func(): return hidden_enemies.call().is_empty(), 3.0)
	var enemy_seen: Array = hidden_enemies.call()
	_check(enemy_seen.is_empty(), "the host never sends enemy units hidden by fog (%d)" % enemy_seen.size())
	g.camera.settings["edge_scroll"] = false  # the mouse may rest on the window edge
	g.camera.focus_world(tc.position)
	await get_tree().process_frame
	await get_tree().create_timer(1.5, true, false, true).timeout
	await _shot("mp_02_client_view")



func _rejoin() -> void:
	await get_tree().create_timer(1.0, true, false, true).timeout
	if online:
		_check(Net.join_online("Cliente", FileAccess.get_file_as_string(CODE_FILE)) == "", "reconnects to the running online match")
	else:
		_check(Net.join("Cliente", "127.0.0.1") == "", "reconnects to the running match")
	var started := await _wait(func(): return _game() != null and is_instance_valid(_game()) and _game().config.get("replica", false), 30.0)
	_check(started, "the running match opens on the returning client")
	if not started:
		return
	var g := _game()
	_check(g.local_player == 2, "it is player 2 again")
	_check(await _wait(func(): return g.unit_system.units.filter(func(u): return u.owner_id == 2).size() >= 3, 15.0), "its units are back on screen")
	_check(await _wait(func(): return g.buildings.buildings.any(func(b): return b.owner_id == 2 and b.type_id == "house"), 10.0), "the house built before leaving is still there")
	await get_tree().create_timer(3.0, true, false, true).timeout


func _house_spot(g: Game, tc: Building) -> Vector2i:
	var c := Iso.tile_of(tc.grid_pos)
	for r in range(4, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var o := c + Vector2i(dx, dy)
				if g.buildings.placement_error("house", o) == "":
					return o
	return c + Vector2i(5, 5)

extends "res://src/debug/smoke_test.gd"
## AI vs AI match, played from start to finish at high speed and written down in
## GAME time (Spanish timeline, JSON data, screenshots). It observes, it never
## touches the match: a run passes when it reaches its end, whatever happened.
##
## Run (headless = fastest, no screenshots; windowed = watchable):
##   --headless --path . -- --smoke=aimatch --mode=skirmish --difficulty=easy --seed=4242
##   --path . -- --smoke=aimatch --mode=skirmish --difficulty=easy --seed=4242 --speed=40 --slowmo
## Teams: add --players=4 --teams (Azul + Verde against Rojo + Amarillo).
## Video: put `--write-movie out.avi --fixed-fps 30` before the `--`.
## Options: --speed=N (default 60) --cap=game minutes (default 120) --slowmo (slow
## down during fights) --ticks=N (forces physics ticks, only to compare with the
## naive way of speeding up) --tag=text (output file suffix).
##
## Speed: Godot passes physics_step * time_scale to _physics_process, so raising
## time_scale alone stretches every tick (x60 = 1 s per tick: units jump over
## waypoints). Here the tick rate rises with the speed, so every tick stays the
## normal 1/60 s and the simulation is the same as at x1; a slow PC only makes the
## run take longer. The "delta" field of the JSON proves it for each run.

const OUT_DIR := "res://production/qa/aimatch/"
const EVIDENCE := "res://production/qa/evidence/"
## Game seconds between two samples of the economy table.
const SAMPLE_EVERY := 30.0
## Game seconds without blows that close a combat episode.
const QUIET_AFTER := 30.0
## Tiles from an enemy building at which a wave counts as arrived.
const ARRIVED_TILES := 12.0
const SLOWMO_SPEED := 6.0
const NAMES := {1: "Azul", 2: "Rojo", 3: "Verde", 4: "Amarillo"}
const AGE_NAMES := ["Oscura", "Feudal", "Castillos", "Imperial", "Pólvora", "Industrial", "Militar"]

var _speed := 60.0
var _cap_minutes := 120.0
var _forced_ticks := 0
var _slowmo := false
var _tag := ""
var _windowed := true
var _base_ticks := 60

var _ended := false
var _end_reason := ""
var _t := 0.0
var _next_poll := 0.0
var _next_sample := 0.0
var _next_print := 0.0
var _next_fp := 60.0
var _wall0 := 0
var _delta_min := INF
var _delta_max := 0.0

var _events: Array = []
var _samples: Array = []
var _prints: Dictionary = {}
var _firsts: Dictionary = {}
var _age_times: Dictionary = {}
var _waves: Array = []
var _open_wave: Dictionary = {}
var _researching: Dictionary = {}
var _kills: Dictionary = {}
var _wild_kills: Dictionary = {}
var _buildings_lost: Dictionary = {}
var _in_fight := false
var _fight_start := 0.0
var _fight_kills0: Dictionary = {}
var _last_blow := -INF
var _fight_at := Vector2.INF
var _combats: Array = []
var _shot_queue: Array = []
var _shot_n := 0
var _idle_since: Dictionary = {}
var _pids: Array[int] = []
var _winners: Array = []

var _frame := 0
var _clock: Label
var _rows: Array[Label] = []
var _feed: Label
var _banner: Label
var _banner_left := 0
var _cam_goal := Vector2.ZERO
var _cam_turn := 0


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	for p in game.players:
		_pids.append(p.id)
		_age_times[p.id] = {}
		_kills[p.id] = 0
		_wild_kills[p.id] = 0
		_buildings_lost[p.id] = []
		_idle_since[p.id] = -1.0
	game.camera.settings["edge_scroll"] = false
	game.camera.input_enabled = false
	game.set_process(false)  # Game._process only autosaves: never overwrite the user's autosave
	AudioServer.set_bus_mute(0, true)
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_speed = float(opts.get("speed", 60.0))
	_cap_minutes = float(opts.get("cap", 120.0))
	_forced_ticks = int(opts.get("ticks", 0))
	_slowmo = opts.has("slowmo")
	_tag = String(opts.get("tag", ""))
	_windowed = DisplayServer.get_name() != "headless"
	_base_ticks = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	EventBus.age_changed.connect(_on_age)
	EventBus.entity_killed.connect(_on_killed)
	EventBus.player_defeated.connect(_on_defeated)
	EventBus.game_over.connect(_on_game_over)
	if _windowed:
		_make_overlay()
		game.hud.visible = false
		game.fog._overlay.visible = false
	_play.call_deferred()


func _set_speed(x: float) -> void:
	Engine.time_scale = x
	Engine.physics_ticks_per_second = _forced_ticks if _forced_ticks > 0 else int(_base_ticks * x)
	Engine.max_physics_steps_per_frame = maxi(8, int(x * 4.0))


func _play() -> void:
	await _frames(2)
	_wall0 = Time.get_ticks_msec()
	_set_speed(_speed)
	var d: String = _game.ai_players[0].difficulty
	_event("start", "Empieza la partida: %s, IA %s, mapa %s, semilla %d" % [_sides(), d, _game.config.get("map_type", "?"), _game.map.seed])
	_want_shot("inicio", _home(1))
	while not _ended:
		await get_tree().process_frame
		_frame += 1
		if _windowed:
			_show_all()
			_update_overlay()
			_move_camera()
			if not _shot_queue.is_empty():
				var s: Array = _shot_queue.pop_front()
				_game.camera.focus_world(Iso.grid_to_world(s[1]))
				_cam_goal = _game.camera.position
				await _frames(2)
				await _shot_to(s[0])
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = _base_ticks
	if _windowed:
		for i in 120:
			await get_tree().process_frame
			_show_all()
		await _shot_to("final")
	_write_report()
	_check(_samples.size() > 1, "the match produced a timeline (%d samples)" % _samples.size())
	_check(is_equal_approx(_delta_max, _delta_min) or _forced_ticks > 0, "every tick lasted the same game time (%.5f..%.5f s)" % [_delta_min, _delta_max])
	_finish()


# --- Observation ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _ended or _wall0 == 0:
		return
	_delta_min = minf(_delta_min, delta)
	_delta_max = maxf(_delta_max, delta)
	_t = _game.victory.elapsed
	if _t >= _next_poll:
		_next_poll += 1.0
		_poll()
	if _t >= _next_sample:
		_next_sample += SAMPLE_EVERY
		_sample()
	if _t >= _next_fp:
		_next_fp += 60.0
		_prints[str(int(_t / 60.0))] = _fingerprint()
	if _t >= _cap_minutes * 60.0 and not _ended:
		_event("cap", "Se llegó al tope de %d minutos de juego sin ganador" % int(_cap_minutes))
		_sample()
		_end_reason = "tope de tiempo"
		_ended = true


func _poll() -> void:
	for ai in _game.ai_players:
		_watch_wave(ai)
		_watch_research(ai)
	var blows := 0
	var sum := Vector2.ZERO
	var count := {}
	for u in _game.unit_system.units:
		if u.dead or u.owner_id <= 0 or not is_instance_valid(u.target):
			continue
		var o: int = u.target.owner_id
		if o <= 0 or CombatSystem.are_allies(o, u.owner_id) or u.target.def.has("animal") or u.is_worker:
			continue
		if u.type_id == "scout":
			# The starting scouts bump into anything on their rounds: that is no attack.
			if not _firsts.has("first_scout_contact"):
				_firsts["first_scout_contact"] = _t
				_event("scout", "Un explorador de %s se cruza con el enemigo (roce, no es un ataque)" % NAMES[u.owner_id])
		else:
			blows += 1
			sum += u.grid_pos
			count[u.owner_id] = count.get(u.owner_id, 0) + 1
	if blows > 0:
		_last_blow = _t
		_fight_at = sum / blows
		if not _firsts.has("first_engagement"):
			_firsts["first_engagement"] = _t
			_event("engage", "PRIMER COMBATE: soldados peleando cerca %s" % _where(_fight_at), true)
			_want_shot("primer_combate", _fight_at)
		if not _in_fight:
			_in_fight = true
			_fight_start = _t
			_fight_kills0 = _kills.duplicate()
			_slow(true)
			_event("fight", "Combate cerca %s (%s)" % [_where(_fight_at), _tally(count)])
	elif _in_fight and _t - _last_blow > QUIET_AFTER:
		_in_fight = false
		_slow(false)
		var dead := {}
		for pid in _pids:
			dead[pid] = _kills[pid] - _fight_kills0[pid]
		_combats.append({"from": _fight_start, "to": _last_blow, "kills": dead})
		_event("fight_end", "Fin del combate: %d s, bajas causadas: %s" % [int(_last_blow - _fight_start), _tally(dead)])
	_watch_idle()


## Wave launched, arrived at the enemy base, wiped out or gone home.
func _watch_wave(ai: AIPlayer) -> void:
	var pid: int = ai.player.id
	var open: Dictionary = _open_wave.get(pid, {})
	if ai.wave.is_empty():
		if not open.is_empty():
			open["ended"] = _t
			_waves.append(open)
			_open_wave.erase(pid)
			_event("wave_end", "La oleada de %s terminó (%d s en el campo, %s)" % [NAMES[pid], int(_t - float(open["launched"])), "llegó a la base enemiga" if open.has("arrived") else "no llegó a la base enemiga"])
		return
	if open.is_empty():
		var kinds := {}
		for u in ai.wave:
			kinds[u.type_id] = kinds.get(u.type_id, 0) + 1
		open = {"player": pid, "launched": _t, "size": ai.wave.size(), "units": kinds}
		_open_wave[pid] = open
		if not _firsts.has("first_wave"):
			_firsts["first_wave"] = _t
			_firsts["first_wave_player"] = pid
		_event("wave", "%s lanza un ataque con %d unidades %s" % [NAMES[pid], ai.wave.size(), str(kinds)], true)
		_want_shot("oleada_%s" % NAMES[pid].to_lower(), _group_center(ai.wave))
	if not open.has("arrived"):
		for u in ai.wave:
			if _near_enemy_building(u, pid):
				open["arrived"] = _t
				if not _firsts.has("first_arrival"):
					_firsts["first_arrival"] = _t
				_event("arrive", "El ataque de %s llega a la base enemiga (viajó %d s)" % [NAMES[pid], int(_t - float(open["launched"]))], true)
				_want_shot("llegada_%s" % NAMES[pid].to_lower(), u.grid_pos)
				break


func _watch_research(ai: AIPlayer) -> void:
	var pid: int = ai.player.id
	var id := ai._next_age_id()
	if id == "" or _researching.get(pid, "") == id:
		return
	for b in _game.buildings.buildings:
		if b.owner_id == pid and b.queue.has(id):
			_researching[pid] = id
			_age_times[pid]["start_%d" % (ai.player.age + 1)] = _t
			_event("research", "%s empieza a investigar la edad %s" % [NAMES[pid], AGE_NAMES[ai.player.age + 1]])
			return


## Writes down when most of a player's villagers stand idle for a long time.
func _watch_idle() -> void:
	for pid in _pids:
		var v := _workers(pid)
		var idle := v.filter(func(u): return u.task.is_empty() and u.state == Unit.State.IDLE).size()
		if not v.is_empty() and idle * 2 >= v.size():
			if _idle_since[pid] < 0.0:
				_idle_since[pid] = _t
			elif _t - _idle_since[pid] >= 120.0 and not _firsts.has("idle_%d" % pid):
				_firsts["idle_%d" % pid] = _t
				_event("idle", "ATENCIÓN: %s tiene %d de %d aldeanos parados hace 2 minutos" % [NAMES[pid], idle, v.size()], true)
				_want_shot("parados_%s" % NAMES[pid].to_lower(), _home(pid))
		else:
			_idle_since[pid] = -1.0


func _on_age(pid: int, age: int) -> void:
	if not _age_times.has(pid) or _ended:
		return
	_age_times[pid]["done_%d" % age] = _t
	_researching.erase(pid)
	_event("age", "%s llega a la edad %s" % [NAMES[pid], AGE_NAMES[age]], true)
	_want_shot("edad_%s_%d" % [NAMES[pid].to_lower(), age], _home(pid))


func _on_killed(e: Node, attacker: Node) -> void:
	if _ended or e.owner_id <= 0 or e.def.has("animal"):
		return
	var by := -1
	if attacker != null and is_instance_valid(attacker):
		by = attacker.owner_id
	if by == -1:
		return  # collapse of a defeated player, or a butchered sheep
	var name := Loc.text(String(e.def.get("display_name", "")))
	if by == Entity.GAIA:
		_wild_kills[e.owner_id] += 1
		if _wild_kills[e.owner_id] == 1:
			_event("wild", "Un animal salvaje mata por primera vez a un %s de %s" % [name, NAMES[e.owner_id]])
		return
	if CombatSystem.are_allies(by, e.owner_id):
		return
	_kills[by] += 1
	var duel: bool = e.type_id == "scout" and attacker is Unit and attacker.type_id == "scout"
	if duel:
		_event("scout", "Un explorador de %s mata al explorador de %s" % [NAMES[by], NAMES[e.owner_id]])
	elif not _firsts.has("first_kill"):
		_firsts["first_kill"] = _t
		_event("kill", "PRIMERA BAJA: %s mata a un %s de %s" % [NAMES[by], name, NAMES[e.owner_id]], true)
	if e is Building:
		_buildings_lost[e.owner_id].append({"t": _t, "type": e.type_id})
		if not _firsts.has("first_building"):
			_firsts["first_building"] = _t
			_want_shot("primer_edificio", e.grid_pos)
		_event("building", "%s destruye %s de %s" % [NAMES[by], name, NAMES[e.owner_id]], e.type_id == "town_center")


func _on_defeated(pid: int) -> void:
	if not _ended:
		_event("defeat", "%s queda derrotado" % NAMES.get(pid, str(pid)), true)


func _on_game_over(winners: Array) -> void:
	if _ended:
		return
	_winners = winners.duplicate()
	var names: PackedStringArray = []
	for w in winners:
		names.append(NAMES.get(w, "?"))
	_event("win", "GANA %s en el minuto %s" % [" y ".join(names) if not names.is_empty() else "nadie", _clock_text(_t)], true)
	_sample()
	_end_reason = "victoria"
	_ended = true


func _sample() -> void:
	var row := {"t": snappedf(_t, 0.1)}
	var line: PackedStringArray = []
	for pid in _pids:
		var a := _snapshot(pid)
		row[str(pid)] = a
		line.append("%s: edad %d, %d ald, %d ejército, %s" % [NAMES[pid], a["age"], a["villagers"], a["army"], str(a["res"])])
	_samples.append(row)
	if int(_t) % 300 < 1 or _ended:
		print("  [%s] %s" % [_clock_text(_t), " | ".join(line)])


func _snapshot(pid: int) -> Dictionary:
	var p := _game.player(pid)
	var vill := 0
	var idle := 0
	var army := 0
	var types := {}
	var tasks := {"food": 0, "wood": 0, "gold": 0, "stone": 0, "build": 0, "idle": 0}
	for u in _game.unit_system.units:
		if u.owner_id != pid or u.dead or u.def.has("animal"):
			continue
		if u.is_worker:
			vill += 1
			if u.task.is_empty():
				if u.state == Unit.State.IDLE:
					idle += 1
				tasks["idle"] += 1
			elif u.task.get("type", "") == "gather":
				tasks[u.task.get("kind", "food")] = tasks.get(u.task.get("kind", "food"), 0) + 1
			else:
				tasks["build"] += 1
		else:
			army += 1
			types[u.type_id] = types.get(u.type_id, 0) + 1
	var blds := {}
	for b in _game.buildings.buildings:
		if b.owner_id == pid and not b.dead:
			blds[b.type_id] = blds.get(b.type_id, 0) + 1
	return {"age": p.age, "villagers": vill, "idle": idle, "army": army, "army_types": types, "tasks": tasks,
		"pop": _game.population(pid), "cap": _game.population_cap(pid), "res": p.resources.duplicate(),
		"buildings": blds, "gathered": p.stats["gathered"].duplicate(), "trained": p.stats["units_trained"],
		"lost": p.stats["units_lost"], "kills": _kills[pid], "wild_deaths": _wild_kills[pid], "buildings_lost": p.stats["buildings_lost"]}


## A number that changes with any difference in the state of the simulation.
func _fingerprint() -> int:
	var parts: Array = []
	for u in _game.unit_system.units:
		parts.append([u.entity_id, u.owner_id, snappedf(u.grid_pos.x, 0.001), snappedf(u.grid_pos.y, 0.001), u.hp])
	for b in _game.buildings.buildings:
		parts.append([b.entity_id, b.owner_id, b.hp])
	for p in _game.players:
		parts.append(p.resources.values())
	return str(parts).hash()


# --- Helpers ---------------------------------------------------------------------------

func _event(kind: String, text: String, big: bool = false) -> void:
	_events.append({"t": snappedf(_t, 0.1), "kind": kind, "text": text})
	print("[%s] %s" % [_clock_text(_t), text])
	if big and _windowed:
		_banner.text = "%s\nminuto %s" % [text, _clock_text(_t)]
		_banner_left = 110


func _clock_text(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


## "Azul contra Rojo", or "Azul y Verde contra Rojo y Amarillo" with teams.
func _sides() -> String:
	var by_team := {}
	for p in _game.players:
		var key: int = p.team if p.team != 0 else -p.id
		if not by_team.has(key):
			by_team[key] = PackedStringArray()
		by_team[key].append(NAMES[p.id])
	var out: PackedStringArray = []
	for key in by_team:
		out.append(" y ".join(by_team[key]))
	return " contra ".join(out)


## "Azul 3, Rojo 2" for a player id -> number dictionary.
func _tally(values: Dictionary) -> String:
	var out: PackedStringArray = []
	for pid in _pids:
		out.append("%s %d" % [NAMES[pid], values.get(pid, 0)])
	return ", ".join(out)


func _home(pid: int) -> Vector2:
	return Iso.tile_center(_game.map.start_positions[pid - 1])


func _where(g: Vector2) -> String:
	var near := _pids[0]
	for pid in _pids:
		if g.distance_to(_home(pid)) < g.distance_to(_home(near)):
			near = pid
	if g.distance_to(_home(near)) > 18.0:
		return "del medio del mapa"
	return "de la base de %s" % NAMES[near]


func _workers(pid: int) -> Array:
	return _game.unit_system.units.filter(func(u): return u.owner_id == pid and u.is_worker and not u.dead)


func _group_center(list: Array) -> Vector2:
	var s := Vector2.ZERO
	for u in list:
		s += u.grid_pos
	return s / maxf(1.0, list.size())


func _near_enemy_building(u: Unit, pid: int) -> bool:
	for b in _game.buildings.buildings:
		if b.owner_id > 0 and not CombatSystem.are_allies(b.owner_id, pid) and not b.dead and b.grid_pos.distance_to(u.grid_pos) <= ARRIVED_TILES:
			return true
	return false


func _want_shot(name: String, at: Vector2) -> void:
	if _windowed:
		_shot_n += 1
		_shot_queue.append(["%02d_%s" % [_shot_n, name], at])


func _shot_to(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path(EVIDENCE)
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir + "aimatch_%d%s_%s.png" % [_game.map.seed, _tag, name])


func _slow(on: bool) -> void:
	if _slowmo:
		_set_speed(SLOWMO_SPEED if on else _speed)


# --- What the viewer sees --------------------------------------------------------------

## Fog stays on for the AIs; only the drawing shows both sides.
func _show_all() -> void:
	for u in _game.unit_system.units:
		if u.aboard == null:
			u.visible = true
	for b in _game.buildings.buildings:
		b.visible = true


func _make_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.62)
	back.position = Vector2(12, 12)
	back.size = Vector2(640, 165 + _pids.size() * 60)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(back)
	_clock = _label(layer, Vector2(24, 18), 26, Color.WHITE)
	for pid in _pids:
		_rows.append(_label(layer, Vector2(24, 56 + (pid - 1) * 60), 18, _game.player(pid).color().lightened(0.35)))
	_feed = _label(layer, Vector2(24, 60 + _pids.size() * 60), 15, Color(0.88, 0.88, 0.88))
	_banner = _label(layer, Vector2(0, 200 + _pids.size() * 60), 34, Color(1.0, 0.9, 0.45))
	_banner.size = Vector2(get_viewport().get_visible_rect().size.x, 100)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 8)


func _label(parent: Node, at: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _update_overlay() -> void:
	_clock.text = "Minuto %s   ·   x%d   ·   semilla %d" % [_clock_text(_t), int(Engine.time_scale), _game.map.seed]
	for pid in _pids:
		var s := _snapshot(pid)
		var r: Dictionary = s["res"]
		_rows[pid - 1].text = "%s · edad %s · %d aldeanos · %d soldados · %d edificios\ncomida %d  madera %d  oro %d  piedra %d" % [NAMES[pid], AGE_NAMES[s["age"]], s["villagers"], s["army"], s["buildings"].values().reduce(func(a, b): return a + b, 0), r["food"], r["wood"], r["gold"], r["stone"]]
	var lines: PackedStringArray = []
	for e in _events.slice(maxi(0, _events.size() - 8)):
		lines.append("%s  %s" % [_clock_text(e["t"]), String(e["text"]).left(72)])
	_feed.text = "\n".join(lines)
	_banner_left -= 1
	_banner.visible = _banner_left > 0


## Follows the fight; with no fight it moves from one base to the other.
func _move_camera() -> void:
	var goal := _cam_goal
	if _t - _last_blow < 5.0 and _fight_at != Vector2.INF:
		goal = Iso.grid_to_world(_fight_at)
	else:
		var moving := []
		for ai in _game.ai_players:
			if not ai.wave.is_empty():
				moving = ai.wave
		if not moving.is_empty():
			goal = Iso.grid_to_world(_group_center(moving))
		else:
			if _frame % 240 == 1:
				_cam_turn = _cam_turn % _pids.size() + 1
			goal = Iso.grid_to_world(_home(maxi(1, _cam_turn)))
	_cam_goal = goal
	_game.camera.focus_world(_game.camera.position.lerp(goal, 0.08))


# --- Report ----------------------------------------------------------------------------

## What is left on the map: explains a match that stopped moving.
func _final_state() -> Dictionary:
	var units := []
	for u in _game.unit_system.units:
		if u.owner_id > 0 and not u.dead and not u.def.has("animal"):
			var aim := "-"
			if is_instance_valid(u.target):
				aim = "%s(j%d) a %.1f" % [u.target.type_id, u.target.owner_id, u.grid_pos.distance_to(u.target.grid_pos)]
			units.append({"p": u.owner_id, "type": u.type_id, "at": [snappedf(u.grid_pos.x, 0.1), snappedf(u.grid_pos.y, 0.1)], "state": u.state, "aim": aim, "task": str(u.task.get("type", "")), "aboard": u.aboard != null})
	var blds := []
	for b in _game.buildings.buildings:
		if b.owner_id > 0 and not b.dead:
			blds.append({"p": b.owner_id, "type": b.type_id, "at": [snappedf(b.grid_pos.x, 0.1), snappedf(b.grid_pos.y, 0.1)], "hp": b.hp, "done": b.is_complete()})
	var ais := []
	for ai in _game.ai_players:
		var ready: int = ai._army.filter(func(u): return not u.has_target()).size()
		ais.append({"p": ai.player.id, "army": ai._army.size(), "free": ready, "wave": ai.wave.size(), "threat": str(ai._threat), "targets": ai.enemy_targets.slice(0, 5).map(str), "needs_boat": ai._needs_boat, "last_wave": ai.last_wave_time})
	return {"units": units, "buildings": blds, "ai": ais}


func _write_report() -> void:
	var wall := (Time.get_ticks_msec() - _wall0) / 1000.0
	var ending := {}
	for ai in _game.ai_players:
		ending[str(ai.player.id)] = {"age": ai.player.age, "next_age": ai._next_age_id(), "ready_for_age": ai._ready_for_age(),
			"villager_target": int(ai.diff.get("villager_target", 0)), "age_threshold": ai.diff.get("age_up_villagers", []),
			"enemy_targets": ai.enemy_targets.size(), "defeated": ai.player.defeated}
	var data := {"players": _pids.size(), "seed": _game.map.seed, "map": _game.config.get("map_type", ""), "size": _game.map.width,
		"difficulty": _game.ai_players[0].difficulty, "victory": _game.victory.condition, "speed": _speed,
		"forced_ticks": _forced_ticks, "delta": [_delta_min, _delta_max], "wall_seconds": wall,
		"effective_speed": _t / maxf(wall, 0.01), "game_seconds": _t, "end": _end_reason,
		"winners": _winners, "firsts": _firsts, "ages": _age_times, "waves": _waves, "combats": _combats,
		"kills": _kills, "wild_kills": _wild_kills, "buildings_lost": _buildings_lost, "ending": ending,
		"events": _events, "samples": _samples, "fingerprints": _prints, "final_state": _final_state()}
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "aimatch_%s_%s_%d%s.json" % [data["difficulty"], data["map"], data["seed"], _tag]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_log.append("AIMATCH %s tras %s de juego en %.0f s reales (x%.1f real), delta %.5f..%.5f -> %s" % [_end_reason, _clock_text(_t), wall, data["effective_speed"], _delta_min, _delta_max, path])

class_name GameAudio
extends Node
## World sound of one match: positional effects, selection/order voices,
## alerts, ambience and the music that follows the age and the fighting.
##
## Sources: entities and systems emit EventBus.sound_at(key, world_pos) from
## code that runs on the host and on network replicas alike (attack
## animations, work frames, deaths, effect bursts), so every player hears the
## same match. A sound plays only when its spot is on (or just off) screen and
## visible to the local player, so the fog never leaks.
## Limits: a pool of AudioStreamPlayer2D, at most N instances per key and a
## minimum interval per key (audio_settings.json).
## Ambience: wind / water / forest / night / battle loops mixed from what the
## camera shows, plus birds by day, owls and wolves by night (night amount
## comes from game.day_night when present).
## Music: the age playlist; a battle playlist while many fights are heard.

var _game: Game
var _cfg: Dictionary
var _pool: Array[AudioStreamPlayer2D] = []
var _next := 0
var _active: Dictionary = {}      # key -> Array of players
var _last_play: Dictionary = {}   # key -> msec
var _ambient: Dictionary = {}     # loop key -> AudioStreamPlayer
var _emitters: Dictionary = {}    # entity id -> AudioStreamPlayer2D
var _amb_timer := 0.0
var _loop_timer := 0.0
var _one_shot_timers: Dictionary = {}
var _battle_hits: Array[int] = []
var _battle_mode := false
var _calm_time := 0.0
var _last_sel_ids: Array = []
var _last_voice_ms := 0
var _rng := RandomNumberGenerator.new()
var _was_night := false
var _view_mix := {"water": 0.0, "forest": 0.0, "open": 1.0}
## Extra gain (dB) for every world sound (the title backdrop plays quieter).
var master_db := 0.0
## Plays per key since the match started (diagnostics and smoke tests).
var played: Dictionary = {}


func setup(game: Game) -> void:
	_game = game
	_cfg = GameData.audio
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if game.config.get("showcase", false):
		master_db = -8.0
	for i in int(_cfg.get("pool_size", 40)):
		var p := AudioStreamPlayer2D.new()
		p.bus = "Sfx"
		add_child(p)
		_pool.append(p)
	for key in _cfg.get("ambient", {}).get("loops", {}):
		var a := AudioStreamPlayer.new()
		a.bus = "Ambient"
		a.stream = Audio.stream(String(key), true)
		a.volume_db = -60.0
		add_child(a)
		if a.stream != null:
			a.play(_rng.randf() * maxf(0.1, a.stream.get_length() - 0.5))
		_ambient[key] = a
	EventBus.sound_at.connect(play_at)
	game.fx.burst_emitted.connect(_on_burst)
	if game.config.get("showcase", false):
		return
	EventBus.selection_changed.connect(_on_selection)
	EventBus.local_order.connect(_on_order)
	EventBus.notify.connect(_on_notify)
	EventBus.age_changed.connect(_on_age)
	EventBus.tech_researched.connect(_on_tech)
	EventBus.unit_trained.connect(_on_trained)
	EventBus.player_defeated.connect(_on_defeated)
	EventBus.game_over.connect(_on_game_over)
	EventBus.ui_sound.connect(func(key: String) -> void: Audio.ui(key))
	_play_age_music()


# --- Positional one-shots ------------------------------------------------------------------------

## Plays `key` at a world position if the local player can see that spot.
func play_at(key: String, world_pos: Vector2, volume_db: float = 0.0) -> void:
	if key == "" or _pool.is_empty():
		return
	if not _audible(world_pos):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(key, -100000)) < int(float(_cfg.get("min_interval", 0.04)) * 1000.0):
		return
	var playing: Array = _active.get(key, []).filter(func(p): return p.playing)
	_active[key] = playing
	var limit := int(_cfg.get("max_instances_by_key", {}).get(key, _cfg.get("max_instances", 4)))
	if playing.size() >= limit:
		return
	var s := Audio.stream(key)
	if s == null:
		return
	_last_play[key] = now
	var p := _take_player()
	p.stream = s
	p.position = world_pos
	p.volume_db = Audio.key_db(key) + volume_db + master_db + _zoom_db()
	p.pitch_scale = _rng.randf_range(0.94, 1.06)
	p.max_distance = _view_radius() * 1.6
	p.attenuation = float(_cfg.get("positional", {}).get("attenuation", 1.4))
	p.play()
	played[key] = int(played.get(key, 0)) + 1
	playing.append(p)
	_active[key] = playing
	if _is_combat_key(key):
		_battle_hits.append(now)


func _take_player() -> AudioStreamPlayer2D:
	# Prefer an idle player; otherwise steal the oldest in round-robin order.
	for i in _pool.size():
		var p := _pool[(_next + i) % _pool.size()]
		if not p.playing:
			_next = (_next + i + 1) % _pool.size()
			return p
	var q := _pool[_next]
	_next = (_next + 1) % _pool.size()
	q.stop()
	return q


func _view_rect() -> Rect2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)


func _view_radius() -> float:
	return _view_rect().size.length() * 0.5


func _zoom_db() -> float:
	var z: Dictionary = _cfg.get("positional", {}).get("zoom_volume", {})
	var zoom := _game.camera.zoom.x
	var min_zoom := float(z.get("min_zoom", 0.5))
	var levels: Array = _game.camera.zoom_levels
	var top := float(levels.max()) if not levels.is_empty() else 2.0
	return lerpf(float(z.get("min_db", -9.0)), 0.0, clampf((zoom - min_zoom) / maxf(0.01, top - min_zoom), 0.0, 1.0))


func _audible(world_pos: Vector2) -> bool:
	var r := _view_rect()
	var margin := float(_cfg.get("positional", {}).get("screen_margin", 0.25))
	if not r.grow_individual(r.size.x * margin, r.size.y * margin, r.size.x * margin, r.size.y * margin).has_point(world_pos):
		return false
	return _game.fog.is_tile_visible(_game.local_player, Iso.tile_of(Iso.world_to_grid(world_pos)))


func _is_combat_key(key: String) -> bool:
	return key.begins_with("hit_") or key in ["swing", "bow", "musket", "rifle", "machine_gun", "cannon", "explosion", "crossbow", "artillery", "tank_gun", "death", "arrow_hit"]


func _on_burst(world_pos: Vector2, kind: String, sound: String) -> void:
	var key := sound if sound != "" else String(_cfg.get("fx_sounds", {}).get(kind, ""))
	play_at(key, world_pos)


# --- Player feedback ------------------------------------------------------------------------------

func _on_selection(list: Array) -> void:
	var ids := []
	for e in list:
		if is_instance_valid(e):
			ids.append(e.entity_id)
	var first_changed: bool = ids.is_empty() or _last_sel_ids.is_empty() or ids[0] != _last_sel_ids[0]
	var grew := ids.size() > _last_sel_ids.size()
	_last_sel_ids = ids
	if ids.is_empty() or not (first_changed or grew):
		return
	var e: Entity = list[0]
	if e is Unit:
		var animal := SoundRules.animal_voice(_cfg, e.type_id)
		if animal != "":
			_voice(animal)
		elif e.owner_id == _game.local_player:
			_voice("sel_" + SoundRules.voice(_cfg, e.type_id, e.def))
	elif e is Building:
		_voice(SoundRules.building_key(_cfg, e.type_id))


func _on_order(units: Array) -> void:
	for u in units:
		if is_instance_valid(u) and u is Unit and not u.dead:
			var v := SoundRules.voice(_cfg, u.type_id, u.def)
			_voice("ack_" + v if v != "" else SoundRules.animal_voice(_cfg, u.type_id))
			return


## Selection and order voices: never stacked, at most one every 0.2 s.
func _voice(key: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_voice_ms < 200 or not Audio.has_sound(key):
		return
	_last_voice_ms = now
	Audio.ui(key)


func _on_notify(pid: int, text: String) -> void:
	if pid != 0 and pid != _game.local_player:
		return
	Audio.ui(SoundRules.notify_key(_cfg, text))


func _on_age(pid: int, _age: int) -> void:
	if pid == _game.local_player:
		Audio.ui("age_up")
		_play_age_music()


func _on_tech(pid: int, tech_id: String) -> void:
	if pid == _game.local_player and not GameData.ages.has(tech_id):
		Audio.ui("research_done")


func _on_trained(u: Node) -> void:
	if u is Unit and u.owner_id == _game.local_player:
		Audio.ui("unit_ready")


func _on_defeated(pid: int) -> void:
	if pid != _game.local_player:
		Audio.ui("player_defeated")


func _on_game_over(winners: Array) -> void:
	Audio.stop_music(1.0)
	Audio.ui("victory" if winners.has(_game.local_player) else "defeat")


# --- Music --------------------------------------------------------------------------------------------

func _play_age_music() -> void:
	var by_age: Array = _cfg.get("music", {}).get("by_age", [])
	if by_age.is_empty():
		return
	var age := clampi(_game.local_state().age, 0, by_age.size() - 1)
	Audio.play_playlist(by_age[age], "age_%d" % age)


func _update_battle(delta: float) -> void:
	var m: Dictionary = _cfg.get("music", {})
	var window := int(float(m.get("battle_window", 8.0)) * 1000.0)
	var now := Time.get_ticks_msec()
	while not _battle_hits.is_empty() and now - _battle_hits[0] > window:
		_battle_hits.pop_front()
	var enter := int(m.get("battle_enter", 14))
	if not _battle_mode and _battle_hits.size() >= enter:
		_battle_mode = true
		_calm_time = 0.0
		Audio.play_playlist(m.get("battle", []), "battle")
	elif _battle_mode:
		_calm_time = 0.0 if _battle_hits.size() >= enter / 3 else _calm_time + delta
		if _calm_time > float(m.get("battle_exit_seconds", 25.0)):
			_battle_mode = false
			_play_age_music()


# --- Ambience and loops ------------------------------------------------------------------------------

## 0 (day) .. 1 (deep night), from the day/night cycle when the match has one.
func _night() -> float:
	if _game.get("day_night") != null:
		return float(_game.day_night.night_amount())
	return 0.0


func _process(delta: float) -> void:
	if _game == null or _game.map == null:
		return
	if not _game.config.get("showcase", false):
		_update_battle(delta)
	_amb_timer -= delta
	if _amb_timer <= 0.0:
		_amb_timer = float(_cfg.get("ambient", {}).get("update_interval", 0.5))
		_sample_view()
		_mix_ambience()
	_one_shots(delta)
	_loop_timer -= delta
	if _loop_timer <= 0.0:
		_loop_timer = 0.25
		_update_emitters()
	for id in _emitters:
		var e: Entity = _game.entity(id)
		if e != null:
			_emitters[id].position = e.position


func _sample_view() -> void:
	var r := _view_rect()
	var counts := {"water": 0, "forest": 0, "open": 0}
	var total := 0
	for iy in 8:
		for ix in 12:
			var w := r.position + Vector2((ix + 0.5) / 12.0 * r.size.x, (iy + 0.5) / 8.0 * r.size.y)
			var t := Iso.tile_of(Iso.world_to_grid(w))
			if not _game.map.in_bounds(t):
				continue
			total += 1
			var ter := _game.map.get_terrain(t)
			if ter == MapData.Terrain.WATER or ter == MapData.Terrain.DEEP_WATER:
				counts["water"] += 1
			elif ter == MapData.Terrain.FOREST or _game.static_entity_at(t) is ResourceNode:
				counts["forest"] += 1
			else:
				counts["open"] += 1
	for k in counts:
		_view_mix[k] = float(counts[k]) / maxf(1.0, total)


func _mix_ambience() -> void:
	var loops: Dictionary = _cfg.get("ambient", {}).get("loops", {})
	var night := _night()
	var battle := clampf(float(_battle_hits.size()) / float(_cfg.get("music", {}).get("battle_enter", 14)), 0.0, 1.0)
	for key in loops:
		var a: AudioStreamPlayer = _ambient.get(key)
		if a == null or a.stream == null:
			continue
		var d: Dictionary = loops[key]
		var level := 1.0
		if d.has("per_open"):
			level = 0.35 + float(d["per_open"]) * _view_mix["open"]
		elif d.has("per_water"):
			level = clampf(_view_mix["water"] * 2.5, 0.0, 1.0)
		elif d.has("per_forest"):
			level = clampf(_view_mix["forest"] * 2.0, 0.0, 1.0) * (1.0 - night * 0.7)
		elif d.has("per_battle"):
			level = battle
		if d.get("night_only", false):
			level = night
		var target := -60.0 if level <= 0.01 else float(d.get("base_db", -12.0)) + linear_to_db(level) + master_db + _zoom_db() * 0.5
		a.volume_db = lerpf(a.volume_db, target, 0.35)
	var is_night := night > 0.6
	if _was_night and not is_night and not _game.config.get("showcase", false):
		var dawn := String(_cfg.get("ambient", {}).get("dawn_sound", ""))
		Audio.ui(dawn, -6.0)
		play_at("rooster", _random_visible_point())
	_was_night = is_night


func _one_shots(delta: float) -> void:
	var amb: Dictionary = _cfg.get("ambient", {})
	var night := _night()
	var lists := []
	if night < 0.5:
		lists.append(amb.get("day_one_shots", []))
	else:
		lists.append(amb.get("night_one_shots", []))
	if _view_mix["water"] > 0.1:
		lists.append(amb.get("coast_one_shots", []))
	for list in lists:
		for entry in list:
			var key := String(entry[0])
			var t := float(_one_shot_timers.get(key, _rng.randf_range(float(entry[1]), float(entry[2]))))
			t -= delta
			if t <= 0.0:
				t = _rng.randf_range(float(entry[1]), float(entry[2]))
				var p := _random_visible_point()
				if p != Vector2.INF and not (key == "frog" and _view_mix["water"] < 0.05):
					play_at(key, p, -4.0 if key == "wolf_howl" else 0.0)
			_one_shot_timers[key] = t
	# Animals on screen bleat, gobble and growl now and then.
	var chatter: Array = amb.get("animal_chatter", [6.0, 14.0])
	var ct := float(_one_shot_timers.get("_animals", float(chatter[0]))) - delta
	if ct <= 0.0:
		ct = _rng.randf_range(float(chatter[0]), float(chatter[1]))
		var r := _view_rect()
		var candidates := []
		for u in _game.unit_system.units:
			if u.def.has("animal") and not u.dead and r.has_point(u.position):
				candidates.append(u)
		if not candidates.is_empty():
			var a: Unit = candidates[_rng.randi() % candidates.size()]
			play_at(SoundRules.animal_voice(_cfg, a.type_id), a.position, -3.0)
	_one_shot_timers["_animals"] = ct


func _random_visible_point() -> Vector2:
	var r := _view_rect()
	for i in 6:
		var p := r.position + Vector2(_rng.randf(), _rng.randf()) * r.size
		var t := Iso.tile_of(Iso.world_to_grid(p))
		if _game.map.in_bounds(t) and _game.fog.is_tile_visible(_game.local_player, t):
			return p
	return Vector2.INF


## Looping sounds that follow entities: burning buildings, moving vehicles, aircraft.
func _update_emitters() -> void:
	var lcfg: Dictionary = _cfg.get("loops", {})
	var r := _view_rect().grow(120.0)
	var center := r.get_center()
	var cands := []
	for b in _game.buildings.buildings:
		if b.visible and not b.dead and b.is_burning() and r.has_point(b.position):
			cands.append([b, "fire_loop"])
	for u in _game.unit_system.units:
		if u.dead or not u.visible or not r.has_point(u.position):
			continue
		if u.altitude > 0.0:
			cands.append([u, "prop_loop"])
		elif u.classes().has("vehicle") and u.state == Unit.State.MOVING:
			cands.append([u, "engine_loop"])
	cands.sort_custom(func(a, b): return a[0].position.distance_squared_to(center) < b[0].position.distance_squared_to(center))
	cands = cands.slice(0, int(lcfg.get("max_emitters", 5)))
	var keep := {}
	for c in cands:
		var e: Entity = c[0]
		keep[e.entity_id] = true
		if not _emitters.has(e.entity_id):
			var p := AudioStreamPlayer2D.new()
			p.bus = "Sfx"
			p.stream = Audio.stream(String(c[1]), true)
			p.volume_db = float(lcfg.get(c[1], {}).get("db", -12.0)) + master_db
			p.max_distance = _view_radius() * 1.6
			p.position = e.position
			add_child(p)
			if p.stream != null:
				p.play(_rng.randf() * maxf(0.1, p.stream.get_length() - 0.2))
			_emitters[e.entity_id] = p
	for id in _emitters.keys():
		if not keep.has(id):
			_emitters[id].queue_free()
			_emitters.erase(id)

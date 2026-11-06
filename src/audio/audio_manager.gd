extends Node
## Sound backbone (autoload `Audio`): mixer buses, saved volumes, sound lookup,
## interface sounds and music playlists with crossfades. World sounds of a
## match are positioned by GameAudio (src/audio/game_audio.gd), which uses
## stream() and the buses defined here.
##
## Buses: Master <- Music, Sfx, Ambient, Ui. Volumes are linear 0..1, saved in
## user://settings.cfg [audio]. Every Button/OptionButton in the game clicks
## on press automatically (node_added hook), so UI code needs no audio calls.
## Sound keys: "chop" picks chop_1/chop_2/chop_3 at random; "ui_click" is a
## single file. Files and variants come from assets/audio/manifest.json.
## Data: audio_settings.json.
## Example:
##   Audio.ui("research_done")
##   Audio.play_playlist(["medieval_1", "medieval_2"], "age_0")

## Bus key (settings and audio_settings.json) -> AudioServer bus name.
const BUSES := {"master": "Master", "music": "Music", "sfx": "Sfx", "ambient": "Ambient", "ui": "Ui"}
const MANIFEST := "res://assets/audio/manifest.json"
const DIRS := {"sfx": "res://assets/audio/sfx/", "loops": "res://assets/audio/loops/", "music": "res://assets/audio/music/"}
const SETTINGS_PATH := "user://settings.cfg"

signal volumes_changed

var cfg: Dictionary = {}
## Linear volume per bus key.
var volumes: Dictionary = {}
var muted := false

var _paths: Dictionary = {}      # file name -> res:// path
var _variants: Dictionary = {}   # key -> Array of file names
var _streams: Dictionary = {}    # file name -> AudioStream
var _ui_pool: Array[AudioStreamPlayer] = []
var _ui_next := 0
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _playlist: Array = []
var _playlist_id := ""
var _track_index := -1
var _gap := -1.0
var _rng := RandomNumberGenerator.new()
## Interface sounds played since launch, per key (diagnostics and smoke tests).
var ui_played: Dictionary = {}


## Sound lookup is ready from _init so headless scripts and tests can use it.
func _init() -> void:
	cfg = GameData.audio
	_rng.randomize()
	_load_manifest()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	_load_volumes()
	for i in int(cfg.get("ui_pool_size", 8)):
		var p := AudioStreamPlayer.new()
		p.bus = "Ui"
		add_child(p)
		_ui_pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
		m.finished.connect(_on_track_finished.bind(m))
	get_tree().node_added.connect(_on_node_added)


# --- Lookup ------------------------------------------------------------------------------------

func _load_manifest() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else null
	if not raw is Dictionary:
		push_warning("Audio: no manifest at %s (run tools/audio/generate_audio.gd)" % MANIFEST)
		return
	for dir in DIRS:
		for name in raw.get(dir, []):
			_paths[String(name)] = DIRS[dir] + String(name) + ".wav"
			var base := variant_base(String(name))
			if not _variants.has(base):
				_variants[base] = []
			_variants[base].append(String(name))
			if base != String(name):
				_variants[String(name)] = [String(name)]


## "chop_2" -> "chop"; names without a numeric suffix are their own key.
static func variant_base(name: String) -> String:
	var i := name.rfind("_")
	if i > 0 and name.substr(i + 1).is_valid_int():
		return name.substr(0, i)
	return name


func has_sound(key: String) -> bool:
	return _variants.has(key)


## A random variant of `key` (or null when there is no such sound).
func stream(key: String, loop: bool = false) -> AudioStream:
	var list: Array = _variants.get(key, [])
	if list.is_empty():
		return null
	var name: String = list[_rng.randi() % list.size()]
	if not _streams.has(name):
		var s: AudioStream = load(_paths[name])
		if loop and s is AudioStreamWAV:
			var w: AudioStreamWAV = s
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			# Last valid sample: the mixer also reads the one at loop_end, and with
			# QOA a length that is a multiple of the frame size would read past the data.
			w.loop_end = int(round(w.get_length() * w.mix_rate)) - 1
		_streams[name] = s
	return _streams[name]


## Extra gain for a key (audio_settings.json volumes_db), in dB.
func key_db(key: String) -> float:
	return float(cfg.get("volumes_db", {}).get(key, 0.0))


# --- Buses and volumes -------------------------------------------------------------------------

func _make_buses() -> void:
	for key in BUSES:
		var bus: String = BUSES[key]
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
	var fx: Dictionary = cfg.get("bus_effects", {})
	for key in fx:
		var idx2 := AudioServer.get_bus_index(BUSES.get(key, ""))
		if idx2 >= 0 and AudioServer.get_bus_effect_count(idx2) == 0:
			var rv := AudioEffectReverb.new()
			rv.wet = float(fx[key].get("reverb_wet", 0.1))
			rv.dry = 1.0
			rv.room_size = float(fx[key].get("reverb_room", 0.5))
			AudioServer.add_bus_effect(idx2, rv)
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0 and ClassDB.class_exists("AudioEffectHardLimiter"):
		AudioServer.add_bus_effect(master, ClassDB.instantiate("AudioEffectHardLimiter"))


func _load_volumes() -> void:
	var defaults: Dictionary = cfg.get("default_volumes", {})
	var file := ConfigFile.new()
	var ok := file.load(SETTINGS_PATH) == OK
	for key in BUSES:
		var v := float(defaults.get(key, 0.8))
		if ok:
			v = float(file.get_value("audio", key, v))
		volumes[key] = clampf(v, 0.0, 1.0)
	muted = ok and bool(file.get_value("audio", "muted", false))
	_apply_volumes()


func _apply_volumes() -> void:
	for key in BUSES:
		var idx := AudioServer.get_bus_index(BUSES[key])
		if idx < 0:
			continue
		var v: float = volumes.get(key, 0.8)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001 or (key == "master" and muted))


## Sets a bus volume (0..1) and remembers it.
func set_volume(key: String, value: float) -> void:
	volumes[key] = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save()
	volumes_changed.emit()


func set_muted(on: bool) -> void:
	muted = on
	_apply_volumes()
	_save()
	volumes_changed.emit()


func _save() -> void:
	var file := ConfigFile.new()
	file.load(SETTINGS_PATH)
	for key in volumes:
		file.set_value("audio", key, volumes[key])
	file.set_value("audio", "muted", muted)
	file.save(SETTINGS_PATH)


# --- Interface sounds ------------------------------------------------------------------------------

## Plays a non-positional sound on the Ui bus (`volume_db` adds to the key's gain).
func ui(key: String, volume_db: float = 0.0) -> void:
	var s := stream(key)
	if s == null or _ui_pool.is_empty():
		return
	var p := _ui_pool[_ui_next]
	_ui_next = (_ui_next + 1) % _ui_pool.size()
	p.stream = s
	p.volume_db = key_db(key) + volume_db
	p.pitch_scale = 1.0
	p.play()
	ui_played[key] = int(ui_played.get(key, 0)) + 1


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b: BaseButton = n
		b.pressed.connect(func() -> void: ui("ui_click"))


# --- Music ----------------------------------------------------------------------------------------

## Starts (or keeps) a playlist; `id` identifies it so asking again does not restart.
## The new list crossfades in; tracks then follow each other with short gaps.
func play_playlist(names: Array, id: String) -> void:
	if id == _playlist_id and not _playlist.is_empty():
		return
	_playlist_id = id
	_playlist = names.filter(func(n): return has_sound(String(n)))
	_playlist.shuffle()
	_track_index = -1
	_gap = -1.0
	if _playlist.is_empty():
		stop_music()
		return
	_next_track()


func playlist_id() -> String:
	return _playlist_id


func stop_music(fade_time: float = 2.0) -> void:
	_playlist = []
	_playlist_id = ""
	_gap = -1.0
	for m in _music:
		if m.playing:
			var tw := create_tween()
			tw.tween_property(m, "volume_db", -80.0, fade_time)
			tw.tween_callback(m.stop)


func _next_track() -> void:
	if _playlist.is_empty():
		return
	_track_index = (_track_index + 1) % _playlist.size()
	var s := stream(String(_playlist[_track_index]))
	if s == null:
		return
	var xf := float(cfg.get("music", {}).get("crossfade", 3.0))
	var old := _music[_music_active]
	_music_active = 1 - _music_active
	var cur := _music[_music_active]
	if old.playing:
		var t1 := create_tween()
		t1.tween_property(old, "volume_db", -80.0, xf)
		t1.tween_callback(old.stop)
	cur.stream = s
	cur.volume_db = -40.0
	cur.play()
	var t2 := create_tween()
	t2.tween_property(cur, "volume_db", 0.0, xf)


func _on_track_finished(m: AudioStreamPlayer) -> void:
	if m != _music[_music_active] or _playlist.is_empty():
		return
	var g: Array = cfg.get("music", {}).get("gap_seconds", [3.0, 9.0])
	_gap = _rng.randf_range(float(g[0]), float(g[1]))


func _process(delta: float) -> void:
	if _gap > 0.0:
		_gap -= delta
		if _gap <= 0.0:
			_gap = -1.0
			_next_track()

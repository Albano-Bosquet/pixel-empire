extends SceneTree
## Generates every sound of the game into res://assets/audio/ (sfx, loops, music).
## Run: Godot --headless --path . -s res://tools/audio/generate_audio.gd [-- --only=sfx|music]
## Re-run after changing a recipe or a music style; then run `--headless --import`.
## Everything is synthesised (tools/audio/synth.gd): no recorded samples.

const Synth := preload("res://tools/audio/synth.gd")
const SfxRecipes := preload("res://tools/audio/sfx_recipes.gd")
const MusicComposer := preload("res://tools/audio/music_composer.gd")

const OUT := "res://assets/audio/"
const SFX_RATE := 32000
const MUSIC_RATE := 22050
## Loops live apart from one-shots so the importer/audio manager can tell them apart.
const LOOP_PREFIXES := ["amb_", "engine_loop", "prop_loop", "fire_loop"]

## Music styles (see MusicComposer.render for the keys).
const STYLES := {
	"menu": {"root": 50, "mode": "mixolydian", "bpm": 72, "progression": [0, 4, 3, 0], "lead": "brass", "pad": "choir", "bass": "strings", "arp": "harp", "drums": "frame", "seed": 11, "density": 0.5},
	"medieval_1": {"root": 50, "mode": "dorian", "bpm": 88, "progression": [0, 6, 3, 0], "lead": "flute", "pad": "strings", "bass": "drone", "arp": "lute", "drums": "frame", "seed": 21, "density": 0.6},
	"medieval_2": {"root": 45, "mode": "aeolian", "bpm": 76, "progression": [0, 5, 2, 6], "lead": "lute", "pad": "choir", "bass": "drone", "arp": "harp", "drums": "frame", "seed": 33, "density": 0.5},
	"medieval_3": {"root": 55, "mode": "mixolydian", "bpm": 100, "progression": [0, 6, 3, 4], "lead": "fife", "pad": "organ", "bass": "pluck", "arp": "lute", "drums": "frame", "seed": 47, "density": 0.65, "swing": 0.15},
	"renaissance": {"root": 53, "mode": "ionian", "bpm": 96, "progression": [0, 3, 4, 0], "lead": "brass", "lead2": "fife", "pad": "strings", "bass": "march", "arp": "harp", "drums": "march", "seed": 58, "density": 0.6},
	"industrial": {"root": 52, "mode": "aeolian", "bpm": 104, "progression": [0, 5, 3, 4], "lead": "strings", "pad": "organ", "bass": "march", "arp": "bell", "drums": "march", "seed": 64, "density": 0.6},
	"modern": {"root": 48, "mode": "harmonic", "bpm": 92, "progression": [0, 5, 3, 4], "lead": "brass", "pad": "strings", "bass": "strings", "arp": "bell", "drums": "modern", "seed": 77, "density": 0.55},
	"battle_1": {"root": 52, "mode": "phrygian", "bpm": 128, "progression": [0, 1, 0, 6], "lead": "brass", "pad": "strings", "bass": "march", "drums": "war", "seed": 85, "density": 0.8},
	"battle_2": {"root": 50, "mode": "harmonic", "bpm": 120, "progression": [0, 5, 4, 0], "lead": "strings", "pad": "choir", "bass": "drone", "arp": "harp", "drums": "war", "seed": 93, "density": 0.75},
}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			only = String(a).get_slice("=", 1)
	for dir in ["sfx", "loops", "music"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + dir))
	if only == "" or only == "sfx":
		var synth := Synth.new(SFX_RATE, 4242)
		var sounds: Dictionary = SfxRecipes.new(synth).all()
		for name in sounds:
			var loop := LOOP_PREFIXES.any(func(p): return String(name).begins_with(p))
			_write(synth, sounds[name], OUT + ("loops/" if loop else "sfx/") + name + ".wav")
		print("SFX: %d sounds in %d ms" % [sounds.size(), Time.get_ticks_msec() - t0])
	if only == "" or only == "music":
		var ms := Synth.new(MUSIC_RATE, 777)
		var composer := MusicComposer.new(ms)
		for name in STYLES:
			var t1 := Time.get_ticks_msec()
			_write(ms, composer.render(STYLES[name]), OUT + "music/" + name + ".wav")
			print("  music %s in %d ms" % [name, Time.get_ticks_msec() - t1])
	_write_manifest()
	print("Audio generated in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


func _write(synth: Synth, buf: PackedFloat32Array, path: String) -> void:
	if synth.save_wav(buf, ProjectSettings.globalize_path(path)) != OK:
		push_error("Failed to save " + path)
	else:
		print("  wrote %s (%.2f s)" % [path, float(buf.size()) / synth.rate])


## Lists every generated file so the game never has to scan res:// (exported
## builds only expose *.import remaps to DirAccess).
func _write_manifest() -> void:
	var m := {}
	for dir in ["sfx", "loops", "music"]:
		var names := []
		for f in DirAccess.get_files_at(OUT + dir):
			if f.ends_with(".wav"):
				names.append(f.get_basename())
		names.sort()
		m[dir] = names
	var f := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(m, "  "))
	f.close()

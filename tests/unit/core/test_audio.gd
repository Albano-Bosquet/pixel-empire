extends "res://tests/test_case.gd"
## Sound map (audio_settings.json + assets/audio/manifest.json): every unit,
## building and game event resolves to a sound file that exists.

var _cfg: Dictionary = GameData.audio


func _exists(key: String) -> bool:
	return key == "none" or Audio.has_sound(key)


func test_variant_base_strips_numeric_suffix_only() -> void:
	assert_eq(Audio.variant_base("chop_2"), "chop", "chop_2 -> chop")
	assert_eq(Audio.variant_base("ui_click"), "ui_click", "no numeric suffix")
	assert_eq(Audio.variant_base("hit_sword_10"), "hit_sword", "two-digit suffix")


func test_manifest_files_exist() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Audio.MANIFEST))
	for dir in Audio.DIRS:
		assert_true(not m.get(dir, []).is_empty(), "manifest lists %s" % dir)
		for name in m.get(dir, []):
			assert_true(ResourceLoader.exists(Audio.DIRS[dir] + String(name) + ".wav"), "%s/%s.wav imported" % [dir, name])


func test_every_unit_has_voice_attack_and_death_sounds() -> void:
	for id in GameData.units:
		var def: Dictionary = GameData.units[id]
		var v := SoundRules.voice(_cfg, id, def)
		if def.has("animal"):
			assert_true(_exists(SoundRules.animal_voice(_cfg, id)), "animal voice for %s" % id)
		else:
			assert_true(_exists("sel_" + v) and _exists("ack_" + v), "voice '%s' for %s" % [v, id])
		var atk := SoundRules.attack_key(_cfg, id, def)
		assert_true(atk == "" or _exists(atk), "attack sound '%s' for %s" % [atk, id])
		assert_true(_exists(SoundRules.death_key(_cfg, def)), "death sound for %s" % id)
		assert_true(_exists(SoundRules.melee_hit_key(_cfg, id, def, false)), "melee hit for %s" % id)


func test_projectile_attacks_use_their_launch_sound() -> void:
	assert_eq(SoundRules.attack_key(_cfg, "archer", GameData.unit("archer")), "bow", "archer -> bow")
	assert_eq(SoundRules.attack_key(_cfg, "catapult", GameData.unit("catapult")), "catapult", "catapult -> catapult")
	assert_eq(SoundRules.attack_key(_cfg, "machine_gunner", GameData.unit("machine_gunner")), "machine_gun", "unit override wins")
	assert_eq(SoundRules.attack_key(_cfg, "swordsman", GameData.unit("swordsman")), "swing", "melee swings")
	assert_eq(SoundRules.attack_key(_cfg, "villager", GameData.unit("villager")), "", "silent attacker")


func test_every_building_has_a_selection_sound() -> void:
	for id in GameData.buildings:
		var key := SoundRules.building_key(_cfg, id)
		assert_true(_cfg.get("building_select", {}).has(id), "building_select lists %s" % id)
		assert_true(_exists(key), "selection sound '%s' for %s" % [key, id])


func test_event_sounds_exist() -> void:
	for key in ["ui_click", "ui_error", "notify", "age_up", "research_done", "unit_ready", "building_done", "under_attack", "victory", "defeat", "player_defeated", "tree_fall", "collapse"]:
		assert_true(_exists(key), "event sound %s" % key)
	for section in ["fx_sounds", "drop_sounds", "attack_by_projectile", "impact_by_projectile", "notify_sounds"]:
		var d: Dictionary = _cfg.get(section, {})
		for k in d:
			assert_true(_exists(String(d[k])), "%s.%s -> %s" % [section, k, d[k]])
	for anim in _cfg.get("work", {}):
		assert_true(_exists(String(_cfg["work"][anim]["sound"])), "work sound for %s" % anim)


func test_farming_uses_farm_sound_not_hammer() -> void:
	assert_eq(String(SoundRules.work_entry(_cfg, "build", true).get("sound", "")), "farm", "farmers hoe")
	assert_eq(String(SoundRules.work_entry(_cfg, "build", false).get("sound", "")), "build", "builders hammer")


func test_music_and_ambience_exist() -> void:
	var m: Dictionary = _cfg.get("music", {})
	assert_eq(m.get("by_age", []).size(), GameData.ages.size() + 1, "one playlist per age")
	for list in m.get("by_age", []) + [m.get("menu", []), m.get("battle", [])]:
		for name in list:
			assert_true(_exists(String(name)), "music track %s" % name)
	for key in _cfg.get("ambient", {}).get("loops", {}):
		assert_true(_exists(String(key)), "ambient loop %s" % key)
	for list in ["day_one_shots", "night_one_shots", "coast_one_shots"]:
		for entry in _cfg.get("ambient", {}).get(list, []):
			assert_true(_exists(String(entry[0])), "ambient one-shot %s" % entry[0])


func test_notify_key_reads_packed_message_template() -> void:
	assert_eq(SoundRules.notify_key(_cfg, "Not enough resources"), "ui_error", "plain text")
	assert_eq(SoundRules.notify_key(_cfg, Loc.msg("%s completed", ["House"])), "notify", "packed message falls back")

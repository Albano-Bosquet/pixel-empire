class_name SoundRules
extends RefCounted
## Pure lookups from game data to sound keys (audio_settings.json). Kept free
## of nodes so unit tests can check every unit and building resolves to a
## sound. `cfg` is GameData.audio.
## Example: SoundRules.attack_key(GameData.audio, "archer", GameData.unit("archer")) -> "bow"


## Matches the first [class, value] pair whose class the definition has.
static func _by_class(pairs: Array, classes: Array, fallback: String) -> String:
	for pair in pairs:
		if classes.has(pair[0]):
			return String(pair[1])
	return fallback


## Voice family of a unit ("villager", "cavalry", "ship"...): sel_<voice> / ack_<voice>.
static func voice(cfg: Dictionary, unit_id: String, unit_def: Dictionary) -> String:
	var direct: Dictionary = cfg.get("unit_voices", {})
	if direct.has(unit_id):
		return String(direct[unit_id])
	if unit_def.has("animal"):
		return ""
	return _by_class(cfg.get("voice_by_class", []), unit_def.get("classes", []), "infantry")


## Sound an animal makes when selected or idling ("" for non-animals).
static func animal_voice(cfg: Dictionary, unit_id: String) -> String:
	return String(cfg.get("animal_voices", {}).get(unit_id, ""))


## Sound of a unit starting an attack ("" = silent).
static func attack_key(cfg: Dictionary, unit_id: String, unit_def: Dictionary) -> String:
	if cfg.get("attack_silent", []).has(unit_id):
		return ""
	var by_unit: Dictionary = cfg.get("attack_by_unit", {})
	if by_unit.has(unit_id):
		return String(by_unit[unit_id])
	if unit_def.has("projectile"):
		return String(cfg.get("attack_by_projectile", {}).get(unit_def["projectile"], "bow"))
	return String(cfg.get("attack_melee", "swing"))


## Sound of a melee blow landing.
static func melee_hit_key(cfg: Dictionary, unit_id: String, unit_def: Dictionary, on_building: bool) -> String:
	var by_unit: Dictionary = cfg.get("melee_hit_by_unit", {})
	if by_unit.has(unit_id):
		return String(by_unit[unit_id])
	if on_building:
		return String(cfg.get("fx_sounds", {}).get("chips", "building_hit"))
	return _by_class(cfg.get("melee_hit_by_class", []), unit_def.get("classes", []), String(cfg.get("melee_hit_default", "hit_sword")))


## Sound of a projectile landing ("" = the default for its effect).
static func impact_key(cfg: Dictionary, projectile: String) -> String:
	return String(cfg.get("impact_by_projectile", {}).get(projectile, ""))


static func death_key(cfg: Dictionary, unit_def: Dictionary) -> String:
	return _by_class(cfg.get("death_by_class", []), unit_def.get("classes", []), String(cfg.get("death_default", "death")))


static func building_key(cfg: Dictionary, building_id: String) -> String:
	return String(cfg.get("building_select", {}).get(building_id, "bld_house"))


## Work-loop sound for an animation; returns {} when the animation is silent.
## Farmers play the "farm" (hoe) animation, whose entry is "farm"; `farming` also
## maps a "build" animation on a farm to it (saves made before the hoe existed).
static func work_entry(cfg: Dictionary, anim: String, farming: bool) -> Dictionary:
	var key := "farm" if farming and anim == "build" else anim
	return cfg.get("work", {}).get(key, {})


## Notification text (or Loc.msg template) -> sound key.
static func notify_key(cfg: Dictionary, text: String) -> String:
	var template := text.get_slice(Loc.SEP, 0)
	return String(cfg.get("notify_sounds", {}).get(template, "notify"))

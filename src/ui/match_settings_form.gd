class_name MatchSettingsForm
extends GridContainer
## Match options form (single-player setup and multiplayer lobby): map type and
## size, victory, starting resources and age, population limit, game speed,
## map visibility, wild animals, day/night cycle and seed. Reads/writes the MatchConfig
## settings dictionary; `editable` false shows the host's choice read-only.
## Option lists come from game_rules.json and map_generation.json.

signal changed(settings: Dictionary)

var _opts: Dictionary = {}     # key -> OptionButton
var _values: Dictionary = {}   # key -> Array of values in item order
var _seed: LineEdit
var _quiet := false


func _init() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 14)
	add_theme_constant_override("v_separation", 6)


func _ready() -> void:
	var rules: Dictionary = GameData.rules
	var d := MatchConfig.default_settings()
	var types: Array = rules.get("map_types_menu", ["continental"])
	var tdefs: Dictionary = GameData.map_gen.get("map_types", {})
	_add("map_type", tr("Map type"), types, types.map(func(t): return tr(String(tdefs.get(t, {}).get("display_name", String(t).capitalize())))), d)
	var sizes: Array = rules.get("map_sizes_menu", ["small"])
	var tiles: Dictionary = GameData.map_gen.get("sizes", {})
	_add("size", tr("Map size"), sizes, sizes.map(func(s): return "%s (%d×%d)" % [tr(String(s).capitalize()), int(tiles.get(s, 96)), int(tiles.get(s, 96))]), d)
	var vcs: Dictionary = rules.get("victory_conditions", {})
	_add("victory", tr("Victory"), vcs.keys(), vcs.keys().map(func(k): return tr(vcs[k]["display_name"])), d)
	var res: Dictionary = rules.get("starting_resources_menu", {})
	var res_names := {"low": "Low", "standard": "Standard", "medium": "Moderate", "high": "High", "very_high": "Very high", "deathmatch": "Deathmatch"}
	_add("resources", tr("Starting resources"), res.keys(), res.keys().map(func(k): return tr(String(res_names.get(k, String(k).capitalize())))), d)
	var ages := MatchConfig.age_names()
	var age_ids := []
	for i in ages.size():
		age_ids.append(i)
	_add("start_age", tr("Starting age"), age_ids, ages.map(func(a): return tr(a)), d)
	var pops: Array = rules.get("population_menu", [200]).map(func(p): return int(p))
	_add("population", tr("Population limit"), pops, pops.map(func(p): return str(p)), d)
	var speeds: Dictionary = rules.get("game_speed_menu", {"normal": 1.0})
	_add("speed", tr("Game speed"), speeds.keys(), speeds.keys().map(func(k): return "%s (×%s)" % [tr(String(k).capitalize().replace("_", " ")), str(speeds[k])]), d)
	var reveals: Array = rules.get("reveal_menu", ["normal"])
	var reveal_names := {"normal": "Fog of war", "explored": "Explored map", "visible": "All visible"}
	_add("reveal", tr("Map visibility"), reveals, reveals.map(func(r): return tr(reveal_names.get(r, r))), d)
	var animals: Dictionary = rules.get("wild_animals_menu", {"normal": 1.0})
	_add("animals", tr("Wild animals"), animals.keys(), animals.keys().map(func(k): return tr(String(k).capitalize())), d)
	_add("day_night", tr("Day and night"), [true, false], [tr("On"), tr("Off")], d)
	add_child(UiStyle.label(tr("Map seed"), 15, UiStyle.TEXT_DIM))
	_seed = LineEdit.new()
	_seed.placeholder_text = tr("random")
	_seed.custom_minimum_size = Vector2(240, 32)
	_seed.text_changed.connect(func(_t: String) -> void: _emit())
	add_child(_seed)


func _add(key: String, label: String, values: Array, names: Array, defaults: Dictionary) -> void:
	add_child(UiStyle.label(label, 15, UiStyle.TEXT_DIM))
	var o := UiStyle.option(names, maxi(0, values.find(defaults.get(key))))
	o.custom_minimum_size = Vector2(240, 32)
	o.item_selected.connect(func(_i: int) -> void: _emit())
	add_child(o)
	_opts[key] = o
	_values[key] = values


func _emit() -> void:
	if not _quiet:
		changed.emit(get_settings())


## The chosen settings (MatchConfig keys).
func get_settings() -> Dictionary:
	var out := {}
	for key in _opts:
		out[key] = _values[key][(_opts[key] as OptionButton).selected]
	var t := _seed.text.strip_edges()
	out["seed"] = 0 if t == "" else (int(t) if t.is_valid_int() else t.hash() & 0x7fffffff)
	return out


## Shows `settings` without emitting `changed` (lobby mirrors the host).
func set_settings(settings: Dictionary) -> void:
	_quiet = true
	for key in _opts:
		if settings.has(key):
			var i: int = _values[key].find(settings[key])
			if i >= 0:
				(_opts[key] as OptionButton).select(i)
	if settings.has("seed") and not _seed.has_focus():
		_seed.text = "" if int(settings["seed"]) == 0 else str(settings["seed"])
	_quiet = false


func set_editable(on: bool) -> void:
	for key in _opts:
		(_opts[key] as OptionButton).disabled = not on
	_seed.editable = on

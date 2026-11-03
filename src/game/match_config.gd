class_name MatchConfig
extends RefCounted
## Match setup shared by the single-player screen and the multiplayer lobby:
## turns the chosen settings and player slots into the config Game.start()
## reads, and resolves the options Game applies (starting stockpile, age,
## population limit, speed, map visibility, map size for many players).
## Data: game_rules.json (menus and presets), players_config.json.
##
## settings keys: map_type, size, victory, resources (preset id), start_age
## (int), population (int), speed (preset id), reveal ("normal" | "explored" |
## "visible"), animals (preset id, Gaia wildlife), day_night (bool), seed (int, 0 = random).
## player slot keys: name, ai (bool), difficulty, team (0 = none, 1..4).
## Example:
##   var cfg := MatchConfig.build(MatchConfig.default_settings(), [{"name": "Ana", "ai": false}, {"name": "CPU", "ai": true}])

## Settings a fresh setup screen shows.
static func default_settings() -> Dictionary:
	var rules: Dictionary = GameData.rules
	return {
		"map_type": GameData.map_gen.get("default_map_type", "continental"),
		"size": GameData.map_gen.get("default_size", "small"),
		"victory": rules.get("default_victory", "conquest"),
		"resources": rules.get("default_starting_resources", "standard"),
		"start_age": 0,
		"population": int(GameData.economy.get("max_population", 200)),
		"speed": rules.get("default_game_speed", "normal"),
		"reveal": "normal",
		"animals": rules.get("default_wild_animals", "normal"),
		"day_night": true,
		"seed": 0,
	}


## Builds the Game.start() config. `players[0]` is player 1.
static func build(settings: Dictionary, players: Array) -> Dictionary:
	var s := default_settings()
	s.merge(settings, true)
	var any_ai := players.any(func(p): return bool(p.get("ai", false)))
	var defs := []
	for p in players:
		defs.append({"name": String(p.get("name", "Player")), "ai": bool(p.get("ai", false)),
			"difficulty": String(p.get("difficulty", "normal")), "team": int(p.get("team", 0))})
	return {
		"mode": "skirmish" if any_ai or players.size() > 1 else "sandbox",
		"size": map_size_for(String(s["size"]), players.size()),
		"map_type": s["map_type"],
		"victory": s["victory"],
		"seed": int(s["seed"]),
		"fog": s["reveal"] != "visible",
		"reveal": s["reveal"],
		"resources": s["resources"],
		"start_age": int(s["start_age"]),
		"population": int(s["population"]),
		"speed": s["speed"],
		"animals": s["animals"],
		"day_night": bool(s["day_night"]),
		"players": defs,
	}


## Small maps grow to fit many players (game_rules.json min_map_size_by_players).
static func map_size_for(size: String, player_count: int) -> String:
	var order: Array = GameData.rules.get("map_sizes_menu", ["tiny", "small", "medium", "large", "huge"])
	var out := size
	for rule in GameData.rules.get("min_map_size_by_players", []):
		if player_count >= int(rule[0]) and order.find(out) < order.find(String(rule[1])):
			out = String(rule[1])
	return out


## Starting stockpile for a preset id (unknown ids use players_config.json).
static func starting_resources(preset: String) -> Dictionary:
	var menu: Dictionary = GameData.rules.get("starting_resources_menu", {})
	return menu.get(preset, GameData.players.get("starting_resources", {}))


## Engine.time_scale for a speed preset id.
static func speed_scale(preset: String) -> float:
	return float(GameData.rules.get("game_speed_menu", {}).get(preset, 1.0))


## Team of each player id (1-based) from a config's "players".
static func teams_of(cfg: Dictionary) -> Dictionary:
	var out := {}
	var defs: Array = cfg.get("players", [])
	for i in defs.size():
		out[i + 1] = int(defs[i].get("team", 0))
	return out


## Display names of the ages in order (index = age number), for menus.
static func age_names() -> Array:
	var names := ["Dark Age"]
	var by_age := {}
	for id in GameData.ages:
		by_age[int(GameData.ages[id].get("sets_age", 0))] = String(GameData.ages[id].get("display_name", id))
	var keys := by_age.keys()
	keys.sort()
	for k in keys:
		names.append(by_age[k])
	return names

extends "res://tests/test_case.gd"
## Match setup (MatchConfig) and alliances (CombatSystem.are_allies / is_enemy).


func _players(n_ai: int, teams: Array = []) -> Array:
	var out := [{"name": "Me", "ai": false, "team": teams[0] if not teams.is_empty() else 0}]
	for i in n_ai:
		out.append({"name": "CPU %d" % i, "ai": true, "difficulty": ["easy", "normal", "hard"][i % 3], "team": teams[i + 1] if teams.size() > i + 1 else 0})
	return out


func test_no_computer_players_makes_a_sandbox() -> void:
	var cfg := MatchConfig.build({}, _players(0))
	assert_eq(cfg["mode"], "sandbox", "alone = sandbox")
	assert_eq(MatchConfig.build({}, _players(2))["mode"], "skirmish", "with AIs = skirmish")


func test_each_ai_keeps_its_difficulty_and_team() -> void:
	var cfg := MatchConfig.build({}, _players(3, [1, 1, 2, 2]))
	assert_eq(cfg["players"].size(), 4, "four players")
	assert_eq(cfg["players"][1]["difficulty"], "easy", "first AI easy")
	assert_eq(cfg["players"][3]["difficulty"], "hard", "third AI hard")
	assert_eq(MatchConfig.teams_of(cfg), {1: 1, 2: 1, 3: 2, 4: 2}, "teams by player id")


func test_map_grows_for_many_players() -> void:
	assert_eq(MatchConfig.map_size_for("tiny", 2), "tiny", "2 players keep tiny")
	assert_eq(MatchConfig.map_size_for("tiny", 5), "small", "5 players need small")
	assert_eq(MatchConfig.map_size_for("small", 8), "medium", "8 players need medium")
	assert_eq(MatchConfig.map_size_for("huge", 8), "huge", "never shrinks")


func test_starting_resource_presets() -> void:
	var std := MatchConfig.starting_resources("standard")
	assert_eq(std, GameData.players["starting_resources"], "standard preset equals the default stockpile")
	var high := MatchConfig.starting_resources("high")
	assert_true(int(high["food"]) > int(std["food"]), "high gives more food")
	assert_eq(MatchConfig.starting_resources("unknown"), GameData.players["starting_resources"], "unknown preset falls back")


func test_speed_presets() -> void:
	assert_eq(MatchConfig.speed_scale("normal"), 1.0, "normal speed")
	assert_true(MatchConfig.speed_scale("fast") > 1.0, "fast is faster")


func test_age_names_cover_every_age() -> void:
	assert_eq(MatchConfig.age_names().size(), GameData.ages.size() + 1, "Dark Age plus each advance")


func test_eight_player_colours_and_slots() -> void:
	assert_eq(GameData.players["colors"].size(), 8, "eight team colours")
	assert_eq(int(GameData.rules.get("max_players", 0)), 8, "eight players allowed")


func test_allies_share_a_team_and_never_fight() -> void:
	CombatSystem.teams = {1: 1, 2: 1, 3: 2, 4: 0, 5: 0}
	assert_true(CombatSystem.are_allies(1, 2), "same team")
	assert_true(not CombatSystem.are_allies(1, 3), "different teams")
	assert_true(not CombatSystem.are_allies(4, 5), "team 0 means no allies")
	assert_true(CombatSystem.are_allies(4, 4), "a player is their own ally")
	var a := Entity.new()
	var b := Entity.new()
	a.owner_id = 1
	b.owner_id = 2
	assert_true(not CombatSystem.is_enemy(a, b), "allied entities are not enemies")
	b.owner_id = 3
	assert_true(CombatSystem.is_enemy(a, b), "rival team entities are enemies")
	assert_true(not CombatSystem.hurts(1, a), "own splash never hurts")
	assert_true(CombatSystem.hurts(1, b), "splash hurts enemies")
	a.free()
	b.free()
	CombatSystem.teams = {}

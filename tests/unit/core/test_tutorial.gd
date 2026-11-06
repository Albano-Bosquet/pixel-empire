extends "res://tests/test_case.gd"
## Rules of the guided match (TutorialSystem) and the integrity of its data:
## a step that names something that does not exist would leave the arrow dead.

const POINTS := ["villager", "scout", "soldiers", "town_center", "barracks", "food", "wood", "gold", "stone", "camp"]


func test_step_finishes_when_any_alternative_is_complete() -> void:
	var step := {"done": [{"a": 2, "b": 1}, {"c": 1}]}
	assert_true(not TutorialSystem.is_done(step, {"a": 2}), "half an alternative is not enough")
	assert_true(TutorialSystem.is_done(step, {"a": 2, "b": 1}), "first alternative")
	assert_true(TutorialSystem.is_done(step, {"c": 1}), "second alternative")


func test_step_without_goals_never_finishes_by_itself() -> void:
	assert_true(not TutorialSystem.is_done({"done": []}, {"a": 1}), "only victory ends the last step")
	assert_true(not TutorialSystem.is_done({}, {}), "missing goal")


func test_progress_shows_goals_that_count_several_things() -> void:
	var step := {"done": [{"unit_militia": 5}]}
	assert_eq(TutorialSystem.progress(step, {"unit_militia": 3}), [3, 5], "count")
	assert_eq(TutorialSystem.progress(step, {"unit_militia": 9}), [5, 5], "capped at the goal")
	assert_eq(TutorialSystem.progress({"done": [{"camp_seen": 1}]}, {}), [], "yes/no goals show no count")


func test_touch_text_falls_back_to_the_common_text() -> void:
	assert_eq(TutorialSystem.step_text({"text": "a", "text_touch": "b"}, true), "b", "touch text")
	assert_eq(TutorialSystem.step_text({"text": "a", "text_touch": "b"}, false), "a", "mouse text")
	assert_eq(TutorialSystem.step_text({"text": "a"}, true), "a", "no touch variant")


func test_match_config_is_a_two_sided_tutorial_without_ai() -> void:
	var cfg := MatchConfig.tutorial()
	assert_true(cfg.get("tutorial", false), "flag")
	assert_eq(cfg["players"].size(), 2, "player and bandits")
	assert_true(cfg["players"].all(func(p): return not p["ai"]), "nobody drives the camp")
	assert_eq(cfg["mode"], "skirmish", "the victory rules of a normal match apply")


func test_steps_refer_to_things_that_exist() -> void:
	var seen := {}
	var steps: Array = GameData.tutorial["steps"]
	for i in steps.size():
		var s: Dictionary = steps[i]
		assert_true(not seen.has(s["id"]), "unique id %s" % s["id"])
		seen[s["id"]] = true
		assert_true(s.get("title", "") != "" and s.get("text", "") != "", "%s has text" % s["id"])
		assert_true(not s["done"].is_empty() or i == steps.size() - 1, "only the last step has no goal (%s)" % s["id"])
		for p in s.get("point", []):
			assert_true(POINTS.has(p), "%s points at a known target (%s)" % [s["id"], p])
		var b: String = s.get("button", "")
		if b != "":
			assert_true(GameData.units.has(b) or GameData.buildings.has(b) or GameData.ages.has(b) or GameData.techs.has(b), "%s names a real button (%s)" % [s["id"], b])
		for k in s.get("ensure", {}):
			assert_true(PlayerState.RESOURCE_KEYS.has(k), "%s tops up a resource (%s)" % [s["id"], k])


## The supplies of each step must pay for what it asks: the player can never be
## left waiting on an empty stockpile with nothing explained.
func test_steps_hand_out_what_they_ask_for() -> void:
	for s in GameData.tutorial["steps"]:
		var b: String = s.get("button", "")
		if b == "" or s["id"] == "feudal_reached":
			continue
		var cost: Dictionary = {}
		var n := 1
		if GameData.units.has(b):
			cost = GameData.unit(b)["cost"]
			for option in s["done"]:
				for key in option:
					if key == "unit_" + b and b != "villager":
						n = int(option[key])
		elif GameData.buildings.has(b):
			cost = GameData.building(b)["cost"]
		elif GameData.ages.has(b):
			cost = GameData.ages[b]["cost"]
		else:
			cost = GameData.techs[b]["cost"]
		for k in cost:
			assert_true(int(s.get("ensure", {}).get(k, 0)) >= int(cost[k]) * n, "%s pays %d %s" % [s["id"], int(cost[k]) * n, k])


func test_camp_can_be_placed_and_can_fall() -> void:
	var ignored: Array = GameData.rules["conquest_ignored_buildings"]
	var camp: Dictionary = GameData.tutorial["camp"]
	var keeps_alive := 0
	for e in camp["buildings"]:
		assert_true(GameData.buildings.has(e["type"]), "camp building %s" % e["type"])
		if not ignored.has(e["type"]):
			keeps_alive += 1
	assert_eq(keeps_alive, 1, "one building to destroy, as the last step says")
	for id in camp["units"]:
		assert_true(GameData.units.has(id), "camp unit %s" % id)

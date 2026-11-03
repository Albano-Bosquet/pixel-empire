extends "res://tests/test_case.gd"
## Technologies (design/game-brief.md MVP item 5): effect stacking and
## research prerequisites.


func _player() -> PlayerState:
	return PlayerState.new(1, "T", 0, false, {"food": 5000, "wood": 5000, "gold": 5000, "stone": 5000})


func test_add_effects_stack() -> void:
	var p := _player()
	TechSystem.apply_effects(p, GameData.techs["forging"]["effects"])
	TechSystem.apply_effects(p, GameData.techs["iron_casting"]["effects"])
	assert_near(TechSystem.add_mod(p, "attack_add:infantry"), 2.0, 0.001, "two blacksmith attack techs stack additively")


func test_mul_effects_compound() -> void:
	var p := _player()
	TechSystem.apply_effects(p, GameData.techs["double_bit_axe"]["effects"])
	TechSystem.apply_effects(p, GameData.techs["bow_saw"]["effects"])
	assert_near(p.modifier("gather_wood"), 1.44, 0.001, "1.2 x 1.2 wood gathering")


func test_age_and_prerequisite_gating() -> void:
	var p := _player()
	assert_true(TechSystem.research_error(p, "forging").begins_with("Requires"), "Forging needs the Feudal Age")
	p.age = 2
	assert_true(TechSystem.research_error(p, "iron_casting") == Loc.msg("Requires %s", ["Forging"]), "Iron Casting needs Forging")
	p.researched["forging"] = true
	assert_eq(TechSystem.research_error(p, "iron_casting"), "", "available once Forging is done")
	assert_eq(TechSystem.research_error(p, "forging"), "Already researched", "no double research")


func test_every_tech_is_researchable_somewhere() -> void:
	for id in GameData.techs:
		var b: String = GameData.techs[id]["building"]
		assert_true(GameData.building(b).get("researches", []).has(id), "%s listed at %s" % [id, b])
		for e in GameData.techs[id]["effects"]:
			assert_true(e["op"] in ["add", "mul"], "%s effect op valid" % id)


func test_no_tech_hotkey_steals_camera_keys() -> void:
	for id in GameData.techs:
		assert_true(not GameData.techs[id]["hotkey"] in ["W", "A", "S", "D"], "%s hotkey avoids WASD" % id)


func test_no_unit_hotkey_steals_camera_keys() -> void:
	for id in GameData.units:
		var hk: String = GameData.unit(id).get("hotkey", "")
		assert_true(not hk in ["W", "A", "S", "D"], "%s hotkey avoids WASD" % id)

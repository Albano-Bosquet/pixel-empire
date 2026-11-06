extends "res://tests/test_case.gd"
## Regressions from player reports before release 1.8: repaired buildings kept
## burning, and the easy AI was not easy.


func test_repair_above_the_burn_threshold_puts_the_fire_out() -> void:
	var b := Building.new()
	b.setup("house", GameData.building("house"), 1, 0, Vector2i(3, 3), true)
	b.take_damage(int(b.max_hp * 0.8), null)
	assert_true(b.is_burning(), "a badly damaged building burns")
	b.heal(b.max_hp)
	assert_eq(b.hp, b.max_hp, "repaired to full")
	assert_true(not b.is_burning(), "the fire goes out")
	b.free()


func test_partial_repair_keeps_burning_below_the_threshold() -> void:
	var b := Building.new()
	b.setup("house", GameData.building("house"), 1, 0, Vector2i(3, 3), true)
	b.take_damage(int(b.max_hp * 0.8), null)
	b.heal(1)
	assert_true(b.is_burning(), "still under the threshold")
	b.free()


func test_easy_ai_is_weaker_than_normal_on_every_axis() -> void:
	var easy: Dictionary = GameData.ai["difficulties"]["easy"]
	var normal: Dictionary = GameData.ai["difficulties"]["normal"]
	for key in ["gather_multiplier", "villager_target", "max_army", "max_techs", "reaction_radius"]:
		assert_true(float(easy[key]) < float(normal[key]), "easy has less %s" % key)
	for key in ["first_attack_minute", "wave_interval_seconds"]:
		assert_true(float(easy[key]) > float(normal[key]), "easy has more %s" % key)


func test_easy_ai_only_trains_units_of_its_own_age() -> void:
	var easy: Dictionary = GameData.ai["difficulties"]["easy"]
	for id in easy["army_mix"]:
		assert_eq(int(GameData.unit(id)["age"]), 0, "%s needs no age up" % id)

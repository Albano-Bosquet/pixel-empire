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


func test_every_difficulty_trains_the_same_units() -> void:
	var diffs: Dictionary = GameData.ai["difficulties"]
	for d in diffs:
		assert_eq(diffs[d]["army_mix"].size(), diffs["hard"]["army_mix"].size(), "%s army" % d)
		for id in diffs["hard"]["army_mix"]:
			assert_true(diffs[d]["army_mix"].has(id), "%s trains %s" % [d, id])
		assert_eq(diffs[d]["fleet_mix"].size(), diffs["hard"]["fleet_mix"].size(), "%s fleet" % d)


func test_easier_ai_reaches_every_age_later() -> void:
	var diffs: Dictionary = GameData.ai["difficulties"]
	for i in diffs["easy"]["age_up_minutes"].size():
		assert_true(float(diffs["hard"]["age_up_minutes"][i]) < float(diffs["normal"]["age_up_minutes"][i]), "hard before normal, age %d" % (i + 1))
		assert_true(float(diffs["normal"]["age_up_minutes"][i]) < float(diffs["easy"]["age_up_minutes"][i]), "normal before easy, age %d" % (i + 1))


func test_hunt_sweep_covers_the_whole_map() -> void:
	var spacing := 12
	var points := AIPlayer.sweep_points(96, 96, spacing)
	assert_eq(points.size(), 64, "8 x 8 waypoints on a 96 tile map")
	for corner in [Vector2(0, 0), Vector2(95, 0), Vector2(0, 95), Vector2(95, 95)]:
		var near: Vector2 = points[AIPlayer.closest_index(points, corner)]
		assert_true(near.distance_to(corner) <= spacing, "corner %s is covered" % corner)


func test_hunt_goes_to_the_closest_waypoint_first() -> void:
	var points: Array[Vector2] = [Vector2(50, 50), Vector2(10, 10), Vector2(30, 30)]
	assert_eq(AIPlayer.closest_index(points, Vector2(12, 12)), 1, "closest waypoint")
	var none: Array[Vector2] = []
	assert_eq(AIPlayer.closest_index(none, Vector2.ZERO), -1, "no waypoints")


func test_ai_waits_for_the_minute_of_its_next_age() -> void:
	var ai := AIPlayer.new()
	ai.player = PlayerState.new(1, "AI", 0, true, {})
	ai.diff = {"age_up_villagers": [2], "age_up_minutes": [10]}
	ai._villagers.resize(2)
	ai.elapsed = 599.0
	assert_true(not ai._ready_for_age(), "too early")
	ai.elapsed = 600.0
	assert_true(ai._ready_for_age(), "minute reached")
	ai._villagers.resize(1)
	assert_true(not ai._ready_for_age(), "minute reached but few villagers")
	ai.free()


func test_wood_waits_for_the_first_barracks() -> void:
	assert_true(AIPlayer.wood_goes_to_barracks(0, 3, 9, 9, false, false), "no military building yet: wood is saved")


func test_wood_is_free_once_a_military_building_exists() -> void:
	assert_true(not AIPlayer.wood_goes_to_barracks(1, 3, 20, 9, false, false), "the first one is placed: ships may be built")


func test_wood_is_not_saved_before_the_economy_can_afford_it() -> void:
	assert_true(not AIPlayer.wood_goes_to_barracks(0, 3, 8, 9, false, false), "too few villagers to think about an army")


func test_an_island_start_still_builds_its_dock_first() -> void:
	assert_true(not AIPlayer.wood_goes_to_barracks(0, 3, 12, 9, true, false), "without a dock the enemy cannot be reached")


func test_wood_is_released_when_the_barracks_is_already_affordable() -> void:
	assert_true(not AIPlayer.wood_goes_to_barracks(0, 3, 12, 9, false, true), "no spot for the building must not stall the rest")


func test_an_ai_that_wants_no_military_saves_nothing() -> void:
	assert_true(not AIPlayer.wood_goes_to_barracks(0, 0, 12, 9, false, false), "nothing to save for")

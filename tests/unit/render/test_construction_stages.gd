extends "res://tests/test_case.gd"
## Construction stage selection (Building.stage_at; render_sprites.json "construction").


func test_stage_at_start_shows_bare_site() -> void:
	var st := Building.stage_at(0.0, 8, 0.55)
	assert_eq(st["index"], 0, "no stage sprite at 0% progress")
	assert_near(st["fade"], 0.0, 0.0001, "nothing fading in at 0%")


func test_stage_at_mid_stage_holds_without_fade() -> void:
	var st := Building.stage_at(0.3125, 8, 0.55)  # 2.5 stages
	assert_eq(st["index"], 2, "third interval shows stage 2")
	assert_near(st["fade"], 0.0, 0.0001, "before fade_start the next stage is hidden")


func test_stage_at_late_in_stage_fades_next() -> void:
	var st := Building.stage_at(0.37, 8, 0.55)  # 2.96 stages
	assert_eq(st["index"], 2, "still stage 2")
	assert_true(st["fade"] > 0.9, "next stage almost fully faded in near the boundary")


func test_first_work_never_shows_the_finished_building() -> void:
	# Regression: FOUNDATION -> CONSTRUCTING made the body visible while it still
	# held the finished sprite, so it flashed until stage 1 was reached.
	var b := Building.new()
	b.setup("house", GameData.building("house"), 1, 0, Vector2i(4, 4), false)
	b.add_progress(0.01)
	assert_eq(b.state, Building.State.CONSTRUCTING, "the first work starts construction")
	assert_true(not b._body.visible, "only the bare site shows before stage 1")
	b.add_progress(0.2)
	assert_true(b._body.visible, "stage sprites show once stage 1 is reached")
	b.free()


func test_stage_at_full_progress_is_last_stage_without_fade() -> void:
	var st := Building.stage_at(1.0, 8, 0.55)
	assert_eq(st["index"], 8, "last stage at 100%")
	assert_near(st["fade"], 0.0, 0.0001, "no stage beyond the last")

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


func test_stage_at_full_progress_is_last_stage_without_fade() -> void:
	var st := Building.stage_at(1.0, 8, 0.55)
	assert_eq(st["index"], 8, "last stage at 100%")
	assert_near(st["fade"], 0.0, 0.0001, "no stage beyond the last")

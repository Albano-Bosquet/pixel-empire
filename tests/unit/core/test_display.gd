extends "res://tests/test_case.gd"
## Interface scale for phones and tablets (Display.scale_for).

const DisplayScript := preload("res://src/core/display_settings.gd")


func test_phone_screen_scales_to_target_height() -> void:
	assert_eq(DisplayScript.scale_for(1080, 640, 3.0), 1080.0 / 640.0, "1080p phone shows 640 logical lines")
	assert_eq(DisplayScript.scale_for(1440, 640, 3.0), 2.25, "1440p phone")


func test_scale_never_shrinks_pc_layouts() -> void:
	assert_eq(DisplayScript.scale_for(480, 640, 3.0), 1.0, "small screens keep native pixels")


func test_scale_is_capped() -> void:
	assert_eq(DisplayScript.scale_for(4000, 640, 3.0), 3.0, "huge tablets stop at max_ui_scale")
	assert_eq(DisplayScript.scale_for(1080, 0, 3.0), 1.0, "a missing target means no scaling")

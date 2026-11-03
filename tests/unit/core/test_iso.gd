extends "res://tests/test_case.gd"
## Iso projection math (architecture.md §4).


func test_round_trip() -> void:
	for g in [Vector2(0, 0), Vector2(10.5, 3.25), Vector2(95.9, 0.1), Vector2(-2, 7)]:
		var back := Iso.world_to_grid(Iso.grid_to_world(g))
		assert_near(back.x, g.x, 0.0001, "round trip x for %s" % g)
		assert_near(back.y, g.y, 0.0001, "round trip y for %s" % g)


func test_tile_centre_projection() -> void:
	assert_eq(Iso.grid_to_world(Vector2(1, 0)), Vector2(32, 16), "+x grid goes right-down")
	assert_eq(Iso.grid_to_world(Vector2(0, 1)), Vector2(-32, 16), "+y grid goes left-down")


func test_direction_index() -> void:
	assert_eq(Iso.direction_index(Vector2(1, 1)), 0, "grid (+1,+1) faces screen south")
	assert_eq(Iso.direction_index(Vector2(1, -1)), 4, "grid (+1,-1) faces screen east")
	assert_eq(Iso.direction_index(Vector2(-1, -1)), 8, "grid (-1,-1) faces screen north")
	assert_eq(Iso.direction_index(Vector2(-1, 1)), 12, "grid (-1,+1) faces screen west")


func test_direction_index_in_between_steps() -> void:
	# Grid +x is 63.4 degrees from screen-down on the 2:1 diamond, so step 3 (67.5).
	assert_eq(Iso.direction_index(Vector2(1, 0)), 3, "grid +x faces screen east-south-east")
	assert_eq(Iso.direction_index(Vector2(0, -1)), 5, "grid -y faces screen east-north-east")


func test_sheet_direction_mirrors_west() -> void:
	assert_eq(Iso.sheet_direction(12), Vector2i(4, 1), "W uses E row flipped")
	assert_eq(Iso.sheet_direction(10), Vector2i(6, 1), "NW uses NE row flipped")
	assert_eq(Iso.sheet_direction(3), Vector2i(3, 0), "in-between SE row not flipped")
	assert_eq(Iso.sheet_direction(8), Vector2i(8, 0), "N not flipped")


func test_direction_delta_takes_shortest_turn() -> void:
	assert_eq(Iso.direction_delta(1, 15), -2, "wraps through south")
	assert_eq(Iso.direction_delta(14, 2), 4, "wraps forward")
	assert_eq(Iso.direction_delta(5, 5), 0, "no turn")

extends "res://tests/test_case.gd"
## Walls and gates (Phase B4): owner-only gate passability, wall line tiles.


## 12x5 map split by a solid column at x = 6 with a single gate at (6, 2).
func _walled() -> Pathfinder:
	var m := MapData.new(12, 5, 1)
	for y in 5:
		if y != 2:
			m.set_blocked(Vector2i(6, y), true)
	var pf := Pathfinder.new(m)
	pf.set_gate(Vector2i(6, 2), 1)
	return pf


func test_gate_owner_walks_through() -> void:
	var path := _walled().find_path(Vector2(2.5, 2.5), Vector2(10.5, 2.5), 1)
	assert_true(not path.is_empty(), "owner finds a path")
	assert_near(path[path.size() - 1].x, 10.5, 0.01, "owner reaches the far side")


func test_gate_blocks_other_players() -> void:
	var path := _walled().find_path(Vector2(2.5, 2.5), Vector2(10.5, 2.5), 2)
	var crossed := false
	for p in path:
		if p.x > 6.0:
			crossed = true
	assert_true(not crossed, "enemy never gets past the gate")
	assert_true(not _walled().is_walkable(Vector2i(6, 2), 2), "gate tile is solid for the enemy")
	assert_true(_walled().is_walkable(Vector2i(6, 2), 1), "gate tile is open for its owner")


func test_gate_closing_is_temporary() -> void:
	var pf := _walled()
	pf.find_path(Vector2(2.5, 2.5), Vector2(10.5, 2.5), 2)
	assert_true(pf.is_walkable(Vector2i(6, 2)), "shared grid keeps the gate open after an enemy search")


func test_wall_line_is_eight_connected() -> void:
	var line := PlacementController.line_tiles(Vector2i(0, 0), Vector2i(4, 2))
	assert_eq(line[0], Vector2i(0, 0), "starts at the press tile")
	assert_eq(line[line.size() - 1], Vector2i(4, 2), "ends at the release tile")
	assert_eq(line.size(), 5, "max(|dx|, |dy|) + 1 pieces")
	for i in range(1, line.size()):
		var d := line[i] - line[i - 1]
		assert_true(maxi(absi(d.x), absi(d.y)) == 1, "step %d touches the previous piece" % i)


func test_wall_line_pure_diagonal() -> void:
	var line := PlacementController.line_tiles(Vector2i(5, 5), Vector2i(2, 8))
	assert_eq(line.size(), 4, "one piece per diagonal step")
	for i in line.size():
		assert_eq(line[i], Vector2i(5 - i, 5 + i), "piece %d on the diagonal" % i)


func test_diagonal_wall_blocks_paths() -> void:
	# Diagonal wall from (0, 4) to (4, 0): nothing may slip through its corners.
	var m := MapData.new(8, 8, 1)
	for t in PlacementController.line_tiles(Vector2i(0, 4), Vector2i(4, 0)):
		m.set_blocked(t, true)
	var pf := Pathfinder.new(m)
	var path := pf.find_path(Vector2(0.5, 0.5), Vector2(6.5, 6.5), 1)
	assert_true(path.is_empty() or path[path.size() - 1].distance_to(Vector2(6.5, 6.5)) > 1.0, "the corner gaps are closed")

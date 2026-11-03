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


func test_wall_line_is_four_connected() -> void:
	var line := PlacementController.line_tiles(Vector2i(0, 0), Vector2i(4, 2))
	assert_eq(line[0], Vector2i(0, 0), "starts at the press tile")
	assert_eq(line[line.size() - 1], Vector2i(4, 2), "ends at the release tile")
	assert_eq(line.size(), 7, "|dx| + |dy| + 1 pieces")
	for i in range(1, line.size()):
		var d := line[i] - line[i - 1]
		assert_eq(absi(d.x) + absi(d.y), 1, "step %d is orthogonal" % i)

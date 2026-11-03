extends "res://tests/test_case.gd"
## Map generator + pathfinder (game-brief MVP item 1).


func _gen(size: int, seed: int, players: int) -> MapData:
	return MapGenerator.new(GameData.map_gen, GameData.resource_nodes).generate(size, seed, players)


func test_deterministic() -> void:
	var a := _gen(64, 777, 2)
	var b := _gen(64, 777, 2)
	assert_eq(a.terrain, b.terrain, "same seed gives same terrain")
	assert_eq(a.resource_spawns.size(), b.resource_spawns.size(), "same seed gives same resources")
	var c := _gen(64, 778, 2)
	assert_true(a.terrain != c.terrain, "different seed gives different terrain")


func test_sizes_from_config() -> void:
	for name in ["tiny", "small", "medium"]:
		var size: int = GameData.map_gen["sizes"][name]
		var m := _gen(size, 5, 2)
		assert_eq(m.width, size, "map width for " + name)
		assert_eq(m.terrain.size(), size * size, "terrain array size for " + name)


func test_terrain_variety() -> void:
	var m := _gen(96, 4242, 2)
	var seen := {}
	for t in m.terrain:
		seen[t] = true
	assert_true(seen.size() >= 6, "at least 6 terrain types present (got %d)" % seen.size())


func test_starts_connected_and_clear() -> void:
	for seed in [1, 2, 3, 4, 5, 99, 4242]:
		var m := _gen(96, seed, 2)
		assert_eq(m.start_positions.size(), 2, "two start positions (seed %d)" % seed)
		var reached := PackedByteArray()
		var count := m.flood_fill(m.start_positions[0], reached)
		assert_true(count > 500, "start area is not enclosed (seed %d, %d tiles)" % [seed, count])
		assert_eq(reached[m.index(m.start_positions[1])], 1, "start 2 reachable from start 1 (seed %d)" % seed)
		for s in m.start_positions:
			assert_true(m.walkable(s), "start tile walkable (seed %d)" % seed)


func test_player_resources_near_starts() -> void:
	var m := _gen(96, 31, 2)
	for s in m.start_positions:
		var found := {}
		for r in m.resource_spawns:
			if Vector2(r["tile"]).distance_to(Vector2(s)) <= 13.0:
				found[r["type"]] = true
		for type in ["gold_mine", "stone_mine", "berry_bush"]:
			assert_true(found.has(type), "%s near start %s" % [type, s])


func test_pathfinder_path_and_blocking() -> void:
	var m := _gen(64, 11, 2)
	var pf := Pathfinder.new(m)
	var a := Iso.tile_center(m.start_positions[0])
	var b := Iso.tile_center(m.start_positions[1])
	var path := pf.find_path(a, b)
	assert_true(not path.is_empty(), "path between starts exists")
	assert_true(path[path.size() - 1].distance_to(b) < 0.01, "path ends at the target")
	var prev := a
	for p in path:
		assert_true(pf.line_walkable(prev, p, 0.0), "smoothed segment is walkable")
		prev = p
	# Blocking a tile updates the pathfinder.
	var t := m.start_positions[0] + Vector2i(2, 0)
	m.set_blocked(t, true)
	pf.refresh_tile(t)
	assert_true(not pf.is_walkable(t), "blocked tile not walkable")
	var near := pf.nearest_walkable(t)
	assert_true(near != t and pf.is_walkable(near), "nearest walkable avoids blocked tile")

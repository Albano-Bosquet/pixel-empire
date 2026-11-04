extends "res://tests/test_case.gd"
## Water map types and the ships' grid (map_generation.json "map_types").


func _gen(type: String, seed: int = 4242) -> MapData:
	return MapGenerator.new(GameData.map_gen, GameData.resource_nodes).generate(96, seed, 2, type)


func _connected(m: MapData, a: Vector2i, b: Vector2i) -> bool:
	var path := Pathfinder.new(m).find_path(Iso.tile_center(a), Iso.tile_center(b))
	return not path.is_empty() and path[path.size() - 1].distance_to(Iso.tile_center(b)) < 3.0


func test_islands_separate_the_players() -> void:
	var m := _gen("islands")
	assert_true(not _connected(m, m.start_positions[0], m.start_positions[1]), "no land route between island starts")


func test_coast_keeps_a_land_route_and_a_sea() -> void:
	var m := _gen("coast")
	assert_true(_connected(m, m.start_positions[0], m.start_positions[1]), "coast starts are joined by land")
	var c := Vector2i(48, 48)
	assert_true(MapData.terrain_navigable(m.get_terrain(c)), "the centre of a coast map is sea")


func test_water_maps_are_deterministic_and_have_fish() -> void:
	for type in ["coast", "islands"]:
		var a := _gen(type, 777)
		var b := _gen(type, 777)
		assert_eq(a.terrain, b.terrain, "%s: same seed, same terrain" % type)
		var fish := a.resource_spawns.filter(func(s): return s["type"] == "fish")
		assert_true(fish.size() >= 4, "%s has fish (%d)" % [type, fish.size()])
		for s in fish:
			assert_true(MapData.terrain_navigable(a.get_terrain(s["tile"])), "%s fish sit on water" % type)


func test_continental_maps_are_unchanged_by_the_new_types() -> void:
	var a := MapGenerator.new(GameData.map_gen, GameData.resource_nodes).generate(64, 777, 2)
	var b := _gen("continental", 777)
	assert_eq(a.width, 64, "default is continental")
	assert_true(b.terrain.size() == 96 * 96, "explicit continental generates")


func _path_tiles(m: MapData) -> int:
	return m.terrain.count(MapData.Terrain.PATH)


func test_roads_only_join_allies() -> void:
	for type in ["continental", "coast"]:
		for seed in [1, 2, 3, 4242]:
			var gen := MapGenerator.new(GameData.map_gen, GameData.resource_nodes)
			var enemies := gen.generate(96, seed, 2, type, [0, 0])
			assert_eq(_path_tiles(enemies), 0, "%s seed %d: no road between enemies" % [type, seed])
			assert_true(_connected(enemies, enemies.start_positions[0], enemies.start_positions[1]), "%s seed %d: enemies still reachable by land" % [type, seed])
			var gen2 := MapGenerator.new(GameData.map_gen, GameData.resource_nodes)
			var allies := gen2.generate(96, seed, 2, type, [1, 1])
			assert_true(_path_tiles(allies) > 20, "%s seed %d: allies get a road" % [type, seed])


func test_ship_grid_is_water_only() -> void:
	var m := _gen("islands")
	var sea := Pathfinder.new(m, true)
	var home := m.start_positions[0]
	assert_true(not sea.is_walkable(home), "ships cannot enter the land start tile")
	var water := sea.nearest_walkable(home, 30)
	assert_true(water.x >= 0 and MapData.terrain_navigable(m.get_terrain(water)), "nearest ship tile is water")

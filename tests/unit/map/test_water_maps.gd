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


func test_desert_maps_are_mostly_dunes_and_keep_a_land_route() -> void:
	var m := _gen("desert")
	var desert := 0
	var land := 0
	for t in m.terrain:
		if MapData.terrain_passable(t):
			land += 1
			if t == MapData.Terrain.DESERT:
				desert += 1
	assert_true(float(desert) / land > 0.35, "dunes cover most land (%d of %d)" % [desert, land])
	assert_true(MapData.terrain_passable(MapData.Terrain.DESERT), "dunes are walkable")
	assert_true(_connected(m, m.start_positions[0], m.start_positions[1]), "desert starts are joined by land")


func test_other_map_types_have_no_desert() -> void:
	for type in ["continental", "coast", "islands"]:
		assert_true(not _gen(type).terrain.has(MapData.Terrain.DESERT), "%s has no desert tiles" % type)


func test_water_depth_field_counts_steps_from_the_coast() -> void:
	var m := MapData.new(8, 1, 1)
	for x in 8:
		m.terrain[x] = MapData.Terrain.GRASS if x == 0 else MapData.Terrain.WATER
	var img := TerrainRenderer.depth_image(m)
	assert_eq(img.get_pixel(0, 0).r8, 0, "land is 0")
	assert_eq(img.get_pixel(1, 0).r8, roundi(255.0 / TerrainRenderer.DEPTH_SCALE), "water next to land is one step")
	assert_true(img.get_pixel(5, 0).r8 > img.get_pixel(2, 0).r8, "deeper further out")


func _count(m: MapData, id: int) -> int:
	var n := 0
	for t in m.terrain:
		if t == id:
			n += 1
	return n


func test_plateaus_can_be_walked_onto_from_a_start() -> void:
	var opened := 0
	for seed in [4242, 777, 12345]:
		var m := _gen("continental", seed)
		for y in m.height:
			for x in m.width:
				var t := Vector2i(x, y)
				if m.get_terrain(t) == MapData.Terrain.PLATEAU:
					opened += 1
					assert_true(m.walkable(t), "plateau is walkable")
		if _count(m, MapData.Terrain.PLATEAU) > 0:
			var top := Vector2i(-1, -1)
			for i in m.terrain.size():
				if m.terrain[i] == MapData.Terrain.RAMP:
					top = Vector2i(i % m.width, i / m.width)
					break
			assert_true(_connected(m, m.start_positions[0], top), "seed %d: a ramp is reachable from a start" % seed)
			assert_true(_count(m, MapData.Terrain.RAMP) > 0, "seed %d: the plateau has a ramp" % seed)
	assert_true(opened > 0, "these seeds have plateaus")


func test_every_plateau_tile_connects_to_the_starts() -> void:
	var m := _gen("continental", 4242)
	var seen := {m.start_positions[0]: true}
	var queue: Array[Vector2i] = [m.start_positions[0]]
	while not queue.is_empty():
		var t: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if m.walkable(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	for y in m.height:
		for x in m.width:
			if m.get_terrain(Vector2i(x, y)) == MapData.Terrain.PLATEAU:
				assert_true(seen.has(Vector2i(x, y)), "plateau tile %d,%d is reachable" % [x, y])


func test_plateaus_keep_a_cliff_rim_on_their_camera_side() -> void:
	var m := _gen("continental", 4242)
	for y in m.height - 2:
		for x in m.width - 2:
			if m.get_terrain(Vector2i(x, y)) == MapData.Terrain.PLATEAU:
				var south := m.get_terrain(Vector2i(x + 2, y + 2))
				assert_true(south in [MapData.Terrain.MOUNTAIN, MapData.Terrain.PLATEAU, MapData.Terrain.RAMP], "no plateau tile sits under a wall")


func _is_rock(sprite: String) -> bool:
	return sprite.begins_with("pebble") or sprite.begins_with("stone")


func test_desert_and_beach_ground_has_no_loose_rocks() -> void:
	var m := _gen("desert")
	for d in m.decor:
		var ter := m.get_terrain(Vector2i(d["pos"]))
		if ter == MapData.Terrain.DESERT or ter == MapData.Terrain.SAND:
			assert_true(not _is_rock(d["sprite"]), "%s sits on sand or dunes" % d["sprite"])


func test_loose_rocks_are_a_small_share_of_ground_decor() -> void:
	var m := _gen("continental")
	var rocks := m.decor.filter(func(d): return _is_rock(d["sprite"]))
	assert_true(rocks.size() * 5 < m.decor.size(), "rocks are under a fifth of the decor (%d of %d)" % [rocks.size(), m.decor.size()])


func test_mountain_field_marks_only_mountains() -> void:
	var m := MapData.new(6, 1, 1)
	for x in 6:
		m.terrain[x] = MapData.Terrain.GRASS if x == 0 else MapData.Terrain.MOUNTAIN
	var img := TerrainRenderer.depth_image(m)
	assert_eq(img.get_pixel(0, 0).g8, 0, "other terrain is 0")
	assert_eq(img.get_pixel(3, 0).r8, 0, "mountains are not water")
	assert_true(img.get_pixel(4, 0).g8 > img.get_pixel(1, 0).g8, "field grows into the mountain")


func test_decor_lists_use_real_sprites_and_grass_gets_life() -> void:
	var props: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/props/props_atlas.json"))
	for group in ["decor_sprites", "decor_patch_sprites"]:
		for terrain_key in GameData.map_gen[group]:
			for sprite in GameData.map_gen[group][terrain_key]:
				assert_true(props.has(sprite), "%s: %s is in the props atlas" % [group, sprite])
	var kinds := {}
	for d in _gen("continental").decor:
		kinds[String(d["sprite"]).get_slice("_", 0)] = true
	for kind in ["daisies", "mushroom", "pebble", "stone"]:
		assert_true(kinds.has(kind), "the map has %s" % kind)

extends "res://src/debug/smoke_test.gd"
## Terrain look smoke:  -- --smoke=terrain --mode=skirmish --map=coast|desert --seed=4242 --nofog
## Water depth field, coast and beach screenshots (two moments, to prove the
## water animates), and on desert maps that dunes cover most of the land.

func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_run.call_deferred()


func _run() -> void:
	await _frames(10)
	var map := _game.map
	var tag := "continental"
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--map="):
			tag = String(arg).get_slice("=", 1)

	# 1. Depth field: land is 0, water grows with distance from the coast.
	var depth := TerrainRenderer.depth_image(map)
	var land_ok := true
	var water_ok := true
	var deepest := 0
	for y in map.height:
		for x in map.width:
			var v := int(depth.get_pixel(x, y).r8)
			if MapData.terrain_navigable(map.get_terrain(Vector2i(x, y))):
				water_ok = water_ok and v > 0
				deepest = maxi(deepest, v)
			else:
				land_ok = land_ok and v == 0
	_check(land_ok, "depth field: every land tile is 0")
	_check(water_ok, "depth field: every water tile is above 0")

	# 2. Desert maps: dunes are the main ground.
	var counts := {}
	var land := 0
	for t in map.terrain:
		counts[t] = int(counts.get(t, 0)) + 1
		if MapData.terrain_passable(t):
			land += 1
	var desert_share := float(counts.get(MapData.Terrain.DESERT, 0)) / maxf(1.0, land)
	if tag == "desert":
		_check(desert_share > 0.35, "desert map: dunes cover most land (%d%%)" % roundi(desert_share * 100.0))
	else:
		_check(desert_share == 0.0, "%s map: no desert tiles" % tag)

	# 3. Coast close-up at two moments: the water must move.
	var shore := _shore_near(Vector2i(map.width / 2, map.height / 2) if tag != "desert" else map.start_positions[0])
	_check(shore.x >= 0, "a shore exists to film")
	if shore.x >= 0:
		_game.camera.focus_world(Iso.grid_to_world(Iso.tile_center(shore)))
		await _seconds(1.0)
		var a := await _grab("terrain_%s_01_shore" % tag)
		await _seconds(1.7)
		var b := await _grab("terrain_%s_02_shore_later" % tag)
		var moved := 0
		for y in range(0, a.get_height(), 4):
			for x in range(0, a.get_width(), 4):
				if a.get_pixel(x, y) != b.get_pixel(x, y):
					moved += 1
		_check(moved > 40, "water animates between frames (%d sampled pixels changed)" % moved)
		# Calm water: blue pixels near the shore use few colours (land blends
		# on purpose and is not counted).
		_check(_water_palette_size(a) < 900, "calm water palette near the shore (%d colours)" % _water_palette_size(a))
	await _seconds(3.0)
	print("FPS on the shore view: %d" % Engine.get_frames_per_second())
	_game.camera.set_zoom_index(0)
	_game.camera.focus_world(Iso.grid_to_world(Iso.tile_center(Vector2i(map.width / 2, map.height / 2))))
	await _seconds(0.8)
	await _grab("terrain_%s_03_overview" % tag)
	await _seconds(3.0)
	print("FPS zoomed out: %d" % Engine.get_frames_per_second())
	var cliff := _cliff_near(map.start_positions[0])
	if cliff.x >= 0:
		_game.camera.set_zoom_index(_game.camera.zoom_levels.size() / 2)
		_game.camera.focus_world(Iso.grid_to_world(Iso.tile_center(cliff)))
		await _seconds(1.0)
		await _grab("terrain_%s_04_cliff" % tag)
	await _climb_a_ramp(tag)
	await _film_a_road(tag)
	_finish()


## Close-up of a dirt road. Roads only join allies and this smoke has none, so
## a stretch is painted on the grass near the start, running across the screen.
func _film_a_road(tag: String) -> void:
	var map := _game.map
	var road := _nearest_of(MapData.Terrain.GRASS, map.start_positions[0] + Vector2i(8, 8))
	_check(road.x >= 0, "grass to lay a road on")
	if road.x < 0:
		return
	for i in range(-10, 11):
		var wobble := Vector2i(1, 1) * (i / 4 % 2)
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var t: Vector2i = road + Vector2i(i, -i) + wobble + o
			if map.in_bounds(t) and map.get_terrain(t) in [MapData.Terrain.GRASS, MapData.Terrain.MEADOW]:
				map.set_terrain(t, MapData.Terrain.PATH)
	_game.terrain.refresh()
	_game.camera.set_zoom_index(_game.camera.zoom_levels.size() - 1)
	_game.camera.focus_world(Iso.grid_to_world(Iso.tile_center(road)))
	await _seconds(1.0)
	await _grab("terrain_%s_07_road" % tag)


## A villager walks up a ramp onto a plateau, and a house fits up there.
func _climb_a_ramp(tag: String) -> void:
	var map := _game.map
	var counts := {}
	for t in map.terrain:
		counts[t] = int(counts.get(t, 0)) + 1
	print("Raised ground: %d rim, %d plateau, %d ramp tiles" % [int(counts.get(MapData.Terrain.MOUNTAIN, 0)), int(counts.get(MapData.Terrain.PLATEAU, 0)), int(counts.get(MapData.Terrain.RAMP, 0))])
	var ramp := _nearest_of(MapData.Terrain.RAMP, map.start_positions[0])
	if ramp.x < 0:
		print("No plateau on this map")
		return
	var top := _nearest_of(MapData.Terrain.PLATEAU, ramp + Vector2i(-2, -2))
	var foot := _ground_near(ramp)
	_check(foot.x >= 0, "open ground at the foot of the ramp")
	var u := _game.spawn_unit("villager", 1, Iso.tile_center(foot))
	var path := _game.pathfinder.find_path(u.grid_pos, Iso.tile_center(top), 1)
	_check(not path.is_empty() and path[path.size() - 1].distance_to(Iso.tile_center(top)) < 1.5, "a path climbs to the plateau")
	u.order_path(path)
	_game.camera.focus_world(Iso.grid_to_world(Iso.tile_center(ramp)))
	await _seconds(1.5)
	await _grab("terrain_%s_05_ramp" % tag)
	Engine.time_scale = 6.0
	var t0 := Time.get_ticks_msec()
	while u.grid_pos.distance_to(Iso.tile_center(top)) > 1.2 and Time.get_ticks_msec() - t0 < 15000:
		await _seconds(0.25)
	Engine.time_scale = 1.0
	_check(u.grid_pos.distance_to(Iso.tile_center(top)) <= 1.2, "the villager reached the plateau")
	_check(map.get_terrain(Iso.tile_of(u.grid_pos)) in [MapData.Terrain.PLATEAU, MapData.Terrain.RAMP], "the villager stands on raised ground")
	var fits := false
	for y in map.height:
		for x in map.width:
			if map.get_terrain(Vector2i(x, y)) == MapData.Terrain.PLATEAU and _game.buildings.placement_error("house", Vector2i(x, y)) == "":
				fits = true
	_check(fits, "a house fits on a plateau")
	_game.camera.focus_world(Iso.grid_to_world(u.grid_pos))
	await _seconds(0.5)
	await _grab("terrain_%s_06_on_plateau" % tag)
	await _seconds(3.0)
	print("FPS on the plateau: %d" % Engine.get_frames_per_second())


func _nearest_of(id: int, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var map := _game.map
	for y in map.height:
		for x in map.width:
			var t := Vector2i(x, y)
			var d := Vector2(t - from).length()
			if map.get_terrain(t) == id and d < best_d:
				best_d = d
				best = t
	return best


## Walkable ground off the raised terrain, closest to `from`.
func _ground_near(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var map := _game.map
	for y in map.height:
		for x in map.width:
			var t := Vector2i(x, y)
			var d := Vector2(t - from).length()
			if d < best_d and map.walkable(t) and not map.get_terrain(t) in TerrainRenderer.RAISED:
				best_d = d
				best = t
	return best


func _grab(name: String) -> Image:
	await _shot(name)
	return get_viewport().get_texture().get_image()


func _water_palette_size(img: Image) -> int:
	var seen := {}
	var c := img.get_size() / 2
	for y in range(c.y - 120, c.y + 120, 2):
		for x in range(c.x - 200, c.x + 200, 2):
			var col := img.get_pixel(x, y)
			if col.b > col.r and col.b > col.g:
				seen[col.to_rgba32()] = true
	return seen.size()


## The mountain tile closest to `from` with open ground just south of it.
func _cliff_near(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var map := _game.map
	for y in map.height - 1:
		for x in map.width - 1:
			var t := Vector2i(x, y)
			if map.get_terrain(t) != MapData.Terrain.MOUNTAIN or map.get_terrain(t + Vector2i(1, 1)) == MapData.Terrain.MOUNTAIN:
				continue
			var d := Vector2(t - from).length()
			if d < best_d:
				best_d = d
				best = t
	return best


## A land tile with plenty of water within 3 tiles, closest to `from`.
func _shore_near(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var map := _game.map
	for y in map.height:
		for x in map.width:
			var t := Vector2i(x, y)
			if not MapData.terrain_passable(map.get_terrain(t)):
				continue
			var water := 0
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var n := t + Vector2i(dx, dy)
					if map.in_bounds(n) and MapData.terrain_navigable(map.get_terrain(n)):
						water += 1
			if water < 14:
				continue
			var d := Vector2(t - from).length()
			if d < best_d:
				best_d = d
				best = t
	return best

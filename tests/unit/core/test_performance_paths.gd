extends "res://tests/test_case.gd"
## Fast paths of the simulation must behave like the plain code they replaced:
## fog stamps, the walkable-tile mirror, the separation grid, drawn-position glide.


func _unit(id: int, at: Vector2) -> Unit:
	var u := Unit.new()
	u.entity_id = id
	u.setup("villager", GameData.unit("villager"), 1, 0, at)
	return u


func _system(map: MapData) -> UnitSystem:
	var s := UnitSystem.new()
	s.setup(map, Pathfinder.new(map), GameData.movement)
	return s


func _free(s: UnitSystem) -> void:
	for u in s.units:
		u.free()
	s.free()


func test_sight_disc_matches_the_circle_rule() -> void:
	var radius := 4
	var grid := Image.create_empty(21, 21, false, Image.FORMAT_R8)
	FogSystem.stamp_disc(grid, FogSystem.sight_disc(radius), Vector2i(10, 10))
	var r2 := (radius + 0.5) * (radius + 0.5)
	for y in 21:
		for x in 21:
			var dx := x - 10
			var dy := y - 10
			var inside := dx * dx + dy * dy <= r2
			assert_eq(grid.get_pixel(x, y).r > 0.5, inside, "tile %d,%d" % [x, y])


func test_sight_disc_clips_at_the_map_corner() -> void:
	var radius := 3
	var grid := Image.create_empty(8, 8, false, Image.FORMAT_R8)
	FogSystem.stamp_disc(grid, FogSystem.sight_disc(radius), Vector2i(0, 0))
	assert_true(grid.get_pixel(0, 0).r > 0.5, "the centre is painted")
	assert_true(grid.get_pixel(3, 0).r > 0.5, "the disc reaches its radius")
	assert_true(grid.get_pixel(4, 0).r < 0.5, "nothing past its radius")
	assert_true(grid.get_pixel(7, 7).r < 0.5, "the far corner stays dark")


func test_sight_disc_adds_to_what_is_already_painted() -> void:
	var grid := Image.create_empty(16, 16, false, Image.FORMAT_R8)
	var disc := FogSystem.sight_disc(2)
	FogSystem.stamp_disc(grid, disc, Vector2i(4, 4))
	FogSystem.stamp_disc(grid, disc, Vector2i(10, 10))
	assert_true(grid.get_pixel(4, 4).r > 0.5, "a later disc never erases an earlier one")


func test_spatial_hash_clear_forgets_everything() -> void:
	var h := SpatialHash.new(16, 16, 2.0)
	var a := RefCounted.new()
	h.insert(a, Vector2(3, 3))
	h.insert(a, Vector2(3.5, 3))
	h.insert(a, Vector2(12, 12))
	var out := []
	h.query(Vector2(3, 3), 1.0, out)
	assert_eq(out.size(), 2, "both nearby items found")
	h.clear()
	out.clear()
	h.query(Vector2(3, 3), 20.0, out)
	assert_eq(out.size(), 0, "nothing survives clear")
	h.insert(a, Vector2(3, 3))
	h.query(Vector2(3, 3), 1.0, out)
	assert_eq(out.size(), 1, "buckets work again after clear")


func test_walkable_follows_tile_changes() -> void:
	var m := MapData.new(8, 8, 1)
	var pf := Pathfinder.new(m)
	var t := Vector2i(3, 3)
	assert_true(pf.is_walkable(t), "open tile")
	m.set_blocked(t, true)
	pf.refresh_tile(t)
	assert_true(not pf.is_walkable(t), "blocked after refresh")
	assert_true(pf.astar.is_point_solid(t), "the search grid agrees")
	m.set_blocked(t, false)
	pf.refresh_tile(t)
	assert_true(pf.is_walkable(t), "open again")
	assert_true(not pf.is_walkable(Vector2i(-1, 0)), "off the map is never walkable")
	assert_true(not pf.is_walkable(Vector2i(8, 0)), "off the far edge is never walkable")


func test_gate_search_leaves_the_mirror_as_it_found_it() -> void:
	var m := MapData.new(8, 3, 1)
	var pf := Pathfinder.new(m)
	var gate := Vector2i(4, 1)
	pf.set_gate(gate, 1)
	pf.find_path(Vector2(1.5, 1.5), Vector2(6.5, 1.5), 2)
	assert_true(pf.is_walkable(gate, 1), "the owner still walks its gate after an enemy search")
	assert_true(not pf.astar.is_point_solid(gate), "the search grid was restored")


func test_line_walkable_sees_a_single_blocked_tile() -> void:
	var m := MapData.new(12, 12, 1)
	m.set_blocked(Vector2i(6, 6), true)
	var pf := Pathfinder.new(m)
	assert_true(not pf.line_walkable(Vector2(2.5, 6.5), Vector2(10.5, 6.5)), "straight through it")
	assert_true(not pf.line_walkable(Vector2(2.5, 5.8), Vector2(10.5, 5.8)), "brushing it with the unit's side")
	assert_true(pf.line_walkable(Vector2(2.5, 3.5), Vector2(10.5, 3.5)), "well clear of it")


func test_overlapping_units_push_apart() -> void:
	var s := _system(MapData.new(16, 16, 1))
	var a := _unit(1, Vector2(8.0, 8.0))
	var b := _unit(2, Vector2(8.1, 8.0))
	s.register(a)
	s.register(b)
	s._build_separation()
	var first := s._active.find(a)
	var push := s._separation(first, a.entity_id)
	assert_true(push.x < 0.0, "pushed away from the other unit")
	assert_near(push.y, 0.0, 0.0001, "only along the line between them")
	_free(s)


func test_units_apart_or_in_the_air_do_not_push() -> void:
	var s := _system(MapData.new(16, 16, 1))
	var a := _unit(1, Vector2(8.0, 8.0))
	var far := _unit(2, Vector2(9.5, 8.0))
	var plane := _unit(3, Vector2(8.05, 8.0))
	plane.altitude = 40.0
	s.register(a)
	s.register(far)
	s.register(plane)
	s._build_separation()
	assert_eq(s._separation(s._active.find(a), a.entity_id), Vector2.ZERO, "nothing touches it on its layer")
	_free(s)


func test_a_wide_neighbour_two_cells_away_still_pushes() -> void:
	var s := _system(MapData.new(16, 16, 1))
	var a := _unit(1, Vector2(8.0, 8.0))
	var ship := _unit(2, Vector2(9.2, 8.0))
	ship.radius = 1.4
	s.register(a)
	s.register(ship)
	s._build_separation()
	assert_true(s._separation(s._active.find(a), a.entity_id).x < 0.0, "the search reaches as far as the widest unit")
	_free(s)


func test_a_resting_unit_wakes_when_ordered() -> void:
	var s := _system(MapData.new(16, 16, 1))
	var a := _unit(1, Vector2(8.0, 8.0))
	s.register(a)
	s._build_separation()
	s._step(a, 0, 0.033)
	assert_true(a.rest_ticks > 0, "alone and idle: it rests")
	a.order_path(PackedVector2Array([Vector2(12.0, 8.0)]))
	s._step(a, 0, 0.033)
	assert_true(a.grid_pos.x > 8.0, "an order moves it at once")
	_free(s)


func test_glide_moves_the_simulation_now_and_the_drawing_later() -> void:
	var a := _unit(1, Vector2(8.0, 8.0))
	var drawn := a.position
	a.glide_to(Vector2(9.0, 8.0))
	assert_eq(a.grid_pos, Vector2(9.0, 8.0), "the simulation position changes at once")
	assert_eq(a.position, drawn, "the drawing catches up on the next frames")
	a.set_grid_pos(Vector2(2.0, 2.0))
	assert_eq(a.position, Iso.grid_to_world(Vector2(2.0, 2.0)).round(), "a teleport lands at once")
	a._glide()
	assert_eq(a.position, Iso.grid_to_world(Vector2(2.0, 2.0)).round(), "and cancels the glide")
	a.free()

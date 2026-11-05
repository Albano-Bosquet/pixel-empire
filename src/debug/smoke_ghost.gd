extends "res://src/debug/smoke_naval.gd"
## Ghost and fog smoke:  -- --smoke=ghost --mode=skirmish --map=coast --seed=4242
## 1. The placement grid agrees with the building tint: a dock is red on land,
##    green on a shore site, all red on open sea; tiles of a house follow the land.
## 2. Birds and their shadows draw nothing over the unexplored dark, and do draw
##    over tiles the player sees (the positive control for the pixel count).


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	game.ambient_life._flock_timer = 99999.0
	_ghost.call_deferred()


func _ghost() -> void:
	await _frames(10)
	var home := Vector2i(_p1_home())
	var spot := _shore_spot(home)
	_check(spot.x >= 0, "the map has a shore site")
	await _show("dock", home, "ghost_01_dock_on_land")
	_marks("dock on land", false, false)
	await _show("dock", spot, "ghost_02_dock_on_shore")
	_marks("dock on the shore", true, true)
	var sea := _open_sea()
	_check(sea.x >= 0, "the map has open sea")
	await _show("dock", sea, "")
	_marks("dock on open sea", false, false)
	await _show("house", _land_spot(home), "")
	_marks("house on land", true, true)
	await _show("house", sea, "")
	_marks("house on the sea", false, false)
	_game.placement.cancel()
	await _birds(home)
	_finish()


func _p1_home() -> Vector2:
	for b in _game.buildings.buildings:
		if b.owner_id == 1 and b.type_id == "town_center":
			return b.grid_pos
	return Vector2.ZERO


## The nearest spot to `home` where a house fits.
func _land_spot(home: Vector2i) -> Vector2i:
	for r in range(4, 40):
		for d in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r), Vector2i(r, r), Vector2i(-r, -r)]:
			if _game.buildings.placement_error("house", home + d) == "":
				return home + d
	return home


## A spot with water under and around it, far from any land.
func _open_sea() -> Vector2i:
	for y in range(4, _game.map.height - 8, 2):
		for x in range(4, _game.map.width - 8, 2):
			var dry := false
			for j in range(-1, 6):
				for i in range(-1, 6):
					dry = dry or not _game.map.navigable(Vector2i(x + i, y + j))
			if not dry and _game.buildings.tile_error("dock", Vector2i(x, y)) == "":
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Puts the ghost of `type_id` on `origin`, as the mouse would.
func _show(type_id: String, origin: Vector2i, shot: String) -> void:
	var s: int = GameData.building(type_id)["size"]
	var mid := Vector2(origin) + Vector2(s, s) * 0.5
	var world := Iso.grid_to_world(mid)
	_game.camera.focus_world(world)
	await _frames(3)
	_game.placement.type_id = type_id
	_game.placement._mouse_screen = get_viewport().get_canvas_transform() * world
	await _frames(3)
	if shot != "":
		_game.fog.set_enabled(false)
		await _frames(3)
		await _shot(shot)
		_game.fog.set_enabled(true)
		await _frames(2)


func _marks(what: String, valid: bool, all_good: bool) -> void:
	var v: Array = _game.placement.tile_marks().values()
	_check(_game.placement._valid == valid, "%s: the building is %s" % [what, "green" if valid else "red"])
	_check(v.all(func(ok): return ok == all_good), "%s: the whole grid is %s" % [what, "green" if all_good else "red"])


func _birds(home: Vector2i) -> void:
	var dark := _dark_tile()
	_check(dark.x >= 0, "there is unexplored map to test over")
	var over_dark := await _flock_pixels(dark)
	_check(over_dark == 0, "a flock over the unexplored dark draws nothing (%d px)" % over_dark)
	await _shot("ghost_03_birds_dark")
	var over_base := await _flock_pixels(home)
	_check(over_base > 0, "the same flock shows over tiles we see (%d px)" % over_base)


## An unexplored tile with unexplored tiles all around it.
func _dark_tile() -> Vector2i:
	for y in range(12, _game.map.height - 12, 3):
		for x in range(12, _game.map.width - 12, 3):
			var clear := true
			for j in range(-10, 11, 5):
				for i in range(-10, 11, 5):
					clear = clear and not _game.fog.is_explored(1, Vector2i(x + i, y + j))
			if clear:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Pixels a still flock of gulls changes around tile `t`.
func _flock_pixels(t: Vector2i) -> int:
	var world := Iso.grid_to_world(Vector2(t) + Vector2(0.5, 0.5))
	_game.camera.focus_world(world)
	var life: AmbientLife = _game.ambient_life
	life._flocks.clear()
	await _frames(4)
	var before := await _grab()
	var members := []
	for i in 7:
		members.append({"o": Vector2(i * 9 - 27, (i % 3) * 7 - 7), "ph": 0.0})
	life._flocks.append({"p": world, "v": Vector2.ZERO, "m": members, "alt": 50.0, "gull": true})
	await _frames(4)
	var after := await _grab()
	life._flocks.clear()
	var scale := Vector2(before.get_size()) / get_viewport().get_visible_rect().size
	var c := (get_viewport().get_canvas_transform() * world) * scale
	var n := 0
	for y in range(int(c.y) - 60, int(c.y) + 90):
		for x in range(int(c.x) - 70, int(c.x) + 70):
			if x < 0 or y < 0 or x >= before.get_width() or y >= before.get_height():
				continue
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.6:
				n += 1
	return n


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

extends "res://src/debug/smoke_combat.gd"
## README showcase capture:  -- --smoke=showcase --mode=skirmish --seed=4242 --nofog
## Stages a few scenes (a Castle Age battle, a city at sunset and at night, a
## Military Age offensive) and saves stills plus short frame sequences for the
## README GIFs. Output folder: env SHOWCASE_OUT, else user://showcase/.
## Not part of run_tests.bat: it checks nothing, it only takes pictures.

const GIF_SIZE := Vector2i(960, 540)

var _out := ""
var _battle_at := Vector2.ZERO


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_out = OS.get_environment("SHOWCASE_OUT")
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://showcase")
	DirAccess.make_dir_recursive_absolute(_out)
	_showcase.call_deferred()


func _showcase() -> void:
	await _frames(10)
	var me := _game.local_state()
	for k in ["food", "wood", "gold", "stone"]:
		me.add(k, 20000)
	var tc := _p1_tc()
	var base := Iso.tile_of(tc.grid_pos)
	_game.day_night.set_process(false)
	_game.day_night.time = 0.45
	_game.day_night._apply()

	await _city(base, 3)
	await _battle(base)
	await _modern(base)
	await _gallery(base)
	_finish()


## Extra stills for the web gallery: a Wonder, a sea fight, an Industrial Age
## battle, the tech tree and the end-of-match screen.
func _gallery(base: Vector2i) -> void:
	_game.hud.visible = true

	# The Wonder rising beside the Imperial city.
	_set_age(3)
	var wspot := _find_build_spot("wonder", base + Vector2i(-4, -14))
	var wonder := _game.buildings.place("wonder", 1, wspot, true)
	if wonder:
		_game.camera.set_zoom_index(1)
		_game.camera.focus_world(Iso.grid_to_world(Iso.tile_center(Iso.tile_of(wonder.grid_pos)) + Vector2(1, 1)))
		await _frames(30)
		await _save("gallery_wonder")

	# Galleys clash off the home shore while a fishing boat works.
	var dock_at := _shore_spot(base)
	if dock_at.x >= 0:
		var dock := _game.buildings.place("dock", 1, dock_at, true)
		var sea := _game.naval_pathfinder.approach(dock.footprint(), dock.grid_pos + Vector2(3, 3))
		var mine: Array[Unit] = []
		var theirs: Array[Unit] = []
		for i in 3:
			var g := _game.spawn_unit("war_galley", 1, sea + Vector2(i * 0.9, -0.8))
			if g: mine.append(g)
		_game.spawn_unit("fishing_ship", 1, sea + Vector2(-1.5, 1.5))
		_game.spawn_unit("transport_ship", 1, sea + Vector2(-2.5, -0.5))
		var far := Iso.tile_center(_game.naval_pathfinder.nearest_walkable(Iso.tile_of(sea + Vector2(7, 3)), 10, sea))
		for i in 3:
			var g := _game.spawn_unit(["war_galley", "fire_ship", "war_galley"][i], 2, far + Vector2(i * 0.9, 0))
			if g: theirs.append(g)
		_game.combat.order_attack_move(mine, far)
		_game.combat.order_attack_move(theirs, sea)
		_game.camera.set_zoom_index(2)
		_game.camera.focus_world(Iso.grid_to_world(sea.lerp(far, 0.45)))
		await _seconds(2.5)
		await _save("gallery_naval")
		for u in mine + theirs:
			if is_instance_valid(u) and not u.dead:
				_game.kill_unit(u)

	# Riflemen, field guns and biplanes against a musket line in the Industrial Age.
	_set_age(5)
	var field := _clearing([Iso.tile_center(base), _battle_at], 18.0)
	var ft := Iso.tile_of(field)
	_game.buildings.place("airfield", 1, _find_build_spot("airfield", ft + Vector2i(-9, -4)), true)
	_game.buildings.place("foundry", 1, _find_build_spot("foundry", ft + Vector2i(-8, 4)), true)
	_game.buildings.place("tower", 2, _find_build_spot("tower", ft + Vector2i(6, -2)), true)
	var army: Array[Unit] = []
	army.append_array(_spawn_group("rifleman", 1, field + Vector2(-5, -1), 9))
	army.append_array(_spawn_group("field_cannon", 1, field + Vector2(-8, 0.5), 2))
	army.append_array(_spawn_group("dragoon", 1, field + Vector2(-5, 2), 3))
	army.append_array(_spawn_group("biplane_fighter", 1, field + Vector2(-7, -3), 2))
	_spawn_group("observation_balloon", 1, field + Vector2(-9, -1), 1)
	var foes: Array[Unit] = []
	foes.append_array(_spawn_group("musketeer", 2, field + Vector2(2, -1), 9))
	foes.append_array(_spawn_group("grenadier", 2, field + Vector2(3, 1.5), 3))
	_game.camera.set_zoom_index(2)
	_game.camera.focus_world(Iso.grid_to_world(field + Vector2(-2, 0)))
	await _frames(10)
	_game.combat.order_attack_move(army, field + Vector2(5, 0))
	_game.combat.order_attack_move(foes, field + Vector2(-5, 0))
	await _seconds(2.0)
	await _save("gallery_industrial")
	for u in army + foes:
		if is_instance_valid(u) and not u.dead:
			_game.kill_unit(u)

	# Tech tree over the city.
	_game.camera.set_zoom_index(1)
	_game.camera.focus_world(Iso.grid_to_world(Iso.tile_center(base)))
	_game.hud.tech_panel.toggle()
	await _frames(20)
	await _save("gallery_techs")
	_game.hud.tech_panel.toggle()

	# End-of-match statistics.
	var end := EndScreen.new()
	get_tree().root.add_child(end)
	end.show_results(_game, [_game.local_player])
	await _frames(20)
	await _save("gallery_victory")


## Nearest valid dock origin to `home` (ring search), or (-1, -1).
func _shore_spot(home: Vector2i) -> Vector2i:
	for r in range(4, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var o := home + Vector2i(dx, dy)
				if _game.buildings.placement_error("dock", o) == "":
					return o
	return Vector2i(-1, -1)


## A walled Imperial city with villagers at work; stills by day, sunset and night.
func _city(base: Vector2i, age: int) -> void:
	_set_age(age)
	var plan := [["castle", Vector2i(7, -6)], ["market", Vector2i(-9, 2)], ["monastery", Vector2i(-6, -9)],
		["blacksmith", Vector2i(6, 4)], ["university", Vector2i(-2, 7)], ["mill", Vector2i(-8, 8)],
		["house", Vector2i(4, 8)], ["house", Vector2i(2, -6)], ["house", Vector2i(-3, -5)],
		["house", Vector2i(9, 2)], ["barracks", Vector2i(11, -1)], ["tower", Vector2i(-11, -4)]]
	for p in plan:
		_game.buildings.place(p[0], 1, _find_build_spot(p[0], base + p[1]), true)
	for i in 4:
		var farm := _game.buildings.place("farm", 1, _find_build_spot("farm", base + Vector2i(-12 + i * 3, 11)), true)
		var f: Array[Unit] = [_game.spawn_unit("villager", 1, Iso.tile_center(Iso.tile_of(farm.grid_pos)))]
		_game.economy.order_gather(f, farm)
	for kind in ["wood", "gold", "stone"]:
		var node := _game.economy.find_node(kind, Iso.tile_center(base), 40, -1)
		if node:
			var g: Array[Unit] = []
			for k in 3:
				g.append(_game.spawn_unit("villager", 1, Iso.tile_center(base) + Vector2(2 + k, 3)))
			_game.economy.order_gather(g, node)
	for k in 3:
		_game.spawn_unit(["knight", "monk", "swordsman"][k], 1, Iso.tile_center(base) + Vector2(3.5 + k * 0.8, -1.5))
	Engine.time_scale = 6.0
	await _seconds(4.0)
	Engine.time_scale = 1.0
	var centre := Iso.grid_to_world(Iso.tile_center(base) + Vector2(0, 1))
	_game.camera.set_zoom_index(1)
	_game.camera.focus_world(centre)
	await _frames(40)
	await _save("city_day_hud")
	_game.hud.visible = false
	await _save("city_day")
	await _clip("city_life", 48, 3)
	_game.day_night.time = 0.755
	_game.day_night._apply()
	await _frames(4)
	await _save("city_sunset")
	_game.day_night.time = 0.05
	_game.day_night._apply()
	await _frames(30)
	await _save("city_night")
	_game.day_night.time = 0.45
	_game.day_night._apply()
	_game.hud.visible = true


## Knights, swordsmen, archers and a catapult storm an enemy outpost.
func _battle(base: Vector2i) -> void:
	var field := _field(base, 0.55)
	_battle_at = field
	var ft := Iso.tile_of(field)
	var enemy_tower := _game.buildings.place("tower", 2, _find_build_spot("tower", ft + Vector2i(5, -4)), true)
	_game.buildings.place("house", 2, _find_build_spot("house", ft + Vector2i(7, 0)), true)
	_game.buildings.place("barracks", 2, _find_build_spot("barracks", ft + Vector2i(8, -8)), true)
	var mine: Array[Unit] = []
	mine.append_array(_spawn_group("knight", 1, field + Vector2(-5, -3), 9))
	mine.append_array(_spawn_group("swordsman", 1, field + Vector2(-5, 1), 9))
	mine.append_array(_spawn_group("archer", 1, field + Vector2(-8, -1), 9))
	mine.append_array(_spawn_group("catapult", 1, field + Vector2(-10, 0), 2))
	var theirs: Array[Unit] = []
	theirs.append_array(_spawn_group("pikeman", 2, field + Vector2(1, -2), 9))
	theirs.append_array(_spawn_group("greatsword", 2, field + Vector2(1, 1.5), 9))
	theirs.append_array(_spawn_group("crossbowman", 2, field + Vector2(4, -0.5), 9))
	if enemy_tower:
		enemy_tower.take_damage(int(enemy_tower.max_hp * 0.6), null)
	_game.camera.set_zoom_index(2)
	_game.camera.focus_world(Iso.grid_to_world(field + Vector2(-2, 0)))
	_game.hud.visible = false
	await _frames(20)
	await _save("battle_lineup")
	_game.combat.order_attack_move(mine, field + Vector2(4, 0))
	_game.combat.order_attack_move(theirs, field + Vector2(-6, 0))
	await _seconds(1.2)
	await _save("battle_charge")
	await _clip("battle", 60, 2)
	await _save("battle")
	await _seconds(1.5)
	await _save("battle_late")
	for u in mine + theirs:
		if is_instance_valid(u) and not u.dead:
			_game.kill_unit(u)
	_game.hud.visible = true
	await _frames(4)


## Tanks, infantry and jets push into an enemy base in the Military Age.
func _modern(base: Vector2i) -> void:
	_set_age(6)
	var field := _clearing([Iso.tile_center(base), _battle_at], 22.0)
	var ft := Iso.tile_of(field)
	_game.buildings.place("tank_factory", 1, _find_build_spot("tank_factory", ft + Vector2i(-9, -5)), true)
	var target := _game.buildings.place("flak_fort", 2, _find_build_spot("flak_fort", ft + Vector2i(6, -3)), true)
	_game.buildings.place("military_base", 2, _find_build_spot("military_base", ft + Vector2i(7, 3)), true)
	var mine: Array[Unit] = []
	mine.append_array(_spawn_group("heavy_tank", 1, field + Vector2(-5, -1.5), 3))
	mine.append_array(_spawn_group("light_tank", 1, field + Vector2(-5, 1.5), 3))
	mine.append_array(_spawn_group("infantryman", 1, field + Vector2(-7, 0), 6))
	mine.append_array(_spawn_group("jet_fighter", 1, field + Vector2(-9, -3), 2))
	var theirs: Array[Unit] = []
	theirs.append_array(_spawn_group("bazooka_trooper", 2, field + Vector2(2, -1), 5))
	theirs.append_array(_spawn_group("machine_gunner", 2, field + Vector2(2.5, 1.5), 4))
	_game.camera.set_zoom_index(2)
	_game.camera.focus_world(Iso.grid_to_world(field))
	_game.hud.visible = false
	await _frames(10)
	_game.combat.order_attack_move(mine, field + Vector2(5, 0))
	_game.combat.order_attack_move(theirs, field + Vector2(-5, 0))
	if target:
		var jets: Array[Unit] = []
		for u in mine:
			if u.type_id == "jet_fighter":
				jets.append(u)
		_game.combat.order_attack(jets, target)
	await _seconds(1.0)
	await _save("modern_early")
	await _clip("modern", 54, 2)
	await _save("modern")
	_game.hud.visible = true


## An open patch of land `f` of the way from `base` to the map centre.
func _field(base: Vector2i, f: float) -> Vector2:
	var centre := Vector2(_game.map.width, _game.map.height) * 0.5
	return _open_spot(Iso.tile_center(base).lerp(centre, f), 6)


## The most open land at least `away` tiles from every point in `avoid`.
func _clearing(avoid: Array, away: float) -> Vector2:
	var best := Vector2.ZERO
	var best_n := -1
	for y in range(10, _game.map.height - 10, 3):
		for x in range(10, _game.map.width - 10, 3):
			var c := Vector2(x, y)
			if avoid.any(func(a): return c.distance_to(a) < away):
				continue
			var n := 0
			for dy in range(-7, 8):
				for dx in range(-7, 8):
					if _game.pathfinder.is_walkable(Vector2i(x + dx, y + dy)):
						n += 1
			if n > best_n:
				best_n = n
				best = Iso.tile_center(Vector2i(x, y))
	return best


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))


## `n` frames, one every `every` rendered frames, downscaled for a GIF.
func _clip(name: String, n: int, every: int) -> void:
	var dir := _out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	for i in n:
		await _frames(every)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(GIF_SIZE.x, GIF_SIZE.y, Image.INTERPOLATE_LANCZOS)
		img.save_png(dir.path_join("%03d.png" % i))


## Sets the local age and nudges the resources so the HUD label refreshes.
func _set_age(age: int) -> void:
	var me := _game.local_state()
	me.age = age
	me.add("food", 1)

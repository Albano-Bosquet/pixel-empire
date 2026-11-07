extends "res://src/debug/smoke_combat.gd"
## Smoke test for bodies behind buildings, death frames and diagonal walls:
##   -- --smoke=occlusion --mode=skirmish
## 1. A villager behind a barracks shows as a silhouette over it and is still
##    picked by a click on the building where it stands.
## 2. A sheep killed behind the barracks leaves a carcass that shows through and
##    wins the click over the building.
## 3. Corpses stay in the y-sort (z 0) instead of sinking under everything.
## 4. A diagonal stone wall line is one piece per step and links at the corners.
## 5. A villager behind a tree shows through it; one in front does not.


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	for ai in game.ai_players:
		ai.set_physics_process(false)
	_run_occlusion.call_deferred()


func _run_occlusion() -> void:
	await _frames(5)
	_game.fog.set_enabled(false)
	var tc := _p1_tc()

	# --- 1. Villager behind a building ---------------------------------------------------
	var spot := _open_spot(tc.grid_pos + Vector2(9, -2), 3)
	var o := Iso.tile_of(spot) - Vector2i(1, 1)
	var barracks := _game.buildings.place("barracks", 1, o, true)
	var s := float(barracks.size)
	# Just past the far (north) corner: drawn before the building and covered by it.
	var behind := Vector2(o) + Vector2(-0.35, -0.35)
	var vil := _game.spawn_unit("villager", 1, behind)
	_game.camera.focus_world(barracks.position)
	await _frames(4)
	_check(vil != null and vil.position.y < barracks.position.y, "villager stands behind the barracks (y-sorted before it)")
	_check(barracks.body_rect().intersects(Rect2(vil.global_pick_rect())), "the barracks sprite covers the villager")
	var xr: Node2D = barracks._xray
	_check(xr != null and _visible_children(xr) >= 1, "a silhouette is drawn over the barracks")
	_check(barracks._body.clip_children == CanvasItem.CLIP_CHILDREN_AND_DRAW, "the silhouette is clipped to the building sprite")
	var at := _game.screen_from_world(vil.position + Vector2(0, -14))
	_click(at)
	await _frames(2)
	_check(_game.selection.selected.size() == 1 and _game.selection.selected[0] == vil, "clicking the silhouette selects the hidden villager")
	await _shot("occlusion_01_villager_behind")

	# --- 2. Carcass behind the building ----------------------------------------------------
	_game.selection.set_selection([])
	vil.set_grid_pos(Vector2(o) + Vector2(s + 0.6, s * 0.5))  # step aside (in front of the east face)
	var sheep := _game.spawn_unit("sheep", Entity.GAIA, Vector2(o) + Vector2(s * 0.5, -0.4))
	await _frames(2)
	sheep.take_damage(sheep.hp, null)
	await _seconds(1.2)
	var carcass: ResourceNode = null
	for n in _game.carcasses:
		if is_instance_valid(n) and n.grid_pos.distance_to(sheep.grid_pos) < 0.1:
			carcass = n
	_check(carcass != null, "the sheep leaves a carcass")
	if carcass != null:
		_check(carcass.z_index == 0, "the carcass stays in the y-sort (z 0)")
		_check(carcass.position.y < barracks.position.y, "the carcass lies behind the barracks")
		await _frames(2)
		var found := false
		for c in xr.get_children():
			if c.visible and c.texture == carcass.body_sprite().texture:
				found = true
		_check(found, "the carcass shows through the barracks")
		at = _game.screen_from_world(carcass.position + carcass.feet_offset + Vector2(0, -6))
		var picked := _game.selection.pick(at)
		_check(picked == carcass, "a click on the carcass picks it, not the barracks (got %s)" % (picked.type_id if picked else "null"))
	await _shot("occlusion_02_carcass_behind")

	# --- 3. Corpses ----------------------------------------------------------------------
	var victim := _game.spawn_unit("villager", 1, Vector2(o) + Vector2(s + 1.5, s + 1.0))
	await _frames(2)
	victim.take_damage(victim.hp, null)
	await _seconds(1.0)
	_check(victim.z_index == 0, "a dying villager stays in the y-sort (z 0)")
	_check(victim.dead and victim.body_sprite().position.y > 0.0, "its body is drawn at its feet while sorting behind them")
	_game.camera.focus_world(victim.position)
	await _frames(2)
	await _shot("occlusion_03_corpses")
	var hold := float(GameData.combat.get("corpse_seconds", 5.0))
	var fade := float(GameData.combat.get("corpse_fade_seconds", 5.0))
	_check(victim.modulate.a > 0.99, "the body lies fully visible at first")
	await _seconds(hold - 1.0 + fade * 0.5)
	var a_mid := victim.modulate.a if is_instance_valid(victim) else -1.0
	_check(a_mid > 0.15 and a_mid < 0.85, "half way through the fade the body is see-through (%.2f)" % a_mid)
	await _shot("occlusion_05_corpse_fading")
	await _seconds(fade * 0.5 + 0.5)
	_check(not is_instance_valid(victim), "the faded body is removed")
	if carcass != null and is_instance_valid(carcass):
		carcass.take(carcass.amount)
		await _seconds(float(GameData.combat.get("carcass_fade_seconds", 1.5)) * 0.5)
		var ca := carcass.modulate.a if is_instance_valid(carcass) else -1.0
		_check(ca > 0.05 and ca < 0.95, "an eaten carcass fades out (%.2f)" % ca)
		await _seconds(float(GameData.combat.get("carcass_fade_seconds", 1.5)))
		_check(not is_instance_valid(carcass), "then it is removed")

	# --- 4. Diagonal wall ----------------------------------------------------------------
	_game.selection.set_selection([])
	var w0 := Iso.tile_of(_open_spot(tc.grid_pos + Vector2(-6, 8), 4)) + Vector2i(-3, -3)
	var line := PlacementController.line_tiles(w0, w0 + Vector2i(5, 5))
	_check(line.size() == 6, "a diagonal drag lays one piece per step (%d)" % line.size())
	var pieces: Array[Building] = []
	for t in line:
		pieces.append(_game.buildings.place("stone_wall", 1, t, true))
	var bend := PlacementController.line_tiles(w0 + Vector2i(5, 5), w0 + Vector2i(9, 5))
	for i in range(1, bend.size()):
		_game.buildings.place("stone_wall", 1, bend[i], true)
	await _frames(2)
	var mid := pieces[2]
	_check(mid._arms.has("pxpy") and mid._arms.has("nxny"), "a diagonal piece links to both diagonal neighbours")
	_check(not mid._arms.has("px") and not mid._arms.has("py"), "no orthogonal arms on a pure diagonal")
	_check(not _game.pathfinder.is_walkable(w0 + Vector2i(1, 1)), "diagonal pieces block their tiles")
	var corner := pieces[pieces.size() - 1]
	_check(corner._arms.has("px") and corner._arms.has("nxny"), "the bend joins the diagonal and the straight run")
	# The other diagonal runs across the screen (grid (1, -1) is screen-horizontal).
	var across := PlacementController.line_tiles(w0 + Vector2i(0, 9), w0 + Vector2i(5, 4))
	var flat: Array[Building] = []
	for t in across:
		flat.append(_game.buildings.place("stone_wall", 1, t, true))
	await _frames(2)
	_check(flat[2]._arms.has("pxny") and flat[2]._arms.has("nxpy"), "a screen-horizontal diagonal links too")
	_game.camera.focus_world(Iso.grid_to_world(Vector2(w0) + Vector2(4, 6)))
	await _frames(3)
	await _shot("occlusion_04_diagonal_wall")

	# --- 5. Villager behind a tree -----------------------------------------------------------
	var tree := _lone_tree(tc.grid_pos)
	_check(tree != null, "a tree with free ground behind it")
	if tree != null:
		var holder_of := func() -> Node2D: return _game.xray._holders.get(tree.body_sprite())
		var hidden := _game.spawn_unit("villager", 1, tree.grid_pos + Vector2(-1.0, -1.0))
		_game.camera.set_zoom_index(_game.camera.zoom_levels.size() - 1)
		_game.camera.focus_world(tree.position + Vector2(0, -30))
		await _frames(4)
		_check(hidden.position.y < tree.position.y, "the villager stands behind the tree")
		var shown: Node2D = holder_of.call()
		_check(shown != null and shown.visible and _visible_children(shown) >= 1, "a silhouette is drawn over the tree")
		await _shot("occlusion_06_villager_behind_tree")
		hidden.set_grid_pos(tree.grid_pos + Vector2(1.0, 1.0))
		await _frames(4)
		_check(hidden.position.y > tree.position.y, "the villager walked in front of the tree")
		shown = holder_of.call()
		_check(shown == null or not shown.visible, "in front of the tree it needs no silhouette")
		await _shot("occlusion_07_villager_before_tree")
	_finish()


## A tall tree near `from` whose far side is open ground.
func _lone_tree(from: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_d := INF
	for c in _game.entities_root.get_children():
		if c is ResourceNode and c.resource_type == "wood" and c.body_sprite().region_rect.size.y >= 40.0:
			var t: Vector2i = c.tile()
			var d: float = c.grid_pos.distance_to(from)
			if d < best_d and _game.pathfinder.is_walkable(t + Vector2i(-1, -1)) and _game.pathfinder.is_walkable(t + Vector2i(1, 1)):
				best_d = d
				best = c
	return best


func _visible_children(n: Node) -> int:
	var k := 0
	for c in n.get_children():
		if c.visible:
			k += 1
	return k

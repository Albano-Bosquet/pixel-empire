class_name FogSystem
extends Node
## Fog of war (design/game-brief.md MVP item 1): per-player visible/explored
## grids rebuilt at fog_update_hz from every owned unit and building's sight.
## The local player's grid feeds the overlay shader; enemy units outside vision
## are hidden; other players' buildings appear once actually seen and out of sight
## show as they were last seen (BuildingMemory). AI players use their
## own grids, so they never see through the fog either.
## Grids live in R8 images (255 = yes) and sight discs are blitted natively:
## this runs several times a second over every unit, too hot for script loops.
## Example: if game.fog.is_visible(player_id, enemy): ...

const SHADER := preload("res://assets/shaders/fog.gdshader")

var enabled := true
## "explored" map visibility: every tile starts explored (set by Game).
var pending_reveal := false

var _game: Game
var _w := 0
var _h := 0
var _visible: Dictionary = {}   # player_id -> PackedByteArray (non-zero = visible now)
var _explored: Dictionary = {}  # player_id -> PackedByteArray (non-zero = ever seen)
var _visible_img: Dictionary = {}   # player_id -> Image the grid above is read from
var _explored_img: Dictionary = {}  # player_id -> Image
var _discs: Dictionary = {}     # sight radius -> sight_disc()
var _timer := 0.0
var _interval := 0.125
var _tex: ImageTexture
var _explored_tex: ImageTexture
var _overlay: Node2D
## What the local player remembers of other players' buildings out of sight.
var memory := BuildingMemory.new()


func setup(game: Game, cfg: Dictionary, fog_enabled: bool) -> void:
	_game = game
	enabled = fog_enabled
	memory.setup(game)
	add_child(memory)
	_w = game.map.width
	_h = game.map.height
	_interval = 1.0 / maxf(1.0, float(cfg.get("fog_update_hz", 8)))
	for p in game.players:
		_visible_img[p.id] = Image.create_empty(_w, _h, false, Image.FORMAT_R8)
		_explored_img[p.id] = Image.create_empty(_w, _h, false, Image.FORMAT_R8)
		_visible[p.id] = _visible_img[p.id].get_data()
		_explored[p.id] = _explored_img[p.id].get_data()
	var blank := Image.create_empty(_w, _h, false, Image.FORMAT_R8)
	_tex = ImageTexture.create_from_image(blank)
	_explored_tex = ImageTexture.create_from_image(blank)
	_overlay = FogOverlay.new()
	_overlay.z_index = 46
	_overlay.visible = enabled
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("fog_map", _tex)
	mat.set_shader_parameter("explored_map", _explored_tex)
	mat.set_shader_parameter("noise_tex", load(SpriteLibrary.TERRAIN_NOISE))
	mat.set_shader_parameter("map_size", Vector2(_w, _h))
	_overlay.material = mat
	_overlay.rect = Iso.map_world_rect(_w, _h).grow(TerrainRenderer.VOID_MARGIN)
	game.world.add_child(_overlay)


func set_enabled(on: bool) -> void:
	enabled = on
	_overlay.visible = on
	update_now()


func is_tile_visible(player_id: int, t: Vector2i) -> bool:
	if not enabled or not _visible.has(player_id):
		return true
	if t.x < 0 or t.y < 0 or t.x >= _w or t.y >= _h:
		return false
	return _visible[player_id][t.y * _w + t.x] != 0


func is_explored(player_id: int, t: Vector2i) -> bool:
	if not enabled or not _explored.has(player_id):
		return true
	if t.x < 0 or t.y < 0 or t.x >= _w or t.y >= _h:
		return false
	return _explored[player_id][t.y * _w + t.x] != 0


## Whether `player_id` currently sees entity `e` (buildings: any corner/centre).
func is_visible(player_id: int, e: Entity) -> bool:
	if not enabled or e.owner_id == player_id or not _visible.has(player_id):
		return true
	if e is Building:
		var r: Rect2i = e.footprint()
		for t in [r.position, r.end - Vector2i.ONE, Vector2i(r.position.x, r.end.y - 1), Vector2i(r.end.x - 1, r.position.y), Iso.tile_of(e.grid_pos)]:
			if is_tile_visible(player_id, t):
				return true
		return false
	return is_tile_visible(player_id, e.tile())


## Raw grids (1 byte per tile, row-major) for bulk readers like the minimap.
func visible_grid(player_id: int) -> PackedByteArray:
	return _visible.get(player_id, PackedByteArray())


func explored_grid(player_id: int) -> PackedByteArray:
	return _explored.get(player_id, PackedByteArray())


## Restores a saved exploration grid.
func set_explored(player_id: int, grid: PackedByteArray) -> void:
	if _explored.has(player_id) and grid.size() == _explored[player_id].size():
		var data := grid.duplicate()
		for i in data.size():
			if data[i] != 0:
				data[i] = 255  # older saves stored 1
		_explored_img[player_id].set_data(_w, _h, false, Image.FORMAT_R8, data)
		_explored[player_id] = data
	# Saves keep no building memory: count what stands on explored ground as seen.
	if player_id == _game.local_player:
		for b in _game.buildings.buildings:
			if is_explored(player_id, Iso.tile_of(b.grid_pos)):
				memory.mark_seen(b)


## Tiles explored by `player_id` (0..1), for statistics and the AI.
func explored_fraction(player_id: int) -> float:
	var e: PackedByteArray = _explored[player_id]
	return float(e.size() - e.count(0)) / float(e.size())


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = _interval
		update_now()


func update_now() -> void:
	var sources := _sight_sources()
	for pid in _visible_img:
		var vis: Image = _visible_img[pid]
		var exp: Image = _explored_img[pid]
		vis.fill(Color.BLACK)
		for owner in sources:
			if CombatSystem.are_allies(owner, pid):
				for key in sources[owner]:
					_stamp(vis, exp, Vector2i(key.x, key.y), key.z)
		_visible[pid] = vis.get_data()
		_explored[pid] = exp.get_data()
	_refresh_local()


## player id -> {Vector3i(tile x, tile y, sight radius): true}. A crowd on one
## tile counts once: repeating the same disc reveals nothing more.
func _sight_sources() -> Dictionary:
	var sources := {}
	for u in _game.unit_system.units:
		if u.owner_id != Entity.GAIA and not u.dead and u.aboard == null:
			var t := u.tile()
			_owner_sources(sources, u.owner_id)[Vector3i(t.x, t.y, u.sight)] = true
	for b in _game.buildings.buildings:
		if b.owner_id != Entity.GAIA and not b.dead:
			var t := Iso.tile_of(b.grid_pos)
			_owner_sources(sources, b.owner_id)[Vector3i(t.x, t.y, int(b.def.get("sight", 4)) if b.is_complete() else 2)] = true
	return sources


static func _owner_sources(sources: Dictionary, owner: int) -> Dictionary:
	if not sources.has(owner):
		sources[owner] = {}
	return sources[owner]


func _stamp(vis: Image, exp: Image, c: Vector2i, radius: int) -> void:
	if not _discs.has(radius):
		_discs[radius] = sight_disc(radius)
	var disc: Dictionary = _discs[radius]
	stamp_disc(vis, disc, c)
	stamp_disc(exp, disc, c)


## Images that paint a filled disc of `radius` tiles with stamp_disc().
static func sight_disc(radius: int) -> Dictionary:
	var side := radius * 2 + 1
	var solid := Image.create_empty(side, side, false, Image.FORMAT_R8)
	solid.fill(Color.WHITE)
	var mask := Image.create_empty(side, side, false, Image.FORMAT_LA8)
	var r2 := (radius + 0.5) * (radius + 0.5)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= r2:
				mask.set_pixel(dx + radius, dy + radius, Color.WHITE)
	return {"solid": solid, "mask": mask, "rect": Rect2i(0, 0, side, side), "radius": radius}


## Paints `disc` centred on tile `c` of `grid`, clipped to the grid.
static func stamp_disc(grid: Image, disc: Dictionary, c: Vector2i) -> void:
	var r: int = disc["radius"]
	grid.blit_rect_mask(disc["solid"], disc["mask"], disc["rect"], c - Vector2i(r, r))


func _refresh_local() -> void:
	var pid := _game.local_player
	if not _visible.has(pid):
		return
	if pending_reveal:
		pending_reveal = false
		for p2 in _explored_img:
			_explored_img[p2].fill(Color.WHITE)
			_explored[p2] = _explored_img[p2].get_data()
	_tex.update(_visible_img[pid])
	_explored_tex.update(_explored_img[pid])
	# Hide what the local player cannot see.
	for u in _game.unit_system.units:
		if u.owner_id != pid:
			u.visible = is_visible(pid, u) and u.aboard == null
	memory.refresh(pid, self)


## Full-map quad that renders the fog shader.
class FogOverlay:
	extends Node2D
	var rect := Rect2()

	func _draw() -> void:
		draw_rect(rect, Color.WHITE)

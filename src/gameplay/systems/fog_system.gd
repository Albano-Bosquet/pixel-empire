class_name FogSystem
extends Node
## Fog of war (design/game-brief.md MVP item 1): per-player visible/explored
## grids rebuilt at fog_update_hz from every owned unit and building's sight.
## The local player's grid feeds the overlay shader; enemy units outside vision
## are hidden; other players' buildings appear once actually seen and out of sight
## show as they were last seen (BuildingMemory). AI players use their
## own grids, so they never see through the fog either.
## Example: if game.fog.is_visible(player_id, enemy): ...

const SHADER := preload("res://assets/shaders/fog.gdshader")

var enabled := true
## "explored" map visibility: every tile starts explored (set by Game).
var pending_reveal := false

var _game: Game
var _w := 0
var _h := 0
var _visible: Dictionary = {}   # player_id -> PackedByteArray (1 = visible now)
var _explored: Dictionary = {}  # player_id -> PackedByteArray (1 = ever seen)
var _offsets: Dictionary = {}   # sight radius -> Array[Vector2i]
var _timer := 0.0
var _interval := 0.125
var _img: Image
var _tex: ImageTexture
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
		var v := PackedByteArray()
		v.resize(_w * _h)
		_visible[p.id] = v
		var e := PackedByteArray()
		e.resize(_w * _h)
		_explored[p.id] = e
	_img = Image.create_empty(_w, _h, false, Image.FORMAT_R8)
	_tex = ImageTexture.create_from_image(_img)
	_overlay = FogOverlay.new()
	_overlay.z_index = 46
	_overlay.visible = enabled
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("fog_map", _tex)
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
		_explored[player_id] = grid.duplicate()
	# Saves keep no building memory: count what stands on explored ground as seen.
	if player_id == _game.local_player:
		for b in _game.buildings.buildings:
			if is_explored(player_id, Iso.tile_of(b.grid_pos)):
				memory.mark_seen(b)


## Tiles explored by `player_id` (0..1), for statistics and the AI.
func explored_fraction(player_id: int) -> float:
	var e: PackedByteArray = _explored[player_id]
	return float(e.count(1)) / float(e.size())


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = _interval
		update_now()


func update_now() -> void:
	for pid in _visible:
		var vis: PackedByteArray = _visible[pid]
		vis.fill(0)
		for u in _game.unit_system.units:
			if u.owner_id != Entity.GAIA and CombatSystem.are_allies(u.owner_id, pid) and not u.dead and u.aboard == null:
				_stamp(vis, u.tile(), u.sight)
		for b in _game.buildings.buildings:
			if b.owner_id != Entity.GAIA and CombatSystem.are_allies(b.owner_id, pid) and not b.dead:
				_stamp(vis, Iso.tile_of(b.grid_pos), int(b.def.get("sight", 4)) if b.is_complete() else 2)
		var exp: PackedByteArray = _explored[pid]
		for i in vis.size():
			if vis[i] != 0:
				exp[i] = 1
	_refresh_local()


func _stamp(vis: PackedByteArray, c: Vector2i, radius: int) -> void:
	if not _offsets.has(radius):
		var list: Array[Vector2i] = []
		var r2 := (radius + 0.5) * (radius + 0.5)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy <= r2:
					list.append(Vector2i(dx, dy))
		_offsets[radius] = list
	for o in _offsets[radius]:
		var x: int = c.x + o.x
		var y: int = c.y + o.y
		if x >= 0 and y >= 0 and x < _w and y < _h:
			vis[y * _w + x] = 1


func _refresh_local() -> void:
	var pid := _game.local_player
	if not _visible.has(pid):
		return
	var vis: PackedByteArray = _visible[pid]
	if pending_reveal:
		pending_reveal = false
		for p2 in _explored:
			_explored[p2].fill(1)
	var exp: PackedByteArray = _explored[pid]
	var data := PackedByteArray()
	data.resize(_w * _h)
	for i in data.size():
		data[i] = 255 if vis[i] != 0 else (128 if exp[i] != 0 else 0)
	_img.set_data(_w, _h, false, Image.FORMAT_R8, data)
	_tex.update(_img)
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

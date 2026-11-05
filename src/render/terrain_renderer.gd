class_name TerrainRenderer
extends Node2D
## Draws the whole terrain with terrain.gdshader in a single quad.
## Example: var tr := TerrainRenderer.new(); add_child(tr); tr.build(map)

const SHADER := preload("res://assets/shaders/terrain.gdshader")
const VOID_MARGIN := 2400.0
## Tiles of open water encoded by depth value 1.0 (must match the shader's depth_scale).
const DEPTH_SCALE := 8
## Terrain the cliff line runs around.
const RAISED: Array[int] = [MapData.Terrain.MOUNTAIN, MapData.Terrain.PLATEAU, MapData.Terrain.RAMP]

var _map: MapData
var _map_tex: ImageTexture
var _depth_tex: ImageTexture
var _material := ShaderMaterial.new()


func _ready() -> void:
	z_index = -100
	_material.shader = SHADER
	material = _material


func build(map: MapData) -> void:
	_map = map
	var img := Image.create_from_data(map.width, map.height, false, Image.FORMAT_R8, map.terrain)
	_map_tex = ImageTexture.create_from_image(img)
	_material.set_shader_parameter("atlas", load(SpriteLibrary.TERRAIN_ATLAS))
	_material.set_shader_parameter("noise_tex", load(SpriteLibrary.TERRAIN_NOISE))
	_material.set_shader_parameter("noise_smooth", load(SpriteLibrary.TERRAIN_NOISE))
	_material.set_shader_parameter("terrain_map", _map_tex)
	_depth_tex = ImageTexture.create_from_image(depth_image(map))
	_material.set_shader_parameter("depth_map", _depth_tex)
	_material.set_shader_parameter("depth_scale", float(DEPTH_SCALE))
	_material.set_shader_parameter("map_size", Vector2(map.width, map.height))
	queue_redraw()


## Re-uploads terrain after it changes (e.g. future farms/roads).
func refresh() -> void:
	if _map_tex:
		_map_tex.update(Image.create_from_data(_map.width, _map.height, false, Image.FORMAT_R8, _map.terrain))
		_depth_tex.update(depth_image(_map))


## Depth fields for the shader, in steps of 8-way distance capped at
## DEPTH_SCALE and stored as /DEPTH_SCALE. R: water tiles, steps to the nearest
## land (land = 0). G: raised tiles (mountain, plateau, ramp), steps to the
## nearest other tile (else 0). B: 255 on ramps, where no wall may be painted.
## Sampled bilinearly, R and G have a 0.5 contour that is a smooth coastline or cliff line.
static func depth_image(map: MapData) -> Image:
	var size := map.width * map.height
	var water := PackedByteArray()
	var mountain := PackedByteArray()
	water.resize(size)
	mountain.resize(size)
	for i in size:
		water[i] = 1 if MapData.terrain_navigable(map.terrain[i]) else 0
		mountain[i] = 1 if map.terrain[i] in RAISED else 0
	var r := _steps_inside(water, map.width, map.height)
	var g := _steps_inside(mountain, map.width, map.height)
	var bytes := PackedByteArray()
	bytes.resize(size * 3)
	for i in size:
		bytes[i * 3] = roundi(255.0 * r[i] / DEPTH_SCALE)
		bytes[i * 3 + 1] = roundi(255.0 * g[i] / DEPTH_SCALE)
		bytes[i * 3 + 2] = 255 if map.terrain[i] == MapData.Terrain.RAMP else 0
	return Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGB8, bytes)


## Breadth-first steps from every tile outside `mask` into it (outside = 0).
static func _steps_inside(mask: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	var queue := PackedInt32Array()
	for i in w * h:
		if mask[i] != 0:
			dist[i] = DEPTH_SCALE
		else:
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % w
		var y := i / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if dist[j] > dist[i] + 1:
					dist[j] = dist[i] + 1
					queue.append(j)
	return dist


func _draw() -> void:
	if _map == null:
		return
	draw_rect(Iso.map_world_rect(_map.width, _map.height).grow(VOID_MARGIN), Color.WHITE)

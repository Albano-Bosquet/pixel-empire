class_name TerrainRenderer
extends Node2D
## Draws the whole terrain with terrain.gdshader in a single quad.
## Example: var tr := TerrainRenderer.new(); add_child(tr); tr.build(map)

const SHADER := preload("res://assets/shaders/terrain.gdshader")
const VOID_MARGIN := 2400.0

var _map: MapData
var _map_tex: ImageTexture
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
	_material.set_shader_parameter("terrain_map", _map_tex)
	_material.set_shader_parameter("map_size", Vector2(map.width, map.height))
	queue_redraw()


## Re-uploads terrain after it changes (e.g. future farms/roads).
func refresh() -> void:
	if _map_tex:
		_map_tex.update(Image.create_from_data(_map.width, _map.height, false, Image.FORMAT_R8, _map.terrain))


func _draw() -> void:
	if _map == null:
		return
	draw_rect(Iso.map_world_rect(_map.width, _map.height).grow(VOID_MARGIN), Color.WHITE)

class_name ResourceNode
extends Entity
## A harvestable deposit occupying one tile (tree, gold, stone, forage).
## Data: resources_nodes.json. Villagers drain it through take().

signal depleted(node: ResourceNode)

var resource_type := "wood"
## Remaining resource; fractional while being gathered, displayed rounded up.
var amount := 0.0
var _sprite := Sprite2D.new()


func setup(id: String, node_def: Dictionary, tile_pos: Vector2i, variant: int) -> void:
	kind = Kind.RESOURCE
	type_id = id
	def = node_def
	resource_type = def.get("resource", "wood")
	amount = float(def.get("amount", 100))
	max_hp = int(amount)
	hp = max_hp
	shadow_sprite = ""
	ring_sprite = "ring_m"
	ring_color = Color("#f2e3a0")
	var sprites: Array = def.get("sprites", [])
	var sprite_name: String = sprites[variant % sprites.size()]
	var region := SpriteLibrary.prop(sprite_name)
	var rect: Rect2 = region["rect"]
	_sprite.texture = SpriteLibrary.props_texture()
	_sprite.region_enabled = true
	_sprite.region_rect = rect
	_sprite.centered = false
	_sprite.offset = -region["anchor"]
	add_child(_sprite)
	pick_rect = Rect2(-region["anchor"], rect.size).grow(-4)
	set_grid_pos(Iso.tile_center(tile_pos))


func is_depleted() -> bool:
	return amount <= 0.0


func remaining() -> int:
	return ceili(amount)


## Removes up to `wanted` units; returns what was actually taken.
## Emits `depleted` once when the node runs out.
func take(wanted: float) -> float:
	if amount <= 0.0:
		return 0.0
	var got := minf(wanted, amount)
	amount -= got
	hp = ceili(amount)
	if amount <= 0.0:
		amount = 0.0
		depleted.emit(self)
	return got


func portrait_region() -> Rect2:
	return _sprite.region_rect

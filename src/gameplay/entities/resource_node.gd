class_name ResourceNode
extends Entity
## A harvestable deposit occupying one tile (tree, gold, stone, forage).
## Data: resources_nodes.json. Villagers drain it through take().

signal depleted(node: ResourceNode)

var resource_type := "wood"
## Sprite variant picked at map generation (kept by saves).
var variant := 0
## Facing of the animal a carcass came from (kept by saves).
var carcass_facing := 0
## Remaining resource; fractional while being gathered, displayed rounded up.
var amount := 0.0
var _sprite := Sprite2D.new()


func setup(id: String, node_def: Dictionary, tile_pos: Vector2i, variant_index: int) -> void:
	kind = Kind.RESOURCE
	type_id = id
	variant = variant_index
	def = node_def
	resource_type = def.get("resource", "wood")
	amount = float(def.get("amount", 100))
	max_hp = int(amount)
	hp = max_hp
	shadow_sprite = ""
	ring_sprite = "ring_m"
	ring_color = Color("#f2e3a0")
	var sprites: Array = def.get("sprites", [])
	var sprite_name: String = sprites[variant_index % sprites.size()]
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


## A food carcass left by a dead animal: shows the animal's last death frame.
func setup_carcass(animal: Unit, food: float) -> void:
	kind = Kind.RESOURCE
	type_id = "carcass_" + animal.type_id
	def = {"resource": "food", "amount": food, "carcass": true, "display_name": animal.display_name()}
	resource_type = "food"
	amount = food
	max_hp = int(food)
	hp = max_hp
	shadow_sprite = ""
	ring_sprite = "ring_s"
	ring_color = Color("#f2e3a0")
	var src: Sprite2D = animal.body_sprite()
	_sprite.texture = src.texture
	_sprite.hframes = src.hframes
	_sprite.vframes = src.vframes
	_sprite.centered = false
	_sprite.offset = src.offset
	_sprite.flip_h = src.flip_h
	_sprite.frame = animal.final_death_frame()
	carcass_facing = animal.facing
	add_child(_sprite)
	pick_rect = Rect2(-12, -16, 24, 18)
	z_index = -1
	set_grid_pos(animal.grid_pos)


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
	if not _sprite.region_enabled:
		var fw := _sprite.texture.get_width() / maxi(1, _sprite.hframes)
		var fh := _sprite.texture.get_height() / maxi(1, _sprite.vframes)
		return Rect2((_sprite.frame % _sprite.hframes) * fw, (_sprite.frame / _sprite.hframes) * fh, fw, fh)
	return _sprite.region_rect


## Texture the portrait region refers to (props atlas, or the animal sheet for carcasses).
func portrait_texture() -> Texture2D:
	return _sprite.texture

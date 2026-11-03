class_name Entity
extends Node2D
## Base for everything that lives on the map grid (units, resources, buildings).
## Simulation state is in grid space (`grid_pos`); `position` is derived.

## Emitted after damage is applied; `attacker` may be null (e.g. splash from a freed unit).
signal damaged(entity: Entity, attacker: Entity, amount: int)
## Emitted once when hp reaches 0.
signal killed(entity: Entity, attacker: Entity)

enum Kind { UNIT, RESOURCE, BUILDING }

const GAIA := 0

var entity_id := 0
var kind: Kind = Kind.UNIT
var type_id := ""
var def: Dictionary = {}
var owner_id := GAIA
var grid_pos := Vector2.ZERO
var max_hp := 1
var hp := 1
var selectable := true
var selected := false:
	set(v):
		if selected != v:
			selected = v
			queue_redraw()
## Local-space rectangle used for mouse picking.
var pick_rect := Rect2(-12, -36, 24, 38)
var shadow_sprite := "shadow_s"
var ring_sprite := "ring_s"
var ring_color := Color.WHITE
var dead := false
## Technology bonuses (TechSystem).
var attack_bonus := 0
var armor_bonus := {"melee": 0, "pierce": 0}
## Seconds since the last hit (drives temporary health bars).
var since_damaged := INF


func set_grid_pos(g: Vector2) -> void:
	grid_pos = g
	position = Iso.grid_to_world(g).round()


func tile() -> Vector2i:
	return Iso.tile_of(grid_pos)


func is_alive() -> bool:
	return not dead and is_instance_valid(self)


func armor(attack_type: String) -> int:
	var a: Dictionary = def.get("armor", {})
	var kind := "pierce" if attack_type == "pierce" else "melee"
	return int(a.get(kind, 0)) + int(armor_bonus.get(kind, 0))


func classes() -> Array:
	return def.get("classes", [])


## Applies already-computed damage. Returns true if this hit killed the entity.
func take_damage(amount: int, attacker: Entity) -> bool:
	if dead:
		return false
	hp = maxi(0, hp - amount)
	since_damaged = 0.0
	damaged.emit(self, attacker, amount)
	if hp <= 0:
		dead = true
		selectable = false
		killed.emit(self, attacker)
		return true
	return false


func display_name() -> String:
	return String(def.get("display_name", type_id))


func global_pick_rect() -> Rect2:
	return Rect2(position + pick_rect.position, pick_rect.size)


## True if the world point should pick this entity (mouse selection / right-click target).
func hit_test(world: Vector2) -> bool:
	return global_pick_rect().has_point(world)


func _draw() -> void:
	if shadow_sprite != "":
		SpriteLibrary.draw_prop(self, shadow_sprite, Vector2.ZERO)
	if selected and ring_sprite != "":
		SpriteLibrary.draw_prop(self, ring_sprite, Vector2.ZERO, ring_color)

class_name DecorLayer
extends Node2D
## Flat ground decoration (grass tufts, flowers, pebbles), below all entities.
## Items are split into square chunks of the world, each a canvas item of its
## own, so the renderer skips every chunk off screen. Tall decor (shrubs) is
## spawned as y-sorted sprites by the Game instead.

## Side of a chunk in world pixels.
const CHUNK_SIZE := 1024.0


func build(map: MapData) -> void:
	for child in get_children():
		child.queue_free()
	var chunks := {}
	for d in map.decor:
		if not d["tall"]:
			var pos: Vector2 = Iso.grid_to_world(d["pos"]).round()
			var key := Vector2i((pos / CHUNK_SIZE).floor())
			chunks.get_or_add(key, []).append({"sprite": d["sprite"], "pos": pos})
	for key in chunks:
		var chunk := Chunk.new()
		chunk.items = chunks[key]
		chunk.items.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
		add_child(chunk)


## One chunk's sprites, drawn in a single canvas item.
class Chunk extends Node2D:
	var items: Array = []

	func _draw() -> void:
		for it in items:
			SpriteLibrary.draw_prop(self, it["sprite"], it["pos"])

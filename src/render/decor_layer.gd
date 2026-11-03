class_name DecorLayer
extends Node2D
## Flat ground decoration (grass tufts, flowers, pebbles) drawn in one node,
## below all entities. Tall decor (crags, shrubs) is spawned as y-sorted
## sprites by the Game instead.

var _items: Array[Dictionary] = []


func build(map: MapData) -> void:
	_items.clear()
	for d in map.decor:
		if not d["tall"]:
			_items.append({"sprite": d["sprite"], "pos": Iso.grid_to_world(d["pos"]).round()})
	_items.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
	queue_redraw()


func _draw() -> void:
	for it in _items:
		SpriteLibrary.draw_prop(self, it["sprite"], it["pos"])

class_name MapData
extends RefCounted
## Grid model of a generated map: terrain per tile, static blockers, start
## positions and the spawn lists the Game turns into entities.

enum Terrain { DEEP_WATER, WATER, SAND, GRASS, MEADOW, FOREST, DIRT, PATH, ROCKY, MOUNTAIN }

const IMPASSABLE: Array[int] = [Terrain.DEEP_WATER, Terrain.WATER, Terrain.MOUNTAIN]

var width: int
var height: int
var seed: int
var terrain: PackedByteArray
var elevation: PackedFloat32Array
var moisture: PackedFloat32Array
## 1 where a static object (tree, mine, building) occupies the tile.
var blocked: PackedByteArray
## 1 where a walkable structure (farm) sits: no other building may overlap it.
var occupied: PackedByteArray
var start_positions: Array[Vector2i] = []
## Each: {"type": String (resources_nodes.json id), "tile": Vector2i, "variant": int}
var resource_spawns: Array[Dictionary] = []
## Each: {"sprite": String (props atlas key), "pos": Vector2 (grid), "tall": bool}
var decor: Array[Dictionary] = []


func _init(w: int, h: int, map_seed: int) -> void:
	width = w
	height = h
	seed = map_seed
	terrain.resize(w * h)
	terrain.fill(Terrain.GRASS)
	elevation.resize(w * h)
	moisture.resize(w * h)
	blocked.resize(w * h)
	occupied.resize(w * h)


func index(t: Vector2i) -> int:
	return t.y * width + t.x


func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < width and t.y < height


func get_terrain(t: Vector2i) -> int:
	return terrain[index(t)]


func set_terrain(t: Vector2i, value: int) -> void:
	terrain[index(t)] = value


static func terrain_passable(id: int) -> bool:
	return not IMPASSABLE.has(id)


## Water ships can sail on.
static func terrain_navigable(id: int) -> bool:
	return id == Terrain.WATER or id == Terrain.DEEP_WATER


## True when a ship can be on the tile (water and not blocked).
func navigable(t: Vector2i) -> bool:
	if not in_bounds(t):
		return false
	var i := index(t)
	return blocked[i] == 0 and terrain_navigable(terrain[i])


## True when units can stand on the tile (terrain passable and not blocked).
func walkable(t: Vector2i) -> bool:
	if not in_bounds(t):
		return false
	var i := index(t)
	return blocked[i] == 0 and terrain_passable(terrain[i])


func is_blocked(t: Vector2i) -> bool:
	return blocked[index(t)] != 0


func set_blocked(t: Vector2i, value: bool) -> void:
	blocked[index(t)] = 1 if value else 0


## Flood fill over walkable tiles; returns the number of reachable tiles and
## writes reached flags into `out_reached` (resized to width*height).
func flood_fill(from: Vector2i, out_reached: PackedByteArray) -> int:
	out_reached.resize(width * height)
	out_reached.fill(0)
	if not walkable(from):
		return 0
	var stack: Array[Vector2i] = [from]
	out_reached[index(from)] = 1
	var count := 0
	while not stack.is_empty():
		var t: Vector2i = stack.pop_back()
		count += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + o
			if in_bounds(n) and out_reached[index(n)] == 0 and walkable(n):
				out_reached[index(n)] = 1
				stack.append(n)
	return count

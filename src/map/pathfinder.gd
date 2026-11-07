class_name Pathfinder
extends RefCounted
## Tile pathfinding over MapData using AStarGrid2D (8-way, no corner cutting),
## with line-of-sight smoothing so units walk straight where they can.
## Example:
##   var pf := Pathfinder.new(map)
##   var waypoints := pf.find_path(unit.grid_pos, target)  # PackedVector2Array in grid space
## Gates (Phase B4): gate tiles are open in the shared grid but solid for every
## player except the gate's owner; pass `owner` to find_path / is_walkable.

var map: MapData
var astar := AStarGrid2D.new()
## True for the ships' grid: water tiles are open, land is solid.
var naval := false
## Gate tile -> owner player id.
var gates: Dictionary = {}
## One byte per tile mirroring astar's solid flags (1 = solid): is_walkable runs
## thousands of times per path, and a byte read is far cheaper than an engine call.
var _solid := PackedByteArray()
var _w := 0
var _h := 0


func _init(map_data: MapData, for_ships: bool = false) -> void:
	map = map_data
	naval = for_ships
	astar.region = Rect2i(0, 0, map.width, map.height)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	_w = map.width
	_h = map.height
	_solid.resize(_w * _h)
	_solid.fill(0)
	for y in map.height:
		for x in map.width:
			var t := Vector2i(x, y)
			if not _open(t):
				_set_solid(t, true)


func _set_solid(t: Vector2i, solid: bool) -> void:
	astar.set_point_solid(t, solid)
	_solid[t.y * _w + t.x] = 1 if solid else 0


func _open(t: Vector2i) -> bool:
	return map.navigable(t) if naval else map.walkable(t)


## Call after MapData.blocked changes for a tile (tree cut, building placed).
func refresh_tile(t: Vector2i) -> void:
	if map.in_bounds(t):
		_set_solid(t, not _open(t))


func is_walkable(t: Vector2i, owner: int = -1) -> bool:
	if t.x < 0 or t.y < 0 or t.x >= _w or t.y >= _h or _solid[t.y * _w + t.x] != 0:
		return false
	return owner < 0 or gates.is_empty() or int(gates.get(t, owner)) == owner


func set_gate(t: Vector2i, owner: int) -> void:
	gates[t] = owner


func clear_gate(t: Vector2i) -> void:
	gates.erase(t)


## Nearest walkable tile to `t` searching square rings up to `max_radius`.
func nearest_walkable(t: Vector2i, max_radius: int = 16, prefer_from: Vector2 = Vector2.INF) -> Vector2i:
	if is_walkable(t):
		return t
	for r in range(1, max_radius + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var n := t + Vector2i(dx, dy)
				if not is_walkable(n):
					continue
				var d := Vector2(dx, dy).length_squared()
				if prefer_from != Vector2.INF:
					d += Iso.tile_center(n).distance_squared_to(prefer_from) * 0.01
				if d < best_d:
					best_d = d
					best = n
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Best standing spot next to a footprint (tiles in `rect`) for a unit at `from`:
## the walkable tile in the surrounding ring closest to `from`, nudged towards
## the footprint. Returns Vector2.INF when the footprint is fully enclosed.
## With `spread` > 0 a random spot among those up to `spread` tiles farther than
## the best is chosen, so crowds (e.g. villagers dropping off) fan out.
## `pull` (0..1) moves each spot from the neighbour tile centre towards the rect
## edge; workers use a larger pull so they stand right against trees and rocks.
func approach(rect: Rect2i, from: Vector2, spread: float = 0.0, pull: float = 0.25) -> Vector2:
	var spots: Array[Vector2] = []
	var dists: Array[float] = []
	var best_d := INF
	var ring := rect.grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var t := Vector2i(x, y)
			if rect.has_point(t) or not is_walkable(t):
				continue
			var cpos := Iso.tile_center(t)
			var d := cpos.distance_to(from)
			var closest := Vector2(clampf(cpos.x, rect.position.x, rect.end.x), clampf(cpos.y, rect.position.y, rect.end.y))
			spots.append(cpos + (closest - cpos) * pull)
			dists.append(d)
			best_d = minf(best_d, d)
	if spots.is_empty():
		return Vector2.INF
	var pool: Array[Vector2] = []
	for i in spots.size():
		if dists[i] <= best_d + spread + 0.001:
			pool.append(spots[i])
	return pool[randi() % pool.size()] if spread > 0.0 else pool[0]


## Grid-space waypoints from `from` to `to` (excluding the start point).
## Returns an empty array when no path exists. If `to` is not walkable the path
## ends at the nearest walkable tile (preferring the side facing `from`).
func find_path(from: Vector2, to: Vector2, owner: int = -1) -> PackedVector2Array:
	# Foreign gates are solid for this search only.
	var closed: Array[Vector2i] = []
	if owner >= 0:
		for g in gates:
			if int(gates[g]) != owner and not astar.is_point_solid(g):
				_set_solid(g, true)
				closed.append(g)
	var path := _find_path(from, to, owner)
	for g in closed:
		_set_solid(g, false)
	return path


func _find_path(from: Vector2, to: Vector2, owner: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var start := nearest_walkable(Iso.tile_of(from), 4)
	if start.x < 0:
		return out
	var goal_tile := Iso.tile_of(to)
	var exact_goal := to
	if not is_walkable(goal_tile):
		goal_tile = nearest_walkable(goal_tile, 16, from)
		if goal_tile.x < 0:
			return out
		exact_goal = Iso.tile_center(goal_tile)
	if start == goal_tile:
		out.append(exact_goal)
		return out
	var ids := astar.get_id_path(start, goal_tile, true)
	if ids.is_empty():
		return out
	var raw := PackedVector2Array()
	raw.append(from)
	for i in range(1, ids.size()):
		raw.append(Iso.tile_center(ids[i]))
	if ids[ids.size() - 1] == goal_tile:
		raw[raw.size() - 1] = exact_goal
	return _smooth(raw, owner)


## Greedy string pulling: keep the farthest waypoint still in line of sight.
func _smooth(raw: PackedVector2Array, owner: int = -1) -> PackedVector2Array:
	var out := PackedVector2Array()
	var anchor := 0
	var i := 1
	while i < raw.size():
		var next := i + 1
		if next < raw.size() and line_walkable(raw[anchor], raw[next], 0.3, owner):
			i = next
			continue
		out.append(raw[i])
		anchor = i
		i += 1
	return out


## True if a unit-sized body can walk straight from a to b (grid space).
func line_walkable(a: Vector2, b: Vector2, half_width: float = 0.3, owner: int = -1) -> bool:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return true
	var dir := d / length
	var perp := Vector2(-dir.y, dir.x) * half_width
	var steps := ceili(length / 0.25)
	# Samples are a quarter tile apart: each lane only checks a tile when it enters it.
	var mid := Vector2i(-9999, 0)
	var left := mid
	var right := mid
	for s in steps + 1:
		var p := a + d * (float(s) / steps)
		var t := Iso.tile_of(p)
		if t != mid:
			mid = t
			if not is_walkable(t, owner):
				return false
		t = Iso.tile_of(p + perp)
		if t != left:
			left = t
			if not is_walkable(t, owner):
				return false
		t = Iso.tile_of(p - perp)
		if t != right:
			right = t
			if not is_walkable(t, owner):
				return false
	return true

class_name SpatialHash
extends RefCounted
## Uniform bucket grid over tiles for neighbour queries. Rebuilt each frame
## without reallocating buckets (cleared in place).
## Example:
##   hash.clear(); for u in units: hash.insert(u, u.grid_pos)
##   hash.query(pos, 1.0, out_array)

var _cell: float
var _cols: int
var _rows: int
var _buckets: Array = []
## Indices of the buckets holding items, so clear() skips the empty ones.
var _used := PackedInt32Array()


func _init(map_w: int, map_h: int, cell_size: float = 2.0) -> void:
	_cell = cell_size
	_cols = ceili(map_w / cell_size) + 1
	_rows = ceili(map_h / cell_size) + 1
	_buckets.resize(_cols * _rows)
	for i in _buckets.size():
		_buckets[i] = []


func clear() -> void:
	for i in _used:
		_buckets[i].clear()
	_used.clear()


func insert(item: Object, pos: Vector2) -> void:
	var i := _index(pos)
	var bucket: Array = _buckets[i]
	if bucket.is_empty():
		_used.append(i)
	bucket.append(item)


## Appends to `out` every item whose bucket overlaps the query square.
func query(pos: Vector2, radius: float, out: Array) -> void:
	var x0 := clampi(floori((pos.x - radius) / _cell), 0, _cols - 1)
	var x1 := clampi(floori((pos.x + radius) / _cell), 0, _cols - 1)
	var y0 := clampi(floori((pos.y - radius) / _cell), 0, _rows - 1)
	var y1 := clampi(floori((pos.y + radius) / _cell), 0, _rows - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append_array(_buckets[y * _cols + x])


func _index(pos: Vector2) -> int:
	var x := clampi(floori(pos.x / _cell), 0, _cols - 1)
	var y := clampi(floori(pos.y / _cell), 0, _rows - 1)
	return y * _cols + x

class_name Iso
extends RefCounted
## Isometric projection between grid space (float tiles) and world space (pixels).
##
## Grid (0.5, 0.5) is the centre of tile (0, 0). Tiles are 64x32 diamonds.
## Example:
##   var world := Iso.grid_to_world(Vector2(10.5, 4.5))
##   var tile := Iso.tile_of(Iso.world_to_grid(get_global_mouse_position()))

const TILE_W: float = 64.0
const TILE_H: float = 32.0
const HALF_W: float = 32.0
const HALF_H: float = 16.0

## Direction indices in 22.5 degree steps, clockwise-from-viewer order:
## 0=S 2=SE 4=E 6=NE 8=N 10=NW 12=W 14=SW (odd indices are the in-betweens).
const DIR_COUNT: int = 16


## Returns `v` if it is a live object, else null (safe before typed assignment;
## Godot errors when a freed instance is assigned to a typed variable).
static func alive(v: Variant) -> Object:
	return v if is_instance_valid(v) else null


static func grid_to_world(g: Vector2) -> Vector2:
	return Vector2((g.x - g.y) * HALF_W, (g.x + g.y) * HALF_H)


static func world_to_grid(w: Vector2) -> Vector2:
	return Vector2((w.x / HALF_W + w.y / HALF_H) * 0.5, (w.y / HALF_H - w.x / HALF_W) * 0.5)


static func tile_of(g: Vector2) -> Vector2i:
	return Vector2i(floori(g.x), floori(g.y))


static func tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x + 0.5, t.y + 0.5)


## Converts a grid-space direction to a screen-facing index (0..DIR_COUNT-1).
static func direction_index(grid_dir: Vector2) -> int:
	var screen := Vector2(grid_dir.x - grid_dir.y, (grid_dir.x + grid_dir.y) * 0.5)
	if screen.length_squared() < 0.000001:
		return 0
	var idx := roundi((PI * 0.5 - screen.angle()) / (TAU / DIR_COUNT))
	return posmod(idx, DIR_COUNT)


## Maps a direction index to the drawn sheet row (0..DIR_COUNT/2) and whether to flip horizontally.
static func sheet_direction(dir: int) -> Vector2i:
	var half := DIR_COUNT / 2
	if dir <= half:
		return Vector2i(dir, 0)
	return Vector2i(DIR_COUNT - dir, 1)


## Signed shortest step count from direction `from` to `to` (-DIR_COUNT/2..DIR_COUNT/2).
static func direction_delta(from: int, to: int) -> int:
	var d := posmod(to - from, DIR_COUNT)
	return d - DIR_COUNT if d > DIR_COUNT / 2 else d


## Axis-aligned world-space bounds of a w x h grid.
static func map_world_rect(w: int, h: int) -> Rect2:
	var left := grid_to_world(Vector2(0, h)).x
	var right := grid_to_world(Vector2(w, 0)).x
	var bottom := grid_to_world(Vector2(w, h)).y
	return Rect2(left, 0.0, right - left, bottom)

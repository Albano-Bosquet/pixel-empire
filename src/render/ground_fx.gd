class_name GroundFx
extends Node2D
## Short-lived ground effects drawn under entities (move-order markers).

const MARKER_TIME := 0.6

var _markers: Array[Dictionary] = []


func add_move_marker(world_pos: Vector2) -> void:
	_markers.append({"pos": world_pos.round(), "t": 0.0})
	queue_redraw()


func _process(delta: float) -> void:
	if _markers.is_empty():
		return
	for m in _markers:
		m["t"] += delta
	_markers = _markers.filter(func(m): return m["t"] < MARKER_TIME)
	queue_redraw()


func _draw() -> void:
	for m in _markers:
		var k: float = m["t"] / MARKER_TIME
		# Pixel-stepped shrinking ring (4 discrete sizes) plus a centre pip.
		var s: float = 1.0 - floorf(k * 4.0) / 4.0 * 0.7
		var col := Color(0.55, 1.0, 0.45, 1.0 - k * 0.6)
		draw_set_transform(m["pos"], 0.0, Vector2(s, s))
		SpriteLibrary.draw_prop(self, "ring_m", Vector2.ZERO, col)
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(m["pos"] - Vector2(1, 1), Vector2(2, 2)), col)

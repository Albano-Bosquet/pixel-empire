class_name GroundFx
extends Node2D
## Short-lived ground effects drawn under entities: move-order markers and the
## blinking ring under an order's target (AoE-style: gather, build, attack...).

const MARKER_TIME := 0.6
## Target ring: total time on screen and number of on/off blinks.
const TARGET_TIME := 1.1
const TARGET_BLINKS := 3
const TARGET_FRIENDLY := Color(0.55, 1.0, 0.45)
const TARGET_HOSTILE := Color(1.0, 0.32, 0.25)

var _markers: Array[Dictionary] = []
var _targets: Array[Dictionary] = []


func add_move_marker(world_pos: Vector2) -> void:
	_markers.append({"pos": world_pos.round(), "t": 0.0})
	queue_redraw()


## Blinks a ring under `e` (follows it if it moves). Red when `hostile`.
## Replaces any ring still showing, so only the latest order's target blinks.
func add_target_marker(e: Entity, hostile: bool) -> void:
	_targets = [{"e": e, "t": 0.0, "col": TARGET_HOSTILE if hostile else TARGET_FRIENDLY}]
	queue_redraw()


func _process(delta: float) -> void:
	if _markers.is_empty() and _targets.is_empty():
		return
	for m in _markers:
		m["t"] += delta
	_markers = _markers.filter(func(m): return m["t"] < MARKER_TIME)
	for m in _targets:
		m["t"] += delta
	_targets = _targets.filter(func(m): return m["t"] < TARGET_TIME and is_instance_valid(m["e"]) and not m["e"].dead)
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
	for m in _targets:
		# On during the first half of each blink period.
		if fmod(m["t"] * TARGET_BLINKS / TARGET_TIME, 1.0) > 0.55:
			continue
		var e: Entity = m["e"]
		var tiles := float((e as Building).size) if e is Building else 1.0
		var rx := tiles * Iso.HALF_W * 0.78
		if e is Unit:
			rx = maxf(10.0, (e as Unit).radius * Iso.TILE_W * 0.9)
		var col: Color = m["col"]
		# Iso ellipse: squash a circle to half height; dark under-stroke keeps it readable on grass.
		draw_set_transform(e.position.round(), 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, rx, 0.0, TAU, 32, Color(0.05, 0.05, 0.08, 0.55), 4.0)
		draw_arc(Vector2.ZERO, rx, 0.0, TAU, 32, col, 2.0)
		draw_set_transform(Vector2.ZERO)

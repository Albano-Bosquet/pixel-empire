class_name TutorialPanel
extends CanvasLayer
## On-screen side of TutorialSystem: the card with the current step (top left,
## under the resource bar) and the bouncing arrow on what to use next. An arrow
## whose target is off screen or under the HUD waits at the edge, pointing at it.

const PANEL_WIDTH := 340.0
## Wrapped labels need a width of their own to report a sensible height.
const TEXT_WIDTH := 320.0
## Height a finger can hit on touch screens.
const TOUCH_BUTTON_HEIGHT := 44.0
const PANEL_TOP := 52.0
const PANEL_LEFT := 8.0
## Keeps the edge arrow off the top bar and the selection panel.
const EDGE_TOP := 96.0
const EDGE_BOTTOM := 210.0
const EDGE_SIDE := 44.0

var _game: Game
var _tutorial: TutorialSystem
var _panel: PanelContainer
var _count: Label
var _title: Label
var _text: Label
var _progress: Label
var _skip: Button
var _arrow := ArrowDraw.new()
var _time := 0.0


func setup(game: Game, tutorial: TutorialSystem) -> void:
	_game = game
	_tutorial = tutorial
	layer = 12
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_arrow)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Hud.panel_style())
	_panel.position = Vector2(PANEL_LEFT, PANEL_TOP)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	_count = UiStyle.label("", 13, UiStyle.TEXT_DIM)
	v.add_child(_count)
	_title = UiStyle.label("", 19, UiStyle.GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = TEXT_WIDTH
	v.add_child(_title)
	_text = UiStyle.label("", 15, UiStyle.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = TEXT_WIDTH
	v.add_child(_text)
	var row := HBoxContainer.new()
	v.add_child(row)
	_progress = UiStyle.label("", 15, UiStyle.GOLD)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_progress)
	_skip = UiStyle.button(tr("Skip step"), 0)
	_skip.focus_mode = Control.FOCUS_NONE
	if _game.touch != null and _game.touch.enabled:
		_skip.custom_minimum_size.y = TOUCH_BUTTON_HEIGHT
	_skip.pressed.connect(_tutorial.advance)
	row.add_child(_skip)
	_tutorial.step_changed.connect(_show_step)
	Loc.language_changed.connect(_on_language_changed)
	_show_step()


func _on_language_changed(_code: String) -> void:
	_skip.text = tr("Skip step")
	_show_step()


func _show_step() -> void:
	_panel.visible = not _tutorial.over
	var step := _tutorial.current()
	_count.text = tr("Tutorial · step %d of %d") % [_tutorial.index + 1, _tutorial.steps.size()]
	_title.text = tr(String(step.get("title", "")))
	_text.text = tr(TutorialSystem.step_text(step, _game.touch != null and _game.touch.enabled))
	_skip.visible = _tutorial.can_skip()
	_panel.reset_size()


func _process(delta: float) -> void:
	if _game == null:
		return
	_time += delta
	var have: Array = _tutorial.current_progress()
	_progress.text = "%d / %d" % [have[0], have[1]] if not have.is_empty() else ""
	var bob := absf(sin(_time * 4.0)) * 10.0
	var p := _tutorial.pointer()
	if p.has("control"):
		var r: Rect2 = p["control"].get_global_rect()
		_arrow.point_at(Vector2(r.get_center().x, r.position.y - 4.0 - bob), 0.0)
	elif p.has("entity"):
		_point_at_world(p["entity"], bob)
	else:
		_arrow.hide_arrow()


## Above the target when it is in the clear part of the screen, otherwise at the
## nearest edge of that area, turned towards it.
func _point_at_world(e: Entity, bob: float) -> void:
	var zoom := _game.camera.zoom.y
	var at := _game.screen_from_world(e.global_position)
	var vp := _arrow.get_viewport_rect().size
	var clear := Rect2(EDGE_SIDE, EDGE_TOP, vp.x - EDGE_SIDE * 2.0, vp.y - EDGE_TOP - EDGE_BOTTOM)
	if clear.has_point(at):
		var lift := 34.0 * zoom if e is Unit else 10.0 * zoom
		_arrow.point_at(at - Vector2(0, lift + bob), 0.0)
		return
	var edge := at.clamp(clear.position, clear.end)
	var dir := (at - edge).normalized()
	_arrow.point_at(edge - dir * bob, Vector2.DOWN.angle_to(dir))


## Draws the arrow in screen space. Its tip is at the given point; angle 0 points down.
class ArrowDraw extends Control:
	const SHAPE := [Vector2(0, 0), Vector2(-20, -24), Vector2(-9, -24), Vector2(-9, -50), Vector2(9, -50), Vector2(9, -24), Vector2(20, -24)]
	const FILL := Color("#ffd45e")
	const EDGE := Color("#140e09")

	var _shown := false
	var _tip := Vector2.ZERO
	var _angle := 0.0

	func point_at(tip: Vector2, angle: float) -> void:
		_shown = true
		_tip = tip.round()
		_angle = angle
		queue_redraw()

	func hide_arrow() -> void:
		if _shown:
			_shown = false
			queue_redraw()

	## Whether the arrow is on screen, and where (tests and smoke checks).
	func tip() -> Variant:
		return _tip if _shown else null

	func _draw() -> void:
		if not _shown:
			return
		draw_set_transform(_tip, _angle, Vector2.ONE)
		var pts := PackedVector2Array(SHAPE)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_colored_polygon(pts, FILL)
		draw_polyline(outline, EDGE, 4.0)

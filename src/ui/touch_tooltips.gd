class_name TouchTooltips
extends CanvasLayer
## Touch screens have no hover, so Godot's tooltips never appear there. Holding
## a finger on a HUD control that has a tooltip shows it as an InfoCard (the
## same card the PC shows on hover, without keyboard hints); lifting the finger
## does not run the button, and the card stays a moment so it can be read.
## A quick tap still presses the button as before.
## Settings (touch_settings.json): long_press_ms, drag_threshold_px,
## long_press_vibrate_ms, tip_linger_ms.
## Example: var tips := TouchTooltips.new(); hud.add_child(tips); tips.setup(hud, GameData.touch)

## Emitted when a card appears (tests).
signal card_shown(target: Control)

## The card on screen, or null.
var card: PanelContainer
var _root: Node
var _cfg: Dictionary = {}
var _holding := false
var _press_ms := 0
var _press_pos := Vector2.ZERO
var _target: Control
var _blocked: BaseButton
var _hide_ms := -1


## `root`: the subtree whose controls get hold-to-see tooltips (the HUD).
func setup(root: Node, cfg: Dictionary) -> void:
	_root = root
	_cfg = cfg
	layer = 60


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			hide_card()
			_target = control_at(event.position)
			_holding = _target != null
			_press_ms = Time.get_ticks_msec()
			_press_pos = event.position
		else:
			_holding = false
			if card != null:
				_hide_ms = Time.get_ticks_msec() + int(_cfg.get("tip_linger_ms", 2500))
			# After the GUI has seen the release, so the held button is not run.
			_unblock.call_deferred()
	elif event is InputEventMouseMotion and _holding and card == null:
		if event.position.distance_to(_press_pos) > float(_cfg.get("drag_threshold_px", 14)):
			_holding = false


func _process(_delta: float) -> void:
	if _holding and card == null and Time.get_ticks_msec() - _press_ms >= int(_cfg.get("long_press_ms", 450)):
		# Panels that rebuild themselves (technology tree) may have replaced it.
		if not is_instance_valid(_target) or not _target.is_visible_in_tree():
			_target = control_at(_press_pos)
		if _target != null:
			show_for(_target)
		else:
			_holding = false
	if card != null and not _holding and _hide_ms >= 0 and Time.get_ticks_msec() >= _hide_ms:
		hide_card()


## Shows the card of `target` next to it; a held button is kept from firing.
func show_for(target: Control) -> void:
	hide_card()
	var info: Dictionary = {}
	if target is InfoButton or target is InfoPanel:
		info = target.info
	if info.is_empty():
		info = {"text": target.tooltip_text}
	card = InfoCard.build(info, false, true)
	add_child(card)
	card.reset_size()
	var size := card.get_combined_minimum_size()
	var view := card.get_viewport_rect().size
	var r := target.get_global_rect()
	var pos := Vector2(r.get_center().x - size.x * 0.5, r.position.y - size.y - 8.0)
	if pos.y < 4.0:
		pos.y = r.end.y + 8.0
	pos.x = clampf(pos.x, 4.0, maxf(4.0, view.x - size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, view.y - size.y - 4.0))
	card.position = pos
	_hide_ms = -1
	if target is BaseButton and not target.disabled:
		target.disabled = true  # drops the press, so lifting the finger does nothing
		_blocked = target
	Input.vibrate_handheld(int(_cfg.get("long_press_vibrate_ms", 25)))
	card_shown.emit(target)


func hide_card() -> void:
	if card != null:
		card.queue_free()
		card = null
	_hide_ms = -1


## Topmost visible control under `pos` (viewport coordinates) with a tooltip.
func control_at(pos: Vector2) -> Control:
	if _root == null:
		return null
	var found: Array = [null]
	_scan(_root, pos, Rect2(-1e9, -1e9, 2e9, 2e9), found)
	return found[0]


func _scan(n: Node, pos: Vector2, clip: Rect2, found: Array) -> void:
	if n == self:
		return
	if n is CanvasItem and not n.visible:
		return
	if n is CanvasLayer and not n.visible:
		return
	var c := n as Control
	if c != null:
		var r := c.get_global_rect()
		if c.clip_contents:
			clip = clip.intersection(r)
		if not clip.has_point(pos):
			return
		var tipped: bool = c.tooltip_text != "" or ((c is InfoButton or c is InfoPanel) and not c.info.is_empty())
		if tipped and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and r.has_point(pos):
			found[0] = c
	for ch in n.get_children():
		_scan(ch, pos, clip, found)


func _unblock() -> void:
	if is_instance_valid(_blocked):
		_blocked.disabled = false
	_blocked = null

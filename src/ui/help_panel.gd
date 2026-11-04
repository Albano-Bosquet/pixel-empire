class_name HelpPanel
extends CanvasLayer
## Keyboard and mouse reference (F1 in a match), or the touch gestures on touch
## screens. Closes with F1, Esc or the button.

const ROWS := [
	["Left click / drag", "Select (Shift adds)"],
	["Double click / Ctrl+click", "Select all of that type on screen"],
	["Right click", "Move, gather, build, attack"],
	["Shift + right click", "Queue a waypoint"],
	["Ctrl + 0-9", "Make a control group"],
	["Shift + 0-9", "Add the selection to a group"],
	["0-9 (twice)", "Recall a group (and centre on it)"],
	["Letters on the buttons", "Train, build and research"],
	["Shift + train", "Queue five units"],
	["Period (.)", "Next idle villager"],
	["Comma (,)", "Next idle military unit"],
	["Home", "Select the Town Center"],
	["Ctrl + A", "Select every military unit"],
	["Space", "Jump to the latest attack"],
	["Ctrl + Space", "Centre on the selection"],
	["Delete", "Destroy what is selected"],
	["+ / -", "Game speed (single player)"],
	["F2", "Technology tree"],
	["F5", "Quick save"],
	["F10 / Esc / Pause", "Menu"],
	["F11 / Alt + Enter", "Full screen"],
	["WASD, arrows, screen edges", "Move the camera"],
	["Mouse wheel", "Zoom"],
]

const TOUCH_ROWS := [
	["Tap", "Select a unit (twice: all of that type)"],
	["Tap with units selected", "Move, gather, build, attack"],
	["Hold", "Select anything (buildings too)"],
	["Drag", "Move the camera"],
	["Two fingers", "Move the camera and pinch to zoom"],
	["Area button, then drag", "Select an area"],
	["Building: drag, then lift", "Place it where you lift the finger"],
	["Back button", "Cancel / clear the selection / menu"],
]


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UiStyle.dimmer(0.45))
	var pv: Array = UiStyle.centered_panel(root, 720)
	var v: VBoxContainer = pv[1]
	v.add_child(UiStyle.title(tr("Controls"), 34))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 3)
	v.add_child(grid)
	for row in TOUCH_ROWS if Display.touch_screen() else ROWS:
		grid.add_child(UiStyle.label(tr(row[0]), 15, UiStyle.GOLD))
		grid.add_child(UiStyle.label(tr(row[1]), 15, UiStyle.TEXT))
	var close := UiStyle.button(tr("Close"), 680)
	close.pressed.connect(queue_free)
	v.add_child(close)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F1]:
		queue_free()
		get_viewport().set_input_as_handled()

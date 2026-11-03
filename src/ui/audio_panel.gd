class_name AudioPanel
extends CanvasLayer
## Sound options dialog (main menu and pause menu): one slider per mixer bus
## plus mute. Changes apply at once and are saved by the Audio autoload.

signal closed

## [bus key, label].
const ROWS := [["master", "General"], ["music", "Music"], ["sfx", "Effects"], ["ambient", "Ambience"], ["ui", "Interface"]]


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UiStyle.dimmer(0.45))
	var pv: Array = UiStyle.centered_panel(root, 440)
	var v: VBoxContainer = pv[1]
	v.add_child(UiStyle.title(tr("Sound"), 36))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for row in ROWS:
		var key: String = row[0]
		grid.add_child(UiStyle.label(tr(row[1]), 16, UiStyle.TEXT_DIM))
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = float(Audio.volumes.get(key, 0.8))
		s.custom_minimum_size = Vector2(220, 28)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(s)
		var pct := UiStyle.label("%d%%" % roundi(s.value * 100.0), 15, UiStyle.TEXT)
		pct.custom_minimum_size.x = 52
		grid.add_child(pct)
		s.value_changed.connect(func(val: float) -> void:
			Audio.set_volume(key, val)
			pct.text = "%d%%" % roundi(val * 100.0)
			if key == "ui" or key == "sfx" or key == "master":
				Audio.ui("ui_queue"))
	var mute := CheckButton.new()
	mute.text = tr("Mute all sound")
	mute.button_pressed = Audio.muted
	mute.toggled.connect(func(on: bool) -> void: Audio.set_muted(on))
	v.add_child(mute)
	var close := UiStyle.button(tr("Close"), 400)
	close.pressed.connect(_close)
	v.add_child(close)
	close.grab_focus()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

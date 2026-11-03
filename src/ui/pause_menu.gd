class_name PauseMenu
extends CanvasLayer
## In-game menu (F10, Esc with nothing selected, or the top-bar button).
## Pauses the scene tree while open. Save/load slots arrive in Stage 5.

signal resume_pressed
signal restart_pressed
signal menu_pressed
signal quit_pressed

var _restart: Button


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UiStyle.dimmer(0.5))
	var pv: Array = UiStyle.centered_panel(root, 320)
	var v: VBoxContainer = pv[1]
	v.add_child(UiStyle.title(tr("Paused"), 40))
	for entry in [[tr("Resume"), resume_pressed], [tr("Restart match"), restart_pressed], [tr("Main menu"), menu_pressed], [tr("Quit game"), quit_pressed]]:
		var b := UiStyle.button(entry[0], 280)
		var sig: Signal = entry[1]
		b.pressed.connect(func() -> void: sig.emit())
		v.add_child(b)
		if sig == restart_pressed:
			_restart = b
	var lang := HBoxContainer.new()
	lang.add_child(UiStyle.label(tr("Language"), 16, UiStyle.TEXT_DIM))
	var pick := UiStyle.language_option()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size.x = 0
	lang.add_child(pick)
	v.add_child(lang)
	(v.get_child(1) as Button).grab_focus()


## Multiplayer: no restart; "Main menu" leaves the session.
func set_networked() -> void:
	if _restart:
		_restart.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_F10):
		resume_pressed.emit()
		get_viewport().set_input_as_handled()

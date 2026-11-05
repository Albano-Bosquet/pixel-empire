class_name PauseMenu
extends CanvasLayer
## In-game menu (F10, Esc with nothing selected, or the top-bar button).
## Single player: Main pauses the scene tree while it is open. Multiplayer: it
## opens only for the local player and the match keeps running. Save / load
## (single player), sound options and language live here too.

signal resume_pressed
signal restart_pressed
signal menu_pressed
signal quit_pressed
## A save was picked in the load dialog.
signal load_requested(data: Dictionary)

## The running match (save dialog); set by Main.
var game: Game = null
var _restart: Button
var _title: Label
var _save_btns: Array[Button] = []


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UiStyle.dimmer(0.5))
	var pv: Array = UiStyle.centered_panel(root, 320)
	var v: VBoxContainer = pv[1]
	_title = UiStyle.title(tr("Paused"), 40)
	v.add_child(_title)
	for entry in [[tr("Resume"), resume_pressed], [tr("Restart match"), restart_pressed], [tr("Main menu"), menu_pressed], [tr("Quit game"), quit_pressed]]:
		var b := UiStyle.button(entry[0], 280)
		var sig: Signal = entry[1]
		b.pressed.connect(func() -> void: sig.emit())
		v.add_child(b)
		if sig == restart_pressed:
			_restart = b
	for saving in [true, false]:
		var sb := UiStyle.button(tr("Save game") if saving else tr("Load game"), 280)
		var mode: bool = saving
		sb.pressed.connect(func() -> void:
			var panel := SaveLoadPanel.new()
			panel.setup(mode, game)
			panel.load_requested.connect(func(d: Dictionary) -> void: load_requested.emit(d))
			add_child(panel))
		v.add_child(sb)
		_save_btns.append(sb)
	var snd := UiStyle.button(tr("Sound"), 280)
	snd.pressed.connect(func() -> void: add_child(AudioPanel.new()))
	v.add_child(snd)
	var lang := HBoxContainer.new()
	lang.add_child(UiStyle.label(tr("Language"), 16, UiStyle.TEXT_DIM))
	var pick := UiStyle.language_option()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size.x = 0
	lang.add_child(pick)
	v.add_child(lang)
	v.add_child(UiStyle.fullscreen_toggle())
	(v.get_child(1) as Button).grab_focus()


## Multiplayer: no restart; "Main menu" leaves the session. `live` is true when
## the match keeps running behind the menu (titled "Menu", not "Paused").
func set_networked(live: bool = false) -> void:
	if _restart:
		_restart.visible = false
	for b in _save_btns:
		b.visible = false
	if live and _title:
		_title.text = tr("Menu")


## Esc / F10 close the menu; every other key stops here so game hotkeys do not
## fire behind it while a networked match keeps running.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_F10):
		resume_pressed.emit()
	get_viewport().set_input_as_handled()

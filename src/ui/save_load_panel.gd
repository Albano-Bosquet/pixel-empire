class_name SaveLoadPanel
extends CanvasLayer
## Save / load dialog (pause menu: both; title screen: load only).
## Save mode: a name field and "Save" (new slot), or overwrite a listed save.
## Load mode: pick a save to load, or delete it. Lists SaveGame.list().
## Emits `load_requested(data)`; Main starts the match from the save.

signal load_requested(data: Dictionary)
signal closed

var game: Game = null
var _saving := false
var _list: VBoxContainer
var _name: LineEdit
var _status: Label


## `saving` true shows the save controls; `match` is the running game (save mode).
func setup(saving: bool, match: Game = null) -> void:
	_saving = saving
	game = match


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UiStyle.dimmer(0.5))
	var pv: Array = UiStyle.centered_panel(root, 640)
	var v: VBoxContainer = pv[1]
	v.add_child(UiStyle.title(tr("Save game") if _saving else tr("Load game"), 36))
	if _saving:
		var row := HBoxContainer.new()
		_name = LineEdit.new()
		_name.placeholder_text = tr("Save name")
		_name.text = tr("My empire") + " " + Time.get_datetime_string_from_system().replace("T", " ").left(16)
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.custom_minimum_size.y = 36
		row.add_child(_name)
		var save_btn := UiStyle.button(tr("Save"), 140)
		save_btn.pressed.connect(func() -> void: _save("save_%d" % int(Time.get_unix_time_from_system()), _name.text))
		row.add_child(save_btn)
		v.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_status = UiStyle.label("", 14, UiStyle.GOLD)
	v.add_child(_status)
	var close := UiStyle.button(tr("Close"), 600)
	close.pressed.connect(_close)
	v.add_child(close)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var saves := SaveGame.list()
	if saves.is_empty():
		_list.add_child(UiStyle.label(tr("No saved games yet."), 15, UiStyle.TEXT_DIM))
	var ages := MatchConfig.age_names()
	for meta in saves:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var when := Time.get_datetime_string_from_unix_time(int(meta.get("time", 0)) + _tz_offset()).replace("T", " ").left(16)
		var t := float(meta.get("elapsed", 0.0))
		var info := "%s\n%s  ·  %s %d:%02d  ·  %s" % [String(meta.get("title", meta.get("slot", "?"))), when, tr("Time"), int(t) / 60, int(t) % 60,
			tr(ages[clampi(int(meta.get("age", 0)), 0, ages.size() - 1)])]
		var main := UiStyle.button(info, 430)
		main.custom_minimum_size.y = 56
		main.alignment = HORIZONTAL_ALIGNMENT_LEFT
		main.add_theme_font_size_override("font_size", 15)
		var slot := String(meta.get("slot", ""))
		if _saving:
			main.tooltip_text = tr("Overwrite this save")
			main.pressed.connect(func() -> void: _save(slot, String(meta.get("title", slot))))
		else:
			main.pressed.connect(func() -> void: _load(slot))
		row.add_child(main)
		if not _saving:
			var del := UiStyle.button(tr("Delete"), 120)
			del.pressed.connect(func() -> void:
				SaveGame.delete(slot)
				_refresh())
			row.add_child(del)
		_list.add_child(row)


func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _save(slot: String, title: String) -> void:
	if game == null:
		return
	var err := game.save_to(slot, title.strip_edges())
	_status.text = tr("Game saved") if err == OK else tr("Could not save the game")
	_refresh()


func _load(slot: String) -> void:
	var data := SaveGame.read(slot)
	if data.is_empty():
		_status.text = tr("This save cannot be read")
		return
	load_requested.emit(data)
	_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

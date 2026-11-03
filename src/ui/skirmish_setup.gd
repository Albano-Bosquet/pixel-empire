class_name SkirmishSetup
extends CanvasLayer
## Single-player match setup (opened from the title screen): the player list
## (you plus up to seven computer players, each with its difficulty and team)
## and the match options. With no computer player the match is a sandbox.
## Emits `start_requested(config)` with a MatchConfig.build() config.

signal start_requested(config: Dictionary)
signal closed

var _slots: Array = []
var _list: PlayerSlotsList
var _form: MatchSettingsForm
var _add_ai: Button
var _ai_diff: OptionButton
var _start: Button
var _mode_label: Label


func _ready() -> void:
	layer = 30
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UiStyle.dimmer(0.55))
	var pv: Array = UiStyle.centered_panel(root, 1040)
	var v: VBoxContainer = pv[1]
	v.add_child(UiStyle.title(tr("Single player"), 38))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	v.add_child(cols)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 520
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	left.add_child(UiStyle.label(tr("Players"), 20, UiStyle.GOLD))
	_list = PlayerSlotsList.new()
	_list.editable = func(i: int) -> bool: return true
	_list.removable = func(i: int) -> bool: return i > 0
	_list.team_changed.connect(func(i: int, t: int) -> void:
		_slots[i]["team"] = t
		_refresh())
	_list.difficulty_changed.connect(func(i: int, d: String) -> void:
		_slots[i]["difficulty"] = d
		_slots[i]["name"] = _ai_name(i, d))
	_list.remove_requested.connect(func(i: int) -> void:
		_slots.remove_at(i)
		_rename_ais()
		_refresh())
	left.add_child(_list)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	var diffs: Array = GameData.rules.get("difficulties_menu", ["easy", "normal", "hard"])
	_ai_diff = UiStyle.option(diffs.map(func(d): return tr(String(d).capitalize())), maxi(0, diffs.find("normal")))
	_ai_diff.custom_minimum_size = Vector2(150, 36)
	add_row.add_child(_ai_diff)
	_add_ai = UiStyle.button(tr("Add computer player"), 300)
	_add_ai.pressed.connect(func() -> void: add_ai(diffs[_ai_diff.selected]))
	add_row.add_child(_add_ai)
	left.add_child(add_row)
	_mode_label = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_mode_label)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	right.add_child(UiStyle.label(tr("Match options"), 20, UiStyle.GOLD))
	_form = MatchSettingsForm.new()
	right.add_child(_form)
	_form.changed.connect(func(_s: Dictionary) -> void: _refresh())

	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 16)
	v.add_child(brow)
	var back := UiStyle.button(tr("Back"), 240)
	back.pressed.connect(_close)
	brow.add_child(back)
	_start = UiStyle.button(tr("Start game"), 320)
	_start.pressed.connect(func() -> void: start_requested.emit(config()))
	brow.add_child(_start)

	var me := OS.get_environment("USERNAME")
	_slots = [{"name": me if me != "" else tr("Player"), "ai": false, "you": true, "team": 0}]
	add_ai("normal")
	_start.grab_focus()


## Adds a computer player (up to game_rules.json max_players).
func add_ai(difficulty: String) -> void:
	if _slots.size() >= int(GameData.rules.get("max_players", 8)):
		return
	_slots.append({"name": _ai_name(_slots.size(), difficulty), "ai": true, "difficulty": difficulty, "team": 0})
	_refresh()


func _ai_name(index: int, difficulty: String) -> String:
	return "%s %d (%s)" % [tr("Computer"), index, tr(difficulty.capitalize())]


func _rename_ais() -> void:
	for i in _slots.size():
		if _slots[i]["ai"]:
			_slots[i]["name"] = _ai_name(i, _slots[i]["difficulty"])


func _refresh() -> void:
	_list.show_slots(_slots)
	var full := _slots.size() >= int(GameData.rules.get("max_players", 8))
	_add_ai.disabled = full
	var cfg := config()
	var size_note := ""
	var chosen: String = _form.get_settings().get("size", "small") if _form.is_node_ready() else ""
	if chosen != "" and cfg["size"] != chosen:
		size_note = "  " + tr("The map grows to %s for this many players.") % tr(String(cfg["size"]).capitalize())
	_mode_label.text = (tr("No computer players: sandbox, build in peace.") if cfg["mode"] == "sandbox" else tr("%d players") % _slots.size()) + size_note


## The match configuration currently chosen.
func config() -> Dictionary:
	var settings := _form.get_settings() if _form != null and _form.is_node_ready() else MatchConfig.default_settings()
	return MatchConfig.build(settings, _slots)


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

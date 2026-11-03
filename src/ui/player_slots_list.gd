class_name PlayerSlotsList
extends VBoxContainer
## Player list of a match setup (single player and lobby): colour, name, kind
## (human / computer), difficulty and team per slot, with a remove button.
## Displays the slots it is given and reports edits; the owner screen applies
## them (and in multiplayer forwards them to the host).
## Slot keys: name, ai, difficulty, team, ready (optional), connected (optional).

signal team_changed(index: int, team: int)
signal difficulty_changed(index: int, difficulty: String)
signal remove_requested(index: int)

## Which slots this screen may edit / remove (index -> bool); default: none.
var editable: Callable = func(_i: int) -> bool: return false
var removable: Callable = func(_i: int) -> bool: return false


func _init() -> void:
	add_theme_constant_override("separation", 4)


## Rebuilds the rows for `slots`.
func show_slots(slots: Array) -> void:
	for c in get_children():
		c.queue_free()
	var colors: Array = GameData.players.get("colors", [])
	var diffs: Array = GameData.rules.get("difficulties_menu", ["easy", "normal", "hard"])
	var teams := int(GameData.rules.get("teams_menu", 4))
	var team_names := [tr("No team")]
	for t in teams:
		team_names.append(tr("Team %d") % (t + 1))
	for i in slots.size():
		var s: Dictionary = slots[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(20, 20)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = Color(colors[i % colors.size()]["primary"]) if not colors.is_empty() else Color.WHITE
		row.add_child(sw)
		var name_l := UiStyle.label(String(s.get("name", "?")), 16, UiStyle.TEXT if s.get("ready", true) else UiStyle.TEXT_DIM)
		name_l.custom_minimum_size.x = 170
		name_l.clip_text = true
		row.add_child(name_l)
		var can_edit: bool = editable.call(i)
		var idx := i
		if s.get("ai", false):
			var d := UiStyle.option(diffs.map(func(x): return tr(String(x).capitalize())), maxi(0, diffs.find(s.get("difficulty", "normal"))))
			d.custom_minimum_size = Vector2(130, 32)
			d.disabled = not can_edit
			d.item_selected.connect(func(k: int) -> void: difficulty_changed.emit(idx, diffs[k]))
			row.add_child(d)
		else:
			var tag := tr("You") if s.get("you", false) else (tr("ready") if s.get("ready", true) else tr("not ready"))
			if not s.get("connected", true):
				tag = tr("disconnected")
			var l := UiStyle.label(tag, 15, UiStyle.TEXT_DIM)
			l.custom_minimum_size.x = 130
			row.add_child(l)
		var t := UiStyle.option(team_names, clampi(int(s.get("team", 0)), 0, teams))
		t.custom_minimum_size = Vector2(130, 32)
		t.disabled = not can_edit
		t.item_selected.connect(func(k: int) -> void: team_changed.emit(idx, k))
		row.add_child(t)
		if removable.call(i):
			var rm := UiStyle.button("✕", 44)
			rm.tooltip_text = tr("Remove")
			rm.pressed.connect(func() -> void: remove_requested.emit(idx))
			row.add_child(rm)
		add_child(row)

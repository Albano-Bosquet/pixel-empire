class_name Hud
extends CanvasLayer
## In-game HUD: top resource bar (resources, population/cap, age, clock),
## bottom selection panel (portrait, HP/progress, stats, training queue,
## multi-select grid, command panel), notifications, drag rectangle and a
## debug readout (F3). Reads state through EventBus and the Game API only.

const AGE_NAMES: Array[String] = ["Dark Age", "Feudal Age", "Castle Age", "Imperial Age", "Gunpowder Age", "Industrial Age", "Military Age"]
const PANEL_BG := Color(0.11, 0.10, 0.09, 0.93)
const PANEL_BORDER := Color("#8a6d3b")
const TEXT := Color("#f1e6cf")
const TEXT_DIM := Color("#b5a88e")
const NOTIFY_SECONDS := 3.5

var _game: Game
var _res_labels: Dictionary = {}
var _pop_label: Label
var _age_label: Label
var _clock_label: Label
var _fps_label: Label
var _notify_label: Label
var _notify_time := 0.0
var _last_notify := ""
var _last_notify_ms := 0
var _chat_edit: LineEdit
var _bottom: PanelContainer
var _portrait: TextureRect
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _stats_label: Label
var _task_label: Label
var _progress_bar: ProgressBar
var _queue_row: HBoxContainer
var _multi_grid: GridContainer
var _single_box: VBoxContainer
var _commands: CommandPanel
var _box := SelectionBoxDraw.new()
var minimap: Minimap
var tech_panel: TechPanel
var _idle_button: Button
var _selection: Array = []
var _elapsed := 0.0
var _queue_sig := ""


func setup(game: Game) -> void:
	_game = game
	layer = 10
	_build_top_bar()
	_build_bottom_panel()
	_build_minimap()
	tech_panel = TechPanel.new()
	add_child(tech_panel)
	tech_panel.setup(game)
	_notify_label = _label("", 18, Color("#ffe9a8"))
	_notify_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notify_label.offset_left = -400
	_notify_label.offset_right = 400
	_notify_label.offset_top = 54
	_notify_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notify_label)
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	game.selection.box_changed.connect(_box.set_box)
	EventBus.resources_changed.connect(_on_resources_changed)
	EventBus.selection_changed.connect(_on_selection_changed)
	EventBus.notify.connect(_on_notify)
	Net.chat_received.connect(_on_chat)
	EventBus.age_changed.connect(func(pid: int, _a: int) -> void: _on_resources_changed(pid, game.player(pid).resources))
	_on_resources_changed(game.local_player, game.local_state().resources)
	_on_selection_changed([])


func _process(delta: float) -> void:
	if _game == null:
		return
	_elapsed += delta
	if Net.is_client():
		_elapsed = _game.victory.elapsed  # the host's match clock
	var s := int(_elapsed)
	_clock_label.text = "%02d:%02d" % [s / 60, s % 60]
	var pop := _game.population(_game.local_player)
	var cap := _game.population_cap(_game.local_player)
	_pop_label.text = "%d/%d" % [pop, cap]
	_pop_label.add_theme_color_override("font_color", Color("#ff8a7a") if pop >= cap else TEXT)
	_fps_label.text = tr("%d fps · %d units") % [Engine.get_frames_per_second(), _game.unit_system.units.size()]
	var idle := _idle_count()
	_idle_button.text = tr("Idle: %d") % idle
	_idle_button.modulate = Color(1, 0.85, 0.5) if idle > 0 else Color(0.7, 0.7, 0.7)
	if _notify_time > 0.0:
		_notify_time -= delta
		_notify_label.modulate.a = clampf(_notify_time, 0.0, 1.0)
	if _selection.size() == 1 and is_instance_valid(_selection[0]):
		_refresh_single(_selection[0])
	elif _selection.size() > 0 and _selection.any(func(e): return not is_instance_valid(e)):
		_on_selection_changed(_selection.filter(func(e): return is_instance_valid(e)))


func _unhandled_key_input(event: InputEvent) -> void:
	if _game == null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ENTER and Net.is_networked():
		_open_chat()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F3:
		_fps_label.visible = not _fps_label.visible
	elif event.keycode == KEY_F2:
		tech_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F10:
		EventBus.pause_requested.emit()
		get_viewport().set_input_as_handled()
	elif not event.ctrl_pressed and _commands.handle_key(event.keycode):
		get_viewport().set_input_as_handled()


## Shows a notification for the local player (id 0 = everyone). The same line
## arriving again within 2 s (host echo of a local message) is ignored.
func _on_notify(player_id: int, text: String) -> void:
	if player_id != _game.local_player and player_id != 0:
		return
	var now := Time.get_ticks_msec()
	if text == _last_notify and now - _last_notify_ms < 2000:
		return
	_last_notify = text
	_last_notify_ms = now
	_show_notice(Loc.text(text))


func _show_notice(text: String) -> void:
	_notify_label.text = text
	_notify_time = NOTIFY_SECONDS


## Multiplayer chat line (Enter opens it, Enter sends, Esc closes).
func _open_chat() -> void:
	if _chat_edit == null:
		_chat_edit = LineEdit.new()
		_chat_edit.placeholder_text = tr("Message to all players")
		_chat_edit.custom_minimum_size = Vector2(420, 30)
		_chat_edit.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_chat_edit.position = Vector2(-210, 92)
		_chat_edit.text_submitted.connect(func(t: String) -> void:
			Net.send_chat(t)
			_chat_edit.text = ""
			_chat_edit.visible = false)
		_chat_edit.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
				_chat_edit.visible = false
				_chat_edit.accept_event())
		add_child(_chat_edit)
	_chat_edit.visible = true
	_chat_edit.grab_focus()


func _on_chat(from: String, text: String) -> void:
	if from == "":
		_on_notify(0, text)
	else:
		_show_notice("%s: %s" % [from, text])


# --- Construction -----------------------------------------------------------

static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 4
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _icon(prop_name: String, scale: float = 2.0) -> TextureRect:
	var r := SpriteLibrary.prop(prop_name)
	var at := AtlasTexture.new()
	at.atlas = SpriteLibrary.props_texture()
	at.region = r["rect"]
	var tr_ := TextureRect.new()
	tr_.texture = at
	tr_.custom_minimum_size = r["rect"].size * scale
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr_.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr_


func _bar(fill: Color, w: float, h: float) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(w, h)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#2a1d1a")
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", panel_style())
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 44
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	bar.add_child(row)
	for key in ["wood", "food", "gold", "stone"]:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.add_child(_icon("icon_" + key, 1.6))
		var l := _label("0", 18)
		l.custom_minimum_size.x = 56
		box.add_child(l)
		box.tooltip_text = tr(key.capitalize())
		row.add_child(box)
		_res_labels[key] = l
	var pop := HBoxContainer.new()
	pop.add_child(_icon("icon_pop", 1.6))
	_pop_label = _label("0/0", 18)
	pop.add_child(_pop_label)
	pop.tooltip_text = tr("Population / limit")
	row.add_child(pop)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_age_label = _label(tr(AGE_NAMES[0]), 18, Color("#f0c96a"))
	row.add_child(_age_label)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer2)
	_fps_label = _label("", 14, TEXT_DIM)
	row.add_child(_fps_label)
	_clock_label = _label("00:00", 18)
	row.add_child(_clock_label)
	var techs := _top_button(tr("Technologies"), tr("Technology tree  [F2]"))
	techs.pressed.connect(func() -> void: tech_panel.toggle())
	row.add_child(techs)
	var menu := _top_button(tr("Menu"), tr("Game menu  [F10]"))
	menu.pressed.connect(func() -> void: EventBus.pause_requested.emit())
	row.add_child(menu)


func _top_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color("#f0c96a"))
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#2b2620") if st == "normal" else Color("#3d342a")
		sb.border_color = PANEL_BORDER.darkened(0.2)
		sb.set_border_width_all(1)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		b.add_theme_stylebox_override(st, sb)
	return b


## Minimap (bottom-left, framed) with the idle-villager button above it.
func _build_minimap() -> void:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", panel_style())
	frame.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	frame.offset_left = 6
	frame.offset_right = 6 + 300
	frame.offset_top = -176
	frame.offset_bottom = -6
	add_child(frame)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(280, 150)
	frame.add_child(minimap)
	minimap.setup(_game)
	_idle_button = Button.new()
	_idle_button.focus_mode = Control.FOCUS_NONE
	_idle_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_idle_button.offset_left = 8
	_idle_button.offset_top = -214
	_idle_button.offset_right = 150
	_idle_button.offset_bottom = -182
	_idle_button.tooltip_text = tr("Select the next idle villager  [.]")
	_idle_button.add_theme_font_size_override("font_size", 14)
	var r := SpriteLibrary.prop("icon_pop")
	var at := AtlasTexture.new()
	at.atlas = SpriteLibrary.props_texture()
	at.region = r["rect"]
	_idle_button.icon = at
	_idle_button.pressed.connect(func() -> void: _game.selection.select_idle_worker())
	add_child(_idle_button)


func _idle_count() -> int:
	var n := 0
	for u in _game.unit_system.units:
		if u.owner_id == _game.local_player and u.is_worker and not u.dead and u.task.is_empty() and u.state == Unit.State.IDLE:
			n += 1
	return n


func _build_bottom_panel() -> void:
	_bottom = PanelContainer.new()
	_bottom.add_theme_stylebox_override("panel", panel_style())
	_bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bottom.offset_left = -470
	_bottom.offset_right = 470
	_bottom.offset_top = -150
	_bottom.offset_bottom = -6
	_bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bottom)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_bottom.add_child(root)

	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color("#2c3a2a")
	fs.border_color = PANEL_BORDER.darkened(0.2)
	fs.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", fs)
	frame.custom_minimum_size = Vector2(124, 124)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(_portrait)
	root.add_child(frame)

	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(stack)

	_single_box = VBoxContainer.new()
	_single_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_single_box.add_theme_constant_override("separation", 5)
	stack.add_child(_single_box)
	_name_label = _label("", 19)
	_single_box.add_child(_name_label)
	var hp_row := HBoxContainer.new()
	_hp_bar = _bar(Color("#4fbf4a"), 200, 12)
	hp_row.add_child(_hp_bar)
	_hp_label = _label("", 14, TEXT_DIM)
	hp_row.add_child(_hp_label)
	_single_box.add_child(hp_row)
	_stats_label = _label("", 14, TEXT_DIM)
	_single_box.add_child(_stats_label)
	# What a unit is doing gets its own line: translated text is longer.
	_task_label = _label("", 14, TEXT_DIM)
	_single_box.add_child(_task_label)
	# Never push under the command panel: cut with "…" if a line is too long.
	for l in [_name_label, _stats_label, _task_label]:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = 1
	_progress_bar = _bar(Color("#d9a922"), 200, 10)
	_single_box.add_child(_progress_bar)
	_queue_row = HBoxContainer.new()
	_queue_row.add_theme_constant_override("separation", 3)
	_single_box.add_child(_queue_row)

	_multi_grid = GridContainer.new()
	_multi_grid.columns = 9
	_multi_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_multi_grid.add_theme_constant_override("h_separation", 3)
	_multi_grid.add_theme_constant_override("v_separation", 3)
	stack.add_child(_multi_grid)

	_commands = CommandPanel.new()
	_commands.custom_minimum_size = Vector2(270, 0)
	root.add_child(_commands)
	_commands.setup(_game)


# --- Updates ----------------------------------------------------------------

func _on_resources_changed(player_id: int, resources: Dictionary) -> void:
	if player_id != _game.local_player:
		return
	for k in _res_labels:
		_res_labels[k].text = str(resources.get(k, 0))
	_age_label.text = tr(AGE_NAMES[clampi(_game.local_state().age, 0, AGE_NAMES.size() - 1)])


func _on_selection_changed(list: Array) -> void:
	_selection = list.duplicate()
	_bottom.visible = not _selection.is_empty()
	_queue_sig = ""
	for c in _multi_grid.get_children():
		c.queue_free()
	if _selection.is_empty():
		return
	_portrait.texture = portrait_texture(_selection[0])
	var single := _selection.size() == 1
	_single_box.visible = single
	_multi_grid.visible = not single
	if single:
		_refresh_single(_selection[0])
		return
	for e in _selection:
		var b := Button.new()
		b.icon = portrait_texture(e)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(40, 44)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.tooltip_text = tr(e.display_name())
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _game.selection.set_selection([e]))
		_multi_grid.add_child(b)


func _refresh_single(e: Entity) -> void:
	var owner_name := tr("Gaia") if e.owner_id == Entity.GAIA else _game.player(e.owner_id).name
	_name_label.text = "%s  ·  %s" % [tr(e.display_name()), owner_name]
	_progress_bar.visible = false
	_queue_row.visible = false
	_task_label.visible = false
	if e is ResourceNode:
		_hp_bar.visible = false
		_hp_label.text = ""
		_stats_label.text = tr("%s remaining: %d") % [tr(String(e.resource_type).capitalize()), e.remaining()]
		return
	_hp_bar.visible = true
	_hp_bar.max_value = e.max_hp
	_hp_bar.value = e.hp
	_hp_label.text = "  %d / %d" % [e.hp, e.max_hp]
	if e is Unit:
		var task := ""
		if not e.task.is_empty():
			var tt: String = e.task["type"]
			task = tr("Gathering %s") % tr(String(e.task.get("kind", "")).capitalize()) if tt == "gather" else tr({"build": "Building", "repair": "Repairing", "drop": "Dropping off"}.get(tt, ""))
		var carry := "%s: %d" % [tr("Carrying"), floori(e.carry_amount)] if e.carry_amount >= 1.0 else ""
		var arm: Dictionary = e.def.get("armor", {})
		var rng := "   " + tr("Range %d") % int(e.attack_range()) if e.attack_range() >= 1.0 else ""
		_stats_label.text = tr("Attack %d   Armor %d/%d   Speed %.1f") % [int(e.def.get("attack_damage", 0)), int(arm.get("melee", 0)), int(arm.get("pierce", 0)), e.speed] + rng
		_task_label.text = task + ("   ·   " if task != "" and carry != "" else "") + carry
		_task_label.visible = _task_label.text != ""
	elif e is Building:
		var b: Building = e
		if not b.is_complete():
			_stats_label.text = tr("Under construction: %d%%") % roundi(b.progress * 100.0)
			_progress_bar.visible = true
			_progress_bar.value = b.progress * 100.0
		else:
			var parts: PackedStringArray = []
			if b.is_farm():
				parts.append(tr("Food remaining: %d") % b.remaining())
			if int(b.def.get("population", 0)) > 0:
				parts.append(tr("Houses %d") % int(b.def["population"]))
			if not b.def.get("drop_off", []).is_empty():
				parts.append(tr("Accepts: %s") % ", ".join(b.def["drop_off"].map(func(r): return tr(r))))
			_stats_label.text = "   ".join(parts) if not parts.is_empty() else tr(b.def.get("description", ""))
			_refresh_queue(b)


func _refresh_queue(b: Building) -> void:
	_queue_row.visible = not b.queue.is_empty()
	_progress_bar.visible = not b.queue.is_empty()
	_progress_bar.value = ProductionSystem.front_progress(b) * 100.0
	var sig := ",".join(b.queue)
	if sig == _queue_sig:
		return
	_queue_sig = sig
	for c in _queue_row.get_children():
		c.queue_free()
	for i in b.queue.size():
		var udef := ProductionSystem.item_def(b.queue[i])
		var at := AtlasTexture.new()
		if ProductionSystem.is_research(b.queue[i]):
			at.atlas = SpriteLibrary.props_texture()
			at.region = (CommandPanel.tech_icon(b.queue[i]) if GameData.techs.has(b.queue[i]) else SpriteLibrary.prop("icon_age"))["rect"]
		else:
			var layout := SpriteLibrary.unit_layout(udef.get("sprite", b.queue[i]))
			var pr: Array = layout.get("portrait_rect", [0, 0, 48, 48])
			at.atlas = SpriteLibrary.unit_sheet(udef.get("sprite", b.queue[i]), b.color_slot)
			at.region = Rect2(pr[0], pr[1], pr[2], pr[3])
		var btn := Button.new()
		btn.icon = at
		btn.expand_icon = true
		btn.custom_minimum_size = Vector2(28, 30)
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = tr("Cancel %s (refund)") % tr(udef.get("display_name", ""))
		var idx := i
		btn.pressed.connect(func() -> void: _game.orders.submit({"t": "cancel", "b": b.entity_id, "idx": idx}))
		_queue_row.add_child(btn)


## Portrait for an entity: unit portrait_rect, building body, or prop sprite.
static func portrait_texture(e: Entity) -> Texture2D:
	var at := AtlasTexture.new()
	if e is Unit:
		var layout := SpriteLibrary.unit_layout(e.def.get("sprite", e.type_id))
		var pr: Array = layout.get("portrait_rect", [0, 0] + layout.get("frame_size", [48, 48]))
		at.atlas = SpriteLibrary.unit_sheet(e.def.get("sprite", e.type_id), (e as Unit).color_slot)
		at.region = Rect2(pr[0], pr[1], pr[2], pr[3])
	elif e is Building:
		at.atlas = Building.atlas_texture()
		at.region = Building.sprite_region(e.type_id)["rect"]
	elif e is ResourceNode:
		at.atlas = SpriteLibrary.props_texture()
		at.region = (e as ResourceNode).portrait_region()
	return at


## Draws the drag-selection rectangle.
class SelectionBoxDraw:
	extends Control
	var _rect := Rect2()
	var _active := false

	func set_box(r: Rect2, active: bool) -> void:
		_rect = r
		_active = active
		queue_redraw()

	func _draw() -> void:
		if _active:
			draw_rect(_rect, Color(0.85, 1.0, 0.8, 0.10))
			draw_rect(_rect, Color(0.85, 1.0, 0.8, 0.9), false, 1.0)

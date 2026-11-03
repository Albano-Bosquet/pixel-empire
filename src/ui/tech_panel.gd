class_name TechPanel
extends PanelContainer
## Technology overview (F2 / top-bar button): every age and technology grouped by
## the building that researches it, with its state for the local player:
## researched, in progress (with %), available, or locked (with the reason).
## Read-only: research is started from the building's command panel.

var _game: Game
## Space kept free above and below the panel (top bar, selection panel edge).
const FIT_MARGIN := 110.0

var _grid: GridContainer
var _scroll: ScrollContainer
var _refresh_timer := 0.0


func setup(game: Game) -> void:
	_game = game
	add_theme_stylebox_override("panel", UiStyle.panel(14))
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(900, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UiStyle.label(tr("Technologies"), 26, UiStyle.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UiStyle.button(tr("Close  [F2]"), 120)
	close.pressed.connect(toggle)
	head.add_child(close)
	v.add_child(head)
	# The list is taller than most windows: it scrolls inside a panel that
	# always fits the viewport (see _fit).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(_grid)
	EventBus.tech_researched.connect(func(_p: int, _t: String) -> void: _rebuild())
	EventBus.age_changed.connect(func(_p: int, _a: int) -> void: _rebuild())
	get_viewport().size_changed.connect(func() -> void:
		if visible:
			_fit())


func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild()
		_fit.call_deferred()


## Sizes the scroll area to the content, capped to the window height, and
## centres the panel.
func _fit() -> void:
	var view := get_viewport_rect().size
	var avail := maxf(160.0, view.y - FIT_MARGIN - 70.0)
	_scroll.custom_minimum_size = Vector2(_grid.get_combined_minimum_size().x + 12, minf(_grid.get_combined_minimum_size().y, avail))
	reset_size()
	position = ((view - size) * 0.5).floor()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		_rebuild()


## Ordered list: TC (ages + techs), then each building that researches something.
func _rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var p := _game.local_state()
	for bid in GameData.buildings:
		var researches: Array = GameData.building(bid).get("researches", [])
		if researches.is_empty():
			continue
		var reg := Building.sprite_region(bid)
		var name_box := VBoxContainer.new()
		var icon := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = Building.atlas_texture()
		at.region = reg["rect"]
		icon.texture = at
		icon.custom_minimum_size = Vector2(64, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		name_box.add_child(icon)
		name_box.add_child(UiStyle.label(tr(GameData.building(bid)["display_name"]), 13, UiStyle.TEXT_DIM))
		name_box.custom_minimum_size.x = 110
		_grid.add_child(name_box)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		row.custom_minimum_size.x = 740
		for rid in researches:
			row.add_child(_chip(p, rid))
		_grid.add_child(row)


func _chip(p: PlayerState, id: String) -> Control:
	var is_age := GameData.ages.has(id)
	var d: Dictionary = GameData.ages[id] if is_age else GameData.techs[id]
	var state := "available"
	var detail := ""
	if (is_age and p.age >= int(d.get("sets_age", 0))) or (not is_age and p.researched.has(id)):
		state = "done"
	else:
		for b in _game.buildings.buildings:
			if b.owner_id == p.id and not b.queue.is_empty() and b.queue[0] == id:
				state = "progress"
				detail = " %d%%" % roundi(ProductionSystem.front_progress(b) * 100.0)
			elif b.owner_id == p.id and b.queue.has(id) and state != "progress":
				state = "progress"
				detail = " (" + tr("queued") + ")"
		if state == "available":
			var err := TechSystem.research_error(p, id) if not is_age else ""
			if is_age and p.age < int(d.get("requires_age", 0)):
				err = Loc.msg("Requires %s", [Hud.AGE_NAMES[int(d.get("requires_age", 0))]])
			if err != "" and err != "Not enough resources":
				state = "locked"
				detail = "\n" + Loc.text(err)
	var col: Color = {"done": UiStyle.GOOD, "progress": UiStyle.GOLD, "available": UiStyle.TEXT, "locked": Color(0.5, 0.48, 0.44)}[state]
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiStyle.BG_LIGHT if state != "done" else Color("#23331f")
	sb.border_color = col.darkened(0.3)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(5)
	chip.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	var tex := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = SpriteLibrary.props_texture()
	at.region = (SpriteLibrary.prop("icon_age") if is_age else CommandPanel.tech_icon(id))["rect"]
	tex.texture = at
	tex.custom_minimum_size = Vector2(26, 26)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.modulate = Color.WHITE if state != "locked" else Color(0.5, 0.5, 0.5)
	h.add_child(tex)
	if state == "done":
		detail = " - " + tr("done")
	h.add_child(UiStyle.label(tr(d["display_name"]) + detail, 13, col))
	chip.add_child(h)
	chip.tooltip_text = "%s\n%s\n%s" % [tr(d["display_name"]), tr(d.get("description", "")), CommandPanel.cost_text(d.get("cost", {}))]
	return chip

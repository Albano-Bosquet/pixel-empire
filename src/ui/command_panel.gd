class_name CommandPanel
extends VBoxContainer
## Context-sensitive command grid (bottom-right of the selection panel).
##   Workers selected   -> building pages (economy / military), hotkeys from data
##   Own building       -> train buttons (`trains`) and age research (`researches`)
##   Military units     -> stop, stances (aggressive/defensive/stand), formations (box/line)
## Buttons only request actions through game systems; locked or unaffordable
## entries stay visible with the reason in their tooltip.

const COLS := 5
const MAX_ROWS := 2
const BTN := Vector2(50, 50)
## Smaller buttons once a page needs more than WIDE_COLS columns (the military
## building page), so the grid keeps two rows without crowding the unit info.
const BTN_COMPACT := Vector2(42, 42)
const WIDE_COLS := 8
const RES_ORDER: Array[String] = ["food", "wood", "gold", "stone"]

var _game: Game
var _grid := GridContainer.new()
var _title := Label.new()
var _page := "economy"
var _mode := ""
var _building: Building = null
var _hotkeys: Dictionary = {}  # keycode -> Callable
var _buttons: Array[Dictionary] = []  # {"button", "check": Callable}


func setup(game: Game) -> void:
	_game = game
	add_theme_constant_override("separation", 4)
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", Hud.TEXT_DIM)
	add_child(_title)
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	add_child(_grid)
	EventBus.selection_changed.connect(func(_l: Array) -> void: rebuild())
	EventBus.resources_changed.connect(func(_p: int, _r: Dictionary) -> void: _refresh_states())
	EventBus.population_changed.connect(func(_p: int) -> void: rebuild())
	EventBus.age_changed.connect(func(_p: int, _a: int) -> void: rebuild())
	EventBus.tech_researched.connect(func(_p: int, _t: String) -> void: rebuild())
	EventBus.production_changed.connect(func(_b: Node) -> void: _refresh_states())
	_game.buildings.building_completed.connect(func(_b: Building) -> void: rebuild())


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in RES_ORDER:
		if cost.has(k):
			parts.append("%d %s" % [int(cost[k]), TranslationServer.translate(k.capitalize())])
	return TranslationServer.translate("Cost: %s") % ", ".join(parts)


func rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_hotkeys.clear()
	_buttons.clear()
	_building = null
	var sel: Array = _game.selection.selected
	var workers := _game.selection.own_units().filter(func(u): return u.is_worker)
	var own_b := _game.selection.own_buildings()
	var soldiers := _game.selection.own_units()
	if not workers.is_empty():
		_mode = "build"
		_build_pages()
	elif not soldiers.is_empty():
		_mode = "military"
		_build_military(soldiers)
	elif own_b.size() == 1 and sel.size() == 1 and own_b[0].is_complete() and (not own_b[0].def.get("trains", []).is_empty() or not own_b[0].def.get("researches", []).is_empty()):
		_mode = "train"
		_building = own_b[0]
		_build_training(_building)
	else:
		_mode = ""
	# Widen instead of adding rows: the bottom panel only has height for MAX_ROWS.
	_grid.columns = maxi(COLS, ceili(_buttons.size() / float(MAX_ROWS)))
	var size := BTN_COMPACT if _grid.columns > WIDE_COLS else BTN
	for e in _buttons:
		e["button"].custom_minimum_size = size
	_title.text = {"build": tr("Build — %s") % tr(_page.capitalize()), "train": tr("Train & research"), "military": tr("Orders")}.get(_mode, "")
	visible = _mode != ""
	_refresh_states()


func _build_pages() -> void:
	var ids := GameData.buildings.keys().filter(func(id): return GameData.building(id).get("category", "economy") == _page)
	ids.sort_custom(func(a, b): return int(GameData.building(a)["age"]) * 100 + int(GameData.building(a)["size"]) < int(GameData.building(b)["age"]) * 100 + int(GameData.building(b)["size"]))
	for id in ids:
		var def := GameData.building(id)
		var reg := Building.sprite_region(id)
		var tip := "%s  [%s]\n%s\n%s\n%s" % [tr(def["display_name"]), def.get("hotkey", ""), tr(def.get("description", "")), cost_text(def.get("cost", {})), _age_req(int(def.get("age", 0)))]
		_add_button(Building.atlas_texture(), reg["rect"], tip, def.get("hotkey", ""), func() -> void: _game.placement.begin(id),
			func() -> String: return _game.buildings.requirement_error(_game.local_state(), id))
	var other := "military" if _page == "economy" else "economy"
	var flip := func() -> void:
		_page = other
		rebuild()
	_add_button(null, Rect2(), tr("Show %s buildings  [Tab]") % tr(other), "Tab", flip, func() -> String: return "", tr(other.capitalize()))


func _build_training(b: Building) -> void:
	for unit_id in b.def.get("trains", []):
		var udef := GameData.unit(unit_id)
		var layout := SpriteLibrary.unit_layout(udef.get("sprite", unit_id))
		var pr: Array = layout.get("portrait_rect", [0, 0, 48, 48])
		var tip := "%s  [%s]\n%s\n%s · %ds" % [tr(udef.get("display_name", unit_id)), udef.get("hotkey", ""), tr(udef.get("description", "")), cost_text(udef.get("cost", {})), int(udef.get("train_time", 0))]
		var bb := b
		_add_button(SpriteLibrary.unit_sheet(udef.get("sprite", unit_id), b.color_slot), Rect2(pr[0], pr[1], pr[2], pr[3]), tip, udef.get("hotkey", ""),
			func() -> void:
				# Shift queues a batch (economy_settings.json shift_queue_count).
				var n := int(GameData.economy.get("shift_queue_count", 5)) if Input.is_key_pressed(KEY_SHIFT) else 1
				for k in n:
					_game.orders.submit({"t": "enqueue", "b": bb.entity_id, "item": unit_id}),
			func() -> String: return _game.production.enqueue_error(bb, unit_id))
	if b.def.get("exchange", false):
		_build_exchange(b)
	var shown_age := false
	for rid in b.def.get("researches", []):
		if GameData.techs.has(rid):
			_add_tech_button(b, rid)
			continue
		if shown_age:
			continue
		var r: Dictionary = GameData.ages[rid]
		if _game.player(b.owner_id).age >= int(r.get("sets_age", 0)):
			continue
		shown_age = true
		var rtip := "%s  [%s]\n%s\n%s · %ds" % [tr("Advance to %s") % tr(r["display_name"]), r.get("hotkey", ""), tr(r.get("description", "")), cost_text(r.get("cost", {})), int(r.get("research_time", 0))]
		var bb2 := b
		var research_id: String = rid
		_add_button(SpriteLibrary.props_texture(), SpriteLibrary.prop("icon_age")["rect"], rtip, r.get("hotkey", ""),
			func() -> void: _game.orders.submit({"t": "enqueue", "b": bb2.entity_id, "item": research_id}),
			func() -> String: return _game.production.enqueue_error(bb2, research_id))


## Market buy/sell buttons: one pair per tradable resource, prices live in the tooltip.
func _build_exchange(b: Building) -> void:
	var p := _game.player(b.owner_id)
	for res in MarketSystem.TRADABLE:
		var r: String = res
		for buying in [true, false]:
			var buy: bool = buying
			var tip := func() -> String:
				return (tr("Buy %d %s for %d gold") if buy else tr("Sell %d %s for %d gold")) % [_game.market.lot(), tr(r.capitalize()), _game.market.buy_cost(r) if buy else _game.market.sell_value(r)]
			_add_button(SpriteLibrary.props_texture(), SpriteLibrary.prop("icon_" + r)["rect"], tip.call(), "",
				func() -> void:
					_game.orders.submit({"t": "market", "res": r, "buy": buy})
					rebuild(),
				func() -> String: return _game.market.exchange_error(p, r, buy))
			var btn: Button = _buttons[-1]["button"]
			var tag := Label.new()
			tag.text = tr("Buy") if buy else tr("Sell")
			tag.add_theme_font_size_override("font_size", 10)
			tag.add_theme_color_override("font_color", Color("#9be28a") if buy else Color("#f08a7a"))
			tag.position = Vector2(3, 35)
			btn.add_child(tag)


func _build_military(units: Array) -> void:
	var typed: Array[Unit] = []
	typed.assign(units)
	var none := func() -> String: return ""
	var loaded := typed.filter(func(u): return NavalSystem.is_transport(u) and not u.cargo.is_empty())
	if not loaded.is_empty():
		_add_button(null, Rect2(), tr("Unload passengers on the nearest shore  [U]"), "U", func() -> void:
			_game.orders.submit({"t": "unload", "units": OrderRouter.ids(loaded)}), none, tr("Unload"))
	_add_button(SpriteLibrary.props_texture(), SpriteLibrary.prop("icon_stop")["rect"], tr("Stop  [X]"), "X", func() -> void: _game.orders.submit({"t": "stop", "units": OrderRouter.ids(typed)}), none)
	var stance_of: String = typed[0].stance
	for st in [["aggressive", "Aggressive stance: chase enemies in sight"], ["defensive", "Defensive stance: short chase, return to post"], ["stand", "Stand ground: only attack what is in range"]]:
		var key: String = st[0]
		var active := func() -> String: return "" if typed.all(func(u): return u.stance == key) else "inactive"
		_add_button(SpriteLibrary.props_texture(), SpriteLibrary.prop("icon_" + key)["rect"], tr(st[1]), "", func() -> void:
			_game.orders.submit({"t": "stance", "units": OrderRouter.ids(typed), "stance": key})
			_refresh_states(), active)
	for fm in [["box", "Box formation: melee in front, ranged behind"], ["line", "Line formation: one wide row"]]:
		var f: String = fm[0]
		var active_f := func() -> String: return "" if _game.commands.formation_of(_game.local_player) == f else "inactive"
		_add_button(SpriteLibrary.props_texture(), SpriteLibrary.prop("icon_" + f)["rect"], tr(fm[1]), "", func() -> void:
			_game.orders.submit({"t": "formation", "f": f})
			_refresh_states(), active_f)


static func tech_icon(id: String) -> Dictionary:
	var icon: String = GameData.techs.get(id, {}).get("icon", "attack")
	return SpriteLibrary.prop("icon_" + icon if icon in ["food", "wood", "gold", "stone"] else "icon_tech_" + icon)


func _add_tech_button(b: Building, id: String) -> void:
	var p := _game.player(b.owner_id)
	if p.researched.has(id):
		return
	var t: Dictionary = GameData.techs[id]
	var req := ""
	for r in t.get("requires", []):
		req += "\n" + tr("Requires %s") % tr(GameData.techs[r]["display_name"])
	var tip := "%s  [%s]\n%s\n%s · %ds%s%s" % [tr(t["display_name"]), t.get("hotkey", ""), tr(t.get("description", "")), cost_text(t.get("cost", {})), int(t.get("research_time", 0)), "\n" + _age_req(int(t.get("age", 0))) if int(t.get("age", 0)) > 0 else "", req]
	var bb := b
	_add_button(SpriteLibrary.props_texture(), tech_icon(id)["rect"], tip, t.get("hotkey", ""),
		func() -> void: _game.orders.submit({"t": "enqueue", "b": bb.entity_id, "item": id}),
		func() -> String: return _game.production.enqueue_error(bb, id))


func _age_req(age: int) -> String:
	return "" if age <= 0 else tr("Requires %s") % tr(Hud.AGE_NAMES[age])


func _add_button(tex: Texture2D, region: Rect2, tip: String, hotkey: String, action: Callable, check: Callable, text: String = "") -> void:
	var b := Button.new()
	b.custom_minimum_size = BTN
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_theme_stylebox_override("normal", _btn_style(Color("#2b2620")))
	b.add_theme_stylebox_override("hover", _btn_style(Color("#3d342a")))
	b.add_theme_stylebox_override("pressed", _btn_style(Color("#4d4233")))
	b.add_theme_stylebox_override("disabled", _btn_style(Color("#1e1b18")))
	if tex != null:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = region
		b.icon = at
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		b.text = text
		b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(action)
	if hotkey.length() == 1:
		var hk := Label.new()
		hk.text = hotkey
		hk.add_theme_font_size_override("font_size", 11)
		hk.add_theme_color_override("font_color", Color("#f0c96a"))
		hk.position = Vector2(4, 1)
		b.add_child(hk)
		_hotkeys[OS.find_keycode_from_string(hotkey)] = action
	elif hotkey == "Tab":
		_hotkeys[KEY_TAB] = action
	_grid.add_child(b)
	_buttons.append({"button": b, "check": check})


static func _btn_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color("#6b5530")
	s.set_border_width_all(1)
	s.set_content_margin_all(3)
	return s


## Dims buttons whose action is currently impossible (keeps them clickable so
## the reason is shown as a notification).
func _refresh_states() -> void:
	for entry in _buttons:
		var b: Button = entry["button"]
		if not is_instance_valid(b):
			continue
		var err: String = entry["check"].call()
		if err == "inactive":
			b.modulate = Color(0.6, 0.6, 0.6)
		else:
			b.modulate = Color.WHITE if err == "" else (Color(0.45, 0.45, 0.45) if err.begins_with("Requires") or err.begins_with("Already") else Color(1.0, 0.6, 0.55))


func handle_key(keycode: int) -> bool:
	if _hotkeys.has(keycode):
		_hotkeys[keycode].call()
		return true
	return false

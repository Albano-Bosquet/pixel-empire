class_name InfoCard
extends RefCounted
## Detail card for a command (building, unit, research, order): a large pixel
## preview of what it makes next to its name, purpose, cost and what it still
## needs. Shown as the PC tooltip of InfoButton / InfoPanel and, on touch
## screens, by TouchTooltips when a finger is held on a control.
##
## `info` keys (all optional):
##   title: String     translated name (gold heading)
##   desc: String      translated purpose
##   text: String      plain tooltip; first line becomes the title when no `title`
##   texture: Texture2D, region: Rect2   what to preview (atlas region)
##   hotkey: String    PC key, hidden when `show_keys` is false
##   cost: Dictionary  resource -> amount (icons; red when `player` lacks it)
##   player: PlayerState
##   lines: Array      extra translated lines (time, requirements)
##   status: Callable  -> error key; shown in red unless empty / "inactive"
## Example: hud.add_child(InfoCard.build({"title": tr("House"), "cost": {"wood": 25}}, false))

## Largest side of the preview, in logical pixels (3x a 50 px command button).
const PREVIEW := 144.0
const TEXT_WIDTH := 250.0
const RES_ORDER: Array[String] = ["food", "wood", "gold", "stone"]
static var _keys_re: RegEx


## Builds the card. `framed` adds the brass frame (the PC tooltip popup already
## draws one); `show_keys` keeps keyboard shortcuts in the text.
static func build(info: Dictionary, show_keys: bool = true, framed: bool = true) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.frame_small(12.0, 10.0) if framed else StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var tex: Texture2D = info.get("texture")
	if tex != null:
		row.add_child(_preview(tex, info.get("region", Rect2())))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	row.add_child(col)
	var title: String = info.get("title", "")
	var desc: String = info.get("desc", "")
	var extra: Array = info.get("lines", []).duplicate()
	if title == "" and info.has("text"):
		var parts: PackedStringArray = String(info["text"]).split("\n")
		title = parts[0]
		for i in range(1, parts.size()):
			if parts[i].strip_edges() != "":
				extra.append(parts[i])
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(_text(title if show_keys else strip_keys(title), 18, UiStyle.GOLD, false))
	var key: String = info.get("hotkey", "")
	if show_keys and key != "":
		head.add_child(_text("[%s]" % key, 14, UiStyle.TEXT_DIM, false))
	if desc != "":
		col.add_child(_text(desc, 14, UiStyle.TEXT))
	var cost: Dictionary = info.get("cost", {})
	if not cost.is_empty():
		col.add_child(_cost_row(cost, info.get("player")))
	for line in extra:
		var s: String = line if show_keys else strip_keys(line)
		if s != "":
			col.add_child(_text(s, 14, UiStyle.TEXT_DIM))
	var status: Callable = info.get("status", Callable())
	if status.is_valid():
		var err: String = status.call()
		if err != "" and err != "inactive" and not extra.has(Loc.text(err)):
			col.add_child(_text(Loc.text(err), 14, UiStyle.BAD))
	_ignore_mouse(card)
	return card


## Removes PC keyboard hints ("  [H]", "[Ctrl+A]") from a tooltip line.
static func strip_keys(s: String) -> String:
	if _keys_re == null:
		_keys_re = RegEx.create_from_string("\\s*\\[[^\\]\\n]+\\]")
	return _keys_re.sub(s, "", true).strip_edges()


## Plain-text version of `info` (the control's tooltip_text: PC hover needs one).
static func plain(info: Dictionary) -> String:
	var out: PackedStringArray = []
	var key: String = info.get("hotkey", "")
	out.append(info.get("title", "") + ("  [%s]" % key if key != "" else ""))
	if info.get("desc", "") != "":
		out.append(info["desc"])
	if not info.get("cost", {}).is_empty():
		out.append(CommandPanel.cost_text(info["cost"]))
	for line in info.get("lines", []):
		out.append(line)
	return "\n".join(out)


static func _preview(tex: Texture2D, region: Rect2) -> TextureRect:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = region
	var src := region.size if region.has_area() else Vector2(tex.get_size())
	# Whole-number zoom keeps the pixels square once it is 2x or more; between
	# 1x and 2x a smooth fit still makes the preview large. Big sprites shrink.
	var k := PREVIEW / maxf(src.x, src.y)
	if k >= 2.0:
		k = floorf(k)
	var r := TextureRect.new()
	r.texture = at if region.has_area() else tex
	r.custom_minimum_size = src * k
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


static func _cost_row(cost: Dictionary, player: Variant) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for k in RES_ORDER:
		if not cost.has(k):
			continue
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		var at := AtlasTexture.new()
		at.atlas = SpriteLibrary.props_texture()
		at.region = SpriteLibrary.prop("icon_" + k)["rect"]
		var icon := TextureRect.new()
		icon.texture = at
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		box.add_child(icon)
		var short: bool = player is PlayerState and int(player.resources.get(k, 0)) < int(cost[k])
		box.add_child(_text(str(int(cost[k])), 16, UiStyle.BAD if short else UiStyle.TEXT, false))
		row.add_child(box)
	return row


static func _text(s: String, size: int, color: Color, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("#140e09"))
	l.add_theme_constant_override("outline_size", 3)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = TEXT_WIDTH
	return l


static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

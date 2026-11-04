class_name UiStyle
extends RefCounted
## Shared look for every screen: dark walnut panels with a brass border,
## warm parchment text, pixel-crisp icons. Builders return configured nodes.
## Example: var b := UiStyle.button("Start"); add_child(UiStyle.title("Pixel Empire"))

const BG := Color(0.11, 0.10, 0.09, 0.94)
const BG_LIGHT := Color("#2b2620")
const BORDER := Color("#8a6d3b")
const GOLD := Color("#f0c96a")
const TEXT := Color("#f1e6cf")
const TEXT_DIM := Color("#b5a88e")
const GOOD := Color("#7fd36a")
const BAD := Color("#ff8a7a")


static func panel(margin: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BORDER
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	sb.set_content_margin_all(margin)
	return sb


static func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func button(text: String, min_width: float = 220.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 40)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_stylebox_override("normal", _btn_box(BG_LIGHT, BORDER.darkened(0.3)))
	b.add_theme_stylebox_override("hover", _btn_box(Color("#3d342a"), BORDER))
	b.add_theme_stylebox_override("pressed", _btn_box(Color("#4d4233"), GOLD))
	b.add_theme_stylebox_override("focus", _btn_box(Color("#3d342a"), GOLD))
	return b


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func title(text: String, size: int = 56) -> Label:
	var l := label(text, size, GOLD)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color("#2a1a0e"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(String(items[i]), i)
	o.select(selected)
	o.custom_minimum_size = Vector2(220, 36)
	o.add_theme_font_size_override("font_size", 16)
	o.add_theme_stylebox_override("normal", _btn_box(BG_LIGHT, BORDER.darkened(0.3)))
	o.add_theme_stylebox_override("hover", _btn_box(Color("#3d342a"), BORDER))
	o.add_theme_stylebox_override("focus", _btn_box(Color("#3d342a"), GOLD))
	return o


## Language selector (each language named in itself). Picking one switches
## the game language right away; listeners of Loc.language_changed rebuild.
static func language_option() -> OptionButton:
	var codes: Array = Loc.LANGUAGES.map(func(l): return l[0])
	var o := option(Loc.LANGUAGES.map(func(l): return l[1]), maxi(0, codes.find(Loc.language)))
	o.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	o.item_selected.connect(func(i: int) -> void: Loc.set_language.call_deferred(codes[i]))
	return o


## Full-screen switch bound to `Display`; F11 / Alt+Enter keep it in sync.
static func fullscreen_toggle() -> CheckButton:
	var c := CheckButton.new()
	c.text = "Full screen"
	c.add_theme_font_size_override("font_size", 16)
	c.add_theme_color_override("font_color", TEXT_DIM)
	c.button_pressed = Display.fullscreen
	c.toggled.connect(func(on: bool) -> void: Display.set_fullscreen(on))
	Display.fullscreen_changed.connect(c.set_pressed_no_signal)
	return c


## Full-screen dim layer that blocks clicks to the game below.
static func dimmer(alpha: float = 0.55) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## Room kept free above and below a centred panel (its border and padding included).
const PANEL_SCREEN_MARGIN := 80.0


## Centred panel container with a VBox inside; returns [panel, vbox].
## Taller than the screen (phones, scaled UI), its content scrolls instead of
## being cut off: the VBox sits in a ScrollContainer sized to fit the screen.
static func centered_panel(parent: Control, width: float) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel(20))
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var fit := func() -> void:
		if is_instance_valid(scroll) and scroll.is_inside_tree():
			scroll.custom_minimum_size.y = minf(v.get_combined_minimum_size().y, scroll.get_viewport_rect().size.y - PANEL_SCREEN_MARGIN)
	v.minimum_size_changed.connect(fit)
	scroll.tree_entered.connect(func() -> void:
		if not scroll.get_viewport().size_changed.is_connected(fit):
			scroll.get_viewport().size_changed.connect(fit)
		fit.call_deferred())
	scroll.tree_exiting.connect(func() -> void:
		if scroll.get_viewport().size_changed.is_connected(fit):
			scroll.get_viewport().size_changed.disconnect(fit))
	return [p, v]

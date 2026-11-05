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


## Framed walnut panel with brass corner brackets (every dialog).
## The frame itself is ~30 px wide, so the content margin never goes below 24.
static func panel(margin: int = 12) -> StyleBox:
	return pixel_panel(maxf(24.0, margin + 8.0))


static func button(text: String, min_width: float = 220.0) -> Button:
	return pixel_button(text, min_width, 44.0, 18)


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
	l.add_theme_font_override("font", spaced_font(maxi(1, size / 14)))
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))
	l.add_theme_color_override("font_outline_color", Color("#1a1009"))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(String(items[i]), i)
	o.select(selected)
	o.custom_minimum_size = Vector2(220, 40)
	skin_pixel(o, 16)
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
	c.add_theme_color_override("font_color", TEXT)
	c.add_theme_color_override("font_hover_color", GOLD)
	c.add_theme_color_override("font_pressed_color", TEXT)
	c.add_theme_icon_override("checked", load(UI_ART + "toggle_on.png"))
	c.add_theme_icon_override("unchecked", load(UI_ART + "toggle_off.png"))
	c.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	c.button_pressed = Display.fullscreen
	c.toggled.connect(func(on: bool) -> void: Display.set_fullscreen(on))
	Display.fullscreen_changed.connect(c.set_pressed_no_signal)
	return c


# --- Pixel-art skins (assets/ui, painted by tools/art/make_ui_art.py) ----------

const UI_ART := "res://assets/ui/"
## Size of one art pixel in the UI textures (make_ui_art.SCALE).
const UI_PIXEL := 3


## 9-patch box from assets/ui/<name>.png; `edge` is the fixed border in art pixels.
static func pixel_box(name: String, edge: int, pad_x: float = 16.0, pad_y: float = 8.0, pixel: int = UI_PIXEL) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(UI_ART + name + ".png")
	sb.set_texture_margin_all(edge * pixel)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## Framed walnut panel with brass corners (title screen).
static func pixel_panel(pad: float = 30.0) -> StyleBoxTexture:
	return pixel_box("panel", 10, pad, pad)


## Button skin styleboxes by state; `small` uses the 2x art (HUD, compact rows).
static func button_boxes(small: bool = false, pad_x: float = 16.0, pad_y: float = 8.0) -> Dictionary:
	var pre := "button_small_" if small else "button_"
	var px := 2 if small else UI_PIXEL
	return {
		"normal": pixel_box(pre + "normal", 4, pad_x, pad_y, px),
		"hover": pixel_box(pre + "hover", 4, pad_x, pad_y, px),
		"pressed": pixel_box(pre + "pressed", 4, pad_x, pad_y + 1.0, px),
		"hover_pressed": pixel_box(pre + "pressed", 4, pad_x, pad_y + 1.0, px),
		"disabled": pixel_box(pre + "disabled", 4, pad_x, pad_y, px),
		"focus": pixel_box(pre + "hover", 4, pad_x, pad_y, px),
	}


## Gives a button (or option button) the bevelled plank skin.
static func skin_pixel(b: BaseButton, font_size: int = 19, small: bool = false) -> void:
	var boxes := button_boxes(small, 10.0 if small else 16.0, 4.0 if small else 8.0)
	for st in boxes:
		b.add_theme_stylebox_override(st, boxes[st])
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_hover_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM.darkened(0.25))
	b.add_theme_color_override("font_outline_color", Color("#140e09"))
	b.add_theme_constant_override("outline_size", 4)


## Title-screen button: bevelled plank, brass rim on hover.
static func pixel_button(text: String, min_width: float = 360.0, height: float = 48.0, font_size: int = 19) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, height)
	b.focus_mode = Control.FOCUS_ALL
	skin_pixel(b, font_size)
	return b


## Thin brass frame (HUD bars, tooltips, popups).
static func frame_small(pad_x: float = 10.0, pad_y: float = 6.0) -> StyleBoxTexture:
	return pixel_box("frame_small", 4, pad_x, pad_y, 2)


## Sunken dark well (text fields, progress bar troughs, portraits).
static func inset(pad: float = 6.0) -> StyleBoxTexture:
	return pixel_box("inset", 2, pad, pad, 2)


## Game-wide theme so every control without its own overrides (plain buttons,
## drop-down lists, tooltips, sliders, check boxes, text fields, scroll bars)
## shares the pixel look. Set on the root window by Main.
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	var boxes := button_boxes(true, 10.0, 4.0)
	for type in ["Button", "OptionButton", "MenuButton"]:
		for st in boxes:
			t.set_stylebox(st, type, boxes[st])
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD)
		t.set_color("font_focus_color", type, GOLD)
		t.set_color("font_pressed_color", type, GOLD)
		t.set_color("font_hover_pressed_color", type, GOLD)
		t.set_color("font_disabled_color", type, TEXT_DIM.darkened(0.3))
		t.set_color("font_outline_color", type, Color("#140e09"))
		t.set_constant("outline_size", type, 3)
	for type in ["CheckBox", "CheckButton"]:
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_stylebox(st, type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, GOLD)
	t.set_icon("checked", "CheckBox", load(UI_ART + "check_on.png"))
	t.set_icon("unchecked", "CheckBox", load(UI_ART + "check_off.png"))
	t.set_icon("checked", "CheckButton", load(UI_ART + "toggle_on.png"))
	t.set_icon("unchecked", "CheckButton", load(UI_ART + "toggle_off.png"))
	t.set_stylebox("panel", "PanelContainer", frame_small())
	t.set_stylebox("panel", "PopupMenu", frame_small(6.0, 6.0))
	var hl := StyleBoxFlat.new()
	hl.bg_color = Color("#5c4a34")
	hl.border_color = GOLD
	hl.set_border_width_all(1)
	t.set_stylebox("hover", "PopupMenu", hl)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("panel", "TooltipPanel", frame_small(10.0, 6.0))
	t.set_color("font_color", "TooltipLabel", TEXT)
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, inset(8.0))
		var f := inset(8.0)
		f.modulate_color = Color(1.3, 1.2, 1.0)
		t.set_stylebox("focus", type, f)
		t.set_color("font_color", type, TEXT)
		t.set_color("caret_color", type, GOLD)
		t.set_color("selection_color", type, Color(GOLD, 0.35))
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#120d08")
	track.border_color = Color("#140e09")
	track.set_border_width_all(2)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#c9963f")
	fill.border_color = Color("#140e09")
	fill.set_border_width_all(2)
	for type in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", type, track)
		t.set_stylebox("grabber_area", type, fill)
		t.set_stylebox("grabber_area_highlight", type, fill)
		t.set_icon("grabber", type, load(UI_ART + "slider_grabber.png"))
		t.set_icon("grabber_highlight", type, load(UI_ART + "slider_grabber.png"))
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color("#120d08")
	sc.set_content_margin_all(4)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color("#8a6d3b")
	grab.border_color = Color("#140e09")
	grab.set_border_width_all(1)
	var grab_hi: StyleBoxFlat = grab.duplicate()
	grab_hi.bg_color = GOLD.darkened(0.15)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, sc)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_hi)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = GOOD
	bar_fill.border_color = Color("#140e09")
	bar_fill.set_border_width_all(1)
	t.set_stylebox("background", "ProgressBar", inset(0.0))
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "Label", TEXT)
	return t


## The default font with wider letter spacing (headings, taglines).
static func spaced_font(spacing: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.spacing_glyph = spacing
	return f


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
	p.add_theme_stylebox_override("panel", panel(22))
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

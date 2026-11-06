class_name MainMenu
extends CanvasLayer
## Title screen over the live village backdrop: single player (opens
## SkirmishSetup), multiplayer lobby, sound options, language, update, quit.
## The Update button checks GitHub for a newer release (UpdateChecker) and is
## enabled only when one exists; pressing it downloads and runs the installer.
## Emits `start_requested(config)`; Main starts the match.

signal start_requested(config: Dictionary)
signal quit_requested

var _single: Button
var _message: Label
var _lobby: LobbyMenu
var _setup: SkirmishSetup
var _update_btn: Button
var _updater: UpdateChecker
var _title: TextureRect
var _tagline: Label
var _rule: TextureRect
var _panel: PanelContainer
var _gap: Control
var _hint: Label
var _title_top := 34.0
var _title_h := 128.0
## Title bob offset in pixels, animated by a looping tween.
var _bob := 0.0

## Below this logical screen height (phones) the title screen is compacted.
const COMPACT_HEIGHT := 820.0


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Dark at the top (title) and bottom (hints), clear in the middle so the
	# live village shows through around the menu.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	grad.colors = PackedColorArray([Color(0.03, 0.02, 0.04, 0.82), Color(0.03, 0.02, 0.04, 0.32),
		Color(0.03, 0.02, 0.04, 0.28), Color(0.03, 0.02, 0.04, 0.78)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gtex.width = 4
	gtex.height = 256
	var shade := TextureRect.new()
	shade.texture = gtex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	# Pixel logo (same art as the web page), bobbing gently. Positions come
	# from _layout(), which also shrinks everything on short (phone) screens.
	_title = TextureRect.new()
	_title.texture = load(UiStyle.UI_ART + "title.png")
	_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title)
	var bob := create_tween().set_loops()
	bob.tween_property(self, "_bob", 5.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(self, "_bob", 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_tagline = UiStyle.label(tr("Gather · Build · Advance · Conquer").to_upper(), 19, Color("#ecd6aa"))
	_tagline.add_theme_font_override("font", UiStyle.spaced_font(3))
	_tagline.add_theme_color_override("font_outline_color", Color("#140e09"))
	_tagline.add_theme_constant_override("outline_size", 5)
	_tagline.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline.offset_left = -500
	_tagline.offset_right = 500
	root.add_child(_tagline)
	_rule = _divider(root, 216)
	_rule.modulate.a = 0.9

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.pixel_panel(30))
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = -230
	_panel.offset_right = 230
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_single = UiStyle.pixel_button(tr("Single player"), 400, 54, 22)
	_single.pressed.connect(open_setup)
	v.add_child(_single)
	var start_row := HBoxContainer.new()
	start_row.add_theme_constant_override("separation", 10)
	v.add_child(start_row)
	var tutorial := UiStyle.pixel_button(tr("Tutorial"), 195)
	tutorial.pressed.connect(func() -> void: start_requested.emit(MatchConfig.tutorial()))
	start_row.add_child(tutorial)
	var load_btn := UiStyle.pixel_button(tr("Load game"), 195)
	load_btn.disabled = SaveGame.list().is_empty()
	load_btn.pressed.connect(func() -> void:
		var dlg := SaveLoadPanel.new()
		dlg.setup(false)
		dlg.load_requested.connect(func(d: Dictionary) -> void: start_requested.emit({"save": d}))
		add_child(dlg))
	start_row.add_child(load_btn)
	var mp := UiStyle.pixel_button(tr("Multiplayer (LAN / VPN)"), 400)
	mp.pressed.connect(_open_lobby)
	v.add_child(mp)
	_gap = Control.new()
	_gap.custom_minimum_size = Vector2(0, 4)
	v.add_child(_gap)
	# Settings row: sound and language side by side, full screen below.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var snd := UiStyle.pixel_button(tr("Sound"), 150, 44, 17)
	snd.pressed.connect(func() -> void: add_child(AudioPanel.new()))
	row.add_child(snd)
	var pick := UiStyle.language_option()
	UiStyle.skin_pixel(pick, 17)
	pick.custom_minimum_size = Vector2(0, 44)
	pick.tooltip_text = tr("Language")
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pick)
	v.add_child(row)
	var full := UiStyle.fullscreen_toggle()
	full.add_theme_color_override("font_color", UiStyle.TEXT)
	full.add_theme_color_override("font_hover_color", UiStyle.GOLD)
	full.add_theme_color_override("font_pressed_color", UiStyle.TEXT)
	full.add_theme_font_size_override("font_size", 17)
	full.add_theme_icon_override("checked", load(UiStyle.UI_ART + "toggle_on.png"))
	full.add_theme_icon_override("unchecked", load(UiStyle.UI_ART + "toggle_off.png"))
	full.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	v.add_child(full)
	_message = UiStyle.label("", 14, Color("#ff8a7a"))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false
	v.add_child(_message)
	var quit := UiStyle.pixel_button(tr("Quit"), 400, 44, 18)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	v.add_child(quit)

	# Version / updates in the bottom-right corner.
	_update_btn = UiStyle.pixel_button(tr("Checking for updates..."), 0, 38, 15)
	_update_btn.disabled = true
	_update_btn.pressed.connect(func() -> void: _updater.download_and_install())
	_update_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_update_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_update_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_update_btn.offset_right = -18
	_update_btn.offset_bottom = -16
	root.add_child(_update_btn)
	var keys := "Tap: select or order · Drag: camera · Pinch: zoom · Hold: select · Back: menu" if Display.touch_screen() 		else "WASD / edges: camera · Wheel: zoom · Left: select · Right: order · F2: technologies · F10: menu"
	_hint = UiStyle.label(tr(keys), 13, UiStyle.TEXT_DIM)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_left = -600
	_hint.offset_right = 600
	_hint.offset_top = -36
	root.add_child(_hint)
	_layout()
	get_viewport().size_changed.connect(_layout)
	_single.grab_focus()
	_updater = UpdateChecker.new()
	add_child(_updater)
	_updater.state_changed.connect(_on_update_state)
	_updater.check()


func _process(_delta: float) -> void:
	if _title != null:
		_title.offset_top = _title_top + _bob
		_title.offset_bottom = _title_top + _bob + _title_h
	if _updater != null and _updater.state == UpdateChecker.State.DOWNLOADING:
		_update_btn.text = tr("Downloading update... %d%%") % roundi(_updater.progress() * 100.0)


func _on_update_state(st: UpdateChecker.State) -> void:
	_update_btn.disabled = st != UpdateChecker.State.AVAILABLE
	match st:
		UpdateChecker.State.CHECKING:
			_update_btn.text = tr("Checking for updates...")
		UpdateChecker.State.UP_TO_DATE:
			_update_btn.text = tr("Up to date (%s)") % UpdateChecker.current_version()
		UpdateChecker.State.AVAILABLE:
			_update_btn.text = tr("Update to %s") % _updater.latest_version
		UpdateChecker.State.DOWNLOADING:
			_update_btn.text = tr("Downloading update... %d%%") % 0
		UpdateChecker.State.LAUNCHED:
			_update_btn.text = tr("Starting installer...")
		UpdateChecker.State.FAILED:
			_update_btn.text = tr("Update")
			_update_btn.tooltip_text = tr("Could not reach the update server")


## Places title, tagline, rule and menu for the current screen height. On a
## short screen (a phone draws ~640 logical px) the logo shrinks and the menu
## moves up so nothing reaches the controls hint at the bottom.
func _layout() -> void:
	var h := get_viewport().get_visible_rect().size.y
	var compact := h < COMPACT_HEIGHT
	var k := clampf((h - 560.0) / (COMPACT_HEIGHT - 560.0), 0.0, 1.0) if compact else 1.0
	_title_top = lerpf(10.0, 34.0, k)
	_title_h = lerpf(70.0, 128.0, k)
	_title.offset_left = -480
	_title.offset_right = 480
	var tag_y := _title_top + _title_h + lerpf(6.0, 20.0, k)
	_tagline.add_theme_font_size_override("font_size", 15 if compact else 19)
	_tagline.offset_top = tag_y
	var rule_y := tag_y + lerpf(24.0, 34.0, k)
	_rule.offset_top = rule_y
	_rule.offset_bottom = rule_y + _rule.texture.get_height()
	_panel.add_theme_stylebox_override("panel", UiStyle.pixel_panel(24 if compact else 30))
	_panel.offset_top = rule_y + lerpf(14.0, 46.0, k)
	_gap.visible = not compact
	_hint.add_theme_font_size_override("font_size", 12 if compact else 13)
	_hint.offset_top = -26 if compact else -36


## Gold rule with a diamond, centred at height `y`.
func _divider(parent: Control, y: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load(UiStyle.UI_ART + "divider.png")
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.set_anchors_preset(Control.PRESET_CENTER_TOP)
	r.offset_left = -r.texture.get_width() * 0.5
	r.offset_right = r.texture.get_width() * 0.5
	r.offset_top = y
	r.offset_bottom = y + r.texture.get_height()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## Opens the single-player setup screen.
func open_setup() -> void:
	if _setup != null and is_instance_valid(_setup):
		return
	_setup = SkirmishSetup.new()
	add_child(_setup)
	_setup.start_requested.connect(func(cfg: Dictionary) -> void: start_requested.emit(cfg))
	_setup.closed.connect(func() -> void:
		_setup = null
		_single.grab_focus())


## Shows a one-line message (e.g. why a network session ended).
func show_message(text: String) -> void:
	if _message:
		_message.text = Loc.text(text)
		_message.visible = not _message.text.is_empty()


func _open_lobby() -> void:
	if _lobby != null and is_instance_valid(_lobby):
		return
	_lobby = LobbyMenu.new()
	add_child(_lobby)
	_lobby.closed.connect(func() -> void: _lobby = null)

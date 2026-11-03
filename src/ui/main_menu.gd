class_name MainMenu
extends CanvasLayer
## Title screen: match setup (mode, difficulty, map size, victory condition,
## fog of war, seed). Emits `start_requested(config)`; Main starts the match.

signal start_requested(config: Dictionary)
signal quit_requested

const MODES := [["skirmish", "Skirmish vs Computer"], ["sandbox", "Sandbox (no enemies)"]]

var _mode: OptionButton
var _difficulty: OptionButton
var _size: OptionButton
var _map_type: OptionButton
var _victory: OptionButton
var _fog: CheckButton
var _seed: LineEdit
var _start: Button
var _message: Label
var _lobby: LobbyMenu


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Soft vignette so the live backdrop does not fight the text.
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var title := UiStyle.title("PIXEL EMPIRE", 76)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -500
	title.offset_right = 500
	title.offset_top = 46
	root.add_child(title)
	var tagline := UiStyle.label(tr("Gather · Build · Advance · Conquer"), 20, UiStyle.TEXT)
	tagline.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.offset_left = -400
	tagline.offset_right = 400
	tagline.offset_top = 138
	root.add_child(tagline)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(22))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -230
	panel.offset_right = 230
	panel.offset_top = -205
	panel.offset_bottom = 281
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UiStyle.label(tr("New game"), 24, UiStyle.GOLD))

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 16)
	form.add_theme_constant_override("v_separation", 8)
	v.add_child(form)
	var rules: Dictionary = GameData.rules
	_mode = UiStyle.option(MODES.map(func(m): return tr(m[1])))
	_add_row(form, tr("Mode"), _mode)
	var diffs: Array = rules.get("difficulties_menu", ["easy", "normal", "hard"])
	_difficulty = UiStyle.option(diffs.map(func(d): return tr(String(d).capitalize())), diffs.find("normal"))
	_add_row(form, tr("Difficulty"), _difficulty)
	var sizes: Array = rules.get("map_sizes_menu", ["small"])
	var tiles: Dictionary = GameData.map_gen.get("sizes", {})
	_size = UiStyle.option(sizes.map(func(s): return "%s (%d×%d)" % [tr(String(s).capitalize()), int(tiles.get(s, 96)), int(tiles.get(s, 96))]), maxi(0, sizes.find(GameData.map_gen.get("default_size", "small"))))
	_add_row(form, tr("Map size"), _size)
	var types: Array = rules.get("map_types_menu", ["continental"])
	var tdefs: Dictionary = GameData.map_gen.get("map_types", {})
	_map_type = UiStyle.option(types.map(func(t): return tr(String(tdefs.get(t, {}).get("display_name", String(t).capitalize())))), maxi(0, types.find(GameData.map_gen.get("default_map_type", "continental"))))
	_add_row(form, tr("Map type"), _map_type)
	var vcs: Dictionary = rules.get("victory_conditions", {})
	_victory = UiStyle.option(vcs.keys().map(func(k): return tr(vcs[k]["display_name"])), maxi(0, vcs.keys().find(rules.get("default_victory", "conquest"))))
	_add_row(form, tr("Victory"), _victory)
	_fog = CheckButton.new()
	_fog.button_pressed = true
	_fog.text = tr("Explore the map")
	_add_row(form, tr("Fog of war"), _fog)
	_seed = LineEdit.new()
	_seed.placeholder_text = tr("random")
	_seed.custom_minimum_size = Vector2(220, 34)
	_add_row(form, tr("Map seed"), _seed)
	_add_row(form, tr("Language"), UiStyle.language_option())
	_mode.item_selected.connect(func(i: int) -> void: _difficulty.disabled = MODES[i][0] == "sandbox")

	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	v.add_child(gap)
	_start = UiStyle.button(tr("Start game"), 400)
	_start.pressed.connect(func() -> void: start_requested.emit(config()))
	v.add_child(_start)
	var mp := UiStyle.button(tr("Multiplayer (LAN / VPN)"), 400)
	mp.pressed.connect(_open_lobby)
	v.add_child(mp)
	_message = UiStyle.label("", 14, Color("#ff8a7a"))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_message)
	var quit := UiStyle.button(tr("Quit"), 400)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	v.add_child(quit)
	var hint := UiStyle.label(tr("WASD / edges: camera · Wheel: zoom · Left: select · Right: order · F2: technologies · F10: menu"), 13, UiStyle.TEXT_DIM)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.offset_left = -600
	hint.offset_right = 600
	hint.offset_top = -40
	root.add_child(hint)
	_start.grab_focus()


## Shows a one-line message (e.g. why a network session ended).
func show_message(text: String) -> void:
	if _message:
		_message.text = Loc.text(text)


func _open_lobby() -> void:
	if _lobby != null and is_instance_valid(_lobby):
		return
	_lobby = LobbyMenu.new()
	add_child(_lobby)
	_lobby.closed.connect(func() -> void: _lobby = null)


func _add_row(form: GridContainer, text: String, control: Control) -> void:
	form.add_child(UiStyle.label(text, 16, UiStyle.TEXT_DIM))
	form.add_child(control)


## The match configuration currently selected.
func config() -> Dictionary:
	var rules: Dictionary = GameData.rules
	var seed_text := _seed.text.strip_edges()
	return {
		"mode": MODES[_mode.selected][0],
		"difficulty": rules.get("difficulties_menu", ["normal"])[_difficulty.selected],
		"size": rules.get("map_sizes_menu", ["small"])[_size.selected],
		"map_type": rules.get("map_types_menu", ["continental"])[_map_type.selected],
		"victory": rules.get("victory_conditions", {}).keys()[_victory.selected],
		"fog": _fog.button_pressed,
		"seed": seed_text.hash() & 0x7fffffff if seed_text != "" and not seed_text.is_valid_int() else int(seed_text) if seed_text != "" else 0,
	}

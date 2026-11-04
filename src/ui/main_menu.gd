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
	panel.offset_top = -170
	panel.offset_bottom = 316
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_single = UiStyle.button(tr("Single player"), 400)
	_single.pressed.connect(open_setup)
	v.add_child(_single)
	var load_btn := UiStyle.button(tr("Load game"), 400)
	load_btn.disabled = SaveGame.list().is_empty()
	load_btn.pressed.connect(func() -> void:
		var dlg := SaveLoadPanel.new()
		dlg.setup(false)
		dlg.load_requested.connect(func(d: Dictionary) -> void: start_requested.emit({"save": d}))
		add_child(dlg))
	v.add_child(load_btn)
	var mp := UiStyle.button(tr("Multiplayer (LAN / VPN)"), 400)
	mp.pressed.connect(_open_lobby)
	v.add_child(mp)
	var snd := UiStyle.button(tr("Sound"), 400)
	snd.pressed.connect(func() -> void: add_child(AudioPanel.new()))
	v.add_child(snd)
	var lang := HBoxContainer.new()
	lang.add_child(UiStyle.label(tr("Language"), 16, UiStyle.TEXT_DIM))
	var pick := UiStyle.language_option()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang.add_child(pick)
	v.add_child(lang)
	v.add_child(UiStyle.fullscreen_toggle())
	_update_btn = UiStyle.button(tr("Checking for updates..."), 400)
	_update_btn.disabled = true
	_update_btn.pressed.connect(func() -> void: _updater.download_and_install())
	v.add_child(_update_btn)
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
	_single.grab_focus()
	_updater = UpdateChecker.new()
	add_child(_updater)
	_updater.state_changed.connect(_on_update_state)
	_updater.check()


func _process(_delta: float) -> void:
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


func _open_lobby() -> void:
	if _lobby != null and is_instance_valid(_lobby):
		return
	_lobby = LobbyMenu.new()
	add_child(_lobby)
	_lobby.closed.connect(func() -> void: _lobby = null)

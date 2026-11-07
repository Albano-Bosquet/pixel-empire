extends Node
## Window mode (autoload `Display`). F11 or Alt+Enter toggles full screen
## anywhere in the game, and the menus show a switch bound to the same state.
## The choice is stored in user://settings.cfg [display] fullscreen; the
## command line can force it with `-- --fullscreen` or `-- --windowed`.
## Interface scale: 1 on PC; on phones and tablets the whole game is drawn larger
## so the HUD fits a logical screen height (touch_settings.json); `-- --ui-scale=1.5`
## forces a value (tests, small PC screens).

signal fullscreen_changed(on: bool)

const SETTINGS_PATH := "user://settings.cfg"
## Frame rate limits offered in the menus (0 = no limit).
const FPS_CHOICES: Array[int] = [60, 90, 120, 0]
## Phones start limited: at 120 fps they heat up and throttle within a minute.
const MOBILE_FPS_LIMIT := 60

signal fps_limit_changed(limit: int)

var fullscreen := false
## Highest frame rate the game draws at (0 = no limit). Stored in settings.cfg.
var fps_limit := 0
## Factor applied to the root window's content (1 = native pixels).
var ui_scale := 1.0


## Scale that makes a screen `short_side_px` tall show `target_height` logical
## pixels: never below 1 (PC layouts stay as designed), at most `max_scale`.
## Example: Display.scale_for(1080, 640, 3.0) -> 1.6875
static func scale_for(short_side_px: int, target_height: int, max_scale: float) -> float:
	if target_height <= 0:
		return 1.0
	return clampf(float(short_side_px) / float(target_height), 1.0, max_scale)


## Limit before the player picks one: phones are limited, PCs are not.
static func default_fps_limit(mobile: bool) -> int:
	return MOBILE_FPS_LIMIT if mobile else 0


## The choice after `limit` in FPS_CHOICES, wrapping; unknown limits go to the first.
## Example: Display.next_fps_limit(60) -> 90
static func next_fps_limit(limit: int) -> int:
	return FPS_CHOICES[(FPS_CHOICES.find(limit) + 1) % FPS_CHOICES.size()]


## Stores and applies a frame rate limit (0 = none).
func set_fps_limit(limit: int) -> void:
	fps_limit = limit
	Engine.max_fps = limit
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "fps_limit", limit)
	cfg.save(SETTINGS_PATH)
	fps_limit_changed.emit(limit)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Pixel-art skin for every control that does not style itself. Merged into
	# the engine default theme (not set on the root window) so it also reaches
	# controls under CanvasLayers, which do not inherit a window theme.
	if DisplayServer.get_name() != "headless":
		ThemeDB.get_default_theme().merge_with(UiStyle.theme())
	fps_limit = default_fps_limit(OS.has_feature("mobile"))
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
		fps_limit = int(cfg.get_value("display", "fps_limit", fps_limit))
	Engine.max_fps = fps_limit
	for a in OS.get_cmdline_user_args():
		if a == "--fullscreen":
			fullscreen = true
		elif a == "--windowed":
			fullscreen = false
	if DisplayServer.get_name() != "headless":
		_apply()
		_apply_scale()


## Whether the player plays with fingers: a touch screen, or `-- --touch` (tests).
func touch_screen() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch")


func _apply_scale() -> void:
	var cfg: Dictionary = GameData.touch
	if OS.has_feature("mobile"):
		var screen := DisplayServer.screen_get_size()
		ui_scale = scale_for(mini(screen.x, screen.y), int(cfg.get("mobile_target_height", 640)), float(cfg.get("max_ui_scale", 3.0)))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-scale="):
			ui_scale = maxf(float(a.trim_prefix("--ui-scale=")), 0.5)
	if is_equal_approx(ui_scale, 1.0):
		return
	# Layout at window / scale logical pixels, then drawn scaled up: the HUD keeps
	# its anchors and fits the screen instead of being zoomed past its edges.
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(Vector2(root.size) / ui_scale)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()


## Switches full screen on or off and remembers it for the next launch.
func set_fullscreen(on: bool) -> void:
	if on == fullscreen:
		return
	fullscreen = on
	_apply()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)
	fullscreen_changed.emit(fullscreen)


## Exclusive full screen, with the cursor confined to the window so it cannot
## drift onto a second monitor (edge scrolling needs the screen edges).
func _apply() -> void:
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED if fullscreen else Input.MOUSE_MODE_VISIBLE


## Windows drops the cursor clip when the game loses focus (Alt+Tab), so it
## is set again when the window comes back.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and fullscreen:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED

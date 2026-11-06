extends "res://src/debug/smoke_layout.gd"
## Tutorial smoke: plays the guided match from the first step to the victory screen.
##   -- --smoke=tutorial --mode=tutorial
## Phone size: `--resolution 1600x720 -- --smoke=tutorial --mode=tutorial --windowed --ui-scale=1.125`
## Each step is finished with the orders a player would give, and the step only
## moves on because the match really changed. Also checks the arrow (entity,
## command button, page flip, rest), the Skip button, that a save resumes at the
## same step without a second camp or a second gift, and the menu button.

const SPEED := 10.0
## In game seconds: the longest wait is the age research.
const STEP_TIMEOUT := 300.0

const BUILD_OFFSETS := {"barracks": Vector2i(-9, -6), "house": Vector2i(5, -7), "farm": Vector2i(5, 3)}

## Free tiles required on every side of the Barracks.
const OPEN_MARGIN := 5
## Tiles from the Town Center where the search starts.
const BARRACKS_MIN_DIST := 6

var _t: TutorialSystem
var _panel: TutorialPanel


func run_mode(game: Game, _mode: String) -> void:
	_game = game
	game.camera.settings["edge_scroll"] = false
	_play.call_deferred()


func _play() -> void:
	await _frames(10)
	_t = _game.tutorial
	_panel = _game.get_node("TutorialPanel")
	_check(_t != null and _t.steps.size() > 0, "the match starts as a tutorial")
	_check(_t.index == 0, "it starts at the first step")
	_check(_count(2, false) == GameData.tutorial["camp"]["units"]["militia"], "the camp has its guards")
	_check(not _enemy_has("town_center"), "the bandits have no Town Center")
	_check(_game.ai_players.is_empty(), "no AI drives the camp")
	_panel_fits()
	await _shot("tutorial_01_start")
	if OS.get_cmdline_user_args().has("--cards"):
		await _cards()
		_finish()
		return

	_game.camera.position += Vector2(260, 0)
	await _until("select_villager")
	_game.camera.focus_world(Iso.grid_to_world(Iso.tile_center(_game.map.start_positions[0])))
	await _seconds(0.4)
	_check(_points_at_type("villager"), "the arrow points at a villager")
	await _shot("tutorial_02_arrow_on_villager")
	var v := _villagers()
	_game.selection.set_selection([v[0]])
	await _until("gather_food")
	await _seconds(0.4)
	var food: Entity = _t.pointer().get("entity")
	_check(food is ResourceNode and food.resource_type == "food", "with a villager selected the arrow moves to the food")
	_gather([v[0]], food)
	await _until("gather_wood")
	await _seconds(0.4)
	_game.selection.set_selection([v[1]])
	await _seconds(0.4)
	_gather([v[1]], _t.pointer().get("entity"))
	await _until("train_villager")

	Engine.time_scale = SPEED
	_game.selection.set_selection([])
	await _seconds(0.5)
	_check(_t.pointer().get("entity") == _building("town_center"), "the arrow points at the Town Center")
	var tc := _building("town_center")
	_game.selection.set_selection([tc])
	await _frames(4)
	var train: Button = _t.pointer().get("control")
	_check(train != null, "with the Town Center selected the arrow moves to the train button")
	Engine.time_scale = 1.0
	await _seconds(0.3)
	await _shot("tutorial_03_arrow_on_button")
	Engine.time_scale = SPEED
	train.pressed.emit()
	await _frames(4)
	_check(_t.pointer().is_empty(), "the arrow rests once the villager is queued")
	await _until("house")

	await _build("house", v[2])
	await _until("more_villagers")
	_game.selection.set_selection([tc])
	await _frames(4)
	for k in 2:
		_game.orders.submit({"t": "enqueue", "b": tc.entity_id, "item": "villager"})
	await _until("gather_gold")
	var idle := _villagers().filter(func(u: Unit) -> bool: return u.task.is_empty())
	_check(not idle.is_empty(), "the new villagers wait for orders")
	_game.selection.set_selection([idle[0]])
	await _seconds(0.5)
	_gather([idle[0]], _t.pointer().get("entity"))
	await _until("farm")
	await _build("farm", idle[1] if idle.size() > 1 else v[2])
	await _until("scout")

	var scout := _scout()
	_game.selection.set_selection([scout])
	var camp_at := Iso.tile_center(_game.map.start_positions[1] + Vector2i(3, -2))
	Engine.time_scale = 1.0
	await _seconds(0.3)
	_check(_t.pointer().get("entity") != null and _t.pointer()["entity"].owner_id == 2, "with the scout selected the arrow points at the camp")
	var tip: Variant = _panel._arrow.tip()
	_check(tip != null and get_viewport().get_visible_rect().has_point(tip), "an arrow to an off-screen target stays on screen")
	await _shot("tutorial_04_arrow_at_edge")
	Engine.time_scale = SPEED
	_game.orders.submit({"t": "issue", "units": [scout.entity_id], "buildings": [], "grid": camp_at, "target": 0})
	await _until("advance_age")
	_check(_game.local_state().resources["food"] >= 500, "the supplies for the age arrive")
	_game.selection.set_selection([tc])
	await _frames(4)
	_game.orders.submit({"t": "enqueue", "b": tc.entity_id, "item": "feudal_age"})
	await _until("barracks")

	_game.selection.set_selection([v[2]])
	await _frames(4)
	var panel: CommandPanel = _find(_game.hud, func(n): return n is CommandPanel)
	_check(panel.button_for("barracks") != null, "the Barracks points at the page flip while the economy page shows")
	var title := func() -> String: return panel.button_for("barracks").info.get("title", "")
	if title.call() != tr("Barracks"):
		panel.handle_key(KEY_TAB)
		await _frames(4)
	_check(title.call() == tr("Barracks"), "the Barracks has its own button on the military page")
	await _build("barracks", v[2], false)
	await _until("second_house")
	await _build("house", v[2])
	await _until("militia")
	await _resumes_from_save()
	var bk := _building("barracks")
	for k in 5:
		_game.orders.submit({"t": "enqueue", "b": bk.entity_id, "item": "militia"})
	await _until("feudal_reached")
	await _until("technology")
	tc = _building("town_center")
	_game.orders.submit({"t": "enqueue", "b": tc.entity_id, "item": "wheelbarrow"})
	await _until("spearmen")
	bk = _building("barracks")
	for k in 2:
		_game.orders.submit({"t": "enqueue", "b": bk.entity_id, "item": "spearman"})
	await _until("select_army")

	var skip_from := _t.index
	_panel._skip.pressed.emit()
	await _frames(3)
	_check(_t.index == skip_from + 1 and _t.current()["id"] == "attack", "Skip moves to the next step")
	var army := _game.unit_system.units.filter(func(u): return u.owner_id == 1 and not u.dead and u.is_military() and u.type_id != "scout")
	_check(army.size() >= 7, "the army is ready (%d)" % army.size())
	_game.selection.set_selection(army)
	await _seconds(0.5)
	_game.orders.submit({"t": "attack_move", "units": OrderRouter.ids(army), "grid": camp_at})
	await _until("destroy_camp")
	_check(not _t.can_skip(), "the last step cannot be skipped")
	Engine.time_scale = SPEED
	var won := [false]
	EventBus.game_over.connect(func(w: Array) -> void: won[0] = w.has(1))
	var left := STEP_TIMEOUT
	while not _t.over and left > 0.0:
		var target := _enemy_entity()
		var idle_army := _game.unit_system.units.filter(func(u): return u.owner_id == 1 and not u.dead and u.is_military() and u.type_id != "scout" and u.state == Unit.State.IDLE and not u.has_target())
		if target != null and not idle_army.is_empty():
			_game.orders.submit({"t": "issue", "units": OrderRouter.ids(idle_army), "buildings": [], "grid": target.grid_pos, "target": target.entity_id})
		await _seconds(5.0)
		left -= 5.0
	Engine.time_scale = 1.0
	_check(_t.over and won[0], "destroying the camp wins the match")
	await _frames(6)
	_check(not _panel._panel.visible, "the step card leaves with the victory screen")
	await _shot("tutorial_05_victory")
	await _menu_button()
	_finish()


## Touch wording and the longest cards, without playing the match:
##   --resolution 1600x720 -- --smoke=tutorial --mode=tutorial --windowed --ui-scale=1.125 --touch --cards
func _cards() -> void:
	var touch: bool = _game.touch != null and _game.touch.enabled
	var words := ["right click", "left click", "mouse", "wasd", "ctrl", "shift", "f2", "key"]
	for step in _t.steps:
		var text := TutorialSystem.step_text(step, touch).to_lower()
		if touch:
			_check(not words.any(func(w): return text.contains(w)), "step '%s' has no mouse or keyboard words" % step["id"])
			_check(step["id"] == "select_villager" or step["id"] == "destroy_camp" or step["id"] == "camera" or step.has("text_touch") or not step.has("point"), "step '%s' has touch text" % step["id"])
	for id in ["house", "scout", "barracks", "attack"]:
		while _t.current()["id"] != id:
			_t.advance()
		await _frames(4)
		await _shot("tutorial_touch_" + id)


## Saves and reloads: same step, one camp, no second helping of supplies.
func _resumes_from_save() -> void:
	var was := _t.index
	var guards := _count(2, false)
	var gold: int = _game.local_state().resources["gold"]
	var main: Node = get_parent()
	main.start_game({"save": SaveGame.capture(_game)})
	await _frames(12)
	_game = main.game
	_game.camera.settings["edge_scroll"] = false
	Engine.time_scale = SPEED
	_t = _game.tutorial
	_panel = _game.get_node("TutorialPanel")
	_check(_t != null and _t.index == was, "a save resumes at the same step")
	_check(_count(2, false) == guards, "loading does not add a second camp")
	_check(_game.local_state().resources["gold"] == gold, "loading does not repeat the supplies")


func _menu_button() -> void:
	var menu := MainMenu.new()
	get_tree().root.add_child(menu)
	await _frames(6)
	var got: Array = []
	menu.start_requested.connect(func(cfg: Dictionary) -> void: got.append(cfg))
	var b: Button = _find(menu, func(n): return n is Button and n.text == tr("Tutorial"))
	_check(b != null, "the main menu has a Tutorial button")
	if b != null:
		b.pressed.emit()
	_check(not got.is_empty() and got[0].get("tutorial", false), "the button starts the tutorial")
	menu.queue_free()


## Waits for step `id`, with the checks of a player who is not looking at the clock.
func _until(id: String) -> void:
	var left := STEP_TIMEOUT
	while _t.current().get("id", "") != id and left > 0.0:
		await _seconds(0.5)
		left -= 0.5
	_check(_t.current().get("id", "") == id, "reaches step '%s' (at '%s')" % [id, _t.current().get("id", "")])


func _panel_fits() -> void:
	var vp := get_viewport().get_visible_rect()
	var r := _panel._panel.get_global_rect()
	_check(vp.encloses(r), "the step card is on screen (%s in %s)" % [r, vp])
	_check(r.end.y <= vp.size.y - TutorialPanel.EDGE_BOTTOM - 40.0, "the step card stays clear of the quick bar (ends at %.0f of %.0f)" % [r.end.y, vp.size.y])
	for step in _t.steps:
		_panel._text.text = tr(TutorialSystem.step_text(step, _game.touch != null and _game.touch.enabled))
		_panel._title.text = tr(String(step["title"]))
		_panel._panel.reset_size()
		var tall := _panel._panel.get_combined_minimum_size().y
		_check(TutorialPanel.PANEL_TOP + tall <= vp.size.y - TutorialPanel.EDGE_BOTTOM - 40.0, "step '%s' fits (%.0f px)" % [step["id"], tall])
	_panel._show_step()


func _gather(units: Array, node: Entity) -> void:
	_check(node != null, "there is something to gather")
	if node != null:
		_game.orders.submit({"t": "issue", "units": OrderRouter.ids(units), "buildings": [], "grid": node.grid_pos, "target": node.entity_id})


## Places `type_id` near the Town Center with `builder`, the way the HUD does.
func _build(type_id: String, builder: Unit, select: bool = true) -> void:
	if select:
		_game.selection.set_selection([builder])
		await _frames(4)
	_check(_t.pointer().has("control"), "%s: the arrow is on the command panel" % type_id)
	var near: Vector2i = _game.map.start_positions[0] + BUILD_OFFSETS.get(type_id, Vector2i(6, 4))
	var spot := _open_spot_for(type_id, near) if type_id == "barracks" else _find_build_spot(type_id, near)
	_game.orders.submit({"t": "place", "type": type_id, "origins": [spot], "builders": [builder.entity_id]})
	await _seconds(0.6)
	_check(_t.pointer().is_empty() or _t.current().get("id", "") != String(type_id), "%s: the arrow rests once it is placed" % type_id)


## Closest spot to the Town Center with open ground all around and a straight
## walk back to it: what leaves the Barracks must not end up behind a lake.
func _open_spot_for(type_id: String, near: Vector2i) -> Vector2i:
	var start: Vector2i = _game.map.start_positions[0]
	var size := int(GameData.building(type_id)["size"])
	for r in range(BARRACKS_MIN_DIST, 24):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := start + Vector2i(dx, dy)
				if _game.buildings.placement_error(type_id, o) == "" and _clear_around(o, size) and _clear_walk(start, o):
					return o
	return _find_build_spot(type_id, near)


## Every tile on the way from the edge of the Town Center to `to` can be walked.
func _clear_walk(from: Vector2i, to: Vector2i) -> bool:
	var steps := int(Vector2(to - from).length())
	for i in range(BARRACKS_MIN_DIST - 1, steps):
		var t := Vector2i(Vector2(from).lerp(Vector2(to), float(i) / steps).round())
		if not _game.pathfinder.is_walkable(t):
			return false
	return true


func _clear_around(origin: Vector2i, size: int) -> bool:
	for y in range(-OPEN_MARGIN, size + OPEN_MARGIN):
		for x in range(-OPEN_MARGIN, size + OPEN_MARGIN):
			if not _game.pathfinder.is_walkable(origin + Vector2i(x, y)):
				return false
	return true


func _villagers() -> Array:
	return _game.unit_system.units.filter(func(u): return u.owner_id == 1 and not u.dead and u.is_worker)


func _scout() -> Unit:
	for u in _game.unit_system.units:
		if u.owner_id == 1 and u.type_id == "scout":
			return u
	return null


func _building(type_id: String) -> Building:
	for b in _game.buildings.buildings:
		if b.owner_id == 1 and b.type_id == type_id and not b.dead:
			return b
	return null


func _enemy_has(type_id: String) -> bool:
	return _game.buildings.buildings.any(func(b): return b.owner_id == 2 and b.type_id == type_id)


func _enemy_entity() -> Entity:
	for u in _game.unit_system.units:
		if u.owner_id == 2 and not u.dead:
			return u
	for b in _game.buildings.buildings:
		if b.owner_id == 2 and not b.dead and b.type_id != "house":
			return b
	return null


func _count(owner: int, workers: bool) -> int:
	return _game.unit_system.units.filter(func(u): return u.owner_id == owner and not u.dead and u.is_worker == workers).size()


func _points_at_type(type_id: String) -> bool:
	var e: Variant = _t.pointer().get("entity")
	return e is Unit and e.type_id == type_id

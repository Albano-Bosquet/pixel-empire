class_name SelectionSystem
extends Node
## Left-mouse selection: click, shift-click (toggle), drag rectangle,
## double-click or Ctrl+click (all of that type on screen), control groups
## (Ctrl+0..9 to assign, Shift+0..9 to add, 0..9 to recall, double-tap to
## centre the camera), Esc to clear.
## Emits EventBus.selection_changed.

signal box_changed(screen_rect: Rect2, active: bool)

const DRAG_THRESHOLD_PX := 6.0
const DOUBLE_CLICK_MS := 350

var selected: Array[Entity] = []
var groups: Dictionary = {}

var _game: Game
var _pressing := false
var _box_active := false
var _press_pos := Vector2.ZERO
var _last_click_ms := -10000
var _last_click_type := ""
var _last_group_key := -1
var _last_group_ms := -10000
var _idle_cursor := -1


func setup(game: Game) -> void:
	_game = game


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_box_active = false
			_press_pos = event.position
		elif _pressing:
			_pressing = false
			if _box_active:
				_box_active = false
				box_changed.emit(Rect2(), false)
				select_in_screen_rect(_rect(_press_pos, event.position), event.shift_pressed)
			else:
				_click(event.position, event.shift_pressed, event.ctrl_pressed)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pressing:
		if not _box_active and event.position.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_box_active = true
		if _box_active:
			box_changed.emit(_rect(_press_pos, event.position), true)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _rect(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(a.min(b), (a - b).abs())


## Selects the local player's units whose body lies inside the screen rect.
func select_in_screen_rect(screen_rect: Rect2, additive: bool) -> void:
	var found: Array[Entity] = []
	for u in _game.unit_system.units:
		if u.owner_id == _game.local_player and screen_rect.has_point(_game.screen_from_world(u.position + Vector2(0, -14))):
			found.append(u)
	var people := found.filter(func(e): return not e.def.has("animal"))
	if not people.is_empty():
		found = people
	if found.is_empty():
		for b in _game.buildings.buildings:
			if b.owner_id == _game.local_player and screen_rect.has_point(_game.screen_from_world(b.position)):
				found.append(b)
				break
	if additive:
		for e in selected:
			if not found.has(e):
				found.append(e)
	if found.is_empty() and additive:
		return
	set_selection(found)


func _click(screen_pos: Vector2, additive: bool, same_type: bool = false) -> void:
	var e := pick(screen_pos)
	var now := Time.get_ticks_msec()
	var is_double := e != null and (same_type or now - _last_click_ms < DOUBLE_CLICK_MS and _last_click_type == e.type_id)
	_last_click_ms = now
	_last_click_type = e.type_id if e != null else ""
	if e == null:
		if not additive:
			set_selection([])
		return
	if is_double and e is Unit and e.owner_id == _game.local_player:
		var vp_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		var same: Array[Entity] = []
		for u in _game.unit_system.units:
			if u.owner_id == e.owner_id and u.type_id == e.type_id and vp_rect.has_point(_game.screen_from_world(u.position)):
				same.append(u)
		set_selection(same)
		return
	if additive and e.owner_id == _game.local_player and e is Unit:
		var list := selected.duplicate()
		if list.has(e):
			list.erase(e)
		else:
			list.append(e)
		set_selection(list)
	else:
		set_selection([e])


## Front-most selectable entity under the screen position (units preferred).
func pick(screen_pos: Vector2) -> Entity:
	var world := _game.world_from_screen(screen_pos)
	var g := Iso.world_to_grid(world)
	var best: Entity = null
	var near: Array = []
	_game.unit_system.units_near(g + Vector2(1, 1), 2.5, near)
	for u in near:
		if u.visible and not u.dead and u.global_pick_rect().has_point(world) and (best == null or u.position.y > best.position.y):
			best = u
	if best != null:
		return best
	var t := Iso.tile_of(g)
	for dy in range(-1, 6):
		for dx in range(-1, 6):
			var e: Entity = _game.static_entity_at(t + Vector2i(dx, dy))
			if e != null and e.selectable and e.visible and e.hit_test(world) and (best == null or e.position.y > best.position.y):
				best = e
	return best


func set_selection(list: Array) -> void:
	for e in selected:
		if is_instance_valid(e):
			e.selected = false
	selected.clear()
	for e in list:
		if is_instance_valid(e) and e.selectable:
			e.ring_color = _ring_color(e)
			e.selected = true
			selected.append(e)
	EventBus.selection_changed.emit(selected)


## Removes freed entities from the selection (call when entities die).
func prune() -> void:
	var before := selected.size()
	selected = selected.filter(func(e): return is_instance_valid(e) and not e.dead)
	if selected.size() != before:
		EventBus.selection_changed.emit(selected)


func own_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for e in selected:
		if is_instance_valid(e) and e is Unit and not e.dead and e.owner_id == _game.local_player:
			out.append(e)
	return out


func own_buildings() -> Array[Building]:
	var out: Array[Building] = []
	for e in selected:
		if is_instance_valid(e) and e is Building and e.owner_id == _game.local_player:
			out.append(e)
	return out


## Selects the next idle worker of the local player and centres the camera on it.
func select_idle_worker() -> void:
	var idle: Array[Unit] = []
	for u in _game.unit_system.units:
		if u.owner_id == _game.local_player and u.is_worker and u.task.is_empty() and u.state == Unit.State.IDLE:
			idle.append(u)
	if idle.is_empty():
		EventBus.notify.emit(_game.local_player, "No idle villagers")
		return
	_idle_cursor = (_idle_cursor + 1) % idle.size()
	set_selection([idle[_idle_cursor]])
	_game.camera.focus_world(idle[_idle_cursor].position)


func _ring_color(e: Entity) -> Color:
	if e.owner_id == Entity.GAIA:
		return Color("#f2e3a0")
	if e.owner_id == _game.local_player:
		return Color("#e8ffe0")
	return Color("#ff8a7a")


func _key(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
		if selected.is_empty():
			EventBus.pause_requested.emit()
		else:
			set_selection([])
		return
	if event.keycode == KEY_PERIOD:
		select_idle_worker()
		return
	if event.keycode == KEY_DELETE:
		var own := selected.filter(func(e): return is_instance_valid(e) and e.owner_id == _game.local_player)
		if not own.is_empty():
			_game.orders.submit({"t": "delete", "ids": OrderRouter.ids(own)})
		return
	var digit: int = event.keycode - KEY_0
	if digit < 0 or digit > 9:
		return
	if event.ctrl_pressed:
		groups[digit] = selected.duplicate()
		return
	if event.shift_pressed:
		var merged: Array = groups.get(digit, []).filter(func(e): return is_instance_valid(e))
		for e in selected:
			if not merged.has(e):
				merged.append(e)
		groups[digit] = merged
		EventBus.notify.emit(_game.local_player, Loc.msg("Group %s: %s", [digit, merged.size()]))
		return
	if not groups.has(digit):
		return
	var g: Array = groups[digit].filter(func(e): return is_instance_valid(e))
	groups[digit] = g
	set_selection(g)
	var now := Time.get_ticks_msec()
	if _last_group_key == digit and now - _last_group_ms < DOUBLE_CLICK_MS and not g.is_empty():
		_game.camera.focus_world(g[0].position)
	_last_group_key = digit
	_last_group_ms = now

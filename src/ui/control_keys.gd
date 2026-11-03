class_name ControlKeys
extends RefCounted
## Quality-of-life shortcuts (Phase 5), checked by the HUD after the command
## panel's own letter hotkeys:
##   Space        jump to the latest "under attack" alert (cycles back through recent ones)
##   Ctrl+Space   centre the camera on the selection
##   ,            next idle military unit
##   Home         select the Town Center (cycles through them)
##   Ctrl+A       select every military unit
##   + / -        game speed (single player)
##   Pause        pause menu
##   F1           shortcut help
## Control groups gain Shift+0..9 (add the selection to a group), see SelectionSystem.

const ALERT_MEMORY := 6

var _game: Game
var _alerts: Array[Vector2] = []
var _alert_cursor := -1
var _idle_cursor := -1
var _tc_cursor := -1


func _init(game: Game) -> void:
	_game = game
	EventBus.under_attack.connect(_on_under_attack)


## Stops listening (the HUD calls this when it is rebuilt or the match ends).
func dispose() -> void:
	if EventBus.under_attack.is_connected(_on_under_attack):
		EventBus.under_attack.disconnect(_on_under_attack)


func _on_under_attack(pid: int, where: Vector2) -> void:
	if not is_instance_valid(_game) or pid != _game.local_player:
		return
	if not _alerts.is_empty() and _alerts[0].distance_to(where) < 6.0:
		_alerts[0] = where
	else:
		_alerts.push_front(where)
		if _alerts.size() > ALERT_MEMORY:
			_alerts.pop_back()
	_alert_cursor = -1


## Handles a pressed key; returns true when it was one of these shortcuts.
func handle(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_SPACE:
			if event.ctrl_pressed:
				return _center_selection()
			return _jump_to_alert()
		KEY_COMMA:
			return _next_idle_military()
		KEY_HOME:
			return _select_town_center()
		KEY_A:
			if event.ctrl_pressed:
				return _select_military()
		KEY_PLUS, KEY_KP_ADD, KEY_EQUAL:
			return _change_speed(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			return _change_speed(-1)
		KEY_PAUSE:
			EventBus.pause_requested.emit()
			return true
	return false


func _jump_to_alert() -> bool:
	if _alerts.is_empty():
		EventBus.notify.emit(_game.local_player, "No recent attacks")
		return true
	_alert_cursor = (_alert_cursor + 1) % _alerts.size()
	_game.camera.focus_world(Iso.grid_to_world(_alerts[_alert_cursor]))
	return true


func _center_selection() -> bool:
	var sel := _game.selection.selected.filter(func(e): return is_instance_valid(e))
	if sel.is_empty():
		return false
	var c := Vector2.ZERO
	for e in sel:
		c += e.position
	_game.camera.focus_world(c / sel.size())
	return true


## Military units of the local player with nothing to do.
func idle_military() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in _game.unit_system.units:
		if u.owner_id == _game.local_player and not u.dead and not u.is_worker and u.aboard == null and not u.def.has("animal") and u.state == Unit.State.IDLE and not u.has_target() and u.task.is_empty():
			out.append(u)
	return out


func _next_idle_military() -> bool:
	var idle := idle_military()
	if idle.is_empty():
		EventBus.notify.emit(_game.local_player, "No idle military units")
		return true
	_idle_cursor = (_idle_cursor + 1) % idle.size()
	_game.selection.set_selection([idle[_idle_cursor]])
	_game.camera.focus_world(idle[_idle_cursor].position)
	return true


func _select_town_center() -> bool:
	var tcs := _game.buildings.buildings.filter(func(b): return b.owner_id == _game.local_player and not b.dead and b.type_id == "town_center")
	if tcs.is_empty():
		return false
	_tc_cursor = (_tc_cursor + 1) % tcs.size()
	_game.selection.set_selection([tcs[_tc_cursor]])
	_game.camera.focus_world(tcs[_tc_cursor].position)
	return true


func _select_military() -> bool:
	var army := _game.unit_system.units.filter(func(u): return u.owner_id == _game.local_player and not u.dead and not u.is_worker and u.aboard == null and not u.def.has("animal"))
	_game.selection.set_selection(army)
	return true


func _change_speed(step: int) -> bool:
	if Net.is_networked():
		return false
	var speeds: Dictionary = GameData.rules.get("game_speed_menu", {"normal": 1.0})
	var values: Array = speeds.values()
	values.sort()
	var cur := Engine.time_scale
	var idx := 0
	for i in values.size():
		if absf(float(values[i]) - cur) < absf(float(values[idx]) - cur):
			idx = i
	idx = clampi(idx + step, 0, values.size() - 1)
	Engine.time_scale = float(values[idx])
	EventBus.notify.emit(_game.local_player, Loc.msg("Game speed ×%s", [str(values[idx])]))
	return true

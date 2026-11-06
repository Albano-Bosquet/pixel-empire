class_name TutorialSystem
extends Node
## Guided first match (main menu "Tutorial"). Walks the player through the steps
## of tutorial_steps.json. Nothing is locked: each step only watches the match
## and moves on once its goal is true, so a player who runs ahead sees the steps
## they already did pass by on their own.
##
## A step: id, title, text, text_touch (optional), and
##   done    alternatives, each {fact: minimum}; any complete one finishes the
##           step. Empty: never (the last step ends with the victory screen).
##   point   where the arrow goes, first target not already selected wins:
##           villager, scout, soldiers, town_center, barracks, food, wood, gold, camp.
##   button  command button the arrow prefers while it is on screen.
##   quiet   {fact: minimum}: the arrow rests once this holds (already ordered).
##   ensure  stockpile the player is topped up to on entering the step, so the
##           lesson never turns into a wait for resources.
## Facts come from facts(); is_done() is pure so it is unit-tested without a match.
## Example: TutorialSystem.is_done({"done": [{"unit_villager": 4}]}, {"unit_villager": 4})  # true

## The current step changed (the panel redraws).
signal step_changed

var steps: Array = []
var index := 0
## The match ended: nothing more to teach.
var over := false

var _game: Game
var _cfg: Dictionary
var _poll := 0.0
var _advance_in := -1.0
var _camera_start := Vector2.ZERO
var _camp_tile := Vector2i.ZERO
var _enemy := 2
var _camp_units := 0
var _facts: Dictionary = {}
var _point: Entity = null


## `restored`: the world comes from a save, so the camp already exists and the
## step in progress must not hand out its supplies again.
func setup(game: Game, cfg: Dictionary, restored: bool) -> void:
	_game = game
	_cfg = cfg
	steps = cfg.get("steps", [])
	index = clampi(int(game.config.get("tutorial_step", 0)), 0, maxi(steps.size() - 1, 0))
	_camera_start = game.camera.position
	for p in game.players:
		if p.id != game.local_player:
			_enemy = p.id
	_camp_tile = game.map.start_positions[_enemy - 1]
	for id in cfg.get("camp", {}).get("units", {}):
		_camp_units += int(cfg["camp"]["units"][id])
	EventBus.game_over.connect(_on_game_over)
	if not restored:
		_spawn_camp()
		_enter_step()
	_refresh()


func current() -> Dictionary:
	return steps[index] if index < steps.size() else {}


## Whether `step` is finished given `facts`.
static func is_done(step: Dictionary, facts: Dictionary) -> bool:
	for option in step.get("done", []):
		if meets(option, facts):
			return true
	return false


## Whether every fact in `need` reaches its minimum.
static func meets(need: Dictionary, facts: Dictionary) -> bool:
	for key in need:
		if float(facts.get(key, 0)) < float(need[key]):
			return false
	return true


## [have, want] of a goal that counts several things, else []: "3 / 5" in the panel.
static func progress(step: Dictionary, facts: Dictionary) -> Array:
	var options: Array = step.get("done", [])
	if options.is_empty():
		return []
	for key in options[0]:
		if int(options[0][key]) > 1:
			return [mini(int(facts.get(key, 0)), int(options[0][key])), int(options[0][key])]
	return []


## Text of `step` for this input method.
static func step_text(step: Dictionary, touch: bool) -> String:
	return String(step.get("text_touch", step.get("text", ""))) if touch else String(step.get("text", ""))


## Moves on to the next step (goal reached, or the player's Skip button).
func advance() -> void:
	if index >= steps.size() - 1:
		return
	index += 1
	_advance_in = -1.0
	_enter_step()
	_refresh()
	step_changed.emit()


## Whether the panel should offer Skip: the last step only ends by winning.
func can_skip() -> bool:
	return not over and index < steps.size() - 1


## [have, want] for the current step, or [].
func current_progress() -> Array:
	return progress(current(), _facts)


## What the arrow points at now: {"control": Control}, {"entity": Entity} or {}.
func pointer() -> Dictionary:
	if over or _advance_in >= 0.0 or _game.placement.is_active():
		return {}
	var step := current()
	if step.has("quiet") and meets(step["quiet"], _facts):
		return {}
	var b: Control = _game.hud.command_button(String(step.get("button", "")))
	if b != null:
		return {"control": b}
	if is_instance_valid(_point) and not _point.dead:
		return {"entity": _point}
	return {}


func _process(delta: float) -> void:
	if over:
		return
	if _advance_in >= 0.0:
		_advance_in -= delta
		if _advance_in < 0.0:
			advance()
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = float(_cfg.get("poll_seconds", 0.25))
	_refresh()
	if is_done(current(), _facts):
		_advance_in = float(_cfg.get("advance_delay", 0.9))
		EventBus.ui_sound.emit("ui_place")


func _on_game_over(_winners: Array) -> void:
	over = true
	step_changed.emit()


func _refresh() -> void:
	_facts = facts()
	_point = _resolve_point()


func _enter_step() -> void:
	var need: Dictionary = current().get("ensure", {})
	var p := _game.local_state()
	for k in need:
		if int(p.resources.get(k, 0)) < int(need[k]):
			p.add(k, int(need[k]) - int(p.resources.get(k, 0)))


## The bandits: a few buildings and guards on the second start position. They
## belong to a player nobody controls, so they stand guard and never expand.
func _spawn_camp() -> void:
	var camp: Dictionary = _cfg.get("camp", {})
	for entry in camp.get("buildings", []):
		var off: Array = entry["offset"]
		_game.buildings.place(String(entry["type"]), _enemy, _camp_tile + Vector2i(int(off[0]), int(off[1])), true)
	var units: Dictionary = camp.get("units", {})
	var i := 0
	for id in units:
		for k in int(units[id]):
			var a := TAU * i / maxi(_camp_units, 1)
			_game.spawn_unit(id, _enemy, Iso.tile_center(_camp_tile) + Vector2(cos(a), sin(a)) * 3.0)
			i += 1


## Everything a step can ask about, read straight from the match, so a loaded
## save or a player who ran ahead needs no bookkeeping. Keys: camera_moved,
## selected_villagers, selected_soldiers, unit_<id>, pending_<id> (alive or
## queued), gather_<resource>, placed_<id>, building_<id> (finished), age,
## age_started, tech_started, camp_seen, scout_lost, enemy_hurt.
func facts() -> Dictionary:
	var me := _game.local_player
	var p := _game.local_state()
	var out := {"age": p.age, "age_started": 1 if p.age >= 1 else 0, "tech_started": 1 if not p.researched.is_empty() else 0}
	out["camera_moved"] = 1 if _game.camera.position.distance_to(_camera_start) >= float(_cfg.get("camera_moved_px", 140)) else 0
	var enemy_units := 0
	var hurt := false
	for u in _game.unit_system.units:
		if u.dead:
			continue
		if u.owner_id == _enemy:
			enemy_units += 1
			hurt = hurt or u.hp < u.max_hp
		elif u.owner_id == me:
			_bump(out, "unit_" + u.type_id)
			_bump(out, "pending_" + u.type_id)
			if u.task.has("kind"):
				_bump(out, "gather_" + String(u.task["kind"]))
	for b in _game.buildings.buildings:
		if b.dead:
			continue
		if b.owner_id == _enemy:
			hurt = hurt or b.hp < b.max_hp
		elif b.owner_id == me:
			_bump(out, "placed_" + b.type_id)
			if b.is_complete():
				_bump(out, "building_" + b.type_id)
			for item in b.queue:
				if not ProductionSystem.is_research(item):
					_bump(out, "pending_" + item)
				elif GameData.ages.has(item):
					out["age_started"] = 1
				else:
					out["tech_started"] = 1
	for u in _game.selection.own_units():
		_bump(out, "selected_villagers" if u.is_worker else "selected_soldiers")
	out["camp_seen"] = 1 if _game.fog.is_explored(me, _camp_tile) else 0
	out["scout_lost"] = 1 if int(out.get("unit_scout", 0)) == 0 else 0
	out["enemy_hurt"] = 1 if hurt or enemy_units < _camp_units else 0
	return out


static func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1


## First target of the step's `point` list that still needs the player's
## attention: something already selected gives way to the next one.
func _resolve_point() -> Entity:
	for name in current().get("point", []):
		var e := _target(String(name))
		if e != null:
			return e
	return null


func _target(name: String) -> Entity:
	var start := Iso.tile_center(_game.map.start_positions[_game.local_player - 1])
	match name:
		"villager":
			return null if int(_facts.get("selected_villagers", 0)) > 0 else _own_unit(func(u: Unit) -> bool: return u.is_worker)
		"scout":
			return null if _selected("scout") else _own_unit(func(u: Unit) -> bool: return u.type_id == "scout")
		"soldiers":
			return null if int(_facts.get("selected_soldiers", 0)) > 0 else _own_unit(func(u: Unit) -> bool: return u.is_military() and u.type_id != "scout")
		"town_center", "barracks":
			var sel := _game.selection.own_buildings()
			if sel.any(func(b: Building) -> bool: return b.type_id == name):
				return null
			for b in _game.buildings.buildings:
				if b.owner_id == _game.local_player and not b.dead and b.type_id == name:
					return b
		"food", "wood", "gold", "stone":
			return _game.economy.find_node(name, start, 24, _game.local_player)
		"camp":
			return _camp_target()
	return null


func _own_unit(test: Callable) -> Unit:
	for u in _game.unit_system.units:
		if u.owner_id == _game.local_player and not u.dead and test.call(u):
			return u
	return null


func _selected(type_id: String) -> bool:
	return _game.selection.own_units().any(func(u: Unit) -> bool: return u.type_id == type_id)


## What is left of the camp: guards first, then the building that keeps it alive.
func _camp_target() -> Entity:
	for u in _game.unit_system.units:
		if u.owner_id == _enemy and not u.dead:
			return u
	for b in _game.buildings.buildings:
		if b.owner_id == _enemy and not b.dead:
			return b
	return null

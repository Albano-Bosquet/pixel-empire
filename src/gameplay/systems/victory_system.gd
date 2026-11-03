class_name VictorySystem
extends Node
## Victory and defeat (design/game-brief.md "Player goal & fail state").
## Conditions (game_rules.json):
##   conquest     — a player survives while owning any living unit or any building
##                  not in conquest_ignored_buildings (farms/houses do not count).
##   town_center  — a player survives while owning at least one Town Center
##                  (finished or under construction).
##   wonder       — (any condition) a player who keeps a completed Wonder standing for
##                  wonder_victory_seconds wins; the others are defeated.
## A defeated player's AI stops and their remaining units/buildings are removed.
## The match ends when one player (or none, in sandbox) is left standing.

var condition := "conquest"
var over := false
var winners: Array[int] = []
var elapsed := 0.0

## player id -> seconds their oldest standing Wonder has been complete.
var wonder_time: Dictionary = {}

var _game: Game
var _rules: Dictionary
var _timer := 0.0
var _wonder_notice: Dictionary = {}


func setup(game: Game, rules: Dictionary, victory: String) -> void:
	_game = game
	_rules = rules
	condition = victory if rules.get("victory_conditions", {}).has(victory) else String(rules.get("default_victory", "conquest"))


## Whether `pid` still meets the survival condition.
func is_alive(pid: int) -> bool:
	if condition == "town_center":
		for b in _game.buildings.buildings:
			if b.owner_id == pid and not b.dead and b.type_id == "town_center":
				return true
		return false
	var ignored: Array = _rules.get("conquest_ignored_buildings", [])
	for u in _game.unit_system.units:
		if u.owner_id == pid and not u.dead and not u.def.has("animal"):
			return true
	for b in _game.buildings.buildings:
		if b.owner_id == pid and not b.dead and not ignored.has(b.type_id):
			return true
	return false


func _physics_process(delta: float) -> void:
	if over:
		return
	elapsed += delta
	_tick_wonders(delta)
	if over:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = float(_rules.get("check_interval", 1.0))
	check()


func check() -> void:
	for p in _game.players:
		if not p.defeated and not is_alive(p.id):
			defeat(p.id)
	var standing: Array[int] = []
	for p in _game.players:
		if not p.defeated:
			standing.append(p.id)
	var versus := _game.players.size() > 1 and not _all_allied(_game.players.map(func(p): return p.id))
	if (versus and _all_allied(standing)) or (not versus and standing.is_empty()):
		finish(standing)


## True when every listed player is on one side (also for 0 or 1 players).
func _all_allied(ids: Array) -> bool:
	for a in ids:
		for b in ids:
			if not CombatSystem.are_allies(int(a), int(b)):
				return false
	return true


## Seconds left before `pid` wins by Wonder (INF when they have none standing).
func wonder_remaining(pid: int) -> float:
	if not wonder_time.has(pid):
		return INF
	return maxf(0.0, float(_rules.get("wonder_victory_seconds", 300)) - float(wonder_time[pid]))


func _tick_wonders(delta: float) -> void:
	var holding := {}
	for b in _game.buildings.buildings:
		if b.is_complete() and not b.dead and b.def.get("wonder", false) and not _game.player(b.owner_id).defeated:
			holding[b.owner_id] = true
	for pid in wonder_time.keys():
		if not holding.has(pid):
			wonder_time.erase(pid)
			_wonder_notice.erase(pid)
			EventBus.notify.emit(0, "A Wonder has fallen")
	var goal := float(_rules.get("wonder_victory_seconds", 300))
	for pid in holding:
		var before := float(wonder_time.get(pid, -1.0))
		if before < 0.0:
			before = 0.0
			EventBus.notify.emit(0, Loc.msg("%s has built a Wonder! %s to victory", [_game.player(pid).name, "%d:%02d" % [int(goal) / 60, int(goal) % 60]]))
		wonder_time[pid] = before + delta
		var left := goal - float(wonder_time[pid])
		var minute := ceili(left / 60.0)
		if minute != int(_wonder_notice.get(pid, -1)) and left > 0.0:
			_wonder_notice[pid] = minute
			if minute < ceili(goal / 60.0):
				EventBus.notify.emit(0, Loc.msg("Wonder of %s: %s min to victory", [_game.player(pid).name, minute]))
		if left <= 0.0:
			var won: Array[int] = []
			for p in _game.players:
				if CombatSystem.are_allies(p.id, pid):
					if not p.defeated:
						won.append(p.id)
				elif not p.defeated:
					defeat(p.id)
			finish(won)
			return


func defeat(pid: int) -> void:
	var p := _game.player(pid)
	if p.defeated:
		return
	p.defeated = true
	for ai in _game.ai_players:
		if ai.player == p:
			ai.set_physics_process(false)
	# The vanquished civilisation collapses: remaining units die, buildings fall.
	for u in _game.unit_system.units.duplicate():
		if u.owner_id == pid and not u.dead and not u.def.has("animal"):
			u.take_damage(u.hp, null)
	for b in _game.buildings.buildings.duplicate():
		if b.owner_id == pid and not b.dead:
			b.take_damage(b.hp, null)
	EventBus.player_defeated.emit(pid)
	EventBus.notify.emit(0, Loc.msg("%s has been defeated", [p.name]))


func finish(standing: Array[int]) -> void:
	if over:
		return
	over = true
	winners = standing
	EventBus.game_over.emit(standing)

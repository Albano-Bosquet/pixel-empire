class_name ProductionSystem
extends Node
## Unit training and research queues on completed buildings (design/game-brief.md MVP 3).
## Queue entries are unit ids (units_stats.json) or research ids (ages.json).
## Cost is paid when queued and refunded on cancel. The front item only
## progresses while the owner is below the population cap. Finished units
## spawn beside the building and head to its rally point (gathering if the
## rally target is a resource).

var _game: Game
var _cfg: Dictionary
var _blocked_notified: Dictionary = {}


func setup(game: Game, economy_cfg: Dictionary) -> void:
	_game = game
	_cfg = economy_cfg


static func is_research(id: String) -> bool:
	return GameData.ages.has(id) or GameData.techs.has(id)


static func item_def(id: String) -> Dictionary:
	if GameData.ages.has(id):
		return GameData.ages[id]
	if GameData.techs.has(id):
		return GameData.techs[id]
	return GameData.unit(id)


static func item_time(id: String) -> float:
	var d := item_def(id)
	return float(d.get("research_time", d.get("train_time", 10)))


## Why `unit_id` can't be queued at `b` ("" when it can).
func enqueue_error(b: Building, unit_id: String) -> String:
	if not b.is_complete():
		return "Building not finished"
	if is_research(unit_id):
		return research_error(b, unit_id)
	if not b.def.get("trains", []).has(unit_id):
		return "Cannot train that here"
	if b.queue.size() >= int(_cfg.get("train_queue_limit", 15)):
		return "Queue is full"
	var p := _game.player(b.owner_id)
	var udef := GameData.unit(unit_id)
	if p.age < int(udef.get("age", 0)):
		return Loc.msg("Requires %s", [Hud.AGE_NAMES[int(udef.get("age", 0))]])
	if not p.can_afford(udef.get("cost", {})):
		return "Not enough resources"
	return ""


func research_error(b: Building, id: String) -> String:
	if not b.def.get("researches", []).has(id):
		return "Cannot research that here"
	var p := _game.player(b.owner_id)
	if GameData.techs.has(id):
		for other in _game.buildings.buildings:
			if other.owner_id == b.owner_id and other.queue.has(id):
				return "Already researching"
		return TechSystem.research_error(p, id)
	var r: Dictionary = GameData.ages[id]
	if p.age >= int(r.get("sets_age", 0)):
		return "Already researched"
	if p.age < int(r.get("requires_age", 0)):
		return Loc.msg("Requires %s", [Hud.AGE_NAMES[int(r.get("requires_age", 0))]])
	for other in _game.buildings.buildings:
		if other.owner_id == b.owner_id and other.queue.has(id):
			return "Already researching"
	if not p.can_afford(r.get("cost", {})):
		return "Not enough resources"
	return ""


func enqueue(b: Building, unit_id: String) -> bool:
	var err := enqueue_error(b, unit_id)
	if err != "":
		EventBus.notify.emit(b.owner_id, err)
		return false
	_game.player(b.owner_id).spend(item_def(unit_id).get("cost", {}))
	b.queue.append(unit_id)
	EventBus.production_changed.emit(b)
	return true


func cancel(b: Building, index: int) -> void:
	if index < 0 or index >= b.queue.size():
		return
	var unit_id: String = b.queue[index]
	var cost: Dictionary = item_def(unit_id).get("cost", {})
	var p := _game.player(b.owner_id)
	for k in cost:
		p.add(k, int(cost[k]))
	b.queue.remove_at(index)
	if index == 0:
		b.production_time = 0.0
	EventBus.production_changed.emit(b)


## 0..1 progress of the front item.
static func front_progress(b: Building) -> float:
	if b.queue.is_empty():
		return 0.0
	return clampf(b.production_time / maxf(0.1, item_time(b.queue[0])), 0.0, 1.0)


func _physics_process(delta: float) -> void:
	for b in _game.buildings.buildings:
		if b.queue.is_empty() or not b.is_complete():
			continue
		var pid := b.owner_id
		var front: String = b.queue[0]
		if is_research(front):
			b.production_time += delta
			if b.production_time >= item_time(front):
				b.queue.remove_at(0)
				b.production_time = 0.0
				_complete_research(pid, front)
				EventBus.production_changed.emit(b)
			continue
		if b.production_time <= 0.0 and _game.population(pid) >= _game.buildings.population_cap(pid):
			if not _blocked_notified.get(pid, false):
				EventBus.notify.emit(pid, "Population limit reached — build more houses")
				_blocked_notified[pid] = true
			continue
		_blocked_notified[pid] = false
		b.production_time += delta * _game.player(pid).modifier("train_speed")
		var unit_id: String = b.queue[0]
		if b.production_time >= item_time(unit_id):
			b.queue.remove_at(0)
			b.production_time = 0.0
			_spawn(b, unit_id)
			EventBus.production_changed.emit(b)


func _complete_research(pid: int, id: String) -> void:
	if GameData.techs.has(id):
		_game.techs.complete(pid, id)
		return
	var r: Dictionary = GameData.ages[id]
	var p := _game.player(pid)
	p.age = maxi(p.age, int(r.get("sets_age", p.age)))
	EventBus.age_changed.emit(pid, p.age)
	EventBus.notify.emit(pid, Loc.msg("%s reached!", [r.get("display_name", id)]))
	EventBus.resources_changed.emit(pid, p.resources)


func _spawn(b: Building, unit_id: String) -> void:
	var toward := b.rally_point if b.rally_point != Vector2.INF else b.grid_pos + Vector2(b.size, b.size)
	var spot := _game.nav_for(GameData.unit(unit_id)).approach(b.footprint(), toward)
	if spot == Vector2.INF:
		return
	var u := _game.spawn_unit(unit_id, b.owner_id, spot)
	if u == null:
		return
	_game.player(b.owner_id).stats["units_trained"] += 1
	EventBus.unit_trained.emit(u)
	var one: Array[Unit] = [u]
	if is_instance_valid(b.rally_target) and b.rally_target is ResourceNode and u.is_worker:
		_game.economy.order_gather(one, b.rally_target)
	elif b.rally_point != Vector2.INF:
		_game.unit_system.request_path(u, b.rally_point)

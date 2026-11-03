class_name MonkSystem
extends Node
## Monks (Phase B4): healing and conversion. Data: units_stats.json monk
## ("heal_*", "convert_*" keys) and combat_settings.json "monk".
##
## Healing: every heal_interval an idle monk (not converting) heals the most
## wounded friendly non-siege unit within heal_range by heal_amount.
## Conversion state per monk (entity_id -> {"monk", "target", "time"}):
##   target out of convert_range --> walk towards it (repath every 0.5 s)
##   in range --> stand, face it, chant; time += delta
##   time >= conversion_time(target) --> target changes owner; the monk
##   rests for convert_recharge seconds before it can convert again.
## Converting stops when the target dies, leaves sight or becomes friendly,
## or when the monk gets any other order.
## Example:
##   game.monks.order_convert(selected_monks, enemy_knight)

var _game: Game
var _cfg: Dictionary
var _converting: Dictionary = {}
## monk entity_id -> seconds until it can convert again.
var _recharge: Dictionary = {}
var _heal_timer := 0.0
var _near: Array = []


func setup(game: Game, monk_cfg: Dictionary) -> void:
	_game = game
	_cfg = monk_cfg


## Seconds of chanting needed to convert a unit with definition `target_def`
## (sturdier units take longer; siege and buildings are immune).
static func conversion_time(target_def: Dictionary, cfg: Dictionary) -> float:
	return minf(float(cfg.get("convert_base_seconds", 4.0)) + float(target_def.get("max_hp", 40)) * float(cfg.get("convert_seconds_per_hp", 0.03)),
			float(cfg.get("convert_max_seconds", 9.0)))


## True if `target` can ever be converted (units only, no siege or vehicles, no monks).
static func convertible(target: Entity) -> bool:
	if not (target is Unit):
		return false
	var cls: Array = target.classes()
	return not cls.has("siege") and not cls.has("vehicle") and not cls.has("monk")


static func is_monk(u: Unit) -> bool:
	return u.def.get("convert", false)


func order_convert(monks: Array[Unit], target: Entity) -> void:
	if not convertible(target):
		for m in monks:
			if is_monk(m):
				EventBus.notify.emit(m.owner_id, "Monks cannot convert that")
				return
		return
	for m in monks:
		if not is_monk(m) or not m.is_alive():
			continue
		_game.economy.clear_task(m)
		_converting[m.entity_id] = {"monk": m, "target": target, "time": 0.0, "repath": 0.0}


func cancel(m: Unit) -> void:
	_converting.erase(m.entity_id)


func is_converting(m: Unit) -> bool:
	return _converting.has(m.entity_id)


func _physics_process(delta: float) -> void:
	for id in _recharge.keys():
		_recharge[id] = float(_recharge[id]) - delta
		if _recharge[id] <= 0.0:
			_recharge.erase(id)
	for id in _converting.keys():
		_tick_convert(id, delta)
	_heal_timer -= delta
	if _heal_timer <= 0.0:
		_heal_timer = float(_cfg.get("heal_interval", 1.0))
		_heal_all()


func _tick_convert(id: int, delta: float) -> void:
	var c: Dictionary = _converting[id]
	var m: Unit = Iso.alive(c["monk"])
	var t: Unit = Iso.alive(c["target"])
	if m == null or m.dead or t == null or t.dead or not CombatSystem.is_enemy(m, t) or not _game.fog.is_visible(m.owner_id, t):
		_converting.erase(id)
		if m != null and not m.dead and m.state == Unit.State.MOVING:
			m.stop()
		return
	if _recharge.has(id):
		return
	var dist := m.grid_pos.distance_to(t.grid_pos)
	if dist > float(m.def.get("convert_range", 6.0)):
		c["time"] = 0.0
		c["repath"] = float(c["repath"]) - delta
		if c["repath"] <= 0.0:
			c["repath"] = 0.5
			_game.unit_system.request_path(m, t.grid_pos)
		return
	if m.state == Unit.State.MOVING:
		m.stop()
	m.face(Iso.direction_index(t.grid_pos - m.grid_pos))
	if m.anim_lock <= 0.0:
		m.play_once("attack")
	c["time"] = float(c["time"]) + delta
	if fmod(float(c["time"]), 0.6) < delta:
		_game.fx.burst(t.position + Vector2(0, -22), "holy")
	if float(c["time"]) >= conversion_time(t.def, _cfg):
		_convert(m, t)
		_converting.erase(id)
		_recharge[id] = float(_cfg.get("convert_recharge", 20.0))


func _convert(m: Unit, t: Unit) -> void:
	var old := t.owner_id
	t.change_owner(m.owner_id, _game.player(m.owner_id).color_slot)
	_game.economy.clear_task(t)
	_game.market.cancel(t)
	cancel(t)
	_game.fx.burst(t.position + Vector2(0, -20), "holy")
	_game.selection.prune.call_deferred()
	if _game.fog != null:
		t.visible = _game.fog.is_visible(_game.local_player, t)
	EventBus.population_changed.emit(old)
	EventBus.population_changed.emit(m.owner_id)
	if old == _game.local_player:
		EventBus.notify.emit(old, Loc.msg("Your %s has been converted!", [t.display_name()]))
	elif m.owner_id == _game.local_player:
		EventBus.notify.emit(m.owner_id, Loc.msg("%s converted", [t.display_name()]))


func _heal_all() -> void:
	for u in _game.unit_system.units:
		if u.dead or not is_monk(u) or _converting.has(u.entity_id):
			continue
		var rng := float(u.def.get("heal_range", 4.0))
		_near.clear()
		_game.unit_system.units_near(u.grid_pos, rng, _near)
		var best: Unit = null
		var worst := 1.0
		for o in _near:
			if o == u or o.dead or o.owner_id != u.owner_id or o.classes().has("siege") or o.classes().has("vehicle") or o.hp >= o.max_hp:
				continue
			var frac := float(o.hp) / maxf(1.0, o.max_hp)
			if frac < worst and o.grid_pos.distance_to(u.grid_pos) <= rng:
				worst = frac
				best = o
		if best != null:
			best.hp = mini(best.max_hp, best.hp + int(u.def.get("heal_amount", 2)))
			best.since_damaged = 0.0
			_game.fx.burst(best.position + Vector2(0, -18), "heal")

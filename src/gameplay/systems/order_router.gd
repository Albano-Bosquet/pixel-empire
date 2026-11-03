class_name OrderRouter
extends Node
## Single entry point for every player order (multiplayer, M2).
##
## UI and input never change game state directly: they build an order
## dictionary and call submit(). Orders carry entity ids, never node
## references, so they can cross the network:
##   {"t": "issue", "units": [id], "buildings": [id], "grid": Vector2, "target": id (0 = none), "queue": bool (Shift waypoint)}
##   {"t": "place", "type": String, "origins": [Vector2i], "builders": [id]}
##   {"t": "enqueue", "b": id, "item": String}        {"t": "cancel", "b": id, "idx": int}
##   {"t": "market", "res": String, "buy": bool}
##   {"t": "stop" | "unload", "units": [id]}
##   {"t": "stance", "units": [id], "stance": String}  {"t": "formation", "f": String}
##   {"t": "attack_move", "units": [id], "grid": Vector2}
##   {"t": "delete", "ids": [id]}                     (Delete key: own units/buildings die)
## Offline (and on the host) an order is applied at once for the local player.
## On a client `remote_submit` is set by the network session: the order is sent
## to the host, which calls apply() with the sender's player id.
## apply() only lets a player command entities they own.

## Set by NetSession on clients: Callable(order: Dictionary) -> void.
var remote_submit: Callable = Callable()

var _game: Game


func setup(game: Game) -> void:
	_game = game


func submit(order: Dictionary) -> void:
	if remote_submit.is_valid():
		remote_submit.call(order)
		return
	apply(_game.local_player, order)


## Helpers that turn UI selections into order payloads.
static func ids(list: Array) -> Array:
	var out := []
	for e in list:
		if is_instance_valid(e):
			out.append(e.entity_id)
	return out


func _own_units(pid: int, id_list: Array) -> Array[Unit]:
	var out: Array[Unit] = []
	for id in id_list:
		var e: Entity = _game.entity(int(id))
		if e is Unit and e.owner_id == pid and e.is_alive():
			out.append(e)
	return out


func _own_building(pid: int, id: int) -> Building:
	var e: Entity = _game.entity(id)
	if e is Building and e.owner_id == pid and not e.dead:
		return e
	return null


## Executes `order` on behalf of player `pid`. Returns true if it did anything.
func apply(pid: int, order: Dictionary) -> bool:
	var p := _game.player(pid)
	if p == null or p.defeated:
		return false
	match String(order.get("t", "")):
		"issue":
			var units := _own_units(pid, order.get("units", []))
			var blds: Array[Building] = []
			for id in order.get("buildings", []):
				var b := _own_building(pid, int(id))
				if b != null:
					blds.append(b)
			var target: Entity = _game.entity(int(order.get("target", 0)))
			if target != null and (target.dead or not _game.fog.is_visible(pid, target) and target.owner_id != pid and not (target is ResourceNode)):
				target = null
			return _game.commands.issue(units, blds, order.get("grid", Vector2.ZERO), target, pid, bool(order.get("queue", false)))
		"place":
			var builders := _own_units(pid, order.get("builders", []))
			var none: Array[Unit] = []
			var first := true
			var any := false
			for o in order.get("origins", []):
				var type_id: String = order.get("type", "")
				if _game.buildings.placement_error(type_id, o) != "":
					continue
				if _game.buildings.requirement_error(p, type_id) != "":
					EventBus.notify.emit(pid, "Not enough resources")
					break
				if _game.buildings.try_place(p, type_id, o, builders if first else none) != null:
					first = false
					any = true
			return any
		"enqueue":
			var b2 := _own_building(pid, int(order.get("b", 0)))
			if b2 != null and _game.production.enqueue_error(b2, order.get("item", "")) == "":
				_game.production.enqueue(b2, order.get("item", ""))
				return true
		"cancel":
			var b3 := _own_building(pid, int(order.get("b", 0)))
			if b3 != null:
				_game.production.cancel(b3, int(order.get("idx", 0)))
				return true
		"market":
			return _game.market.buy(p, order.get("res", "")) if order.get("buy", true) else _game.market.sell(p, order.get("res", ""))
		"stop":
			_game.commands.stop(_own_units(pid, order.get("units", [])))
			return true
		"unload":
			for ship in _own_units(pid, order.get("units", [])):
				_game.naval.order_unload(ship, ship.grid_pos)
			return true
		"stance":
			_game.commands.set_stance(_own_units(pid, order.get("units", [])), order.get("stance", "aggressive"))
			return true
		"formation":
			_game.commands.set_formation(pid, order.get("f", "box"))
			return true
		"attack_move":
			_game.commands.attack_move(_own_units(pid, order.get("units", [])), order.get("grid", Vector2.ZERO))
			return true
		"delete":
			var any_del := false
			for id in order.get("ids", []):
				var e: Entity = _game.entity(int(id))
				if e != null and e.owner_id == pid and not e.dead and (e is Unit or e is Building):
					# Lethal damage with no attacker: the normal death path runs
					# (animation/rubble, stats, network kill event), no retaliation.
					e.take_damage(e.hp, null)
					any_del = true
			return any_del
	return false

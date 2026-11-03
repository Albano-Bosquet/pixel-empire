class_name MarketSystem
extends Node
## Market exchange and trade carts (Phase B3; buildings_stats.json "exchange").
##
## Exchange: one shared price per tradable resource (gold per `lot` units).
## Buying costs `price` gold and raises the price by `price_step`; selling pays
## price * (1 - commission) and lowers it. Prices stay within [min_price, max_price].
##
## Trade route per cart (entity_id -> route):
##   heading to `to` --(within reach of its footprint)--> earn trip_gold(distance
##   between the two markets) --> head to the other market --> ...
## A route ends when the cart gets any other order, dies, or a market is lost.
## Data: economy_settings.json "market".
## Example:
##   game.market.buy(player, "food")          # 100 food for the current price
##   game.market.order_trade(carts, far_market)

const TRADABLE: Array[String] = ["food", "wood", "stone"]

var prices: Dictionary = {}

var _game: Game
var _cfg: Dictionary
var _routes: Dictionary = {}


func setup(game: Game, market_cfg: Dictionary) -> void:
	_game = game
	_cfg = market_cfg
	for r in TRADABLE:
		prices[r] = float(_cfg.get("start_price", 100))
	EventBus.entity_spawned.connect(_on_spawned)


# --- Exchange -----------------------------------------------------------------------

func lot() -> int:
	return int(_cfg.get("lot", 100))


## Gold received for selling one lot of `res` now.
func sell_value(res: String) -> int:
	return floori(float(prices.get(res, 100)) * (1.0 - float(_cfg.get("commission", 0.3))))


## Gold needed to buy one lot of `res` now.
func buy_cost(res: String) -> int:
	return ceili(float(prices.get(res, 100)))


## Why `p` cannot buy/sell `res` now ("" when it can).
func exchange_error(p: PlayerState, res: String, buying: bool) -> String:
	if not TRADABLE.has(res):
		return Loc.msg("Cannot trade %s", [res])
	if not _has_market(p.id):
		return "Requires a Market"
	if buying and p.resources.get("gold", 0) < buy_cost(res):
		return "Not enough gold"
	if not buying and p.resources.get(res, 0) < lot():
		return Loc.msg("Not enough %s", [res])
	return ""


func buy(p: PlayerState, res: String) -> bool:
	if exchange_error(p, res, true) != "":
		return false
	p.add("gold", -buy_cost(res))
	p.add(res, lot())
	_shift(res, float(_cfg.get("price_step", 3)))
	return true


func sell(p: PlayerState, res: String) -> bool:
	if exchange_error(p, res, false) != "":
		return false
	p.add(res, -lot())
	p.add("gold", sell_value(res))
	_shift(res, -float(_cfg.get("price_step", 3)))
	return true


func _shift(res: String, by: float) -> void:
	prices[res] = clampf(float(prices[res]) + by, float(_cfg.get("min_price", 20)), float(_cfg.get("max_price", 300)))
	EventBus.resources_changed.emit(_game.local_player, _game.local_state().resources)


func _has_market(pid: int) -> bool:
	for b in _game.buildings.buildings:
		if b.owner_id == pid and b.is_complete() and not b.dead and b.def.get("exchange", false):
			return true
	return false


# --- Trade carts --------------------------------------------------------------------

## Gold earned per delivery between markets `dist` tiles apart (quadratic, so
## long routes pay off; nothing below trade_min_distance).
static func trip_gold(dist: float, cfg: Dictionary) -> int:
	if dist < float(cfg.get("trade_min_distance", 8)):
		return 0
	return roundi(float(cfg.get("trade_gold_per_tile_sq", 0.045)) * dist * dist)


func is_trader(u: Unit) -> bool:
	return bool(u.def.get("trade", false))


## Sends carts to trade between their home market and `market`.
func order_trade(carts: Array[Unit], market: Building) -> void:
	for u in carts:
		if not is_trader(u):
			continue
		var home: Building = _routes.get(u.entity_id, {}).get("home", null)
		if not is_instance_valid(home) or home == market or home.dead:
			home = _nearest_market(u.owner_id, u.grid_pos, market)
		if home == null:
			EventBus.notify.emit(u.owner_id, "Trade needs a second market")
			continue
		_game.economy.clear_task(u)
		_routes[u.entity_id] = {"unit": u, "home": home, "dest": market, "to": market}
		_head(u, market)


func cancel(u: Unit) -> void:
	_routes.erase(u.entity_id)


## Every trade route (saves; entity values are re-linked by SaveGame).
func routes() -> Dictionary:
	return _routes


func restore_routes(saved: Dictionary) -> void:
	_routes = {}
	for id in saved:
		var r: Dictionary = saved[id]
		if r.get("unit") != null and r.get("home") != null:
			_routes[int(id)] = r
			if r.get("to") != null:
				_head(r["unit"], r["to"])


func route_of(u: Unit) -> Dictionary:
	return _routes.get(u.entity_id, {})


func _on_spawned(e: Entity) -> void:
	if e is Unit and is_trader(e):
		var home := _nearest_market(e.owner_id, e.grid_pos, null)
		if home != null:
			_routes[e.entity_id] = {"unit": e, "home": home, "dest": null, "to": null}


func _nearest_market(pid: int, from: Vector2, exclude: Building) -> Building:
	var best: Building = null
	var best_d := INF
	for b in _game.buildings.buildings:
		if b == exclude or b.owner_id != pid or b.dead or not b.is_complete() or not b.def.get("exchange", false):
			continue
		var d := b.grid_pos.distance_to(from)
		if d < best_d:
			best_d = d
			best = b
	return best


func _head(u: Unit, b: Building) -> void:
	var spot := _game.pathfinder.approach(b.footprint(), u.grid_pos)
	if spot != Vector2.INF:
		_game.unit_system.request_path(u, spot)


func _physics_process(_delta: float) -> void:
	for id in _routes.keys():
		var r: Dictionary = _routes[id]
		var u: Unit = Iso.alive(r["unit"])
		if u == null or u.dead:
			_routes.erase(id)
			continue
		var to: Building = Iso.alive(r["to"])
		if r["to"] == null:
			continue  # fresh cart waiting for a destination
		var home: Building = Iso.alive(r["home"])
		var dest: Building = Iso.alive(r["dest"])
		if to == null or home == null or dest == null or home.dead or dest.dead:
			_routes.erase(id)
			u.stop()
			continue
		if u.state == Unit.State.MOVING:
			continue
		if u.grid_pos.distance_to(to.closest_point(u.grid_pos)) <= float(_cfg.get("trade_reach", 1.3)):
			var gold := trip_gold(home.grid_pos.distance_to(dest.grid_pos), _cfg)
			if gold > 0:
				_game.player(u.owner_id).add("gold", gold)
				_game.player(u.owner_id).stats["gathered"]["gold"] = int(_game.player(u.owner_id).stats["gathered"].get("gold", 0)) + gold
				_game.fx.burst(u.position + Vector2(0, -20), "hit", "market")
			r["to"] = home if to == dest else dest
		_head(u, r["to"])

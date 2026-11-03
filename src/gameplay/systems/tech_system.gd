class_name TechSystem
extends Node
## Technologies (design/game-brief.md MVP item 5). A finished research adds its
## effects to PlayerState.modifiers; derived stats are then recomputed for every
## existing unit/building of that player and applied to new ones at spawn.
## Effect keys (technologies.json):
##   attack_add:<class>, armor_melee_add:<class>, armor_pierce_add:<class>,
##   hp_add:<class>, range_add:<class> (additive)
##   speed:<class>, gather_<res>, carry_capacity, build_speed, building_hp (multiplicative)
##   farm_food_add (additive, applied to farms when completed/reseeded)

var _game: Game


func setup(game: Game) -> void:
	_game = game


static func tech(id: String) -> Dictionary:
	return GameData.techs.get(id, {})


static func add_mod(p: PlayerState, key: String) -> float:
	return float(p.modifiers.get(key, 0.0))


static func mul_mod(p: PlayerState, key: String) -> float:
	return float(p.modifiers.get(key, 1.0))


## Why `id` cannot be researched by `p` right now ("" when it can), ignoring
## where it is queued (ProductionSystem checks the building and the queue).
static func research_error(p: PlayerState, id: String) -> String:
	var d := tech(id)
	if d.is_empty():
		return "Unknown technology"
	if p.researched.has(id):
		return "Already researched"
	if p.age < int(d.get("age", 0)):
		return Loc.msg("Requires %s", [Hud.AGE_NAMES[int(d.get("age", 0))]])
	for req in d.get("requires", []):
		if not p.researched.has(req):
			return Loc.msg("Requires %s", [tech(req).get("display_name", req)])
	if not p.can_afford(d.get("cost", {})):
		return "Not enough resources"
	return ""


## Applies a finished research for player `pid`.
func complete(pid: int, id: String) -> void:
	var p := _game.player(pid)
	if p.researched.has(id):
		return
	p.researched[id] = true
	apply_effects(p, tech(id).get("effects", []))
	refresh_player(pid)
	EventBus.tech_researched.emit(pid, id)
	EventBus.notify.emit(pid, Loc.msg("%s researched", [tech(id).get("display_name", id)]))


static func apply_effects(p: PlayerState, effects: Array) -> void:
	for e in effects:
		var key: String = e["key"]
		if e.get("op", "add") == "mul":
			p.modifiers[key] = float(p.modifiers.get(key, 1.0)) * float(e["value"])
		else:
			p.modifiers[key] = float(p.modifiers.get(key, 0.0)) + float(e["value"])


func refresh_player(pid: int) -> void:
	for u in _game.unit_system.units:
		if u.owner_id == pid and not u.dead:
			apply_unit(u)
	for b in _game.buildings.buildings:
		if b.owner_id == pid and not b.dead:
			apply_building(b)


## Recomputes a unit's derived stats from its definition plus its owner's modifiers.
func apply_unit(u: Unit) -> void:
	var p := _game.player(u.owner_id)
	if p == null:
		return  # Gaia animals have no technologies
	var hp_add := 0.0
	var spd := 1.0
	u.attack_bonus = 0
	u.armor_bonus = {"melee": 0, "pierce": 0}
	u.range_bonus = 0.0
	for cls in u.classes():
		hp_add += add_mod(p, "hp_add:" + cls)
		spd *= mul_mod(p, "speed:" + cls)
		u.attack_bonus += int(add_mod(p, "attack_add:" + cls))
		u.armor_bonus["melee"] += int(add_mod(p, "armor_melee_add:" + cls))
		u.armor_bonus["pierce"] += int(add_mod(p, "armor_pierce_add:" + cls))
		u.range_bonus += add_mod(p, "range_add:" + cls)
	var new_max := int(u.def.get("max_hp", 10)) + int(hp_add)
	if new_max != u.max_hp:
		u.hp = clampi(u.hp + new_max - u.max_hp, 1, new_max)
		u.max_hp = new_max
	u.speed = float(u.def.get("speed", 1.0)) * spd


func apply_building(b: Building) -> void:
	var p := _game.player(b.owner_id)
	b.attack_bonus = int(add_mod(p, "attack_add:building"))
	b.armor_bonus = {"melee": int(add_mod(p, "armor_melee_add:building")), "pierce": int(add_mod(p, "armor_pierce_add:building"))}
	var new_max := roundi(float(b.def.get("max_hp", 100)) * mul_mod(p, "building_hp"))
	if new_max != b.max_hp:
		if b.is_complete():
			b.hp = clampi(b.hp + new_max - b.max_hp, 1, new_max)
		b.max_hp = new_max


## Food a freshly completed or reseeded farm of player `pid` holds.
func farm_food(pid: int, def: Dictionary) -> float:
	return float(def.get("farm_food", 0)) + add_mod(_game.player(pid), "farm_food_add")

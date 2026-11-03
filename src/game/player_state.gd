class_name PlayerState
extends RefCounted
## Per-player match state: identity, colour, stockpile and age.

const RESOURCE_KEYS: Array[String] = ["food", "wood", "gold", "stone"]

var id := 1
var name := "Player"
var color_slot := 0
var is_ai := false
var age := 0
var resources: Dictionary = {"food": 0, "wood": 0, "gold": 0, "stone": 0}
## Multiplicative modifiers granted by technologies (Stage 4), e.g. "gather_wood": 1.1.
var modifiers: Dictionary = {}
## Finished technologies (id -> true).
var researched: Dictionary = {}
var defeated := false
## Lifetime statistics (end-of-game screen): resources gathered, units trained/lost...
var stats: Dictionary = {"gathered": {"food": 0, "wood": 0, "gold": 0, "stone": 0}, "units_trained": 0, "units_lost": 0, "kills": 0, "buildings_built": 0, "buildings_lost": 0}


func _init(player_id: int, player_name: String, slot: int, ai: bool, start_resources: Dictionary) -> void:
	id = player_id
	name = player_name
	color_slot = slot
	is_ai = ai
	for k in RESOURCE_KEYS:
		resources[k] = int(start_resources.get(k, 0))


func color() -> Color:
	return Color(GameData.player_color(color_slot).get("primary", "#ffffff"))


func modifier(key: String) -> float:
	return float(modifiers.get(key, 1.0))


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if resources.get(k, 0) < int(cost[k]):
			return false
	return true


## Deducts `cost` if affordable. Returns false (and changes nothing) otherwise.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		resources[k] -= int(cost[k])
	EventBus.resources_changed.emit(id, resources)
	return true


func add(resource: String, amount: int) -> void:
	resources[resource] = resources.get(resource, 0) + amount
	EventBus.resources_changed.emit(id, resources)

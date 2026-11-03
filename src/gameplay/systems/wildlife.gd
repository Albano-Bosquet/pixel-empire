class_name Wildlife
extends RefCounted
## Static rules for Gaia animals (units_stats.json "animal"):
##   "herdable" — sheep, turkeys: anyone's unit passing close claims them;
##                villagers slaughter them for food.
##   "huntable" — deer, boar: wild; villagers hunt them (boar fight back).
##   "predator" — wolves, tigers, bears: attack players' units in sight.
## The behaviour itself lives in WildlifeSystem.


static func kind(e: Entity) -> String:
	return String(e.def.get("animal", "")) if e is Unit else ""


static func is_animal(e: Entity) -> bool:
	return e is Unit and e.def.has("animal")


static func is_predator(e: Entity) -> bool:
	return kind(e) == "predator"


static func is_herdable(e: Entity) -> bool:
	return kind(e) == "herdable"


## A wild (Gaia) animal players may fight: hunted game and predators.
static func is_hostile_animal(e: Entity) -> bool:
	return e != null and e.owner_id == Entity.GAIA and kind(e) in ["huntable", "predator"]

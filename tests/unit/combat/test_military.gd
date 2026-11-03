extends "res://tests/test_case.gd"
## Military Age (ages.json, units_stats.json, buildings_stats.json): age chain,
## roster wiring, tank/anti-tank damage, air targeting, conversion immunity.

const ROSTER := ["infantryman", "machine_gunner", "bazooka_trooper", "light_tank", "heavy_tank",
	"self_propelled_gun", "jet_fighter", "jet_bomber"]


func _unit(id: String, owner: int) -> Unit:
	var u := Unit.new()
	u.setup(id, GameData.unit(id), owner, 0, Vector2(5, 5))
	return u


func test_military_age_follows_the_industrial_age() -> void:
	var a: Dictionary = GameData.ages["military_age"]
	assert_eq(int(a["sets_age"]), 6, "Military Age is age 6")
	assert_eq(int(a["requires_age"]), 5, "it follows the Industrial Age")
	assert_eq(Hud.AGE_NAMES[6], "Military Age", "HUD names it")
	assert_true(GameData.building("town_center")["researches"].has("military_age"), "the town center researches it")


func test_every_military_unit_is_trained_by_a_military_age_building() -> void:
	for id in ROSTER:
		var d: Dictionary = GameData.unit(id)
		assert_eq(int(d["age"]), 6, "%s needs the Military Age" % id)
		var b: Dictionary = GameData.building(d["trained_at"])
		assert_eq(int(b["age"]), 6, "%s is built in a Military Age building" % id)
		assert_true(b["trains"].has(id), "%s appears in %s's train list" % [id, d["trained_at"]])


func test_bazooka_is_the_answer_to_tanks() -> void:
	var tank := _unit("heavy_tank", 2)
	var zook: Dictionary = GameData.unit("bazooka_trooper")
	var mg: Dictionary = GameData.unit("machine_gunner")
	var rocket := CombatSystem.compute_damage(int(zook["attack_damage"]), zook["attack_type"], zook["bonuses"], tank)
	var bullets := CombatSystem.compute_damage(int(mg["attack_damage"]), mg["attack_type"], mg["bonuses"], tank)
	assert_eq(rocket, 66, "20 - 14 pierce armor + 60 vs armored")
	assert_eq(bullets, 1, "machine-gun fire barely scratches a heavy tank")
	tank.free()


func test_tanks_cannot_hit_aircraft_but_jets_can() -> void:
	var jet := _unit("jet_fighter", 2)
	for id in ["light_tank", "heavy_tank", "self_propelled_gun", "bazooka_trooper", "jet_bomber"]:
		assert_true(not CombatSystem.can_target(GameData.unit(id), jet), "%s cannot hit a jet" % id)
	assert_true(CombatSystem.can_target(GameData.unit("jet_fighter"), jet), "jets dogfight")
	assert_true(CombatSystem.can_target(GameData.unit("infantryman"), jet), "rifles can fire at aircraft")
	jet.free()


func test_air_base_rearms_aircraft() -> void:
	assert_true(GameData.building("air_base").get("rearms_air", false), "the air base rearms planes")


func test_vehicles_cannot_be_converted() -> void:
	var tank := _unit("light_tank", 2)
	var soldier := _unit("infantryman", 2)
	assert_true(not MonkSystem.convertible(tank), "monks cannot convert a tank")
	assert_true(MonkSystem.convertible(soldier), "infantry can still be converted")
	tank.free()
	soldier.free()

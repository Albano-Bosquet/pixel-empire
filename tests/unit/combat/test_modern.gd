extends "res://tests/test_case.gd"
## Gunpowder and Industrial ages (ages.json, units_stats.json): age chain,
## aircraft targeting rules, ammunition.


func _unit(id: String, owner: int) -> Unit:
	var u := Unit.new()
	u.setup(id, GameData.unit(id), owner, 0, Vector2(5, 5))
	return u


func test_two_new_ages_follow_the_imperial_age() -> void:
	assert_eq(int(GameData.ages["gunpowder_age"]["sets_age"]), 4, "Gunpowder Age is age 4")
	assert_eq(int(GameData.ages["gunpowder_age"]["requires_age"]), 3, "it follows the Imperial Age")
	assert_eq(int(GameData.ages["industrial_age"]["requires_age"]), 4, "Industrial follows Gunpowder")
	assert_eq(Hud.AGE_NAMES.size(), 6, "six age names for the HUD")
	assert_true(GameData.building("town_center")["researches"].has("industrial_age"), "the town center researches it")


func test_melee_and_bombers_cannot_hit_aircraft() -> void:
	var fighter := _unit("biplane_fighter", 2)
	assert_true(not CombatSystem.can_target(GameData.unit("swordsman"), fighter), "swordsman cannot reach a plane")
	assert_true(not CombatSystem.can_target(GameData.unit("biplane_bomber"), fighter), "bombers do not dogfight")
	assert_true(CombatSystem.can_target(GameData.unit("musketeer"), fighter), "a musketeer can shoot a plane")
	assert_true(CombatSystem.can_target(GameData.unit("biplane_fighter"), fighter), "fighters fight fighters")
	fighter.free()


func test_aircraft_fly_high_and_carry_limited_ammo() -> void:
	var b := _unit("biplane_bomber", 1)
	assert_true(b.altitude > 30.0, "bomber flies above the ground (%.0f px)" % b.altitude)
	assert_eq(b.ammo, int(GameData.unit("biplane_bomber")["ammo"]), "starts fully armed")
	var g := _unit("musketeer", 1)
	assert_eq(g.ammo, -1, "ground units never run out")
	assert_near(g.altitude, 0.0, 0.0001, "ground units stay on the ground")
	b.free()
	g.free()


func test_flak_fort_fires_only_at_aircraft() -> void:
	var atk: Dictionary = GameData.building("flak_fort")["attack"]
	assert_eq(atk["targets"], ["air"], "flak targets aircraft only")
	var dmg := CombatSystem.compute_damage(int(atk["damage"]), atk["type"], atk["bonuses"], _unit("biplane_fighter", 2))
	assert_eq(dmg, 20, "12 - 2 pierce armor + 10 vs air")

extends "res://tests/test_case.gd"
## Gaia animal rules (Wildlife, WildlifeSystem.is_hunting, carcasses) and data.


func _unit(id: String, owner: int) -> Unit:
	var u := Unit.new()
	u.setup(id, GameData.unit(id), owner, 0, Vector2(5, 5))
	return u


func test_every_animal_is_complete_and_neutral() -> void:
	for id in ["sheep", "turkey", "deer", "boar", "wolf", "tiger", "bear"]:
		var d := GameData.unit(id)
		assert_true(d.get("animal", "") in ["herdable", "huntable", "predator"], "%s has an animal kind" % id)
		assert_true(SpriteLibrary.unit_layout(id).get("neutral", false), "%s sheet is neutral" % id)
		assert_true(ResourceLoader.exists(SpriteLibrary.UNIT_SHEET % [id, 0]), "%s sheet exists" % id)
		if d["animal"] != "predator":
			assert_true(int(d.get("food", 0)) > 0, "%s gives food" % id)


func test_wild_game_and_predators_are_hostile_but_herds_are_not() -> void:
	var wolf := _unit("wolf", Entity.GAIA)
	var deer := _unit("deer", Entity.GAIA)
	var sheep := _unit("sheep", Entity.GAIA)
	var vil := _unit("villager", 1)
	assert_true(CombatSystem.is_enemy(wolf, vil), "wolves attack people")
	assert_true(CombatSystem.is_enemy(vil, deer), "deer can be hunted")
	assert_true(not CombatSystem.is_enemy(vil, sheep), "gaia sheep are claimed, not fought")
	assert_true(not CombatSystem.is_enemy(wolf, deer), "animals leave each other alone")
	assert_true(Wildlife.is_predator(wolf) and not Wildlife.is_predator(deer), "predator kind")
	for e in [wolf, deer, sheep, vil]:
		e.free()


func test_villager_may_butcher_own_sheep_only_when_ordered() -> void:
	var sheep := _unit("sheep", 1)
	var vil := _unit("villager", 1)
	assert_true(not CombatSystem.is_enemy(vil, sheep), "own sheep is no enemy")
	assert_true(not WildlifeSystem.is_hunting(vil, sheep), "not hunting yet")
	vil.task = {"type": "hunt", "animal": sheep, "kind": "food"}
	assert_true(WildlifeSystem.is_hunting(vil, sheep), "hunt order lets it strike")
	sheep.free()
	vil.free()


func test_carcass_holds_the_animal_food_and_does_not_block() -> void:
	var deer := _unit("deer", Entity.GAIA)
	var node := ResourceNode.new()
	node.setup_carcass(deer, float(GameData.unit("deer")["food"]))
	assert_eq(node.resource_type, "food", "carcass is food")
	assert_eq(node.remaining(), int(GameData.unit("deer")["food"]), "holds the deer's food")
	assert_true(node.def.get("carcass", false), "marked as carcass")
	assert_near(node.take(30.0), 30.0, 0.001, "can be gathered")
	deer.free()
	node.free()


func test_owned_animals_do_not_count_as_population_class() -> void:
	assert_true(GameData.unit("sheep").get("classes", []).has("animal"), "animal class")
	assert_true(not GameData.unit("sheep").get("worker", false), "sheep are no workers")

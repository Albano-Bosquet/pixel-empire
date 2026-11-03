extends "res://tests/test_case.gd"
## Monk rules (MonkSystem; combat_settings.json "monk").


func _cfg() -> Dictionary:
	return GameData.combat.get("monk", {})


func test_conversion_time_grows_with_hp_and_is_capped() -> void:
	var vil := MonkSystem.conversion_time(GameData.unit("villager"), _cfg())
	var kn := MonkSystem.conversion_time(GameData.unit("knight"), _cfg())
	assert_near(vil, 4.75, 0.001, "4 + 25 hp * 0.03")
	assert_near(kn, 7.0, 0.001, "4 + 100 hp * 0.03")
	assert_near(MonkSystem.conversion_time({"max_hp": 1000}, _cfg()), 9.0, 0.001, "capped at convert_max_seconds")


func test_siege_monks_and_buildings_cannot_be_converted() -> void:
	var cat := Unit.new()
	cat.setup("catapult", GameData.unit("catapult"), 2, 0, Vector2(5, 5))
	var mk := Unit.new()
	mk.setup("monk", GameData.unit("monk"), 2, 0, Vector2(5, 5))
	var kn := Unit.new()
	kn.setup("knight", GameData.unit("knight"), 2, 0, Vector2(5, 5))
	var h := Building.new()
	h.setup("house", GameData.building("house"), 2, 0, Vector2i(3, 3), true)
	assert_true(not MonkSystem.convertible(cat), "siege immune")
	assert_true(not MonkSystem.convertible(mk), "monks immune")
	assert_true(not MonkSystem.convertible(h), "buildings immune")
	assert_true(MonkSystem.convertible(kn), "knights convertible")
	for e in [cat, mk, kn, h]:
		e.free()

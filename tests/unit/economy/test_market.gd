extends "res://tests/test_case.gd"
## Market trade formula (MarketSystem.trip_gold; economy_settings.json "market").


func _cfg() -> Dictionary:
	return GameData.economy.get("market", {})


func test_trip_gold_is_zero_for_markets_too_close() -> void:
	assert_eq(MarketSystem.trip_gold(5.0, _cfg()), 0, "below trade_min_distance pays nothing")


func test_trip_gold_grows_quadratically_with_distance() -> void:
	var near := MarketSystem.trip_gold(20.0, _cfg())
	var far := MarketSystem.trip_gold(40.0, _cfg())
	assert_eq(near, 18, "0.045 * 20^2 = 18")
	assert_eq(far, 72, "0.045 * 40^2 = 72 (double distance, four times the gold)")


func test_market_and_university_data_link_up() -> void:
	assert_true(GameData.building("market").get("exchange", false), "market exchanges resources")
	assert_true(GameData.building("market")["trains"].has("trade_cart"), "market trains trade carts")
	for t in GameData.building("university")["researches"]:
		assert_eq(GameData.techs[t]["building"], "university", "%s is researched at the university" % t)
	assert_eq(GameData.building("bombard_tower")["attack"]["projectile"], "cannonball", "bombard tower fires cannonballs")

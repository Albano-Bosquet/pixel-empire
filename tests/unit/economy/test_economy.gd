extends "res://tests/test_case.gd"
## Economy rules (design/game-brief.md MVP items 2–3): costs, gathering,
## construction speed, building progress.


func test_builder_multiplier_follows_aoe_formula() -> void:
	# Arrange / Act / Assert: (n + 2) / 3
	assert_near(BuildingSystem.builder_multiplier(0), 0.0, 0.0001, "no builders, no progress")
	assert_near(BuildingSystem.builder_multiplier(1), 1.0, 0.0001, "one builder = 1x")
	assert_near(BuildingSystem.builder_multiplier(4), 2.0, 0.0001, "four builders = 2x")
	assert_near(BuildingSystem.builder_multiplier(3, "linear"), 3.0, 0.0001, "linear formula")


func test_spend_is_atomic_when_unaffordable() -> void:
	var p := PlayerState.new(1, "T", 0, false, {"wood": 50, "food": 10})
	var ok := p.spend({"wood": 25, "food": 50})
	assert_true(not ok, "cannot afford 50 food with 10")
	assert_eq(p.resources["wood"], 50, "wood untouched after failed spend")
	assert_true(p.spend({"wood": 25}), "affordable spend succeeds")
	assert_eq(p.resources["wood"], 25, "wood deducted")


func test_modifier_defaults_to_one() -> void:
	var p := PlayerState.new(1, "T", 0, false, {})
	assert_near(p.modifier("gather_wood"), 1.0, 0.0001, "no tech = 1x")
	p.modifiers["gather_wood"] = 1.15
	assert_near(p.modifier("gather_wood"), 1.15, 0.0001, "tech modifier applied")


func test_resource_take_caps_and_depletes_once() -> void:
	var n := ResourceNode.new()
	n.setup("berry_bush", GameData.resource_node("berry_bush"), Vector2i(3, 3), 0)
	var count := [0]
	n.depleted.connect(func(_x): count[0] += 1)
	var total := 0.0
	for i in int(GameData.resource_node("berry_bush")["amount"]) + 50:
		total += n.take(1.0)
	assert_near(total, float(GameData.resource_node("berry_bush")["amount"]), 0.001, "takes exactly the node amount")
	assert_true(n.is_depleted(), "node depleted")
	assert_eq(count[0], 1, "depleted emitted once")
	n.free()


func test_building_progress_grows_hp_and_completes() -> void:
	var b := Building.new()
	b.setup("house", GameData.building("house"), 1, 0, Vector2i(10, 10), false)
	assert_eq(b.state, Building.State.FOUNDATION, "starts as foundation")
	var done := [false]
	b.completed.connect(func(_x): done[0] = true)
	b.add_progress(0.5)
	assert_eq(b.state, Building.State.CONSTRUCTING, "constructing after work")
	assert_true(b.hp > 1 and b.hp < b.max_hp, "hp grows with progress (%d)" % b.hp)
	b.add_progress(0.6)
	assert_true(b.is_complete() and done[0], "completes and emits")
	assert_eq(b.hp, b.max_hp, "full hp when complete")
	assert_true(b.accepts("food") == false, "house is not a drop site")
	b.free()


func test_drop_sites_match_data() -> void:
	var tc := Building.new()
	tc.setup("town_center", GameData.building("town_center"), 1, 0, Vector2i(0, 0), true)
	for r in ["food", "wood", "gold", "stone"]:
		assert_true(tc.accepts(r), "town center accepts " + r)
	var mill := Building.new()
	mill.setup("mill", GameData.building("mill"), 1, 0, Vector2i(0, 0), false)
	assert_true(not mill.accepts("food"), "unfinished mill accepts nothing")
	mill.add_progress(1.0)
	assert_true(mill.accepts("food") and not mill.accepts("wood"), "mill accepts food only")
	tc.free()
	mill.free()


func test_closest_point_on_footprint() -> void:
	var b := Building.new()
	b.setup("barracks", GameData.building("barracks"), 1, 0, Vector2i(5, 5), true)
	assert_eq(b.closest_point(Vector2(0, 6)), Vector2(5, 6), "left side clamps x")
	assert_eq(b.closest_point(Vector2(9, 9)), Vector2(8, 8), "outside corner clamps both")
	assert_eq(b.closest_point(Vector2(6, 6)), Vector2(6, 6), "inside point unchanged")
	b.free()


func test_building_burns_below_half_hp() -> void:
	var b := Building.new()
	b.setup("house", GameData.building("house"), 1, 0, Vector2i(5, 5), true)
	assert_true(not b._fires[0].emitting, "intact building does not burn")
	b.take_damage(int(b.max_hp * 0.6), null)
	assert_true(b._fires[0].emitting, "building below 50%% hp burns (hp %d)" % b.hp)
	b.free()


func test_farm_built_by_progress_holds_food() -> void:
	# Regression: add_progress()'s parameter used to shadow the farm's `amount`,
	# so farms finished by villagers were born empty.
	var f := Building.new()
	f.setup("farm", GameData.building("farm"), 1, 0, Vector2i(4, 4), false)
	f.add_progress(1.0)
	assert_true(f.is_complete(), "farm completes")
	assert_eq(f.remaining(), int(GameData.building("farm")["farm_food"]), "completed farm holds its food")
	assert_true(not f.is_depleted(), "completed farm is harvestable")
	f.free()


func test_farming_alternates_hoe_and_basket() -> void:
	# Arrange: the cycle from economy_settings.json (8 s hoe, 8 s basket).
	var cycle := Vector2(float(GameData.economy["farm_hoe_seconds"]), float(GameData.economy["farm_basket_seconds"]))
	assert_true(cycle.x > 0.0 and cycle.y > 0.0, "both halves of the farming cycle last a while")
	# Act: step the clock at 20 Hz through two full cycles.
	var t := 0.0
	var phases: Array[bool] = []
	for i in int((cycle.x + cycle.y) * 2.0 * 20.0):
		phases.append(EconomySystem.farm_hoeing(t, cycle))
		t = EconomySystem.farm_clock(t, 0.05, cycle)
	# Assert: hoe, basket, hoe, basket - each half as long as configured.
	var switches := 0
	for i in range(1, phases.size()):
		if phases[i] != phases[i - 1]:
			switches += 1
	assert_eq(switches, 3, "hoe -> basket -> hoe -> basket over two cycles")
	assert_eq(phases.slice(0, int(cycle.x * 20.0)).count(true), int(cycle.x * 20.0), "starts with the hoe for the whole hoe time")
	assert_true(not EconomySystem.farm_hoeing(cycle.x + 0.01, cycle), "then the basket")
	assert_near(EconomySystem.farm_clock(cycle.x + cycle.y - 0.5, 1.0, cycle), 0.5, 0.0001, "the clock wraps back to hoeing")


class StubWorker:
	var task: Dictionary = {}


func _worker(task: Dictionary) -> StubWorker:
	var w := StubWorker.new()
	w.task = task
	return w


func test_occupied_nodes_lists_each_assigned_node_once() -> void:
	var farm := RefCounted.new()
	var other := RefCounted.new()
	var units := [_worker({"node": farm}), _worker({"node": farm}), _worker({}), _worker({"type": "build"})]
	var occupied := EconomySystem.occupied_nodes(units)
	assert_true(occupied.has(farm), "a worked farm counts as occupied")
	assert_true(not occupied.has(other), "an unworked farm stays free")
	assert_eq(occupied.size(), 1, "idle units and other tasks add nothing")

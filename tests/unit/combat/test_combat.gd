extends "res://tests/test_case.gd"
## Combat rules (design/game-brief.md MVP item 4): damage formula, armor,
## class bonuses, enemy relation.


func _unit(id: String, owner: int) -> Unit:
	var u := Unit.new()
	u.setup(id, GameData.unit(id), owner, 0, Vector2(5, 5))
	return u


func test_melee_damage_subtracts_melee_armor() -> void:
	var sw := _unit("swordsman", 2)
	# Arrange: swordsman has 1 melee armor. Act/Assert: 9 attack -> 8.
	assert_eq(CombatSystem.compute_damage(9, "melee", {}, sw), 8, "9 - 1 armor")
	sw.free()


func test_pierce_damage_uses_pierce_armor() -> void:
	var kn := _unit("knight", 2)
	assert_eq(CombatSystem.compute_damage(4, "pierce", {}, kn), 2, "arrow 4 - 2 pierce armor")
	kn.free()


func test_minimum_damage_is_one() -> void:
	var b := Building.new()
	b.setup("tower", GameData.building("tower"), 2, 0, Vector2i(3, 3), true)
	assert_eq(CombatSystem.compute_damage(4, "pierce", {}, b), 1, "arrows barely scratch a stone tower")
	b.free()


func test_class_bonus_applies() -> void:
	var kn := _unit("knight", 2)
	var spear: Dictionary = GameData.unit("spearman")
	var dmg := CombatSystem.compute_damage(int(spear["attack_damage"]), spear["attack_type"], spear["bonuses"], kn)
	assert_eq(dmg, 16, "spearman vs knight: max(1, 3 - 2) + 15")
	kn.free()


func test_siege_bonus_vs_buildings() -> void:
	var h := Building.new()
	h.setup("house", GameData.building("house"), 2, 0, Vector2i(3, 3), true)
	var cat: Dictionary = GameData.unit("catapult")
	var dmg := CombatSystem.compute_damage(int(cat["attack_damage"]), cat["attack_type"], cat["bonuses"], h)
	assert_eq(dmg, 100, "catapult 40 - 0 melee armor + 60 building bonus")
	h.free()


func test_take_damage_kills_once() -> void:
	var v := _unit("villager", 1)
	var deaths := [0]
	v.killed.connect(func(_e, _a): deaths[0] += 1)
	v.take_damage(10, null)
	assert_eq(v.hp, 15, "hp reduced")
	v.take_damage(100, null)
	v.take_damage(100, null)
	assert_true(v.dead and v.hp == 0, "dead at 0 hp")
	assert_eq(deaths[0], 1, "killed emitted once")
	v.free()


func test_enemy_relation_ignores_gaia() -> void:
	var a := _unit("villager", 1)
	var b := _unit("villager", 2)
	var c := _unit("villager", 1)
	var tree := ResourceNode.new()
	tree.setup("tree_oak", GameData.resource_node("tree_oak"), Vector2i(1, 1), 0)
	assert_true(CombatSystem.is_enemy(a, b), "different players are enemies")
	assert_true(not CombatSystem.is_enemy(a, c), "same player is not an enemy")
	assert_true(not CombatSystem.is_enemy(a, tree), "Gaia is never an enemy")
	for n in [a, b, c, tree]:
		n.free()


func test_pikeman_counters_camel_with_both_bonuses() -> void:
	var cm := _unit("camel_rider", 2)
	var pike: Dictionary = GameData.unit("pikeman")
	var dmg := CombatSystem.compute_damage(int(pike["attack_damage"]), pike["attack_type"], pike["bonuses"], cm)
	assert_eq(dmg, 34, "pikeman vs camel: 4 - 0 armor + 22 cavalry + 8 camel")
	cm.free()


func test_camel_rider_bonus_vs_cavalier() -> void:
	var cv := _unit("cavalier", 2)
	var camel: Dictionary = GameData.unit("camel_rider")
	var dmg := CombatSystem.compute_damage(int(camel["attack_damage"]), camel["attack_type"], camel["bonuses"], cv)
	assert_eq(dmg, 13, "camel vs cavalier: max(1, 6 - 2 melee armor) + 9 cavalry")
	cv.free()


func test_skirmisher_shrugs_off_arrows_and_punishes_archers() -> void:
	var sk := _unit("skirmisher", 2)
	var ar := _unit("archer", 1)
	var archer: Dictionary = GameData.unit("archer")
	var skirm: Dictionary = GameData.unit("skirmisher")
	assert_eq(CombatSystem.compute_damage(int(archer["attack_damage"]), "pierce", archer["bonuses"], sk), 1, "archer 4 - 3 pierce armor")
	assert_eq(CombatSystem.compute_damage(int(skirm["attack_damage"]), "pierce", skirm["bonuses"], ar), 6, "skirmisher 2 + 4 vs archer")
	sk.free()
	ar.free()


func test_every_trainable_unit_has_a_sprite_layout() -> void:
	for bid in GameData.buildings:
		for uid in GameData.building(bid).get("trains", []):
			var sid: String = GameData.unit(uid).get("sprite", uid)
			assert_true(GameData.sprites["units"].has(sid), "%s (from %s) has a sprite layout" % [uid, bid])
			assert_true(FileAccess.file_exists("res://assets/sprites/units/%s_p0.png" % sid), "%s sheet generated" % sid)


func test_ram_may_only_target_buildings_and_siege() -> void:
	var ram: Dictionary = GameData.unit("battering_ram")
	var sw := _unit("swordsman", 2)
	var cat := _unit("catapult", 2)
	var h := Building.new()
	h.setup("house", GameData.building("house"), 2, 0, Vector2i(3, 3), true)
	assert_true(not CombatSystem.can_target(ram, sw), "ram ignores infantry")
	assert_true(CombatSystem.can_target(ram, cat), "ram may hit siege")
	assert_true(CombatSystem.can_target(ram, h), "ram may hit buildings")
	assert_true(CombatSystem.can_target(GameData.unit("swordsman"), h), "no attack_targets = anything")
	sw.free()
	cat.free()
	h.free()


func test_arrows_barely_scratch_a_ram() -> void:
	var r := _unit("battering_ram", 2)
	assert_eq(CombatSystem.compute_damage(5, "pierce", {}, r), 1, "180 pierce armor -> minimum damage")
	assert_eq(CombatSystem.compute_damage(9, "melee", {}, r), 12, "negative melee armor adds damage: 9 + 3")
	r.free()


func test_distance_to_segment_for_bolt_lines() -> void:
	var a := Vector2(0, 0)
	var b := Vector2(4, 0)
	assert_near(CombatSystem.distance_to_segment(Vector2(2, 0.3), a, b), 0.3, 0.0001, "beside the middle")
	assert_near(CombatSystem.distance_to_segment(Vector2(5, 0), a, b), 1.0, 0.0001, "past the end clamps to b")
	assert_near(CombatSystem.distance_to_segment(Vector2(1, 1), a, a), sqrt(2.0), 0.0001, "degenerate segment")


func test_corpse_lies_then_fades_gradually() -> void:
	assert_near(UnitSystem.corpse_alpha(8.0, 5.0), 1.0, 0.001, "fully visible while it lies")
	assert_near(UnitSystem.corpse_alpha(5.0, 5.0), 1.0, 0.001, "fade starts at full opacity")
	var mid := UnitSystem.corpse_alpha(2.5, 5.0)
	assert_true(mid > 0.2 and mid < 0.8, "half way through the fade it is half transparent (%.2f)" % mid)
	assert_true(UnitSystem.corpse_alpha(1.0, 5.0) < UnitSystem.corpse_alpha(2.0, 5.0), "keeps fading")
	assert_near(UnitSystem.corpse_alpha(0.0, 5.0), 0.0, 0.001, "gone at the end")

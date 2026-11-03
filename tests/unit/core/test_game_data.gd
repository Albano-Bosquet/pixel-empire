extends "res://tests/test_case.gd"
## Data files load and validate (data-files rule).


func test_no_validation_errors() -> void:
	assert_eq(GameData.errors().size(), 0, "GameData validation errors: %s" % ", ".join(GameData.errors()))


func test_resource_sprites_exist_in_atlas() -> void:
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpriteLibrary.PROPS_JSON))
	for id in GameData.resource_nodes:
		for s in GameData.resource_nodes[id]["sprites"]:
			assert_true(atlas.has(s), "prop '%s' for %s exists in atlas" % [s, id])


func test_unit_sheets_exist() -> void:
	for id in GameData.units:
		var sprite: String = GameData.units[id]["sprite"]
		for slot in GameData.players["colors"].size():
			assert_true(ResourceLoader.exists(SpriteLibrary.UNIT_SHEET % [sprite, slot]), "sheet %s_p%d" % [sprite, slot])

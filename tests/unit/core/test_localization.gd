extends "res://tests/test_case.gd"
## Spanish catalog covers every player-facing string, keeps the format
## placeholders of its keys, and packed messages translate on the receiver.

const Extract := preload("res://tools/i18n/extract_strings.gd")
const CATALOG := "res://assets/i18n/es.json"


func _catalog() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CATALOG))


func test_catalog_covers_every_key() -> void:
	var catalog := _catalog()
	var missing := PackedStringArray()
	for key in Extract.collect():
		if not catalog.has(key):
			missing.append(key)
	assert_eq(missing.size(), 0, "untranslated: %s" % ", ".join(missing))


func test_placeholders_match() -> void:
	var re := RegEx.new()
	re.compile("%[-0-9.]*[sdf%]")
	var catalog := _catalog()
	for key in catalog:
		var a := re.search_all(key).map(func(m): return m.get_string())
		var b := re.search_all(String(catalog[key])).map(func(m): return m.get_string())
		assert_eq(b, a, "placeholders of '%s'" % key)


func test_packed_message_translates_per_language() -> void:
	var before := Loc.language
	var m := Loc.msg("Requires %s", ["Feudal Age"])
	assert_true(m.begins_with("Requires %s"), "packed message keeps the English template first")
	Loc._apply("es")
	assert_eq(Loc.text(m), "Requiere: Edad Feudal", "Spanish")
	assert_eq(Loc.text(Loc.msg("%s has been defeated", ["Bob"])), "Bob ha sido derrotado", "unknown args pass through")
	Loc._apply("en")
	assert_eq(Loc.text(m), "Requires Feudal Age", "English")
	assert_eq(Loc.text("Not enough resources"), "Not enough resources", "plain text")
	Loc._apply(before)


func test_unknown_language_falls_back_to_default() -> void:
	var before := Loc.language
	Loc._apply("xx")
	assert_eq(Loc.language, Loc.LANGUAGES[0][0], "fallback language")
	Loc._apply(before)

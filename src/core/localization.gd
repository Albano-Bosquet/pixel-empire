extends Node
## Language selection (autoload `Loc`). English source text is the
## translation key: `tr("Start game")` shows "Empezar partida" in Spanish and
## the key itself in English, so untranslated text degrades to English.
## Catalogs: assets/i18n/<code>.json ({"English text": "translation"}).
## The choice is stored in user://settings.cfg [general] language; the
## command line can force one with `-- --lang=en|es`.
##
## Messages built far from the UI (notifications, errors, network events)
## travel untranslated as `Loc.msg(template, args)` and are translated by the
## receiver with `Loc.text()`, so each player reads them in their own language.

signal language_changed(code: String)

## [code, name shown in the selector]. The first entry is the default.
const LANGUAGES := [["es", "Español"], ["en", "English"]]
const CATALOG_DIR := "res://assets/i18n/"
const SETTINGS_PATH := "user://settings.cfg"
## Separates a message template from its arguments.
const SEP := "\u001f"

var language := "es"


## Loads in _init so the language is set before any other autoload or
## headless script builds text.
func _init() -> void:
	for entry in LANGUAGES:
		var code: String = entry[0]
		var path := CATALOG_DIR + code + ".json"
		if code == "en" or not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			push_error("Loc: bad catalog " + path)
			continue
		var t := Translation.new()
		t.locale = code
		for key in data:
			t.add_message(key, String(data[key]))
		TranslationServer.add_translation(t)
	var cfg := ConfigFile.new()
	var saved := LANGUAGES[0][0]
	if cfg.load(SETTINGS_PATH) == OK:
		saved = String(cfg.get_value("general", "language", saved))
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--lang="):
			saved = String(a).trim_prefix("--lang=")
	_apply(saved)


## Switches the language and remembers it for the next launch.
func set_language(code: String) -> void:
	if code == language:
		return
	_apply(code)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("general", "language", language)
	cfg.save(SETTINGS_PATH)
	language_changed.emit(language)


func _apply(code: String) -> void:
	language = code if LANGUAGES.any(func(l): return l[0] == code) else LANGUAGES[0][0]
	TranslationServer.set_locale(language)


## Packs a translatable message: `Loc.msg("%s completed", ["House"])`.
## Arguments are translated too (entity names, ages, resources); anything
## without a catalog entry (player names, numbers) is shown as is.
func msg(template: String, args: Array = []) -> String:
	if args.is_empty():
		return template
	return template + SEP + SEP.join(PackedStringArray(args.map(func(a): return str(a))))


## Translates plain text or a message packed by `msg()`.
func text(s: String) -> String:
	if not s.contains(SEP):
		return tr(s)
	var parts := s.split(SEP)
	var args := []
	for i in range(1, parts.size()):
		args.append(tr(parts[i]))
	return tr(parts[0]) % args


## Ordinal age name ("Dark Age", "Feudal Age", ...) as a translation key.
func age_name(age: int) -> String:
	return Hud.AGE_NAMES[clampi(age, 0, Hud.AGE_NAMES.size() - 1)]

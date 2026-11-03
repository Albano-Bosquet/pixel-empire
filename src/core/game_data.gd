extends Node
## Read-only registry of all JSON data in res://assets/data.
## Example: GameData.unit("villager").speed

const DATA_DIR := "res://assets/data/"

var units: Dictionary = {}
var movement: Dictionary = {}
var buildings: Dictionary = {}
var economy: Dictionary = {}
var combat: Dictionary = {}
var ages: Dictionary = {}
var ai: Dictionary = {}
var techs: Dictionary = {}
var rules: Dictionary = {}
var players: Dictionary = {}
var resource_nodes: Dictionary = {}
var map_gen: Dictionary = {}
var camera: Dictionary = {}
var sprites: Dictionary = {}
## Sound map and mixer settings (audio_settings.json).
var audio: Dictionary = {}
## Gaia animals: spawning, herding, wandering (wildlife_settings.json).
var wildlife: Dictionary = {}
## Day/night cycle and ambient life (ambience_settings.json).
var ambience: Dictionary = {}

var _errors: PackedStringArray = []


func _init() -> void:
	reload()


func reload() -> void:
	_errors.clear()
	units = _load("units_stats.json")
	movement = _load("units_movement.json")
	buildings = _load("buildings_stats.json")
	economy = _load("economy_settings.json")
	combat = _load("combat_settings.json")
	ages = _load("ages.json")
	ai = _load("ai_settings.json")
	techs = _load("technologies.json")
	rules = _load("game_rules.json")
	players = _load("players_config.json")
	resource_nodes = _load("resources_nodes.json")
	map_gen = _load("map_generation.json")
	camera = _load("camera_settings.json")
	sprites = _load("render_sprites.json")
	audio = _load("audio_settings.json")
	wildlife = _load("wildlife_settings.json")
	ambience = _load("ambience_settings.json")
	_validate()
	for e in _errors:
		push_error("GameData: " + e)


func errors() -> PackedStringArray:
	return _errors


func unit(id: String) -> Dictionary:
	return units.get(id, {})


func building(id: String) -> Dictionary:
	return buildings.get(id, {})


func resource_node(id: String) -> Dictionary:
	return resource_nodes.get(id, {})


func player_color(slot: int) -> Dictionary:
	var colors: Array = players.get("colors", [])
	return colors[slot % colors.size()] if not colors.is_empty() else {}


func _load(file: String) -> Dictionary:
	var path := DATA_DIR + file
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_errors.append("missing or empty " + path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	_errors.append("invalid JSON in " + path)
	return {}


func _validate() -> void:
	for id in units:
		var u: Dictionary = units[id]
		for key in ["max_hp", "speed", "sight", "radius", "sprite"]:
			if not u.has(key):
				_errors.append("unit '%s' missing '%s'" % [id, key])
		if not sprites.get("units", {}).has(u.get("sprite", "")):
			_errors.append("unit '%s' sprite '%s' not in render_sprites.json" % [id, u.get("sprite", "")])
	for id in buildings:
		var b: Dictionary = buildings[id]
		for key in ["size", "max_hp", "build_time", "cost", "age"]:
			if not b.has(key):
				_errors.append("building '%s' missing '%s'" % [id, key])
		for r in b.get("researches", []):
			if not ages.has(r) and not techs.has(r):
				_errors.append("building '%s' researches unknown '%s'" % [id, r])
		for t in b.get("trains", []):
			if not units.has(t):
				_errors.append("building '%s' trains unknown unit '%s'" % [id, t])
	for id in techs:
		var tdef: Dictionary = techs[id]
		if not buildings.get(tdef.get("building", ""), {}).get("researches", []).has(id):
			_errors.append("technology '%s' not listed in its building's researches" % id)
		for req in tdef.get("requires", []):
			if not techs.has(req):
				_errors.append("technology '%s' requires unknown '%s'" % [id, req])
	for id in resource_nodes:
		var r: Dictionary = resource_nodes[id]
		if not r.get("resource", "") in ["wood", "food", "gold", "stone"]:
			_errors.append("resource node '%s' has invalid resource" % id)

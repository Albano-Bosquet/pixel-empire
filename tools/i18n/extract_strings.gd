extends SceneTree
## Lists every player-facing English string the game asks to translate and
## reports the ones missing from the Spanish catalog (assets/i18n/es.json).
## Sources: tr / translate / Loc.msg / Loc.text literals in src/,
## display_name / description in data, and EXTRA_KEYS below.
## Run: Godot --headless --path . -s res://tools/i18n/extract_strings.gd

## Keys reached indirectly (constants, capitalized ids, plain messages
## returned or emitted by systems) that the source scan cannot see.
const EXTRA_KEYS := [
	"Dark Age", "Feudal Age", "Castle Age", "Imperial Age", "Gunpowder Age", "Industrial Age",
	"Skirmish vs Computer", "Sandbox (no enemies)",
	"Result", "Age reached", "Food gathered", "Wood gathered", "Gold gathered", "Stone gathered",
	"Units trained", "Units lost", "Kills", "Buildings built", "Buildings lost", "Winner", "Defeated",
	"Easy", "Normal", "Hard", "Tiny", "Small", "Medium", "Large", "Huge",
	"Food", "Wood", "Gold", "Stone", "food", "wood", "gold", "stone",
	"Economy", "Military", "economy", "military",
	"Aggressive stance: chase enemies in sight", "Defensive stance: short chase, return to post",
	"Stand ground: only attack what is in range", "Box formation: melee in front, ranged behind",
	"Line formation: one wide row", "Building", "Repairing", "Dropping off", "Player", "Computer",
	"A farm is exhausted", "You are under attack!", "Not enough resources to repair",
	"Trade needs a second market", "Monks cannot convert that", "The transport is full",
	"No shore to unload at", "Not enough resources", "Population limit reached — build more houses",
	"No idle villagers", "A Wonder has fallen", "Unknown building", "Outside the map",
	"Cannot build on water or mountains", "Something is in the way",
	"Docks must be built on open water by the shore", "Docks must touch the shore",
	"Docks need open water for ships", "Requires a Market", "Not enough gold", "Building not finished",
	"Cannot train that here", "Queue is full", "Cannot research that here", "Already researching",
	"Already researched", "Unknown technology", "Could not connect to the host",
	"The host closed the game", "Invalid address",
	"No answer from the host (check the IP, the VPN and the firewall)", "Removed by the host",
	"Only the host can start", "Waiting for every player to be ready", "The match has already started",
	"The game is full",
]


func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/i18n/es.json")) if FileAccess.file_exists("res://assets/i18n/es.json") else {}
	var missing := PackedStringArray()
	for key in collect():
		if not catalog.has(key):
			missing.append(key)
	for k in missing:
		print(JSON.stringify(k))
	print("missing: %d" % missing.size())
	quit(1 if not missing.is_empty() else 0)


## Every key found in code and data (sorted, unique).
static func collect() -> PackedStringArray:
	var keys := {}
	for k in EXTRA_KEYS:
		keys[k] = true
	_scan_code("res://src", keys)
	for file in ["units_stats.json", "buildings_stats.json", "technologies.json", "ages.json", "map_generation.json", "game_rules.json"]:
		_scan_data(JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/" + file)), keys)
	var out := PackedStringArray(keys.keys())
	out.sort()
	return out


static func _scan_code(dir: String, keys: Dictionary) -> void:
	var re := RegEx.new()
	re.compile(r'\b(?:tr|translate|Loc\.msg|Loc\.text)\("((?:[^"\\]|\\.)*)"')
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			for m in re.search_all(FileAccess.get_file_as_string(dir + "/" + f)):
				keys[m.get_string(1).c_unescape()] = true
	for sub in d.get_directories():
		if sub != "debug":
			_scan_code(dir + "/" + sub, keys)


static func _scan_data(v: Variant, keys: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			if k in ["display_name", "description"] and v[k] is String and v[k] != "":
				keys[v[k]] = true
			else:
				_scan_data(v[k], keys)
	elif v is Array:
		for x in v:
			_scan_data(x, keys)

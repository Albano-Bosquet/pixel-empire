extends SceneTree
## Generates every sprite PNG of the game into res://assets/sprites/.
## Run: Godot --headless --path . -s res://tools/art/generate_art.gd
## Re-run after changing any painter; then run `--headless --import`.

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")
const TerrainArt := preload("res://tools/art/terrain_art.gd")
const PropArt := preload("res://tools/art/prop_art.gd")
const HumanoidArt := preload("res://tools/art/humanoid_art.gd")
const BuildingArt := preload("res://tools/art/building_art.gd")
const CavalryArt := preload("res://tools/art/cavalry_art.gd")
const SiegeArt := preload("res://tools/art/siege_art.gd")
const SheetBuilder := preload("res://tools/art/sheet_builder.gd")
const ShipArt := preload("res://tools/art/ship_art.gd")
const AirArt := preload("res://tools/art/air_art.gd")
const VehicleArt := preload("res://tools/art/vehicle_art.gd")

const OUT := "res://assets/sprites/"
const PREVIEW := "res://production/qa/screenshots/art_preview.png"

## Per-unit look (non-team colours). Team colour replaces "tunic".
const BASE_LOOK := {"skin": "#e2ad80", "hair": "#6b4426", "pants": "#6e6250", "boots": "#3b2a1e", "belt": "#5c3b22"}
const UNIT_LOOKS := {
	"villager": {"painter": "humanoid"},
	"swordsman": {"painter": "humanoid", "mail": true, "helmet": "nasal", "shield": true, "weapon": "sword", "boots": "#2d2622"},
	"spearman": {"painter": "humanoid", "helmet": "kettle", "weapon": "spear", "pants": "#5a4a38", "hair": "#3a2a1c"},
	"archer": {"painter": "humanoid", "weapon": "bow", "pants": "#4f5a3a", "hair": "#8a5a2b", "skin": "#d39a6c"},
	"scout": {"painter": "cavalry", "coat": "#a8743f", "weapon": "sword"},
	"knight": {"painter": "cavalry", "coat": "#5a3a28", "mail": true, "helmet": "great", "caparison": true, "shield": true, "weapon": "sword"},
	"catapult": {"painter": "siege"},
	"militia": {"painter": "humanoid", "weapon": "sword", "pants": "#5d5446", "hair": "#4a3020"},
	"pikeman": {"painter": "humanoid", "mail": true, "helmet": "kettle", "weapon": "pike", "boots": "#2d2622"},
	"greatsword": {"painter": "humanoid", "mail": true, "helmet": "great", "weapon": "greatsword", "boots": "#2d2622", "pants": "#4a4640"},
	"skirmisher": {"painter": "humanoid", "weapon": "javelin", "shield": true, "pants": "#5a5a3c", "hair": "#2e2218", "skin": "#c98e62"},
	"crossbowman": {"painter": "humanoid", "helmet": "kettle", "weapon": "crossbow", "pants": "#4f4a3a"},
	"hand_cannoneer": {"painter": "humanoid", "helmet": "kettle", "weapon": "gun", "pants": "#3e3a34", "hair": "#2a1d14"},
	"cavalry_archer": {"painter": "cavalry", "coat": "#9a6a3a", "weapon": "bow"},
	"light_cavalry": {"painter": "cavalry", "coat": "#8f8a86", "helmet": "kettle", "weapon": "sword"},
	"cavalier": {"painter": "cavalry", "coat": "#d8cfc0", "mail": true, "helmet": "great", "caparison": true, "shield": true, "weapon": "sword", "plume": true},
	"battering_ram": {"painter": "siege", "model": "battering_ram"},
	"mangonel": {"painter": "siege", "model": "mangonel"},
	"scorpion": {"painter": "siege", "model": "scorpion"},
	"bombard_cannon": {"painter": "siege", "model": "bombard_cannon"},
	"trebuchet": {"painter": "siege", "model": "trebuchet"},
	"trade_cart": {"painter": "siege", "model": "trade_cart"},
	"fishing_ship": {"painter": "ship", "model": "fishing_ship"},
	"transport_ship": {"painter": "ship", "model": "transport_ship"},
	"war_galley": {"painter": "ship", "model": "war_galley"},
	"fire_ship": {"painter": "ship", "model": "fire_ship"},
	"demolition_ship": {"painter": "ship", "model": "demolition_ship"},
	"cannon_galleon": {"painter": "ship", "model": "cannon_galleon"},
	"blunderbussier": {"painter": "humanoid", "weapon": "blunderbuss", "helmet": "tricorn", "pants": "#d8d0bc", "boots": "#1c1412"},
	"musketeer": {"painter": "humanoid", "weapon": "musket", "helmet": "tricorn", "pants": "#e8e1d0", "boots": "#1c1412", "belt": "#e8e1d0"},
	"grenadier": {"painter": "humanoid", "weapon": "grenade", "helmet": "shako", "pants": "#e8e1d0", "boots": "#1c1412", "belt": "#e8e1d0"},
	"rifleman": {"painter": "humanoid", "weapon": "rifle", "helmet": "cap", "pants": "#5a5a40", "boots": "#2a2420", "belt": "#4a3a24"},
	"dragoon": {"painter": "cavalry", "coat": "#6e5038", "weapon": "carbine", "helmet": "shako", "caparison": true},
	"field_cannon": {"painter": "siege", "model": "field_cannon"},
	"mortar": {"painter": "siege", "model": "mortar"},
	"biplane_fighter": {"painter": "air", "model": "biplane_fighter"},
	"biplane_bomber": {"painter": "air", "model": "biplane_bomber"},
	"observation_balloon": {"painter": "air", "model": "observation_balloon"},
	"ironclad": {"painter": "ship", "model": "ironclad"},
	"infantryman": {"painter": "humanoid", "weapon": "assault_rifle", "helmet": "steel", "pants": "#5d6644", "boots": "#2a2420", "belt": "#4a4a30", "hair": "#3a2a1c"},
	"machine_gunner": {"painter": "humanoid", "weapon": "machine_gun", "helmet": "steel", "pants": "#5d6644", "boots": "#2a2420", "belt": "#c9a24a", "skin": "#d39a6c"},
	"bazooka_trooper": {"painter": "humanoid", "weapon": "bazooka", "helmet": "steel", "pants": "#5d6644", "boots": "#2a2420", "belt": "#4a4a30", "skin": "#c98e62"},
	"light_tank": {"painter": "vehicle", "model": "light_tank"},
	"heavy_tank": {"painter": "vehicle", "model": "heavy_tank"},
	"self_propelled_gun": {"painter": "vehicle", "model": "self_propelled_gun"},
	"jet_fighter": {"painter": "air", "model": "jet_fighter"},
	"jet_bomber": {"painter": "air", "model": "jet_bomber"},
	"monk": {"painter": "humanoid", "robe": "#7a5a3a", "weapon": "staff", "skin": "#d9a37a", "boots": "#4a3426"},
	"petard": {"painter": "humanoid", "weapon": "petard", "helmet": "kettle", "pants": "#4a4034", "hair": "#2a1d14"},
	"camel_rider": {"painter": "cavalry", "coat": "#c79a5e", "mount": "camel", "weapon": "sword", "hair": "#2e2218", "skin": "#c98e62"},
}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var sprites: Dictionary = _json("res://assets/data/render_sprites.json")
	var players: Dictionary = _json("res://assets/data/players_config.json")
	for dir in ["terrain", "props", "units", "buildings"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://production/qa/screenshots"))

	var atlas := TerrainArt.build_atlas(sprites["terrain"]["order"])
	_save(atlas, OUT + "terrain/terrain_atlas.png")
	_save(TerrainArt.build_noise(), OUT + "terrain/terrain_noise.png")

	var buildings_def: Dictionary = _json("res://assets/data/buildings_stats.json")
	var b_items := BuildingArt.build_all(buildings_def, sprites.get("construction", {}))
	b_items.merge(BuildingArt.flags(players["colors"]))
	b_items.merge(BuildingArt.sails())
	var b_packed := _pack(b_items, 2048)
	for n in b_items:
		if b_items[n].has("meta") and not b_items[n]["meta"].is_empty():
			b_packed["regions"][n]["meta"] = b_items[n]["meta"]
			# Highest opaque pixel above the anchor (health bars, arrow origin).
			var used: Rect2i = b_items[n]["canvas"].img.get_used_rect()
			b_packed["regions"][n]["meta"]["top"] = used.position.y - b_items[n]["anchor"].y
	_save(b_packed["image"], OUT + "buildings/buildings_atlas.png")
	var bf := FileAccess.open(OUT + "buildings/buildings_atlas.json", FileAccess.WRITE)
	bf.store_string(JSON.stringify(b_packed["regions"], "  "))
	bf.close()

	var props := PropArt.all_props()
	var packed := _pack(props, 512)
	_save(packed["image"], OUT + "props/props_atlas.png")
	var f := FileAccess.open(OUT + "props/props_atlas.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(packed["regions"], "  "))
	f.close()

	var unit_sheets := []
	for unit_id in sprites["units"]:
		var look: Dictionary = BASE_LOOK.duplicate()
		look.merge(UNIT_LOOKS.get(unit_id, UNIT_LOOKS["villager"]), true)
		var colors: Array = players["colors"]
		for slot in colors.size():
			var params := {}
			for k in look:
				params[k] = Color(look[k]) if look[k] is String and String(look[k]).begins_with("#") else look[k]
			params["tunic"] = Color(colors[slot]["primary"])
			var layout: Dictionary = sprites["units"][unit_id]
			var sheet: Image
			match String(look["painter"]):
				"cavalry":
					sheet = CavalryArt.build_sheet(layout, params)
				"siege":
					sheet = SiegeArt.build_sheet(layout, params)
				"ship":
					sheet = ShipArt.build_sheet(layout, params)
				"air":
					sheet = AirArt.build_sheet(layout, params)
				"vehicle":
					sheet = VehicleArt.build_sheet(layout, params)
				_:
					sheet = HumanoidArt.build_sheet(layout, params)
			_save(sheet, OUT + "units/%s_p%d.png" % [unit_id, slot])
			unit_sheets.append(sheet)

	_save(_preview(atlas, packed["image"], unit_sheets), PREVIEW)
	_save(_unit_preview(sprites["units"]), "res://production/qa/screenshots/art_units.png")
	var bprev: Image = b_packed["image"].duplicate()
	var bg := Image.create_empty(bprev.get_width(), bprev.get_height(), false, Image.FORMAT_RGBA8)
	bg.fill(Color("#5d9437"))
	bg.blend_rect(bprev, Rect2i(Vector2i.ZERO, bprev.get_size()), Vector2i.ZERO)
	bg.resize(bg.get_width() * 2, bg.get_height() * 2, Image.INTERPOLATE_NEAREST)
	_save(bg, "res://production/qa/screenshots/art_buildings.png")
	print("Art generated in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _save(img: Image, path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Failed to save " + path)
	else:
		print("  wrote ", path, " ", img.get_size())


## Shelf packer: tallest first, 1px padding.
func _pack(items: Dictionary, width: int) -> Dictionary:
	var names := items.keys()
	names.sort_custom(func(a, b): return items[a]["canvas"].h > items[b]["canvas"].h)
	var x := 0
	var y := 0
	var shelf_h := 0
	var regions := {}
	for n in names:
		var c: PixelCanvas = items[n]["canvas"]
		if x + c.w > width:
			x = 0
			y += shelf_h + 1
			shelf_h = 0
		var anchor: Vector2i = items[n]["anchor"]
		regions[n] = {"rect": [x, y, c.w, c.h], "anchor": [anchor.x, anchor.y]}
		x += c.w + 1
		shelf_h = maxi(shelf_h, c.h)
	var img := Image.create_empty(width, y + shelf_h, false, Image.FORMAT_RGBA8)
	for n in names:
		var r: Array = regions[n]["rect"]
		img.blit_rect(items[n]["canvas"].img, Rect2i(0, 0, r[2], r[3]), Vector2i(r[0], r[1]))
	return {"image": img, "regions": regions}


## One idle/walk/attack/die strip (facing SE) for each unit, blue team, 3x.
func _unit_preview(units: Dictionary) -> Image:
	var rows := []
	var w := 0
	var h := 0
	for id in units:
		var img := Image.load_from_file(ProjectSettings.globalize_path(OUT + "units/%s_p0.png" % id))
		var fs: Array = units[id]["frame_size"]
		var anims: Dictionary = units[id]["animations"]
		var strip := Image.create_empty(fs[0] * 44, fs[1], false, Image.FORMAT_RGBA8)
		var x := 0
		var ai := 0
		for a in anims:
			if a in ["idle", "walk", "attack", "die"]:
				for f in int(anims[a]["frames"]):
					strip.blit_rect(img, Rect2i(f * fs[0], (ai * SheetBuilder.DIRECTIONS + 2) * fs[1], fs[0], fs[1]), Vector2i(x, 0))
					x += fs[0]
			ai += 1
		rows.append(strip)
		w = maxi(w, strip.get_width())
		h += strip.get_height()
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color("#5d9437"))
	var y := 0
	for r in rows:
		out.blend_rect(r, Rect2i(Vector2i.ZERO, r.get_size()), Vector2i(0, y))
		y += r.get_height()
	out.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	return out


## Contact sheet at 3x for visual review of the generated art.
func _preview(terrain: Image, props: Image, units: Array) -> Image:
	var first: Image = units[0]
	var w := maxi(terrain.get_width(), maxi(props.get_width(), first.get_width()))
	var h := terrain.get_height() + props.get_height() + first.get_height() + 8
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("#3a4a3a"))
	img.blend_rect(terrain, Rect2i(Vector2i.ZERO, terrain.get_size()), Vector2i(0, 0))
	img.blend_rect(props, Rect2i(Vector2i.ZERO, props.get_size()), Vector2i(0, terrain.get_height() + 4))
	img.blend_rect(first, Rect2i(Vector2i.ZERO, first.get_size()), Vector2i(0, terrain.get_height() + props.get_height() + 8))
	img.resize(w * 3, h * 3, Image.INTERPOLATE_NEAREST)
	return img

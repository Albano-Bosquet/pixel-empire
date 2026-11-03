class_name SpriteLibrary
extends RefCounted
## Cached access to generated sprite assets (atlas regions, unit sheets).
## Layouts come from render_sprites.json and props_atlas.json so art files can
## be replaced without code changes.
## Example:
##   var r := SpriteLibrary.prop("oak_0")   # {"rect": Rect2, "anchor": Vector2}
##   sprite.texture = SpriteLibrary.props_texture()

const PROPS_TEX := "res://assets/sprites/props/props_atlas.png"
const PROPS_JSON := "res://assets/sprites/props/props_atlas.json"
const TERRAIN_ATLAS := "res://assets/sprites/terrain/terrain_atlas.png"
const TERRAIN_NOISE := "res://assets/sprites/terrain/terrain_noise.png"
const UNIT_SHEET := "res://assets/sprites/units/%s_p%d.png"

static var _props_tex: Texture2D
static var _props: Dictionary = {}
static var _sheets: Dictionary = {}


static func props_texture() -> Texture2D:
	if _props_tex == null:
		_props_tex = load(PROPS_TEX)
	return _props_tex


static func prop(name: String) -> Dictionary:
	if _props.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROPS_JSON))
		if raw is Dictionary:
			for k in raw:
				var r: Array = raw[k]["rect"]
				var a: Array = raw[k]["anchor"]
				_props[k] = {"rect": Rect2(r[0], r[1], r[2], r[3]), "anchor": Vector2(a[0], a[1])}
		else:
			push_error("SpriteLibrary: cannot read " + PROPS_JSON)
	if not _props.has(name):
		push_error("SpriteLibrary: unknown prop '%s'" % name)
		return {"rect": Rect2(0, 0, 1, 1), "anchor": Vector2.ZERO}
	return _props[name]


## Team sheet of a unit; layouts marked "neutral" (animals) have one sheet for all.
static func unit_sheet(sprite_id: String, color_slot: int) -> Texture2D:
	if unit_layout(sprite_id).get("neutral", false):
		color_slot = 0
	var key := "%s:%d" % [sprite_id, color_slot]
	if not _sheets.has(key):
		_sheets[key] = load(UNIT_SHEET % [sprite_id, color_slot])
	return _sheets[key]


static func unit_layout(sprite_id: String) -> Dictionary:
	return GameData.sprites.get("units", {}).get(sprite_id, {})


## Draws a prop region with its anchor at `pos` on `canvas`.
static func draw_prop(canvas: CanvasItem, name: String, pos: Vector2, modulate: Color = Color.WHITE) -> void:
	var r := prop(name)
	var rect: Rect2 = r["rect"]
	canvas.draw_texture_rect_region(props_texture(), Rect2(pos - r["anchor"], rect.size), rect, modulate)

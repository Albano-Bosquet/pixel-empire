extends SceneTree
## Renders the application icon (Town Center sprite on a framed tile) to
## build/icon.png at 256x256. Run: Godot --headless --path . -s res://tools/art/make_icon.gd


func _initialize() -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sprites/buildings/buildings_atlas.png"))
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/buildings/buildings_atlas.json"))
	var r: Array = meta["town_center"]["rect"]
	var tc := atlas.get_region(Rect2i(r[0], r[1], r[2], r[3]))
	var used := tc.get_used_rect()
	tc = tc.get_region(used)
	var side := maxi(used.size.x, used.size.y) + 12
	var canvas := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	# Rounded dark plate with a brass rim so the icon reads on any background.
	var c := side * 0.5
	for y in side:
		for x in side:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
			if d < c - 1.0:
				canvas.set_pixel(x, y, Color("#8a6d3b") if d > c - 4.0 else Color("#2c3a2a").lerp(Color("#3f5a34"), 1.0 - y / float(side)))
	canvas.blend_rect(tc, Rect2i(Vector2i.ZERO, tc.get_size()), Vector2i((side - tc.get_width()) / 2, (side - tc.get_height()) / 2 + 2))
	canvas.resize(256, 256, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	canvas.save_png(ProjectSettings.globalize_path("res://build/icon.png"))
	for s in [48, 32, 16]:
		var small := canvas.duplicate() as Image
		small.resize(s, s, Image.INTERPOLATE_LANCZOS)
		small.save_png(ProjectSettings.globalize_path("res://build/icon_%d.png" % s))
	print("icon written")
	quit()

extends SceneTree
## Loads every .gd under res://src and res://tools/art so parse/compile errors
## surface in CI. Run: Godot --headless --path . -s res://tests/check_scripts.gd


func _initialize() -> void:
	var files := PackedStringArray()
	for root in ["res://src", "res://tools/art", "res://tests/unit"]:
		_collect(root, files)
	var bad := 0
	for f in files:
		var s: Variant = load(f)
		if s == null or (s is GDScript and not (s as GDScript).can_instantiate() and not f.ends_with("_art.gd")):
			print("BROKEN: ", f)
			bad += 1
	print("Checked %d scripts, %d broken" % [files.size(), bad])
	quit(1 if bad > 0 else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_collect(dir + "/" + sub, out)

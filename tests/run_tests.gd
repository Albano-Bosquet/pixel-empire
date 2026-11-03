extends SceneTree
## Minimal headless test runner. Discovers tests/unit/**/test_*.gd; every
## method named test_* is run on a fresh instance. Exit code 1 on failure.
## Run: Godot --headless --path . -s res://tests/run_tests.gd

const TestCase := preload("res://tests/test_case.gd")


func _initialize() -> void:
	var files := PackedStringArray()
	_collect("res://tests/unit", files)
	var passed := 0
	var failed := 0
	for f in files:
		var script: GDScript = load(f)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var inst: TestCase = script.new()
			inst.call(name)
			if inst.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for msg in inst.failures:
					print("FAIL %s::%s — %s" % [f.get_file(), name, msg])
	print("Tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_collect(dir + "/" + sub, out)

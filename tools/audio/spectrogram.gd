extends SceneTree
## QA aid: draws spectrograms of generated sounds into
## production/qa/screenshots/audio_spectrograms.png (log-frequency rows, time
## columns) so the synthesis can be reviewed visually.
## Run: Godot --headless --path . -s res://tools/audio/spectrogram.gd -- [--music=medieval_1] [--sfx=a,b,c]

const BANDS := 72
const F_MIN := 60.0
const F_MAX := 9000.0
const TILE_H := 96


func _initialize() -> void:
	var sfx := ["chop_1", "hit_sword_1", "bow_1", "musket_1", "cannon", "explosion_1", "sel_villager_1", "ack_infantry_1", "sheep_1", "wolf_howl", "tiger_roar", "bird_3", "age_up", "build_1", "collapse", "conversion"]
	var music := "medieval_1"
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--music="):
			music = s.get_slice("=", 1)
		elif s.begins_with("--sfx="):
			sfx = Array(s.get_slice("=", 1).split(","))
	var rows: Array[Image] = []
	rows.append(_spectrogram("res://assets/audio/music/%s.wav" % music, 1500, 0.05))
	var tiles: Array[Image] = []
	for name in sfx:
		tiles.append(_spectrogram("res://assets/audio/sfx/%s.wav" % name, 180, 0.01))
	var w := 1500
	var h := TILE_H + 4 + ceili(tiles.size() / 8.0) * (TILE_H + 4)
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.05, 0.05, 0.08))
	out.blit_rect(rows[0], Rect2i(Vector2i.ZERO, rows[0].get_size()), Vector2i.ZERO)
	for i in tiles.size():
		out.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, tiles[i].get_size()), Vector2i((i % 8) * 186, TILE_H + 4 + (i / 8) * (TILE_H + 4)))
	out.save_png(ProjectSettings.globalize_path("res://production/qa/screenshots/audio_spectrograms.png"))
	print("spectrograms: music=%s sfx=%s" % [music, ", ".join(sfx)])
	quit(0)


func _read(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return [PackedFloat32Array(), 22050]
	f.seek(24)
	var rate := f.get_32()
	f.seek(44)
	var bytes := f.get_buffer(f.get_length() - 44)
	var out := PackedFloat32Array()
	out.resize(bytes.size() / 2)
	for i in out.size():
		out[i] = bytes.decode_s16(i * 2) / 32768.0
	return [out, rate]


## Goertzel power per log-spaced band, one column per `width` slice.
func _spectrogram(path: String, width: int, min_hop: float) -> Image:
	var r := _read(path)
	var x: PackedFloat32Array = r[0]
	var rate: int = r[1]
	var img := Image.create_empty(width, TILE_H, false, Image.FORMAT_RGB8)
	if x.is_empty():
		return img
	var win := mini(512, x.size())
	var cols := width
	var hop := maxf(float(x.size() - win) / cols, min_hop * rate * 0.0 + 1.0)
	for c in cols:
		var start := int(c * hop)
		if start + win > x.size():
			break
		for b in BANDS:
			var f := F_MIN * pow(F_MAX / F_MIN, float(b) / (BANDS - 1))
			var k := 2.0 * cos(TAU * f / rate)
			var s1 := 0.0
			var s2 := 0.0
			for i in win:
				var s0 := x[start + i] + k * s1 - s2
				s2 = s1
				s1 = s0
			var p := s1 * s1 + s2 * s2 - k * s1 * s2
			var db := clampf((10.0 * log(maxf(p, 1e-9)) / log(10.0) + 10.0) / 50.0, 0.0, 1.0)
			var y0 := TILE_H - 1 - int(float(b) / BANDS * TILE_H)
			var col := Color.from_hsv(0.7 - db * 0.7, 0.9, db)
			for yy in range(maxi(0, y0 - 1), y0 + 1):
				img.set_pixel(c, yy, col)
	return img

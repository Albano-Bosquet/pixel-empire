extends RefCounted
## Seamless 64x64 pixel-art ground textures (one per terrain id) packed in a
## horizontal atlas, plus the RG noise texture the terrain shader uses for
## dithered borders and macro shading.

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")

const SIZE := 64


static func build_atlas(order: Array) -> Image:
	var atlas := Image.create_empty(SIZE * order.size(), SIZE, false, Image.FORMAT_RGBA8)
	for i in order.size():
		var tex: Image = _texture(String(order[i]), 1000 + i * 17)
		atlas.blit_rect(tex, Rect2i(0, 0, SIZE, SIZE), Vector2i(i * SIZE, 0))
	return atlas


static func build_noise(size: int = 128) -> Image:
	var a := _noise_img(11, 0.06, 3, size)
	var b := _noise_img(29, 0.06, 3, size)
	var macro := _noise_img(47, 0.015, 2, size)
	var out := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			out.set_pixel(x, y, Color(a.get_pixel(x, y).r, b.get_pixel(x, y).r, macro.get_pixel(x, y).r, 1.0))
	return out


static func _noise_img(seed: int, freq: float, octaves: int, size: int = SIZE) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var img := n.get_seamless_image(size, size, false, false, 0.1, true)
	img.convert(Image.FORMAT_RGBA8)
	return img


## Fills the canvas by mapping noise to ramp shades with ordered dithering.
static func _fill(c: PixelCanvas, noise: Image, ramp: Array[Color], lo: float, hi: float, dither: float) -> void:
	var n := ramp.size()
	for y in SIZE:
		for x in SIZE:
			var v := inverse_lerp(lo, hi, noise.get_pixel(x, y).r)
			var idx := int(floor(v * n + (PixelCanvas.bayer(x, y) - 0.5) * dither))
			c.put(x, y, ramp[clampi(idx, 0, n - 1)])


static func _texture(id: String, seed: int) -> Image:
	var c := PixelCanvas.new(SIZE, SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := _noise_img(seed, 0.09, 3)
	match id:
		"deep_water":
			var r := PixelCanvas.ramp(Color("#1c4b7a"), 4, 0.35)
			_fill(c, noise, r, 0.1, 0.9, 1.0)
			_waves(c, rng, 10, Color("#2f6a9a"), 3, 6)
		"water":
			var r := PixelCanvas.ramp(Color("#2d7fa6"), 4, 0.35)
			_fill(c, noise, r, 0.1, 0.9, 1.0)
			_waves(c, rng, 14, Color("#5fb0cf"), 3, 7)
			_waves(c, rng, 6, Color("#9ad6e6"), 2, 3)
		"sand":
			var r := PixelCanvas.ramp(Color("#d8bd7c"), 4, 0.3)
			_fill(c, noise, r, 0.15, 0.85, 1.2)
			_specks(c, rng, 40, [Color("#b79a5d"), Color("#efdcaa")])
			_ripples(c, rng, 6, Color("#c4a766"))
		"grass":
			var r := PixelCanvas.ramp(Color("#5d9437"), 4, 0.22)
			_fill(c, noise, r, 0.1, 0.9, 0.8)
			_blades(c, rng, 55, Color("#4f8530"), Color("#79ad48"))
		"meadow":
			var r := PixelCanvas.ramp(Color("#72a543"), 4, 0.22)
			_fill(c, noise, r, 0.1, 0.9, 0.8)
			_blades(c, rng, 45, Color("#62933a"), Color("#97c45a"))
			_flowers(c, rng, 14)
		"forest":
			var r := PixelCanvas.ramp(Color("#41702e"), 4, 0.25)
			_fill(c, noise, r, 0.1, 0.9, 0.9)
			_specks(c, rng, 50, [Color("#6b5a2e"), Color("#7d6a35"), Color("#2f5422")])
			_blades(c, rng, 40, Color("#33592a"), Color("#5f8a3a"))
		"dirt":
			var r := PixelCanvas.ramp(Color("#8a6a43"), 4, 0.25)
			_fill(c, noise, r, 0.1, 0.9, 0.9)
			_pebbles(c, rng, 4, Color("#9a8f80"))
			_specks(c, rng, 30, [Color("#6f5434"), Color("#a6865a")])
		"path":
			var r := PixelCanvas.ramp(Color("#a48659"), 4, 0.3)
			_fill(c, noise, r, 0.2, 0.8, 1.1)
			_pebbles(c, rng, 6, Color("#b1a796"))
			_specks(c, rng, 20, [Color("#8c7049")])
		"rocky":
			var r := PixelCanvas.ramp(Color("#857a62"), 4, 0.35)
			_fill(c, noise, r, 0.15, 0.85, 1.3)
			_pebbles(c, rng, 22, Color("#9c9890"))
			_blades(c, rng, 12, Color("#5d6e35"), Color("#7f904a"))
		"mountain":
			var r := PixelCanvas.ramp(Color("#7b7770"), 5, 0.45)
			_fill(c, noise, r, 0.1, 0.9, 1.0)
			_cracks(c, rng, 9, Color("#4f4c49"), Color("#a9a59c"))
		_:
			c.rect(0, 0, SIZE, SIZE, Color.MAGENTA)
	return c.img


static func _blades(c: PixelCanvas, rng: RandomNumberGenerator, count: int, dark: Color, light: Color) -> void:
	for i in count:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		var hgt := rng.randi_range(2, 3)
		c.put_wrap(x, y, dark)
		for k in range(1, hgt):
			c.put_wrap(x + (1 if k == hgt - 1 and rng.randf() < 0.4 else 0), y - k, light)


static func _flowers(c: PixelCanvas, rng: RandomNumberGenerator, count: int) -> void:
	var cols := [Color("#f4f1e4"), Color("#f3d24a"), Color("#c98ee0"), Color("#ea7f6b")]
	for i in count:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		var col: Color = cols[rng.randi() % cols.size()]
		c.put_wrap(x, y + 1, Color("#4f7f2b"))
		c.put_wrap(x - 1, y, col)
		c.put_wrap(x + 1, y, col)
		c.put_wrap(x, y - 1, col)
		c.put_wrap(x, y, Color("#f7e7a0"))


static func _specks(c: PixelCanvas, rng: RandomNumberGenerator, count: int, cols: Array) -> void:
	for i in count:
		c.put_wrap(rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1), cols[rng.randi() % cols.size()])


static func _pebbles(c: PixelCanvas, rng: RandomNumberGenerator, count: int, base: Color) -> void:
	var r := PixelCanvas.ramp(base, 3, 0.5)
	for i in count:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		var big := rng.randf() < 0.35
		c.put_wrap(x, y, r[1])
		c.put_wrap(x + 1, y, r[1])
		c.put_wrap(x, y - 1, r[2])
		c.put_wrap(x + 1, y + 1, r[0])
		c.put_wrap(x, y + 1, r[0])
		if big:
			c.put_wrap(x + 2, y, r[1])
			c.put_wrap(x + 1, y - 1, r[2])
			c.put_wrap(x + 2, y + 1, r[0])


static func _waves(c: PixelCanvas, rng: RandomNumberGenerator, count: int, col: Color, min_len: int, max_len: int) -> void:
	for i in count:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		var l := rng.randi_range(min_len, max_len)
		for k in l:
			c.put_wrap(x + k, y + (1 if k == 0 or k == l - 1 else 0), col)


static func _ripples(c: PixelCanvas, rng: RandomNumberGenerator, count: int, col: Color) -> void:
	for i in count:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		for k in rng.randi_range(4, 9):
			c.put_wrap(x + k, y + int(round(sin(k * 0.8))), col)


static func _cracks(c: PixelCanvas, rng: RandomNumberGenerator, count: int, dark: Color, light: Color) -> void:
	for i in count:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		for k in rng.randi_range(4, 10):
			c.put_wrap(x, y, dark)
			c.put_wrap(x - 1, y - 1, light)
			x += rng.randi_range(-1, 1)
			y += 1 if rng.randf() < 0.6 else 0
			x += 1

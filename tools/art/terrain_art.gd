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


## Shades of `base` that differ in brightness only (PixelCanvas.ramp also shifts
## hue and saturation, which reads as two separate colours on calm ground).
## `amount` is the total value change from the darkest shade to the lightest.
static func _soft_ramp(base: Color, steps: int, amount: float) -> Array[Color]:
	var out: Array[Color] = []
	for i in steps:
		var t := float(i) / float(steps - 1) - 0.5
		out.append(Color.from_hsv(base.h, base.s, clampf(base.v + t * amount, 0.0, 1.0)))
	return out


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
		# Water colour comes from the shader (depth bands); these calm tiles
		# only feed the minimap average and the fallback look.
		"deep_water":
			var r := PixelCanvas.ramp(Color("#1d5fa6"), 3, 0.08)
			_fill(c, noise, r, 0.1, 0.9, 1.0)
		"water":
			var r := PixelCanvas.ramp(Color("#2a7cc4"), 3, 0.08)
			_fill(c, noise, r, 0.1, 0.9, 1.0)
		"sand":
			# Pale, smooth beach sand (AoE-style): low contrast, a few grains.
			var r := _soft_ramp(Color("#dcc58a"), 4, 0.035)
			_fill(c, _noise_img(seed, 0.045, 2), r, 0.15, 0.85, 1.0)
			_specks(c, rng, 90, [Color("#d0b87e"), Color("#e6d29c")])
		# Grass family (AoE-style): near-uniform colour with soft, broad
		# variation (low-frequency noise, low-contrast ramp) and a fine grain of
		# short blades, so it reads as a lawn rather than camouflage blotches.
		# Grass, meadow and forest floor stay close in tone so borders are calm.
		"grass":
			var r := _soft_ramp(Color("#5e9838"), 4, 0.05)
			_fill(c, _noise_img(seed, 0.045, 2), r, 0.15, 0.85, 1.0)
			_blades(c, rng, 170, Color("#4f8630"), Color("#70ab45"))
		"meadow":
			var r := _soft_ramp(Color("#66a03c"), 4, 0.05)
			_fill(c, _noise_img(seed, 0.045, 2), r, 0.15, 0.85, 1.0)
			# No flowers here: on calm grass they show the 64 px tile as a grid.
			# Scattered flower props come from MapGenerator._place_decor.
			_blades(c, rng, 160, Color("#568e33"), Color("#7ab44c"))
		"forest":
			var r := _soft_ramp(Color("#4c7d33"), 4, 0.04)
			_fill(c, _noise_img(seed, 0.045, 2), r, 0.15, 0.85, 1.0)
			_blades(c, rng, 120, Color("#43722e"), Color("#58893a"))
			_specks(c, rng, 22, [Color("#6b5a2e"), Color("#5e6a2c")])
		"dirt":
			var r := _soft_ramp(Color("#8a6a43"), 4, 0.06)
			_fill(c, _noise_img(seed, 0.045, 2), r, 0.15, 0.85, 1.0)
			_specks(c, rng, 70, [Color("#82643f"), Color("#92724a")])
		"path":
			var r := PixelCanvas.ramp(Color("#a48659"), 4, 0.3)
			_fill(c, noise, r, 0.2, 0.8, 1.1)
			_pebbles(c, rng, 6, Color("#b1a796"))
			_specks(c, rng, 20, [Color("#8c7049")])
		"rocky":
			var r := _soft_ramp(Color("#8a7f66"), 4, 0.06)
			_fill(c, _noise_img(seed, 0.045, 2), r, 0.15, 0.85, 1.0)
			_specks(c, rng, 70, [Color("#82775f"), Color("#92876e")])
			_blades(c, rng, 8, Color("#6d7442"), Color("#7f8a4c"))
		"mountain":
			# Cliff rock: the shader paints walls, this tile feeds the minimap.
			var r := _soft_ramp(Color("#8a7458"), 4, 0.05)
			_fill(c, _noise_img(seed, 0.045, 2), r, 0.15, 0.85, 1.0)
		"plateau":
			# Plateau top above the cliffs: dry olive scrub, so it stands apart
			# from the rocky ground at the foot of the walls.
			var r := _soft_ramp(Color("#7f8650"), 4, 0.05)
			_fill(c, _noise_img(seed, 0.045, 2), r, 0.15, 0.85, 1.0)
			_specks(c, rng, 40, [Color("#8e8a62"), Color("#6f7646")])
			_blades(c, rng, 90, Color("#6c7643"), Color("#8c9458"))
		"ramp":
			# Packed earth climbing through the cliff.
			var r := _soft_ramp(Color("#a58c62"), 4, 0.05)
			_fill(c, _noise_img(seed, 0.045, 2), r, 0.15, 0.85, 1.0)
			_specks(c, rng, 70, [Color("#957d55"), Color("#b39b70")])
		"cliff":
			_cliff_face(c, rng, noise)
		"desert":
			_dunes(c, noise)
			_specks(c, rng, 60, [Color("#cb9c55"), Color("#deb26a")])
		_:
			c.rect(0, 0, SIZE, SIZE, Color.MAGENTA)
	return c.img


## Rock wall the shader maps on cliffs (atlas entry only, no terrain id): stacked,
## staggered boulders with warped edges, each lit from the top left, with dark
## gaps between them. Block sizes divide SIZE, so the tile stays seamless.
static func _cliff_face(c: PixelCanvas, rng: RandomNumberGenerator, noise: Image) -> void:
	var ramp: Array[Color] = [Color("#463a30"), Color("#62513f"), Color("#7e6a52"), Color("#9a8468"), Color("#b6a084")]
	var bw := 16
	var bh := 16
	var cols := SIZE / bw
	var rows := SIZE / bh
	var tone: Array[float] = []
	for i in cols * rows:
		tone.append(rng.randf_range(-0.13, 0.13))
	for y in SIZE:
		for x in SIZE:
			var n := noise.get_pixel(x, y).r
			var wy := fposmod(y + (n - 0.5) * 7.0, SIZE)
			var row := int(wy / bh)
			var wx := fposmod(x + (bw / 2 if row % 2 == 1 else 0) + (n - 0.5) * 9.0, SIZE)
			var col := int(wx / bw)
			var fx := fposmod(wx, bw) / bw
			var fy := fposmod(wy, bh) / bh
			var shade := 0.86 - 0.18 * fx - 0.30 * fy + tone[row * cols + col]
			if fx > 0.92 or fy > 0.89:
				shade = 0.16
			var idx := int(floor(shade * ramp.size() + (PixelCanvas.bayer(x, y) - 0.5) * 0.5))
			c.put(x, y, ramp[clampi(idx, 0, ramp.size() - 1)])


## Golden desert sand with soft diagonal dune ridges: every period divides
## SIZE, so the tile stays seamless.
static func _dunes(c: PixelCanvas, noise: Image) -> void:
	var ramp := _soft_ramp(Color("#d6a75e"), 5, 0.07)
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			var n := noise.get_pixel(x, y).r
			# Ridges warped by the (seamless) noise so they wander instead of tiling.
			var phase := TAU * (u + v) + 0.7 * sin(TAU * u) + (n - 0.5) * 7.0
			# Long gentle windward slope, a softer lee shade just past the crest.
			var s := fposmod(phase / TAU, 1.0)
			var shade := 0.40 + 0.30 * s - (0.25 if s > 0.9 else 0.0)
			shade += (n - 0.5) * 0.30
			var idx := int(floor(shade * ramp.size() + (PixelCanvas.bayer(x, y) - 0.5) * 0.9))
			c.put(x, y, ramp[clampi(idx, 0, ramp.size() - 1)])


static func _blades(c: PixelCanvas, rng: RandomNumberGenerator, count: int, dark: Color, light: Color) -> void:
	for i in count:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		var hgt := rng.randi_range(2, 3)
		c.put_wrap(x, y, dark)
		for k in range(1, hgt):
			c.put_wrap(x + (1 if k == hgt - 1 and rng.randf() < 0.4 else 0), y - k, light)


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

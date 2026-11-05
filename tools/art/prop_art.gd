extends RefCounted
## Static world props: trees, resource deposits, ground decor,
## plus shadow and selection-ring sprites. Each builder returns
## {"canvas": PixelCanvas, "anchor": Vector2i} where anchor is the ground point.

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")

const SHADOW := Color(0.05, 0.07, 0.12, 0.30)


static func all_props() -> Dictionary:
	var out := {}
	for i in 4:
		out["oak_%d" % i] = oak(300 + i)
		out["pine_%d" % i] = pine(400 + i)
	for i in 3:
		out["gold_%d" % i] = deposit(500 + i, true)
		out["stone_%d" % i] = deposit(600 + i, false)
	for i in 2:
		out["berry_%d" % i] = berry_bush(700 + i)
	out["stump_0"] = stump(900)
	for i in 3:
		out["tuft_%d" % i] = tuft(1000 + i)
	for i in 2:
		out["flowers_%d" % i] = flower_patch(1100 + i)
	for i in 3:
		out["pebble_%d" % i] = pebbles(1200 + i)
	out["shrub_0"] = shrub(1300)
	out["shrub_1"] = shrub(1301)
	out["mushroom_0"] = mushrooms(1400)
	out["mushroom_1"] = toadstools(1401, Color("#a9713f"), Color("#c99a62"))
	out["mushroom_2"] = toadstools(1402, Color("#e7d7b4"), Color("#f5ecd6"))
	out["daisies_0"] = flower_bed(1110, Color("#f6f2e6"), Color("#f3c63a"))
	out["daisies_1"] = flower_bed(1111, Color("#f6f2e6"), Color("#f3c63a"))
	out["buttercups_0"] = flower_bed(1112, Color("#f5d13f"), Color("#d99a22"))
	out["bluebells_0"] = flower_bed(1113, Color("#8f8fe6"), Color("#d7d4f7"))
	out["poppies_0"] = flower_bed(1114, Color("#e0523f"), Color("#3a2a24"))
	out["clover_0"] = clover(1115)
	out["clover_1"] = clover(1116)
	out["stone_small_0"] = field_stone(1210)
	out["stone_small_1"] = field_stone(1211)
	out["twigs_0"] = twigs(1212)
	for i in 2:
		out["fish_%d" % i] = fish_shoal(1600 + i)
	out["shadow_s"] = shadow(26, 11)
	out["shadow_m"] = shadow(40, 17)
	out["shadow_l"] = shadow(110, 55)
	out["ring_s"] = ring(30, 15)
	out["ring_m"] = ring(46, 23)
	out["ring_l"] = ring(120, 60)
	out["icon_wood"] = icon_wood()
	out["icon_food"] = icon_food()
	out["icon_gold"] = icon_ore(Color("#e3b02a"), 1)
	out["icon_stone"] = icon_ore(Color("#9aa1a8"), 2)
	out["icon_pop"] = icon_pop()
	out["rock"] = rock()
	for n in ["stop", "aggressive", "defensive", "stand", "box", "line", "age"]:
		out["icon_" + n] = ui_icon(n)
	for n in ["hp", "carry", "build", "armor", "attack", "arrow", "speed"]:
		out["icon_tech_" + n] = tech_icon(n)
	for n in range(1, 5):
		out["rubble_%d" % n] = rubble(n, 1500 + n)
	return out


## 20x20 command icons (stances, formations, stop, age advance).
static func ui_icon(kind: String) -> Dictionary:
	var c := PixelCanvas.new(20, 20)
	var metal := PixelCanvas.ramp(Color("#b9c0c8"), 3, 0.5)
	var gold := PixelCanvas.ramp(Color("#e3b02a"), 3, 0.5)
	var red := Color("#c0392b")
	match kind:
		"stop":
			c.ellipse(10, 10, 8, 8, red)
			c.ellipse(10, 10, 6.5, 6.5, Color("#e05a4a"))
			c.rect(5, 9, 10, 3, Color.WHITE)
		"aggressive":
			c.thick_line(4, 16, 16, 4, 2.0, metal[2])
			c.thick_line(4, 4, 16, 16, 2.0, metal[1])
			c.rect(3, 15, 3, 3, Color("#6e4a2c"))
			c.rect(14, 15, 3, 3, Color("#6e4a2c"))
		"defensive":
			c.polygon(PackedVector2Array([Vector2(4, 3), Vector2(16, 3), Vector2(16, 10), Vector2(10, 18), Vector2(4, 10)]), Color("#3d6fd6"))
			c.polygon(PackedVector2Array([Vector2(6, 5), Vector2(10, 5), Vector2(10, 15), Vector2(6, 10)]), Color("#7ea6f2"))
		"stand":
			c.rect(5, 3, 2, 15, Color("#6e4a2c"))
			c.polygon(PackedVector2Array([Vector2(7, 3), Vector2(17, 6), Vector2(7, 10)]), red)
			c.rect(3, 17, 8, 2, Color("#6b5a48"))
		"box":
			for y in 3:
				for x in 3:
					c.ellipse(5 + x * 5, 5 + y * 5, 1.8, 1.8, metal[2])
		"line":
			for x in 5:
				c.ellipse(3 + x * 3.5, 10, 1.6, 1.6, metal[2])
		"age":
			c.polygon(PackedVector2Array([Vector2(3, 15), Vector2(3, 6), Vector2(7, 10), Vector2(10, 4), Vector2(13, 10), Vector2(17, 6), Vector2(17, 15)]), gold[1])
			c.rect(3, 13, 15, 3, gold[0])
			c.put(10, 8, red)
	c.outline(0.6)
	return {"canvas": c, "anchor": Vector2i(10, 10)}


## 20x20 technology icons.
static func tech_icon(kind: String) -> Dictionary:
	var c := PixelCanvas.new(20, 20)
	var metal := PixelCanvas.ramp(Color("#b9c0c8"), 3, 0.5)
	var wood := PixelCanvas.ramp(Color("#8d6139"), 3, 0.5)
	match kind:
		"hp":
			c.ellipse(7, 8, 4, 4, Color("#d6453a"))
			c.ellipse(13, 8, 4, 4, Color("#d6453a"))
			c.polygon(PackedVector2Array([Vector2(3, 9), Vector2(17, 9), Vector2(10, 17)]), Color("#d6453a"))
			c.put(6, 6, Color("#f6a79a"))
			c.put(7, 6, Color("#f6a79a"))
		"carry":
			c.polygon(PackedVector2Array([Vector2(3, 7), Vector2(15, 7), Vector2(13, 12), Vector2(5, 12)]), wood[1])
			c.rect(4, 7, 11, 1, wood[2])
			c.ellipse(9, 15, 2.5, 2.5, Color("#4a3020"))
			c.line(14, 9, 18, 6, wood[0])
			c.ellipse(9, 6, 2, 1.5, Color("#e3b02a"))
		"build":
			c.thick_line(5, 15, 13, 7, 2.0, wood[1])
			c.thick_line(10, 4, 16, 10, 3.0, metal[1])
		"armor":
			c.polygon(PackedVector2Array([Vector2(5, 4), Vector2(15, 4), Vector2(15, 11), Vector2(10, 17), Vector2(5, 11)]), metal[1])
			for y in range(5, 13, 2):
				for x in range(6, 15, 2):
					if c.is_solid(x, y):
						c.put(x, y, metal[0])
			c.polygon(PackedVector2Array([Vector2(6, 5), Vector2(10, 5), Vector2(10, 14), Vector2(6, 10)]), metal[2])
		"attack":
			c.thick_line(5, 15, 15, 5, 2.0, metal[2])
			c.thick_line(4, 12, 8, 16, 1.6, Color("#d8b25a"))
			c.rect(3, 15, 3, 3, wood[0])
		"arrow":
			c.line(4, 16, 15, 5, wood[1])
			c.polygon(PackedVector2Array([Vector2(16, 4), Vector2(12, 5), Vector2(15, 8)]), metal[2])
			c.line(4, 13, 6, 16, Color("#f0ece0"))
			c.line(3, 14, 5, 17, Color("#f0ece0"))
		"speed":
			c.polygon(PackedVector2Array([Vector2(6, 4), Vector2(11, 4), Vector2(11, 12), Vector2(16, 13), Vector2(16, 16), Vector2(6, 16)]), Color("#8a5a32"))
			c.line(2, 8, 5, 8, Color("#f0ece0"))
			c.line(1, 11, 5, 11, Color("#f0ece0"))
			c.line(2, 14, 5, 14, Color("#f0ece0"))
	c.outline(0.6)
	return {"canvas": c, "anchor": Vector2i(10, 10)}


static func rock() -> Dictionary:
	var c := PixelCanvas.new(8, 8)
	c.shaded_blob(4, 4, 3, 2.8, PixelCanvas.ramp(Color("#8f8a80"), 4, 0.5))
	c.outline(0.6)
	return {"canvas": c, "anchor": Vector2i(4, 4)}


## Debris pile covering an n x n footprint (destroyed buildings).
static func rubble(n: int, seed: int) -> Dictionary:
	var rng := _rng(seed)
	var w := n * 64 + 8
	var h := n * 32 + 24
	var c := PixelCanvas.new(w, h)
	var cx := w * 0.5
	var cy := h - n * 16 - 6
	var dirt := PixelCanvas.ramp(Color("#6b5a48"), 4, 0.4)
	for y in h:
		for x in w:
			var dx := absf(x + 0.5 - cx) / (n * 32.0)
			var dy := absf(y + 0.5 - cy) / (n * 16.0)
			if dx + dy <= 0.92:
				c.put(x, y, dirt[clampi(int((rng.randf() * 0.5 + 0.4) * 4), 0, 3)])
	var stone := PixelCanvas.ramp(Color("#8a857d"), 4, 0.5)
	var wood := PixelCanvas.ramp(Color("#4a3426"), 3, 0.4)
	for i in n * n * 10:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.8
		var px := cx + cos(a) * r * n * 30.0
		var py := cy + sin(a) * r * n * 14.0
		if rng.randf() < 0.65:
			c.shaded_blob(px, py - 2, rng.randf_range(2, 4), rng.randf_range(1.5, 3), stone)
		else:
			c.thick_line(px - 4, py, px + 4, py - rng.randf_range(-3, 3), 2.0, wood[rng.randi() % 3])
	c.outline(0.6)
	return {"canvas": c, "anchor": Vector2i(roundi(cx), roundi(cy))}


static func icon_wood() -> Dictionary:
	var c := PixelCanvas.new(18, 18)
	var bark := PixelCanvas.ramp(Color("#7a5230"), 4, 0.45)
	for i in 3:
		var y := 5 + i * 4 - (2 if i == 1 else 0)
		var x0 := 2 + (3 if i == 1 else 0)
		c.rect(x0, y, 11, 4, bark[1])
		c.rect(x0, y, 11, 1, bark[2])
		c.rect(x0, y + 3, 11, 1, bark[0])
		c.ellipse(x0 + 11.5, y + 2, 2, 2, Color("#d6b07a"))
		c.put(x0 + 11, y + 2, Color("#9c7444"))
	c.outline(0.65)
	return {"canvas": c, "anchor": Vector2i(9, 9)}


static func icon_food() -> Dictionary:
	var c := PixelCanvas.new(18, 18)
	var meat := PixelCanvas.ramp(Color("#c4553d"), 4, 0.5)
	c.shaded_blob(8, 9, 6, 5, meat)
	c.rect(12, 11, 4, 2, Color("#efe4cc"))
	c.ellipse(15.5, 11, 1.6, 1.6, Color("#fff6e2"))
	c.ellipse(15.5, 13, 1.6, 1.6, Color("#e2d6bc"))
	c.outline(0.65)
	return {"canvas": c, "anchor": Vector2i(9, 9)}


static func icon_ore(base: Color, seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(18, 18)
	var r := PixelCanvas.ramp(base, 4, 0.6)
	c.shaded_blob(7, 10, 5, 4.5, r, rng, 0.05)
	c.shaded_blob(12, 11, 4, 3.5, r, rng, 0.05)
	c.shaded_blob(9, 6.5, 3.5, 3, r, rng, 0.05)
	c.put(7, 8, Color.WHITE)
	c.outline(0.65)
	return {"canvas": c, "anchor": Vector2i(9, 9)}


static func icon_pop() -> Dictionary:
	var c := PixelCanvas.new(18, 18)
	var skin := PixelCanvas.ramp(Color("#e2ad80"), 3, 0.4)
	var cloth := PixelCanvas.ramp(Color("#c9b48a"), 3, 0.4)
	c.ellipse(9, 6, 3, 3, skin[1])
	c.put(8, 5, skin[2])
	c.ellipse(9, 14, 5, 4, cloth[1])
	c.rect(5, 15, 9, 3, cloth[1])
	c.put(6, 12, cloth[2])
	c.outline(0.65)
	return {"canvas": c, "anchor": Vector2i(9, 9)}


static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


## Semi-transparent dithered ground shadow drawn only on empty pixels.
static func _under_shadow(c: PixelCanvas, cx: float, cy: float, rx: float, ry: float) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d := dx * dx + dy * dy
			if d > 1.0 or c.get_px(x, y).a > 0.0:
				continue
			if d > 0.75 and PixelCanvas.bayer(x, y) > 0.5:
				continue
			c.put(x, y, SHADOW)


static func oak(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(72, 84)
	var bx := 36
	var by := 78
	var bark := PixelCanvas.ramp(Color("#6e4a2c"), 4, 0.4)
	var leaves := PixelCanvas.ramp(Color.from_hsv(rng.randf_range(0.24, 0.30), 0.62, 0.55), 6, 0.6)
	var trunk_top := by - rng.randi_range(22, 26)
	# Trunk with root flare.
	for y in range(trunk_top, by + 1):
		var t := float(y - trunk_top) / float(by - trunk_top)
		var half := 2.5 + pow(t, 4.0) * 3.0
		for x in range(floori(bx - half), ceili(bx + half)):
			var rel := (x + 0.5 - (bx - half)) / (half * 2.0)
			var idx := 3 if rel < 0.3 else (2 if rel < 0.6 else (1 if rel < 0.85 else 0))
			if (x + y * 3) % 7 == 0:
				idx = maxi(0, idx - 1)
			c.put(x, y, bark[idx])
	# Branches.
	c.thick_line(bx, trunk_top + 8, bx - 9, trunk_top - 2, 2.0, bark[1])
	c.thick_line(bx, trunk_top + 5, bx + 10, trunk_top - 4, 2.0, bark[0])
	# Canopy: back clusters (darker) then front clusters.
	var ccx := bx + rng.randf_range(-2.0, 2.0)
	var ccy := trunk_top - 13.0
	var back: Array[Color] = leaves.slice(0, 4)
	for i in 6:
		var a := rng.randf() * TAU
		c.shaded_blob(ccx + cos(a) * 17.0, ccy + sin(a) * 10.0 - 2.0, rng.randf_range(11, 14), rng.randf_range(9, 12), back, rng, 0.12)
	for i in 7:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 11.0)
		c.shaded_blob(ccx + cos(a) * d * 1.3, ccy + sin(a) * d * 0.8, rng.randf_range(10, 13), rng.randf_range(8, 11), leaves, rng, 0.16)
	_leaf_texture(c, rng, leaves)
	c.outline(0.6)
	_under_shadow(c, bx + 6, by - 1, 22, 6)
	return {"canvas": c, "anchor": Vector2i(bx, by)}


static func _leaf_texture(c: PixelCanvas, rng: RandomNumberGenerator, leaves: Array[Color]) -> void:
	# Small leaf clumps: a highlight pixel with a shadow pixel under it.
	for i in 140:
		var x := rng.randi_range(0, c.w - 1)
		var y := rng.randi_range(0, c.h - 1)
		var col := c.get_px(x, y)
		if col.a < 0.5 or col.g < col.r:
			continue
		var idx := leaves.find(col)
		if idx < 0:
			continue
		if c.get_px(x, y + 1).a > 0.5:
			c.put(x, y + 1, leaves[maxi(0, idx - 1)])
		c.put(x, y, leaves[mini(leaves.size() - 1, idx + 1)])


static func pine(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(52, 92)
	var bx := 26
	var by := 86
	var bark := PixelCanvas.ramp(Color("#5e3f27"), 3, 0.4)
	var needles := PixelCanvas.ramp(Color.from_hsv(rng.randf_range(0.36, 0.42), 0.6, 0.42), 5, 0.6)
	for y in range(by - 14, by + 1):
		c.put(bx - 2, y, bark[2])
		c.put(bx - 1, y, bark[1])
		c.put(bx, y, bark[1])
		c.put(bx + 1, y, bark[0])
	var layers := 5
	var top := by - rng.randi_range(76, 80)
	var bottom := by - 10
	for li in layers:
		var t := float(li) / float(layers - 1)
		var ly := lerpf(top + 10, bottom, t)
		var half := lerpf(7.0, 21.0, t) + rng.randf_range(-1.0, 1.0)
		var peak := ly - lerpf(14.0, 20.0, t)
		if li == 0:
			peak = top
		var pts := PackedVector2Array()
		pts.append(Vector2(bx + 0.5, peak))
		var teeth := 6
		for k in teeth + 1:
			var kx := lerpf(bx + half, bx - half, float(k) / teeth)
			var ky := ly + (2.5 if k % 2 == 0 else -0.5) - absf(kx - bx) * 0.12
			pts.append(Vector2(kx, ky))
		var tmp := PixelCanvas.new(c.w, c.h)
		tmp.polygon(pts, Color.WHITE)
		for y in c.h:
			for x in c.w:
				if not tmp.is_solid(x, y):
					continue
				var rel := (x + 0.5 - bx) / half
				var vert := clampf((y - peak) / maxf(1.0, ly - peak), 0.0, 1.0)
				var shade := 0.62 - rel * 0.34 - vert * 0.28 + (PixelCanvas.bayer(x, y) - 0.5) * 0.22 + rng.randf_range(-0.07, 0.07)
				c.put(x, y, needles[clampi(int(shade * needles.size()), 0, needles.size() - 1)])
	c.outline(0.6)
	_under_shadow(c, bx + 6, by - 1, 18, 5)
	return {"canvas": c, "anchor": Vector2i(bx, by)}


static func deposit(seed: int, gold: bool) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(56, 44)
	var bx := 28
	var by := 36
	var rock := PixelCanvas.ramp(Color("#7a6e60") if gold else Color("#7d848c"), 5, 0.45)
	var rocks := [Vector3(-8, -6, 9), Vector3(7, -7, 10), Vector3(0, -13, 9), Vector3(-13, -2, 6), Vector3(13, -2, 6), Vector3(2, -2, 8)]
	rocks.shuffle()
	rocks.sort_custom(func(a, b): return a.y < b.y)
	for r in rocks:
		var rr: float = r.z * rng.randf_range(0.85, 1.1)
		c.shaded_blob(bx + r.x, by + r.y, rr, rr * 0.82, rock, rng, 0.1)
	# Facet lines for a chiselled look.
	for i in 10:
		var x := rng.randi_range(8, 48)
		var y := rng.randi_range(14, 36)
		if c.is_solid(x, y) and c.is_solid(x + 2, y + 1):
			c.line(x, y, x + rng.randi_range(1, 3), y + rng.randi_range(1, 2), rock[0])
	if gold:
		var g := PixelCanvas.ramp(Color("#e3b02a"), 4, 0.6)
		for i in 16:
			var x := rng.randi_range(8, 48)
			var y := rng.randi_range(12, 36)
			if not c.is_solid(x, y):
				continue
			c.put(x, y, g[1])
			c.put(x + 1, y, g[2])
			c.put(x, y - 1, g[3])
			c.put(x + 1, y + 1, g[0])
	else:
		var hi := Color("#b3bac1")
		for i in 14:
			var x := rng.randi_range(8, 48)
			var y := rng.randi_range(12, 36)
			if c.is_solid(x, y) and c.is_solid(x + 1, y):
				c.put(x, y, hi)
				c.put(x + 1, y, rock[3])
	c.outline(0.62)
	_under_shadow(c, bx + 4, by + 1, 24, 6)
	return {"canvas": c, "anchor": Vector2i(bx, by - 2)}


static func berry_bush(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(44, 38)
	var bx := 22
	var by := 32
	var leaves := PixelCanvas.ramp(Color("#3f7a35"), 5, 0.55)
	for p in [Vector3(-8, -8, 9), Vector3(8, -8, 9), Vector3(0, -14, 9), Vector3(0, -6, 10)]:
		c.shaded_blob(bx + p.x, by + p.y, p.z, p.z * 0.85, leaves, rng, 0.14)
	_leaf_texture(c, rng, leaves)
	var berry := PixelCanvas.ramp(Color("#c52f4b"), 3, 0.6)
	for i in 22:
		var x := rng.randi_range(6, 38)
		var y := rng.randi_range(8, 30)
		if not c.is_solid(x, y) or not c.is_solid(x + 1, y + 1):
			continue
		c.put(x, y, berry[1])
		c.put(x + 1, y, berry[0])
		c.put(x, y + 1, berry[0])
		if rng.randf() < 0.5:
			c.put(x, y - 1, berry[2])
		else:
			c.put(x, y, berry[2])
	c.outline(0.6)
	_under_shadow(c, bx + 4, by, 18, 5)
	return {"canvas": c, "anchor": Vector2i(bx, by - 2)}


static func stump(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(24, 18)
	var bark := PixelCanvas.ramp(Color("#6e4a2c"), 4, 0.4)
	c.rect(8, 7, 8, 6, bark[1])
	c.rect(8, 7, 2, 6, bark[2])
	c.rect(14, 7, 2, 6, bark[0])
	c.ellipse(12, 7, 4, 2, Color("#c9a26b"))
	c.put(12, 7, Color("#8c6a3f"))
	c.outline(0.6)
	_under_shadow(c, 14, 13, 9, 3)
	rng.randi()
	return {"canvas": c, "anchor": Vector2i(12, 13)}


static func tuft(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(16, 12)
	var g := PixelCanvas.ramp(Color("#6aa23e"), 4, 0.5)
	for i in 7:
		var x := 3 + rng.randi_range(0, 9)
		var hh := rng.randi_range(4, 8)
		for k in hh:
			var lean := int(round((x - 8) * 0.12 * k))
			c.put(x + lean, 10 - k, g[clampi(1 + k * 2 / hh, 0, 3)])
	return {"canvas": c, "anchor": Vector2i(8, 10)}


static func flower_patch(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(16, 12)
	var cols := [Color("#f4f1e4"), Color("#f3d24a"), Color("#c98ee0"), Color("#ea6f6b")]
	for i in 4:
		var x := rng.randi_range(2, 13)
		var y := rng.randi_range(4, 9)
		var col: Color = cols[rng.randi() % cols.size()]
		c.put(x, y + 1, Color("#4f7f2b"))
		c.put(x, y + 2, Color("#4f7f2b"))
		c.put(x - 1, y, col)
		c.put(x + 1, y, col)
		c.put(x, y - 1, col)
		c.put(x, y, Color("#f9e9a1"))
	return {"canvas": c, "anchor": Vector2i(8, 10)}


## A small bed of one kind of flower: `petal` around a `heart` pixel.
static func flower_bed(seed: int, petal: Color, heart: Color) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(20, 14)
	for i in rng.randi_range(5, 7):
		var x := rng.randi_range(3, 16)
		var y := rng.randi_range(3, 10)
		c.put(x, y + 1, Color("#4f7f2b"))
		c.put(x, y + 2, Color("#47742a"))
		c.put(x - 1, y, petal)
		c.put(x + 1, y, petal)
		c.put(x, y - 1, petal)
		c.put(x, y, heart)
	return {"canvas": c, "anchor": Vector2i(10, 11)}


## A low dark-green leafy patch.
static func clover(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(18, 10)
	var leaves := [Color("#4c8232"), Color("#559038"), Color("#649f40")]
	for i in 26:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf())
		c.put(9 + int(round(cos(a) * d * 7.0)), 5 + int(round(sin(a) * d * 3.5)), leaves[rng.randi() % leaves.size()])
	return {"canvas": c, "anchor": Vector2i(9, 5)}


## One half-buried stone with a touch of moss.
static func field_stone(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(18, 13)
	var r := PixelCanvas.ramp(Color("#98938a"), 4, 0.5)
	c.shaded_blob(9, 7, rng.randf_range(4.5, 6.0), rng.randf_range(3.0, 4.0), r)
	c.put(7, 4, Color("#6d8a3d"))
	c.put(8, 4, Color("#6d8a3d"))
	c.outline(0.55)
	_under_shadow(c, 10, 10, 7, 2)
	return {"canvas": c, "anchor": Vector2i(9, 9)}


## A couple of fallen sticks.
static func twigs(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(18, 9)
	for i in 3:
		var x := rng.randi_range(2, 7)
		var y := rng.randi_range(2, 6)
		var dy := rng.randi_range(-1, 1)
		for k in rng.randi_range(6, 9):
			c.put(x + k, y + (dy if k > 3 else 0), Color("#6e5234") if k % 3 != 0 else Color("#8a6a45"))
	return {"canvas": c, "anchor": Vector2i(9, 5)}


static func pebbles(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(16, 10)
	var r := PixelCanvas.ramp(Color("#9a958c"), 4, 0.5)
	for i in rng.randi_range(2, 3):
		c.shaded_blob(rng.randf_range(4, 12), rng.randf_range(5, 7), rng.randf_range(2, 3.5), rng.randf_range(1.5, 2.5), r)
	c.outline(0.55)
	return {"canvas": c, "anchor": Vector2i(8, 7)}


static func shrub(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(26, 20)
	var g := PixelCanvas.ramp(Color("#4f8a3a"), 5, 0.55)
	c.shaded_blob(9, 12, 6, 5, g, rng, 0.12)
	c.shaded_blob(16, 11, 7, 6, g, rng, 0.12)
	c.shaded_blob(12, 8, 5, 4, g, rng, 0.12)
	_leaf_texture(c, rng, g)
	c.outline(0.6)
	_under_shadow(c, 15, 16, 10, 3)
	return {"canvas": c, "anchor": Vector2i(13, 16)}


static func mushrooms(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(14, 12)
	for i in 3:
		var x := rng.randi_range(3, 10)
		var y := rng.randi_range(6, 9)
		c.put(x, y, Color("#efe6cf"))
		c.put(x, y - 1, Color("#efe6cf"))
		c.put(x - 1, y - 2, Color("#b8402e"))
		c.put(x, y - 2, Color("#d4553d"))
		c.put(x + 1, y - 2, Color("#9a3324"))
		c.put(x, y - 3, Color("#e37a5f"))
	c.outline(0.55)
	return {"canvas": c, "anchor": Vector2i(7, 9)}


## Fish shoal: ripple rings on the water with dark fish backs and a glint.
## Plain brown or pale mushrooms: `cap` with a lighter `top` pixel.
static func toadstools(seed: int, cap: Color, top: Color) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(14, 12)
	for i in rng.randi_range(2, 3):
		var x := rng.randi_range(3, 10)
		var y := rng.randi_range(6, 9)
		c.put(x, y, Color("#efe6cf"))
		c.put(x, y - 1, Color("#efe6cf"))
		c.put(x - 1, y - 2, cap.darkened(0.15))
		c.put(x, y - 2, cap)
		c.put(x + 1, y - 2, cap.darkened(0.3))
		c.put(x, y - 3, top)
	c.outline(0.55)
	return {"canvas": c, "anchor": Vector2i(7, 9)}


static func fish_shoal(seed: int) -> Dictionary:
	var rng := _rng(seed)
	var c := PixelCanvas.new(44, 24)
	var ripple := Color(0.85, 0.95, 1.0, 0.55)
	for k in 2:
		var rx := 15.0 + k * 5.0
		var ry := 6.0 + k * 2.5
		for a in 48:
			var t := TAU * a / 48.0
			if (a + k * 3) % 4 != 0:
				c.put(roundi(22 + cos(t) * rx), roundi(13 + sin(t) * ry), ripple)
	var back := PixelCanvas.ramp(Color("#4a6a80"), 3, 0.5)
	for i in 4:
		var fx := 12.0 + rng.randf_range(0, 20)
		var fy := 10.0 + rng.randf_range(0, 6)
		var d := 1.0 if rng.randf() < 0.5 else -1.0
		c.ellipse(fx, fy, 3.2, 1.3, back[1])
		c.put(roundi(fx - d * 3.5), roundi(fy - 1), back[0])
		c.put(roundi(fx - d * 3.5), roundi(fy + 1), back[0])
		c.put(roundi(fx + d * 1.5), roundi(fy - 1), back[2])
	c.put(30, 8, Color.WHITE)
	return {"canvas": c, "anchor": Vector2i(22, 16)}


static func shadow(width: int, height: int) -> Dictionary:
	var c := PixelCanvas.new(width, height)
	var col := Color(0.03, 0.05, 0.10, 0.34)
	for y in height:
		for x in width:
			var dx := (x + 0.5 - width * 0.5) / (width * 0.5)
			var dy := (y + 0.5 - height * 0.5) / (height * 0.5)
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			if d > 0.7 and PixelCanvas.bayer(x, y) > 0.5:
				continue
			c.put(x, y, col)
	return {"canvas": c, "anchor": Vector2i(width / 2, height / 2)}


static func ring(width: int, height: int) -> Dictionary:
	var c := PixelCanvas.new(width, height)
	var cx := width * 0.5
	var cy := height * 0.5
	for y in height:
		for x in width:
			var dx := (x + 0.5 - cx) / (cx)
			var dy := (y + 0.5 - cy) / (cy)
			var d := sqrt(dx * dx + dy * dy)
			var dx2 := (x + 0.5 - cx) / (cx - 1.6)
			var dy2 := (y + 0.5 - cy) / (cy - 1.6)
			var d2 := sqrt(dx2 * dx2 + dy2 * dy2)
			if d <= 1.0 and d2 > 1.0:
				c.put(x, y, Color.WHITE)
	return {"canvas": c, "anchor": Vector2i(width / 2, height / 2)}

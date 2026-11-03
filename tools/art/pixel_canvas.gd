extends RefCounted
## Image wrapper with pixel-art drawing primitives used by the art generator.
## Example:
##   var c := PixelCanvas.new(48, 48)
##   c.ellipse(24, 30, 6, 4, Color.RED); c.outline(); c.img.save_png(path)

const BAYER4: Array[float] = [
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0,
]

var img: Image
var w: int
var h: int


func _init(width: int, height: int) -> void:
	w = width
	h = height
	img = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)


static func bayer(x: int, y: int) -> float:
	return (BAYER4[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0


## Colour ramp from dark to light with hue shifting (shadows lean blue,
## highlights lean yellow), the classic pixel-art palette technique.
static func ramp(base: Color, steps: int, spread: float = 0.55) -> Array[Color]:
	var out: Array[Color] = []
	for i in steps:
		var t := (float(i) / float(steps - 1) - 0.5) if steps > 1 else 0.0
		var hh := base.h
		var ss := base.s
		var vv := base.v
		if t < 0.0:
			hh = _hue_toward(hh, 0.66, -t * 0.16)
			ss = clampf(ss + (-t) * 0.18, 0.0, 1.0)
			vv = clampf(vv * (1.0 + t * spread * 1.5), 0.0, 1.0)
		else:
			hh = _hue_toward(hh, 0.14, t * 0.10)
			ss = clampf(ss - t * 0.22, 0.0, 1.0)
			vv = clampf(vv + (1.0 - vv) * t * spread * 1.6 + t * 0.08, 0.0, 1.0)
		out.append(Color.from_hsv(hh, ss, vv, base.a))
	return out


static func _hue_toward(h: float, target: float, amount: float) -> float:
	var d := wrapf(target - h, -0.5, 0.5)
	return wrapf(h + d * clampf(amount, 0.0, 1.0), 0.0, 1.0)


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func put(x: int, y: int, c: Color) -> void:
	if not inside(x, y):
		return
	if c.a >= 0.999:
		img.set_pixel(x, y, c)
	elif c.a > 0.0:
		img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


## Writes with wrap-around (for seamless tiling textures).
func put_wrap(x: int, y: int, c: Color) -> void:
	put(posmod(x, w), posmod(y, h), c)


func get_px(x: int, y: int) -> Color:
	if not inside(x, y):
		return Color(0, 0, 0, 0)
	return img.get_pixel(x, y)


func is_solid(x: int, y: int) -> bool:
	return get_px(x, y).a > 0.5


func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
	for yy in range(y, y + rh):
		for xx in range(x, x + rw):
			put(xx, yy, c)


func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				put(x, y, c)


func line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		put(x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


## Thick line made of small discs.
func thick_line(x0: float, y0: float, x1: float, y1: float, width: float, c: Color) -> void:
	var steps := maxi(1, ceili(Vector2(x1 - x0, y1 - y0).length() * 2.0))
	for i in steps + 1:
		var t := float(i) / steps
		ellipse(lerpf(x0, x1, t), lerpf(y0, y1, t), width * 0.5, width * 0.5, c)


## Polygon fill (even-odd scanline).
func polygon(points: PackedVector2Array, c: Color) -> void:
	var miny := INF
	var maxy := -INF
	for p in points:
		miny = minf(miny, p.y)
		maxy = maxf(maxy, p.y)
	for y in range(floori(miny), ceili(maxy) + 1):
		var sy := y + 0.5
		var xs: Array[float] = []
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for x in range(roundi(xs[k]), roundi(xs[k + 1])):
				put(x, y, c)


## Sphere-lit blob: picks ramp shades by a top-left light and dithers between them.
## `ramp` must be dark -> light. `rng` adds texture noise (0 = smooth).
func shaded_blob(cx: float, cy: float, rx: float, ry: float, ramp_colors: Array[Color],
		rng: RandomNumberGenerator = null, noise: float = 0.0, light: Vector3 = Vector3(-0.55, -0.65, 0.55)) -> void:
	var l := light.normalized()
	var n := ramp_colors.size()
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				continue
			var nz := sqrt(1.0 - d2)
			var shade := clampf(Vector3(dx, dy, nz).dot(l) * 0.5 + 0.5, 0.0, 1.0)
			if rng != null and noise > 0.0:
				shade += rng.randf_range(-noise, noise)
			shade += (bayer(x, y) - 0.5) * 0.18
			put(x, y, ramp_colors[clampi(int(shade * n), 0, n - 1)])


## Darkened-neighbour outline ("selective outline"): transparent pixels that touch
## an opaque pixel become a dark version of that pixel.
func outline(darkness: float = 0.62, min_alpha: float = 1.0) -> void:
	var src := img.duplicate() as Image
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.5:
				continue
			var best := Color(0, 0, 0, 0)
			for o in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var xx: int = x + o.x
				var yy: int = y + o.y
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				var c := src.get_pixel(xx, yy)
				if c.a > 0.5:
					best = c
					break
			if best.a > 0.0:
				var d := Color.from_hsv(_hue_toward(best.h, 0.7, 0.3), clampf(best.s + 0.15, 0, 1), best.v * (1.0 - darkness))
				d.a = min_alpha
				img.set_pixel(x, y, d)


## Copies `other` onto this canvas at (ox, oy) with alpha blending.
func blit(other, ox: int, oy: int, flip_h: bool = false) -> void:
	for y in other.h:
		for x in other.w:
			var c: Color = other.img.get_pixel(other.w - 1 - x if flip_h else x, y)
			if c.a > 0.0:
				put(ox + x, oy + y, c)

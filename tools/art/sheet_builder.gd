extends RefCounted
## Assembles unit sprite sheets from a frame painter.
## Sheet layout (shared with SpriteLibrary via render_sprites.json):
##   row = animation_index * DIRECTIONS + direction (0=S .. 4=E .. 8=N, 22.5 degree steps)
##   col = frame. West-facing directions are drawn by flipping at runtime.
## A "die" animation is derived generically: the first idle frame topples
## around the feet, sinks and leaves a dark stain - or, with layout
## "die_style": "sink" (ships), tilts and slips below the waterline.
## Every frame gets a light pass (top-left rim highlight, bottom-right core
## shadow) before the selective outline, so all painters share one lighting look.

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")

## Painted directions from S (0 degrees) to N (180 degrees); must match
## render_sprites.json "directions" and Iso.DIR_COUNT / 2 + 1.
const DIRECTIONS := 9


## Facing angle of a painted direction row: 0 = towards the camera (S),
## PI/2 = screen east, PI = away (N).
static func dir_angle(dir: int) -> float:
	return PI * float(dir) / float(DIRECTIONS - 1)


## Samples keyframe values (evenly spaced over the cycle) at frame/frames with
## linear interpolation, so painters can raise frame counts without new keys.
static func sample(keys: Array, frame: int, frames: int, cyclic: bool = true) -> float:
	var n := keys.size()
	if n == 1:
		return float(keys[0])
	var t: float
	if cyclic:
		t = float(frame) / float(maxi(frames, 1)) * n
	else:
		t = float(frame) / float(maxi(frames - 1, 1)) * (n - 1)
	var i := floori(t)
	var f := t - i
	var a := float(keys[posmod(i, n)])
	var b := float(keys[posmod(i + 1, n)] if cyclic else keys[mini(i + 1, n - 1)])
	return lerpf(a, b, f)


## painter: Callable(c: PixelCanvas, params: Dictionary, dir: int, anim: String,
##                   frame: int, frames: int, feet: Vector2i) -> void
static func build(layout: Dictionary, params: Dictionary, painter: Callable) -> Image:
	var fs: Array = layout["frame_size"]
	var fw: int = fs[0]
	var fh: int = fs[1]
	var anims: Dictionary = layout["animations"]
	var max_frames := 1
	for a in anims:
		max_frames = maxi(max_frames, int(anims[a]["frames"]))
	var sheet := Image.create_empty(fw * max_frames, fh * anims.size() * DIRECTIONS, false, Image.FORMAT_RGBA8)
	var feet := Vector2i(layout["anchor"][0], layout["anchor"][1])
	var idle_frames := int(anims.get("idle", {"frames": 4})["frames"])
	var ai := 0
	for a in anims:
		var n: int = anims[a]["frames"]
		for d in DIRECTIONS:
			for f in n:
				var c := PixelCanvas.new(fw, fh)
				if String(a) == "die":
					var src := PixelCanvas.new(fw, fh)
					painter.call(src, params, d, "idle", 0, idle_frames, feet)
					light_pass(src)
					if layout.get("die_style", "topple") == "sink":
						_sink(c, src, f, n, feet)
					elif layout.get("die_style", "topple") == "crash":
						_crash(c, src, f, n, feet)
					else:
						_topple(c, src, f, n, feet, d)
				else:
					painter.call(c, params, d, String(a), f, n, feet)
					light_pass(c)
				c.outline(0.66)
				sheet.blit_rect(c.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, (ai * DIRECTIONS + d) * fh))
		ai += 1
	return sheet


## Rim light from the top-left and a soft core shadow on the bottom-right edge
## of every opaque shape. Reads a snapshot so the pass does not feed itself.
static func light_pass(c: PixelCanvas, rim: float = 0.16, core: float = 0.14) -> void:
	var src := c.img.duplicate() as Image
	for y in c.h:
		for x in c.w:
			var col := src.get_pixel(x, y)
			if col.a < 0.5:
				continue
			var open_tl := _clear(src, x - 1, y) or _clear(src, x, y - 1)
			var open_br := _clear(src, x + 1, y) or _clear(src, x, y + 1)
			if open_tl and not open_br:
				c.img.set_pixel(x, y, col.lerp(Color(1.0, 0.96, 0.85, col.a), rim))
			elif open_br and not open_tl:
				c.img.set_pixel(x, y, col.lerp(Color(0.10, 0.10, 0.22, col.a), core))


static func _clear(img: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return true
	return img.get_pixel(x, y).a < 0.5


## Ship death: list to one side, settle lower each frame and clip everything
## below the waterline (feet row), with bubbles where the hull went down.
static func _sink(dst: PixelCanvas, src: PixelCanvas, frame: int, frames: int, feet: Vector2i) -> void:
	var t := float(frame) / float(maxi(frames - 1, 1))
	var ang := t * deg_to_rad(28.0)
	var drop := t * t * float(feet.y) * 0.9
	var pivot := Vector2(feet)
	var cs := cos(-ang)
	var sn := sin(-ang)
	var water := feet.y + 2
	for y in dst.h:
		if y > water:
			continue
		for x in dst.w:
			var p := Vector2(x + 0.5, y + 0.5 - drop) - pivot
			var q := Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs) + pivot
			var col := src.get_px(int(floor(q.x)), int(floor(q.y)))
			if col.a > 0.5:
				dst.put(x, y, col.darkened(t * 0.3))
	var foam := Color(0.88, 0.95, 1.0, 0.8 * (1.0 - t * 0.6))
	for k in 6:
		var bx := feet.x - 12 + k * 5 + (frame * 3 + k * 7) % 4
		dst.put(bx, water - (frame + k) % 3, foam)


## Aircraft death: spins, blackens and trails smoke; the game drops the sprite
## to the ground meanwhile, and the last frames are a burning wreck.
static func _crash(dst: PixelCanvas, src: PixelCanvas, frame: int, frames: int, feet: Vector2i) -> void:
	var t := float(frame) / float(maxi(frames - 1, 1))
	var ang := t * TAU * 1.25
	var pivot := Vector2(feet)
	var cs := cos(-ang)
	var sn := sin(-ang)
	var squash := 1.0 if t < 0.8 else 1.0 - (t - 0.8) * 3.0
	for y in dst.h:
		for x in dst.w:
			var p := Vector2(x + 0.5, y + 0.5) - pivot
			p.y /= maxf(0.25, squash)
			var q := Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs) + pivot
			var col := src.get_px(int(floor(q.x)), int(floor(q.y)))
			if col.a > 0.5:
				dst.put(x, y, col.darkened(0.2 + t * 0.5))
	for k in 4:
		var sx := feet.x - 4 + k * 3
		var sy := feet.y - 6 - k * 4 - int(t * 6)
		dst.ellipse(sx, sy, 2.0 + k * 0.6, 1.6 + k * 0.5, Color(0.25, 0.25, 0.27, 0.65 - k * 0.12))
	if t > 0.5:
		dst.ellipse(feet.x, feet.y - 2, 3.0, 2.0, Color("#f08a2a"))
		dst.put(feet.x, feet.y - 4, Color("#ffd35a"))


static func _topple(dst: PixelCanvas, src: PixelCanvas, frame: int, frames: int, feet: Vector2i, dir: int) -> void:
	var lin := float(frame) / float(maxi(frames - 1, 1))
	# Ease in (gravity) and settle with a tiny bounce at the end.
	var t := clampf(lin * lin * 1.15, 0.0, 1.0)
	if lin > 0.85:
		t = 1.0 - sin((lin - 0.85) / 0.15 * PI) * 0.05
	var ang := t * deg_to_rad(84.0) * (-1.0 if dir <= DIRECTIONS / 2 else 1.0)
	var sink := t * 3.0
	var pivot := Vector2(feet) + Vector2(0, -1)
	var cs := cos(-ang)
	var sn := sin(-ang)
	if lin > 0.5:
		var st := (lin - 0.5) / 0.5
		dst.ellipse(feet.x + (-8.0 if ang < 0 else 8.0) * st, feet.y - 1, 6.0 * st, 2.2 * st, Color(0.32, 0.05, 0.05, 0.55))
	for y in dst.h:
		for x in dst.w:
			var p := Vector2(x + 0.5, y + 0.5 - sink) - pivot
			var q := Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs) + pivot
			var col := src.get_px(int(floor(q.x)), int(floor(q.y)))
			if col.a > 0.5:
				dst.put(x, y, col.darkened(t * 0.25))

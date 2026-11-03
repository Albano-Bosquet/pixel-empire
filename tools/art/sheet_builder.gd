extends RefCounted
## Assembles unit sprite sheets from a frame painter.
## Sheet layout (shared with SpriteLibrary via render_sprites.json):
##   row = animation_index * DIRECTIONS + direction (0=S .. 4=E .. 8=N, 22.5 degree steps)
##   col = frame. West-facing directions are drawn by flipping at runtime.
## A "die" animation is derived generically: the first idle frame topples
## around the feet, sinks and leaves a dark stain - or, with layout
## "die_style": "sink" (ships), tilts and slips below the waterline; "crash"
## (aircraft) spins and burns; "wreck" (armoured vehicles) chars and smokes.
## Siege machines (painter "siege") collapse into a heap of timber instead of
## toppling like a person. Every style keeps each frame inside the frame rect.
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
					elif layout.get("die_style", "topple") == "wreck":
						_wreck(c, src, f, n, feet)
					elif params.get("painter", "") == "siege":
						_collapse(c, src, f, n, feet, d)
					else:
						_topple(c, src, f, n, feet, d, params.get("painter", "") in ["animal", "cavalry"])
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
	var squash := 1.0 if t < 0.8 else 1.0 - (t - 0.8) * 3.0
	squash = maxf(0.25, squash)
	# Spin around the airframe's own centre, which drifts down to the feet while
	# the wreck crumples; shrink further if a long hull would still overflow.
	var used := src.img.get_used_rect()
	var centre := Vector2(used.get_center()) if used.size != Vector2i.ZERO else Vector2(feet)
	var target := Vector2(feet) + Vector2(0, -4)
	var pivot := centre.lerp(target, t)
	var scale := lerpf(1.0, 0.7, t)
	var bb := _pose_bbox(src, centre, ang, squash, scale, pivot - centre)
	var room := Vector2(dst.w, dst.h) - Vector2(2.0 * FIT_MARGIN, 2.0 * FIT_MARGIN)
	var over := maxf((bb.size.x) / room.x, (bb.size.y) / room.y)
	if over > 1.0:
		scale /= over
		bb = _pose_bbox(src, centre, ang, squash, scale, pivot - centre)
	var shift := _fit_shift(bb, dst.w, dst.h)
	var cs := cos(-ang)
	var sn := sin(-ang)
	for y in dst.h:
		for x in dst.w:
			var p := Vector2(x + 0.5, y + 0.5) - shift - pivot
			p.y /= squash
			p /= scale
			var q := Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs) + centre
			var col := src.get_px(int(floor(q.x)), int(floor(q.y)))
			if col.a > 0.5:
				dst.put(x, y, col.darkened(0.2 + t * 0.5))
	var at := Vector2i((pivot + shift).round())
	for k in 4:
		var sx := at.x - 4 + k * 3
		var sy := at.y - 6 - k * 4 - int(t * 6)
		dst.ellipse(sx, sy, 2.0 + k * 0.6, 1.6 + k * 0.5, Color(0.25, 0.25, 0.27, 0.65 - k * 0.12))
	if t > 0.5:
		dst.ellipse(at.x, at.y - 2, 3.0, 2.0, Color("#f08a2a"))
		dst.put(at.x, at.y - 4, Color("#ffd35a"))


## Siege machine death: the frame cracks and slumps onto its axles (vertical
## squash with a slight list), the timber darkens and planks scatter around it
## in a puff of dust.
static func _collapse(dst: PixelCanvas, src: PixelCanvas, frame: int, frames: int, feet: Vector2i, dir: int) -> void:
	var lin := float(frame) / float(maxi(frames - 1, 1))
	var t := clampf(lin * lin * 1.3, 0.0, 1.0)
	var side := -1.0 if dir <= DIRECTIONS / 2 else 1.0
	var ang := t * deg_to_rad(9.0) * side
	var squash := lerpf(1.0, 0.5, t)
	var pivot := Vector2(feet) + Vector2(0, -1)
	var shift := _fit_shift(_pose_bbox(src, pivot, ang, squash, 1.0, Vector2.ZERO), dst.w, dst.h)
	# Frame 0 must match the idle pose, even where that pose already touches an edge.
	shift -= _fit_shift(_pose_bbox(src, pivot, 0.0, 1.0, 1.0, Vector2.ZERO), dst.w, dst.h) * (1.0 - t)
	var cs := cos(-ang)
	var sn := sin(-ang)
	for y in dst.h:
		for x in dst.w:
			var p := Vector2(x + 0.5, y + 0.5) - shift - pivot
			p.y /= squash
			var q := Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs) + pivot
			var col := src.get_px(int(floor(q.x)), int(floor(q.y)))
			if col.a > 0.5:
				dst.put(x, y, col.darkened(t * 0.35))
	# Loose planks thrown out to both sides, then lying on the ground.
	var plank := Color("#6e4a2a")
	var spread := float(dst.w) * 0.32
	for k in 6:
		var dx := (float(k) / 5.0 - 0.5) * 2.0 * spread * minf(1.0, lin * 1.6)
		var lift := sin(minf(1.0, lin * 1.6) * PI) * (5.0 + k % 3 * 2.0)
		var px := clampf(feet.x + dx + shift.x, 2.0, dst.w - 4.0)
		var py := clampf(feet.y - 2 - lift + (k % 2) * 2 + shift.y, 2.0, dst.h - 3.0)
		var tilt := 1 if (k + frame) % 2 == 0 else -1
		dst.line(int(px) - 2, int(py) - tilt, int(px) + 2, int(py) + tilt, plank.darkened(0.15 * (k % 3)))
	if lin < 0.6:
		var dust := 1.0 - lin / 0.6
		dst.ellipse(feet.x + shift.x, feet.y - 3 + shift.y, spread * 0.6 * (1.0 - dust * 0.5), 4.0, Color(0.78, 0.7, 0.56, 0.45 * dust))


## Armoured vehicle death: a jolt from the hit, then the hull chars black while
## flames lick out of it and a smoke column rises from the wreck.
static func _wreck(dst: PixelCanvas, src: PixelCanvas, frame: int, frames: int, feet: Vector2i) -> void:
	var t := float(frame) / float(maxi(frames - 1, 1))
	var jolt := 1 if frame == 1 else 0
	for y in dst.h:
		for x in dst.w:
			var col := src.get_px(x - jolt, y + jolt)
			if col.a > 0.5:
				var burnt := col.darkened(0.25 + t * 0.55)
				burnt.h = lerpf(burnt.h, 0.07, t * 0.5)
				dst.put(x, y, burnt)
	var top := feet.y - 14
	if t > 0.05 and t < 0.25:
		dst.ellipse(feet.x, top + 4, 8.0 * (1.0 - t * 2.0) + 3.0, 5.0, Color("#ffd35a"))
	var fire := 1.0 - absf(t - 0.55) * 1.4
	if fire > 0.0:
		for k in 3:
			var fx := feet.x - 6 + k * 6 + (frame + k) % 3 - 1
			dst.ellipse(fx, top + 2 - (frame + k * 2) % 3, 2.2 * fire + 0.8, 3.0 * fire + 1.0, Color("#f08a2a"))
			dst.put(fx, top - 1 - (frame + k) % 2, Color("#ffd35a"))
	for k in 4:
		var sx := feet.x - 2 + k * 2 + int(t * 4.0)
		var sy := top - 4 - k * 5 - int(t * 6.0)
		dst.ellipse(sx, sy, 2.4 + k * 0.8 * t + 0.5, 1.8 + k * 0.5, Color(0.2, 0.2, 0.22, (0.7 - k * 0.13) * minf(1.0, t * 3.0)))


## Margin (pixels) kept free around death poses for the outline pass.
const FIT_MARGIN := 2.0


## Bounding box of the opaque part of `src` rotated by `ang` around `pivot`,
## squashed vertically by `squash`, scaled by `scale` and moved by `move`.
static func _pose_bbox(src: PixelCanvas, pivot: Vector2, ang: float, squash: float, scale: float, move: Vector2) -> Rect2:
	var used := src.img.get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2(pivot, Vector2.ZERO)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for corner in [Vector2(used.position), Vector2(used.position.x + used.size.x, used.position.y),
			Vector2(used.end), Vector2(used.position.x, used.position.y + used.size.y)]:
		var r: Vector2 = (corner - pivot).rotated(ang) * scale
		var p := Vector2(r.x, r.y * squash) + pivot + move
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


## Smallest offset that moves `bb` inside a w x h frame (FIT_MARGIN kept free);
## a box wider than the frame is centred. Never pushes a pose downwards.
static func _fit_shift(bb: Rect2, w: int, h: int) -> Vector2:
	var out := Vector2.ZERO
	if bb.size.x > w - 2.0 * FIT_MARGIN:
		out.x = (w - (bb.position.x * 2.0 + bb.size.x)) * 0.5
	elif bb.position.x < FIT_MARGIN:
		out.x = FIT_MARGIN - bb.position.x
	elif bb.end.x > w - FIT_MARGIN:
		out.x = w - FIT_MARGIN - bb.end.x
	if bb.end.y > h - FIT_MARGIN:
		out.y = h - FIT_MARGIN - bb.end.y
	return out.round()


## Generic death: the idle pose falls over around the feet. Humanoids fall in
## the screen plane; quadrupeds roll onto their side, so a profile view
## flattens (squash) instead of rearing up, and only frontal views tip over.
static func _topple(dst: PixelCanvas, src: PixelCanvas, frame: int, frames: int, feet: Vector2i, dir: int, quadruped: bool) -> void:
	var lin := float(frame) / float(maxi(frames - 1, 1))
	# Ease in (gravity) and settle with a tiny bounce at the end.
	var t := clampf(lin * lin * 1.15, 0.0, 1.0)
	if lin > 0.85:
		t = 1.0 - sin((lin - 0.85) / 0.15 * PI) * 0.05
	var side := -1.0 if dir <= DIRECTIONS / 2 else 1.0
	var full_ang := deg_to_rad(84.0) * side
	var full_squash := 1.0
	if quadruped:
		var profile := absf(sin(dir_angle(dir)))
		full_ang *= 1.0 - profile
		full_squash = 1.0 - 0.55 * profile
	var ang := t * full_ang
	var squash := lerpf(1.0, full_squash, t)
	var sink := t * 3.0
	var pivot := Vector2(feet) + Vector2(0, -1)
	var cs := cos(-ang)
	var sn := sin(-ang)
	# A body lying flat is longer than the frame is wide: slide it back towards
	# the centre (and up off the bottom edge) as it falls so nothing is clipped.
	var shift := _fit_shift(_pose_bbox(src, pivot, ang, squash, 1.0, Vector2(0, sink)), dst.w, dst.h)
	# Frame 0 must match the idle pose, even where that pose already touches an edge.
	shift -= _fit_shift(_pose_bbox(src, pivot, 0.0, 1.0, 1.0, Vector2.ZERO), dst.w, dst.h) * (1.0 - t)
	if lin > 0.5:
		var st := (lin - 0.5) / 0.5
		dst.ellipse(feet.x + shift.x + (-8.0 if ang < 0 else 8.0) * st * 0.5, feet.y - 1 + minf(0.0, shift.y), 6.0 * st, 2.2 * st, Color(0.32, 0.05, 0.05, 0.55))
	for y in dst.h:
		for x in dst.w:
			var p := Vector2(x + 0.5 - shift.x, y + 0.5 - sink - shift.y) - pivot
			p.y /= squash
			var q := Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs) + pivot
			var col := src.get_px(int(floor(q.x)), int(floor(q.y)))
			if col.a > 0.5:
				dst.put(x, y, col.darkened(t * 0.25))

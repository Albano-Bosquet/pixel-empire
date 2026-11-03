extends RefCounted
## Procedural Gaia animals: one quadruped model (sheep, deer, boar, wolf,
## tiger, bear) shaped by parameters, plus a bird (turkey). Built along the
## facing axis in screen space like the horse in cavalry_art.gd, so every
## drawn direction comes from one model. No team colour: animal sheets are
## "neutral" (one sheet for all owners).
## params: species, coat, belly, dark (Colors), size (body scale), leg (leg
## length px), plus flags: wool, antlers, tusks, stripes, ears ("pointed" /
## "round"), tail ("short" / "bushy" / "long" / "stub"), mane.
## Animations: idle (grazing or breathing), walk (alternating gait), attack
## (lunge with open jaws / head butt); "die" is derived by SheetBuilder.

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")
const SheetBuilder := preload("res://tools/art/sheet_builder.gd")


static func build_sheet(layout: Dictionary, params: Dictionary) -> Image:
	if String(params.get("species", "")) == "turkey":
		return SheetBuilder.build(layout, params, paint_bird)
	return SheetBuilder.build(layout, params, paint)


static func paint(c: PixelCanvas, p: Dictionary, dir: int, anim: String, frame: int, frames: int, feet: Vector2i) -> void:
	var ang := SheetBuilder.dir_angle(dir)
	var a := Vector2(snappedf(sin(ang), 0.001), snappedf(cos(ang), 0.001) * 0.5)
	var an := a.normalized()
	var front := a.y * 2.0          # +1 facing camera, -1 away
	var side := absf(a.x)
	var t := float(frame) / float(maxi(frames, 1))
	var phase := TAU * t
	var s := float(p.get("size", 1.0))
	var leg_len := float(p.get("leg", 8.0))
	var walking := anim == "walk"
	var coat := PixelCanvas.ramp(Color(p["coat"]), 5, 0.5)
	var belly := Color(p.get("belly", p["coat"]))
	var dark := Color(p.get("dark", Color(p["coat"]).darkened(0.5)))
	var cx := float(feet.x)
	var ground := float(feet.y)
	var bob := sin(phase * 2.0) * 0.8 if walking else 0.0
	var lunge := 0.0
	if anim == "attack":
		lunge = SheetBuilder.sample([0.0, -1.5, -2.0, 4.0, 3.0, 0.5], frame, frames)
	var body_y := ground - leg_len - 3.0 * s + bob
	var half_len := lerpf(3.2, 7.5, side) * s
	var perp := Vector2(-an.y, an.x)
	var origin := Vector2(cx, body_y) + an * lunge

	# Legs: two pairs, alternating gait; far legs drawn first and darker.
	var legs := []
	for li in 2:
		for k in 2:
			var sgn := -1.0 if k == 0 else 1.0
			var along: float = [-half_len * 0.7, half_len * 0.65][li]
			var off := perp * sgn * lerpf(2.2, 0.9, side) * s
			var ph := phase * 2.0 + (0.0 if li == 0 else PI) + (0.0 if k == 0 else PI)
			var sw := sin(ph) * (2.5 * s if walking else 0.0)
			var lift := maxf(0.0, cos(ph)) * (1.5 if walking else 0.0)
			var top := origin + an * along + off + Vector2(0, 2.0 * s)
			var foot := Vector2(cx, ground - lift) + an * (along + sw * side + lunge * 0.5) + off
			var far: bool = (off.y < 0.0) if side > 0.5 else ((front > 0 and k == 1) or (front <= 0 and k == 0))
			legs.append({"top": top, "foot": foot, "far": far})
	for L in legs:
		if L["far"]:
			_leg(c, L["top"], L["foot"], coat[1], dark, s)

	# Head position: forward and raised; herbivores graze in idle.
	var grazing: bool = anim == "idle" and p.get("grazes", true) and t > 0.25 and t < 0.75
	var neck := origin + an * half_len * 0.95 + Vector2(0, -1.5 * s)
	var head := neck + an * lerpf(1.5, 4.5, side) * s + Vector2(0, -3.5 * s)
	if grazing:
		head = neck + an * lerpf(1.5, 4.0, side) * s + Vector2(0, leg_len * 0.75)
	if anim == "attack":
		head += an * maxf(0.0, lunge) * 0.6 + Vector2(0, -1.0 if lunge > 1.0 else 0.5)
	if anim == "idle" and not p.get("grazes", true):
		head += Vector2(0, sin(phase) * 0.6)
	var head_behind := front < -0.3

	# Tail.
	var tail_root := origin - an * half_len * 0.95 + Vector2(0, -1.0 * s)
	_tail(c, p, tail_root, an, phase, walking, coat, dark, s)
	if head_behind:
		_head(c, p, neck, head, an, side, front, coat, dark, anim, lunge, s)

	# Body: rump to chest blobs.
	var rump := origin - an * half_len * 0.7
	var chest := origin + an * half_len * 0.65
	var rx := 4.6 * s
	var ry := 4.2 * s
	if p.get("wool", false):
		rx *= 1.25
		ry *= 1.2
	c.shaded_blob(rump.x, rump.y, rx, ry, coat)
	for i in 3:
		var pc := rump.lerp(chest, (i + 1) / 4.0)
		c.shaded_blob(pc.x, pc.y, rx * 1.02, ry, coat)
	c.shaded_blob(chest.x, chest.y + 0.3, rx * 1.05, ry * 1.04, coat)
	# Belly band.
	for x in range(int(minf(rump.x, chest.x) - rx), int(maxf(rump.x, chest.x) + rx) + 1):
		var y := int(maxf(rump.y, chest.y) + ry * 0.75)
		if c.is_solid(x, y) and c.is_solid(x, y - 2):
			c.put(x, y, belly)
	if p.get("wool", false):
		# Fleece curls: lighter dots across the body.
		for i in 14:
			var q := rump.lerp(chest, fmod(i * 0.37, 1.0)) + Vector2(sin(i * 2.3) * rx * 0.6, cos(i * 1.7) * ry * 0.5 - 1.0)
			c.put(roundi(q.x), roundi(q.y), coat[4])
	if p.get("stripes", false):
		for i in 6:
			var q2 := rump.lerp(chest, (i + 0.5) / 6.0)
			for dy in range(-int(ry), int(ry * 0.4)):
				if c.is_solid(roundi(q2.x), roundi(q2.y + dy)) and (dy + i) % 3 != 0:
					c.put(roundi(q2.x + dy * 0.25), roundi(q2.y + dy), dark)
	if p.get("mane", false):
		for i in 4:
			var q3 := chest.lerp(neck, i / 4.0) + Vector2(0, -ry * 0.8)
			c.shaded_blob(q3.x, q3.y, 2.2 * s, 1.6 * s, PixelCanvas.ramp(dark, 3, 0.4))

	for L in legs:
		if not L["far"]:
			_leg(c, L["top"], L["foot"], coat[2], dark, s)
	if not head_behind:
		_head(c, p, neck, head, an, side, front, coat, dark, anim, lunge, s)


static func _leg(c: PixelCanvas, top: Vector2, foot: Vector2, col: Color, hoof: Color, s: float) -> void:
	var knee := (top + foot) * 0.5 + Vector2(0.4, 0)
	c.thick_line(top.x, top.y, knee.x, knee.y, 2.2 * maxf(s, 0.8), col)
	c.thick_line(knee.x, knee.y, foot.x, foot.y, 1.6 * maxf(s, 0.8), col)
	c.rect(roundi(foot.x - 1), roundi(foot.y - 1), 2, 1, hoof)


static func _tail(c: PixelCanvas, p: Dictionary, root: Vector2, an: Vector2, phase: float, walking: bool, coat: Array[Color], dark: Color, s: float) -> void:
	var wag := sin(phase * (4.0 if walking else 1.0)) * 1.0
	match String(p.get("tail", "short")):
		"bushy":
			var end := root - an * 5.0 * s + Vector2(wag, 3.0 * s)
			c.thick_line(root.x, root.y, end.x, end.y, 3.0 * s, coat[2])
			c.put(roundi(end.x), roundi(end.y), coat[4])
		"long":
			var mid := root - an * 4.0 * s + Vector2(wag, 2.0)
			var end2 := mid - an * 3.0 * s + Vector2(wag * 1.5, 4.0 * s)
			c.thick_line(root.x, root.y, mid.x, mid.y, 1.8, coat[2])
			c.thick_line(mid.x, mid.y, end2.x, end2.y, 1.6, dark)
		"stub":
			c.shaded_blob(root.x - an.x, root.y, 1.4 * s, 1.2 * s, coat)
		_:
			var end3 := root - an * 2.5 * s + Vector2(wag * 0.5, 2.5 * s)
			c.thick_line(root.x, root.y, end3.x, end3.y, 1.6, coat[1])


static func _head(c: PixelCanvas, p: Dictionary, neck: Vector2, head: Vector2, an: Vector2, side: float, front: float, coat: Array[Color], dark: Color, anim: String, lunge: float, s: float) -> void:
	var face := Color(p.get("face", coat[3]))
	c.thick_line(neck.x, neck.y, head.x, head.y + 1.0, 3.6 * s, coat[3])
	var hr := 2.6 * s * float(p.get("head", 1.0))
	c.shaded_blob(head.x, head.y, hr, hr * 0.92, PixelCanvas.ramp(face, 4, 0.45))
	var snout_len := float(p.get("snout", 2.5)) * s
	var snout := head + an * lerpf(0.6, 1.0, side) * snout_len + Vector2(0, 1.0 * s)
	c.thick_line(head.x, head.y + 0.5, snout.x, snout.y, 2.2 * s, face.lightened(0.05))
	c.put(roundi(snout.x), roundi(snout.y), Color("#1c1412"))
	if anim == "attack" and lunge > 2.0 and p.get("predator", false):
		# Open jaws.
		c.put(roundi(snout.x), roundi(snout.y + 1), Color("#8a1c1c"))
		c.put(roundi(snout.x - an.x), roundi(snout.y + 1), Color("#f0ece0"))
	if p.get("tusks", false) and side > 0.2:
		c.put(roundi(snout.x - an.x), roundi(snout.y + 1), Color("#f0ece0"))
		c.put(roundi(snout.x - an.x * 2.0), roundi(snout.y), Color("#f0ece0"))
	# Eye.
	if front > -0.3:
		c.put(roundi(head.x + an.x * 0.8), roundi(head.y - 0.6), Color("#120c0a"))
	# Ears.
	var ears := String(p.get("ears", "round"))
	for k in [-1.0, 1.0]:
		var e := head + Vector2(k * hr * 0.6 * (1.0 - side * 0.6), -hr * 0.9) - an * 0.5
		if ears == "pointed":
			c.polygon(PackedVector2Array([e + Vector2(-1.2, 1.0), e + Vector2(1.2, 1.0), e + Vector2(0.0, -2.2 * s)]), coat[2])
		elif ears == "floppy":
			c.thick_line(e.x, e.y + 1.0, e.x + k * 1.5, e.y + 2.5, 1.4, coat[1])
		else:
			c.put(roundi(e.x), roundi(e.y), coat[2])
	if p.get("antlers", false):
		for k2 in [-1.0, 1.0]:
			var base := head + Vector2(k2 * 1.0, -hr * 0.9)
			var tip := base + Vector2(k2 * 2.5, -5.0 * s)
			var antler := Color("#c9b38a")
			c.line(roundi(base.x), roundi(base.y), roundi(tip.x), roundi(tip.y), antler)
			c.line(roundi(lerpf(base.x, tip.x, 0.5)), roundi(lerpf(base.y, tip.y, 0.5)), roundi(lerpf(base.x, tip.x, 0.5) + k2 * 2.0), roundi(lerpf(base.y, tip.y, 0.5) - 1.0), antler)


## Turkey: round body, fanned tail, small head with a red wattle.
static func paint_bird(c: PixelCanvas, p: Dictionary, dir: int, anim: String, frame: int, frames: int, feet: Vector2i) -> void:
	var ang := SheetBuilder.dir_angle(dir)
	var a := Vector2(snappedf(sin(ang), 0.001), snappedf(cos(ang), 0.001) * 0.5)
	var an := a.normalized()
	var front := a.y * 2.0
	var side := absf(a.x)
	var t := float(frame) / float(maxi(frames, 1))
	var phase := TAU * t
	var coat := PixelCanvas.ramp(Color(p["coat"]), 5, 0.5)
	var cx := float(feet.x)
	var ground := float(feet.y)
	var walking := anim == "walk"
	var peck := anim == "idle" and t > 0.4 and t < 0.7
	var hop := absf(sin(phase * 2.0)) * 1.0 if walking else 0.0
	var body := Vector2(cx, ground - 7.0 - hop)
	# Legs.
	for k in [-1.0, 1.0]:
		var sw := sin(phase * 2.0 + (0.0 if k < 0 else PI)) * (2.0 if walking else 0.0)
		var top := body + Vector2(k * 1.5, 3.0)
		var foot := Vector2(cx + k * 1.5 + an.x * sw, ground)
		c.thick_line(top.x, top.y, foot.x, foot.y, 1.0, Color("#b0763a"))
	var fan_center := body - an * 3.0 + Vector2(0, -4.0)
	var fan := front < 0.3
	if fan:
		_fan(c, fan_center, coat, 1.0 if anim == "attack" else 0.8)
	c.shaded_blob(body.x, body.y, 4.6, 4.0, coat)
	var head := body + an * lerpf(2.0, 4.0, side) + Vector2(0, -6.0)
	if peck:
		head = body + an * 4.5 + Vector2(0, 1.0)
	c.thick_line(body.x + an.x * 2.0, body.y - 2.0, head.x, head.y + 1.0, 1.6, Color("#5a3d2e"))
	c.shaded_blob(head.x, head.y, 1.6, 1.6, PixelCanvas.ramp(Color("#c7b8a8"), 3, 0.4))
	c.put(roundi(head.x + an.x * 1.5), roundi(head.y + 0.5), Color("#e0a030"))
	c.put(roundi(head.x + an.x * 0.5), roundi(head.y + 1.5), Color("#c8282a"))
	c.put(roundi(head.x + an.x * 0.5), roundi(head.y + 2.5), Color("#c8282a"))
	if front > -0.3:
		c.put(roundi(head.x + an.x * 0.6), roundi(head.y - 0.5), Color("#120c0a"))
	if not fan:
		_fan(c, fan_center + Vector2(0, -1.0), coat, 0.7)


static func _fan(c: PixelCanvas, center: Vector2, coat: Array[Color], spread: float) -> void:
	for i in 7:
		var a := lerpf(-1.3, 1.3, i / 6.0) * spread
		var tip := center + Vector2(sin(a), -cos(a)) * 6.0
		c.thick_line(center.x, center.y, tip.x, tip.y, 2.0, coat[1] if i % 2 == 0 else coat[2])
		c.put(roundi(tip.x), roundi(tip.y), Color("#e8dcc0"))

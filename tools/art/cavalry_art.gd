extends RefCounted
## Procedural horse + rider painter (scout cavalry, knight).
## The horse is built along its facing axis in screen space, so all five drawn
## directions come from one model. params: coat (Color), tunic (team colour),
## skin, hair, "mail" (bool), "helmet", "caparison" (bool), "weapon" ("sword"/"bow"),
## "plume" (bool), "mount" ("horse" or "camel": long legs and neck, a hump under the saddle).

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")
const SheetBuilder := preload("res://tools/art/sheet_builder.gd")
const HumanoidArt := preload("res://tools/art/humanoid_art.gd")

## Sword swing keyframes (degrees), interpolated over the attack cycle.
const SWING := [100, 140, 150, 40, -25, 40]
## Mounted archer string pull per attack frame.
const BOW_PULL := [0.0, 1.5, 3.0, 4.0, 4.0, 0.0]


static func build_sheet(layout: Dictionary, params: Dictionary) -> Image:
	return SheetBuilder.build(layout, params, paint)


static func paint(c: PixelCanvas, p: Dictionary, dir: int, anim: String, frame: int, frames: int, feet: Vector2i) -> void:
	# Facing direction on the ground, in screen space (x, y foreshortened).
	var ang := SheetBuilder.dir_angle(dir)
	var a := Vector2(snappedf(sin(ang), 0.001), snappedf(cos(ang), 0.001) * 0.5)
	var t := float(frame) / float(maxi(frames, 1))
	var an := a.normalized()
	var front := -a.y * -2.0  # +1 facing camera, -1 away
	var side := absf(a.x)
	var phase := TAU * frame / float(maxi(frames, 1))
	var gallop := anim == "walk"
	var camel: bool = p.get("mount", "horse") == "camel"
	var leg_len := 21.0 if camel else 17.0
	var bob := (sin(phase * 2.0) * 1.0) if gallop else (0.5 if anim == "idle" and t >= 0.5 else 0.0)
	var coat := PixelCanvas.ramp(p["coat"], 5, 0.5)
	var mane := PixelCanvas.ramp(Color(p["coat"]).darkened(0.55), 3, 0.4)
	var team := PixelCanvas.ramp(p["tunic"], 4, 0.5)
	var cx := float(feet.x)
	var ground := float(feet.y)
	var body_y := ground - leg_len + bob
	var half_len := lerpf(4.5, 9.5, side) * (0.92 if camel else 1.0)  # body half-length on screen
	var perp := Vector2(-an.y, an.x)

	# --- Legs: rear pair and front pair, alternating gallop swing ---
	var leg_bases := [-half_len * 0.75, half_len * 0.7]
	var legs := []
	for li in 2:
		for k in 2:
			var sgn := -1.0 if k == 0 else 1.0
			var along: float = leg_bases[li]
			var off := perp * sgn * lerpf(3.0, 1.0, side)
			var ph := phase + (0.0 if li == 0 else PI) + (0.0 if k == 0 else 0.6)
			var sw := sin(ph) * (3.5 if gallop else 0.0)
			var lift := maxf(0.0, cos(ph)) * (2.0 if gallop else 0.0)
			var top := Vector2(cx, body_y + 3.0) + an * along + off
			var foot := Vector2(cx, ground - lift) + an * (along + sw * side) + off + Vector2(0, 0) + Vector2(sw * (1.0 - side) * 0.0, 0)
			legs.append({"top": top, "foot": foot, "far": (off.y < 0.0 if side > 0.5 else (front > 0 and k == 1) or (front <= 0 and k == 0))})
	for L in legs:
		if L["far"]:
			_leg(c, L["top"], L["foot"], coat[1])

	# Head and neck position (in front along the axis, raised).
	var neck_base := Vector2(cx, body_y - 3.0) + an * half_len * 0.95
	var head := neck_base + an * lerpf(2.0, 7.0, side) * (1.3 if camel else 1.0) + Vector2(0, (-12.0 if camel else -8.0) + (1.0 if gallop and sin(phase * 2.0 + 0.8) > 0.0 else 0.0) + (0.6 if anim == "idle" and t >= 0.3 and t < 0.6 else 0.0))
	var head_behind := front < -0.3
	var head_front := front > 0.3
	if head_behind:
		_head(c, neck_base, head, an, side, coat, mane)

	# Tail.
	var tail_root := Vector2(cx, body_y - 2.0) - an * half_len * 0.95
	var tail_end := tail_root - an * 4.0 + Vector2(0, 7.0 + sin(phase) * 1.0)
	c.thick_line(tail_root.x, tail_root.y, tail_end.x, tail_end.y, 2.2, mane[1])

	# Body: a row of shaded blobs along the axis.
	# Rump, barrel and a deeper chest give the horse its silhouette.
	var rump := Vector2(cx, body_y - 0.5) - an * half_len * 0.75
	var chest := Vector2(cx, body_y + 0.5) + an * half_len * 0.7
	c.shaded_blob(rump.x, rump.y, 6.2, 5.8, coat)
	for i in 4:
		var pc := rump.lerp(chest, (i + 1) / 5.0) + Vector2(0, 1.0)
		c.shaded_blob(pc.x, pc.y, 5.8, 5.4, coat)
	c.shaded_blob(chest.x, chest.y, 6.4, 6.0, coat)
	# Saddle blanket (team colour, gold trim on knights) and saddle.
	var saddle := Vector2(cx, body_y - 5.0) - an * 1.0
	if camel:
		# Hump between rump and chest lifts the rider.
		var hump := rump.lerp(chest, 0.45) + Vector2(0, -6.0)
		c.shaded_blob(hump.x, hump.y, lerpf(4.5, 6.0, side), 5.2, coat)
		saddle = hump + Vector2(0, -3.5)
	if p.get("caparison", false):
		c.shaded_blob(saddle.x, saddle.y + 4.0, lerpf(4.5, 7.0, side), 4.2, team)
		for x in range(int(saddle.x - 7), int(saddle.x + 8)):
			var y := int(saddle.y + 8)
			if c.is_solid(x, y - 1) and x % 2 == 0:
				c.put(x, y - 1, Color("#e8d27a"))
	c.ellipse(saddle.x, saddle.y + 1.0, 3.5, 1.8, Color("#5b3b22"))

	for L in legs:
		if not L["far"]:
			_leg(c, L["top"], L["foot"], coat[2])
	if not head_behind and not head_front:
		_head(c, neck_base, head, an, side, coat, mane)

	# --- Rider ---
	_rider(c, p, saddle, a, side, front, anim, frame, frames)
	if head_front:
		_head(c, neck_base, head, an, side, coat, mane)


static func _leg(c: PixelCanvas, top: Vector2, foot: Vector2, col: Color) -> void:
	var knee := (top + foot) * 0.5 + Vector2(0.5, 0)
	c.thick_line(top.x, top.y, knee.x, knee.y, 2.4, col)
	c.thick_line(knee.x, knee.y, foot.x, foot.y, 1.8, col)
	c.rect(roundi(foot.x - 1), roundi(foot.y - 1), 2, 1, Color("#2b2320"))


static func _head(c: PixelCanvas, neck_base: Vector2, head: Vector2, an: Vector2, side: float, coat: Array[Color], mane: Array[Color]) -> void:
	c.thick_line(neck_base.x, neck_base.y, head.x, head.y + 1.0, 4.4 if (head - neck_base).length() < 11.0 else 3.4, coat[3])
	c.thick_line(neck_base.x - an.x * 1.5, neck_base.y - 2.0, head.x - an.x * 1.5, head.y - 1.0, 1.4, mane[1])
	var snout := head + an * lerpf(1.0, 4.0, side) + Vector2(0, 2.0)
	c.shaded_blob(head.x, head.y, 2.6, 2.4, coat)
	c.thick_line(head.x, head.y, snout.x, snout.y, 2.6, coat[3])
	c.put(roundi(snout.x), roundi(snout.y), Color("#2b2320"))
	c.put(roundi(head.x - an.x), roundi(head.y - 3.0), coat[1])
	if side > 0.4:
		c.put(roundi(head.x + an.x * 0.5), roundi(head.y - 0.5), Color("#1c1412"))


static func _rider(c: PixelCanvas, p: Dictionary, seat: Vector2, a: Vector2, side: float, front: float, anim: String, frame: int, frames: int) -> void:
	var team := PixelCanvas.ramp(p["tunic"], 4, 0.5)
	var mail := PixelCanvas.ramp(Color("#8f959c"), 4, 0.5)
	var skin := PixelCanvas.ramp(p["skin"], 4, 0.45)
	var has_mail: bool = p.get("mail", false)
	var torso_w := lerpf(8.0, 6.0, side)
	var top := seat.y - 11.0
	# Leg hanging over the flank.
	c.thick_line(seat.x + side * 1.0, seat.y, seat.x + side * 2.0 + (1.5 if side < 0.3 else 0.0), seat.y + 6.0, 2.4, mail[1] if has_mail else Color("#6e6250"))
	for y in range(int(top), int(seat.y)):
		for x in range(int(seat.x - torso_w * 0.5), int(seat.x + torso_w * 0.5)):
			var rel := (x - (seat.x - torso_w * 0.5)) / torso_w
			var idx := 3 if rel < 0.3 else (2 if rel < 0.7 else 1)
			var col: Color = team[idx]
			if has_mail and absf(x + 0.5 - seat.x) > 1.6:
				col = mail[idx]
			c.put(x, y, col)
	var hx := seat.x + side * 1.0
	var hy := top - 4.0
	c.shaded_blob(hx, hy, 4.0, 4.0, skin)
	var helm: String = p.get("helmet", "")
	for y in range(int(hy - 5), int(hy)):
		for x in range(int(hx - 5), int(hx + 5)):
			if c.is_solid(x, y) and Vector2(x + 0.5 - hx, y + 0.5 - hy).length() < 4.2:
				c.put(x, y, mail[2] if helm != "" else Color("#6b4426"))
	if HumanoidArt.HATS.has(helm):
		var hat := PixelCanvas.ramp(Color(HumanoidArt.HATS[helm]), 3, 0.5)
		c.rect(roundi(hx - 4), roundi(hy - 9), 8, 6, hat[1])
		c.rect(roundi(hx - 5), roundi(hy - 3), 10, 1, hat[0])
		c.put(roundi(hx), roundi(hy - 10), p["tunic"])
	elif helm == "great":
		c.rect(roundi(hx - 4), roundi(hy - 1), 8, 4, mail[1])
		if front > 0.0 or side > 0.5:
			c.rect(roundi(hx - 2 + side * 2.0), roundi(hy + 0.5), 3, 1, Color("#1c1412"))
		c.put(roundi(hx), roundi(hy - 5), team[3])
	elif front > 0.3:
		c.put(roundi(hx - 1.5 + side * 2.0), roundi(hy + 0.5), Color("#2b1d18"))
		c.put(roundi(hx + 1.0 + side * 1.5), roundi(hy + 0.5), Color("#2b1d18"))
	if p.get("plume", false):
		for i in 4:
			c.put(roundi(hx - 1.0 + i * 0.5 - side * i * 0.8), roundi(hy - 5.0 - (1 if i in [1, 2] else 0)), team[3] if i < 2 else team[2])
	# Weapon arm.
	var fwd := Vector2(a.x, a.y * 1.2)
	var weapon: String = p.get("weapon", "sword")
	var pull := -1.0
	var theta := deg_to_rad(SheetBuilder.sample(SWING, frame, frames)) if anim == "attack" else deg_to_rad(-60.0)
	if weapon == "bow":
		theta = 0.0
		pull = SheetBuilder.sample(BOW_PULL, frame, frames) if anim == "attack" else 0.0
	elif weapon == "carbine":
		weapon = "gun"
		theta = 0.0 if anim == "attack" else deg_to_rad(60.0)
		pull = SheetBuilder.sample(HumanoidArt.GUN_FLASH, frame, frames) if anim == "attack" else 0.0
	var shoulder := Vector2(seat.x + torso_w * 0.3 + side * 1.0, top + 2.0)
	var dv := fwd.normalized() * cos(theta) + Vector2(0, -1) * sin(theta) if fwd.length() > 0.01 else Vector2(0, -1)
	var hand := shoulder + dv * 6.0
	if front < -0.3:
		HumanoidArt._tool(c, hand, dv, weapon, pull)
	HumanoidArt._arm_to(c, shoulder, hand, mail[2] if has_mail else team[1], skin[2])
	if front >= -0.3:
		HumanoidArt._tool(c, hand, dv, weapon, pull)
	if p.get("shield", false):
		HumanoidArt._shield(c, Vector2(seat.x - torso_w * 0.5 - 0.5 + side * 1.5, top + 5.0), p["tunic"], side)

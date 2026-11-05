extends RefCounted
## Procedural humanoid painter (villagers and foot soldiers).
## params: skin, hair, tunic (team colour), pants, boots, belt (Colors) plus
## optional equipment: "mail" (bool), "helmet" ("", "kettle", "nasal"),
## "shield" (bool), "weapon" ("", "sword", "greatsword", "spear", "pike", "javelin",
## "bow", "crossbow", "gun", "axe", "petard" (powder keg), "staff");
## "robe" (Color: ankle-length habit with hood; the team colour becomes the sash).
## Gunpowder era: weapons "blunderbuss", "musket", "rifle" (aim + muzzle flash),
## "grenade" (overarm throw); helmets "tricorn", "shako", "cap" are cloth hats.
## Military age: weapons "assault_rifle", "machine_gun" (rapid flashes), "bazooka"
## (shoulder tube with backblast); helmet "steel" (olive dome with a brim).
## Animations: idle, walk, chop, mine, forage, build, farm (hoeing), carry_<res>, attack.
## "die" is derived by SheetBuilder.

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")
const SheetBuilder := preload("res://tools/art/sheet_builder.gd")

## Arm angle keyframes (degrees above the forward horizontal) for swings,
## evenly spaced over the cycle and interpolated (SheetBuilder.sample).
const SWING_KEYS := {
	"chop": [95, 130, 145, 60, -20, 25],
	"mine": [100, 140, 150, 50, -30, 30],
	"build": [70, 105, 40, -10, 35, 85],
	"sword": [100, 135, 150, 40, -25, 30],
	"greatsword": [110, 150, 165, 120, 20, -40, -20, 60],
	"axe": [95, 130, 145, 60, -20, 25],
}
## Hoeing a farm: the hoe rises past the head, chops down into the soil and is
## dragged back towards the feet (arm angle per keyframe; strike below -50).
const HOE_KEYS := [5, 40, 80, 105, 100, 55, -20, -58, -62, -55, -35, -10]
const SOIL := Color("#6b4a2c")
const SOIL_LIGHT := Color("#9a7448")
## Javelin throw: arm angle per frame (wind-up behind the head, release low).
const THROW := [70, 120, 150, 160, 90, 20, -10, 30]
## Crossbow recoil and hand-cannon muzzle flash (px / intensity) per frame.
const XBOW_KICK := [0.0, 0.0, 0.0, 2.0, 1.0, 0.0]
const GUN_FLASH := [0.0, 0.0, 0.0, 3.0, 2.0, 0.6, 0.0, 0.0, 0.0, 0.0]
## Firearms that aim at chest height and flash (tool drawn by _tool).
const FIREARMS := ["gun", "blunderbuss", "musket", "rifle", "assault_rifle", "machine_gun", "bazooka"]
## Machine gun: a flash on every other frame of the attack cycle.
const MG_FLASH := [3.0, 0.0, 2.6, 0.0, 3.0, 0.0, 2.6, 0.0, 3.0, 0.0]
## Hat colours for the cloth headgear.
const HATS := {"tricorn": "#2a2420", "shako": "#1f2430", "cap": "#6b6a4a", "steel": "#55603e"}
## Spear thrust: arm angle and extra reach per frame.
const THRUST := [[15, 1.0], [10, 0.0], [5, -1.5], [0, 5.0], [0, 7.0], [10, 3.0]]
## Bow: string pull (px) per frame.
const BOW_PULL := [0.0, 1.5, 3.0, 4.0, 4.0, 0.0]
const METAL := Color("#b9c0c8")
const METAL_DARK := Color("#6c737c")


static func build_sheet(layout: Dictionary, params: Dictionary) -> Image:
	return SheetBuilder.build(layout, params, paint)


## Paints one frame. `feet` is the ground contact point inside the frame.
static func paint(c: PixelCanvas, p: Dictionary, dir: int, anim: String, frame: int, frames: int, feet: Vector2i) -> void:
	var ang := SheetBuilder.dir_angle(dir)
	var side := snappedf(sin(ang), 0.001)
	var front := snappedf(cos(ang), 0.001)
	var cyc := float(frame) / float(maxi(frames, 1))
	var fx := float(feet.x)
	var fy := float(feet.y)
	var phase := TAU * float(frame) / float(maxi(frames, 1))
	var weapon: String = p.get("weapon", "")
	var swing := 0.0
	var bob := 0.0
	var tool := ""
	var carry := ""
	var theta := 0.0
	var reach := 0.0
	var pull := -1.0
	match anim:
		"walk", "carry_wood", "carry_food", "carry_gold", "carry_stone":
			swing = sin(phase)
			# Body rises at mid-stride (legs passing) and dips at full extension.
			bob = -1.0 if absf(swing) < 0.5 else 0.0
			if absf(swing) > 0.95:
				bob = 0.5
			if anim.begins_with("carry_"):
				carry = anim.trim_prefix("carry_")
		"idle":
			# Slow breathing: shoulders rise for half the cycle.
			bob = -1.0 if cyc >= 0.2 and cyc < 0.65 else 0.0
		"chop", "mine", "build":
			tool = {"chop": "axe", "mine": "pick", "build": "hammer"}[anim]
			theta = deg_to_rad(SheetBuilder.sample(SWING_KEYS[anim], frame, frames))
			bob = 1.0 if theta < 0.2 else 0.0
		"farm":
			tool = "hoe"
			theta = deg_to_rad(SheetBuilder.sample(HOE_KEYS, frame, frames))
			# Bent over the furrow while the blade is down.
			bob = 2.0 if theta < -0.6 else (1.0 if theta < 0.3 else 0.0)
			reach = 1.5 if theta < -0.6 else 0.0
		"forage":
			bob = 2.0 + (1.0 if cyc >= 0.33 and cyc < 0.67 else 0.0)
			carry = "basket_low"
		"attack":
			match weapon:
				"spear", "pike":
					tool = weapon
					theta = deg_to_rad(SheetBuilder.sample(THRUST.map(func(k): return k[0]), frame, frames))
					reach = SheetBuilder.sample(THRUST.map(func(k): return k[1]), frame, frames)
				"bow":
					tool = "bow"
					pull = SheetBuilder.sample(BOW_PULL, frame, frames)
				"javelin":
					tool = "javelin"
					theta = deg_to_rad(SheetBuilder.sample(THROW, frame, frames))
				"staff":
					# Conversion chant: staff raised high, body leaning in.
					tool = "staff"
					theta = deg_to_rad(SheetBuilder.sample([80, 100, 118, 128, 128, 118, 100, 85], frame, frames))
					bob = -1.0 if theta > 1.9 else 0.0
				"petard":
					tool = "petard"
					theta = deg_to_rad(SheetBuilder.sample([60, 80, 100, 110, 80, 40], frame, frames))
				"crossbow", "gun", "blunderbuss", "musket", "rifle", "assault_rifle", "bazooka":
					tool = weapon
					theta = 0.0
					pull = SheetBuilder.sample(XBOW_KICK if weapon == "crossbow" else GUN_FLASH, frame, frames)
				"machine_gun":
					tool = weapon
					theta = 0.0
					pull = float(MG_FLASH[frame % MG_FLASH.size()])
				"grenade":
					tool = "grenade"
					theta = deg_to_rad(SheetBuilder.sample(THROW, frame, frames))
					pull = 1.0 if float(frame) / frames < 0.55 else 0.0
				_:
					tool = weapon if weapon != "" else "axe"
					theta = deg_to_rad(SheetBuilder.sample(SWING_KEYS.get(tool, SWING_KEYS["sword"]), frame, frames))
					bob = 1.0 if theta < 0.2 else 0.0
	# Soldiers carry their weapon at rest while idle/walking.
	if tool == "" and carry == "" and weapon != "":
		tool = weapon
		match weapon:
			"sword", "axe", "greatsword":
				theta = deg_to_rad(-70.0 if weapon != "greatsword" else 70.0)
			"spear", "pike", "javelin":
				theta = deg_to_rad(80.0)
			"bow":
				pull = 0.0
			"crossbow":
				theta = deg_to_rad(-35.0)
				pull = 0.0
			"gun", "musket", "rifle", "blunderbuss", "assault_rifle":
				theta = deg_to_rad(65.0)
				pull = 0.0
			"machine_gun":
				# Heavy gun carried low at the hip.
				theta = deg_to_rad(-20.0)
				pull = 0.0
			"bazooka":
				# Tube rides on the shoulder, pointing forward.
				theta = deg_to_rad(12.0)
				pull = 0.0
			"grenade":
				theta = deg_to_rad(-60.0)
				pull = 1.0
			"petard":
				theta = deg_to_rad(60.0)
			"staff":
				theta = deg_to_rad(82.0)

	var robed: bool = p.has("robe")
	var tunic := PixelCanvas.ramp(p["robe"] if robed else p["tunic"], 4, 0.5)
	var pants := PixelCanvas.ramp(p["pants"], 3, 0.45)
	var boots: Color = p["boots"]
	var skin := PixelCanvas.ramp(p["skin"], 4, 0.45)
	var hair := PixelCanvas.ramp(p["hair"], 3, 0.5)
	var belt: Color = p["tunic"] if robed else p["belt"]
	if robed:
		hair = PixelCanvas.ramp(p["robe"], 3, 0.5)
	var mail := PixelCanvas.ramp(Color("#8f959c"), 4, 0.5)
	var has_mail: bool = p.get("mail", false)

	var hip_y := fy - 12.0 + bob
	var shoulder_y := fy - 22.0 + bob
	var body_cx := fx + side * 0.5
	var torso_w := lerpf(10.0, 7.0, side)

	# --- Legs ---
	for i in 2:
		var sgn := -1.0 if i == 0 else 1.0
		var base_off := lerpf(sgn * 2.2, sgn * 0.6, side)
		var leg_swing := swing * 4.5 * side * (1.0 if i == 0 else -1.0)
		var lift := maxf(0.0, swing * (1.0 if i == 0 else -1.0)) * 2.0 * (1.0 - side * 0.6)
		var hx := body_cx + base_off
		var foot_x := hx + leg_swing
		var foot_y := fy - lift
		var far := (side > 0.05 and i == 0) or (side <= 0.05 and front < 0.0 and i == 1)
		var lp := mail if has_mail else pants
		var col: Color = lp[0] if far else lp[1 + (1 if sgn < 0 else 0)]
		c.thick_line(hx, hip_y, foot_x, foot_y - 2.0, 3.0, col)
		c.rect(roundi(foot_x - 1.5), roundi(foot_y - 2.5), 3, 2, boots)
		if side > 0.0:
			c.put(roundi(foot_x + 1.5), roundi(foot_y - 1.5), boots)

	var fwd := Vector2(side, front * 0.6)
	var near_shoulder := Vector2(body_cx + side * 1.0 + (torso_w * 0.4 if side < 0.3 else 0.0), shoulder_y + 2.0)
	var dir_v := fwd * cos(theta) + Vector2(0, -1) * sin(theta)
	var hand := near_shoulder + dir_v * (7.0 + reach)
	if tool == "bow":
		hand = near_shoulder + fwd * 6.0 + Vector2(0, 1)
	elif (tool == "crossbow" or FIREARMS.has(tool)) and anim == "attack":
		# Aimed at chest height; recoil pushes the weapon back.
		hand = near_shoulder + fwd * (5.0 - (pull if tool == "crossbow" else pull * 0.4)) + Vector2(0, 1)
	var behind := front < -0.3
	var shield: bool = p.get("shield", false)
	var shield_pos := Vector2(body_cx - torso_w * 0.55 + side * 1.5 + front * 0.5, shoulder_y + 6.0)
	if tool != "" and behind:
		_tool(c, hand, dir_v, tool, pull)
	if shield and not behind and side < 0.5:
		pass  # front shield drawn after torso
	elif shield:
		_shield(c, shield_pos + Vector2(side * 2.0, 0), p["tunic"], side)
	if carry == "food" and not behind:
		c.shaded_blob(body_cx - side * 3.5, shoulder_y + 3.0, 4.5, 5.0, PixelCanvas.ramp(Color("#c9b285"), 4, 0.4))
	if (carry == "gold" or carry == "stone") and behind:
		_basket(c, Vector2(body_cx + side * 3.0, hip_y - 3.0), carry)

	# Far arm (behind the body in side views).
	if side > 0.3 and tool == "" and carry == "":
		_arm(c, Vector2(body_cx - torso_w * 0.25, shoulder_y + 1.5), swing * 3.0 * side, tunic[0], skin[1])

	# --- Torso and skirt ---
	var skirt_bottom := (fy - 1.0) if robed else (fy - 8.0 + bob)
	for y in range(roundi(shoulder_y), roundi(skirt_bottom)):
		var t := float(y - shoulder_y) / maxf(1.0, skirt_bottom - shoulder_y)
		var half := torso_w * 0.5
		if y == roundi(shoulder_y):
			half -= 1.0
		elif t < 0.6:
			half -= t * 1.6
		else:
			half += -0.96 + (t - 0.6) * 4.0
		var left := body_cx - half
		for x in range(roundi(left), roundi(body_cx + half)):
			var rel := (x + 0.5 - left) / (half * 2.0)
			var idx := 3 if rel < 0.28 else (2 if rel < 0.7 else 1)
			if rel > 0.88 or rel < 0.06:
				idx = 0
			if t > 0.92:
				idx = maxi(0, idx - 1)
			if front < 0.0 and idx == 3:
				idx = 2
			var col: Color = tunic[idx]
			if has_mail:
				var tabard := absf(x + 0.5 - body_cx - side * 1.0) < lerpf(2.2, 1.2, side) and t > 0.08
				col = tunic[idx] if tabard else mail[idx]
				if not tabard and (x + y) % 2 == 0:
					col = mail[maxi(0, idx - 1)]
			c.put(x, y, col)
	if front > 0.2 and not has_mail:
		c.put(roundi(body_cx - 1 + side), roundi(shoulder_y), skin[2])
		c.put(roundi(body_cx + side), roundi(shoulder_y), skin[1])
		c.put(roundi(body_cx + side), roundi(shoulder_y + 1), tunic[0])
	var belt_y := roundi(hip_y - 1.0)
	for x in range(roundi(body_cx - torso_w * 0.5), roundi(body_cx + torso_w * 0.5)):
		c.put(x, belt_y, belt)
	if front > 0.2:
		c.put(roundi(body_cx + side * 1.5), belt_y, Color("#d8b25a"))
	if side > 0.3 and weapon == "":
		c.rect(roundi(body_cx + torso_w * 0.5 - 2), belt_y + 1, 2, 2, belt.darkened(0.15))
	if weapon == "bow" and not behind:
		# Quiver on the back with fletching.
		c.rect(roundi(body_cx - side * 4.0 - 1), roundi(shoulder_y - 1), 3, 8, Color("#6e4a2c"))
		c.put(roundi(body_cx - side * 4.0), roundi(shoulder_y - 2), Color("#e8e1d0"))

	# --- Head, hair, helmet ---
	var hx := body_cx + side * 1.0
	var hy := shoulder_y - 4.5
	c.shaded_blob(hx, hy, 4.6, 4.6, skin)
	var helmet: String = p.get("helmet", "")
	for y in range(floori(hy - 5), ceili(hy + 5)):
		for x in range(floori(hx - 5), ceili(hx + 5)):
			if not c.is_solid(x, y):
				continue
			var dx := x + 0.5 - hx
			var dy := y + 0.5 - hy
			if dx * dx + dy * dy > 4.7 * 4.7:
				continue
			var hair_line := (-0.2 if robed else -1.2) + maxf(0.0, -front) * 4.5
			var is_hair := dy < hair_line
			if side > 0.3 and dx < -1.0 + (1.0 - side) and dy < 2.5:
				is_hair = true
			if front > 0.5 and absf(dx) > 3.4 and dy < 1.5:
				is_hair = true
			if robed and absf(dx) > 3.0 - side * 1.5 and dy < 3.0:
				is_hair = true  # hood sides frame the face
			if HATS.has(helmet) and dy < -0.6:
				var hr := PixelCanvas.ramp(Color(HATS[helmet]), 3, 0.5)
				c.put(x, y, hr[2] if dx < -1.0 and dy < -2.0 else hr[1])
			elif helmet != "" and dy < -0.6:
				var m := 3 if dx < -1.0 and dy < -2.0 else (2 if dy < -2.0 else 1)
				c.put(x, y, mail[m])
			elif is_hair:
				var hidx := 2 if dx < -1.0 and dy < -1.0 else (1 if dy < 1.0 else 0)
				c.put(x, y, hair[hidx])
	if HATS.has(helmet):
		var hat := PixelCanvas.ramp(Color(HATS[helmet]), 3, 0.5)
		match helmet:
			"tricorn":
				c.rect(roundi(hx - 6), roundi(hy - 3), 12, 2, hat[0])
				c.rect(roundi(hx - 4), roundi(hy - 6), 8, 3, hat[1])
				c.put(roundi(hx - 6), roundi(hy - 4), hat[0])
				c.put(roundi(hx + 5), roundi(hy - 4), hat[0])
			"shako":
				c.rect(roundi(hx - 4), roundi(hy - 10), 8, 7, hat[1])
				c.rect(roundi(hx - 4), roundi(hy - 10), 8, 1, hat[2])
				c.rect(roundi(hx - 5), roundi(hy - 3), 10, 1, hat[0])
				c.put(roundi(hx), roundi(hy - 11), p["tunic"])
				c.put(roundi(hx), roundi(hy - 12), Color(p["tunic"]).lightened(0.3))
			"cap":
				c.rect(roundi(hx - 4), roundi(hy - 5), 8, 2, hat[1])
				c.rect(roundi(hx - 1 + side * 3.0), roundi(hy - 3), 5, 1, hat[0])
			"steel":
				# Rounded combat helmet: dome over the hairline, brim all round, chin strap.
				c.shaded_blob(hx, hy - 2.2, 5.2, 3.6, hat)
				c.rect(roundi(hx - 6), roundi(hy - 1), 12, 1, hat[0])
				c.put(roundi(hx - 1.5), roundi(hy - 4), hat[2])
				if front > 0.3:
					c.put(roundi(hx - 3.0 + side * 2.0), roundi(hy + 2), hat[0])
	elif helmet == "kettle":
		for x in range(roundi(hx - 6), roundi(hx + 6)):
			c.put(x, roundi(hy - 0.5), mail[1])
	elif helmet == "nasal" and front > 0.3:
		c.put(roundi(hx - 0.5 + side * 2.0), roundi(hy + 0.5), mail[2])
	if front > 0.3:
		var eye := Color("#2b1d18")
		var ey := roundi(hy + 0.5)
		c.put(roundi(hx - 2.0 + side * 2.5), ey, eye)
		if side < 0.8:
			c.put(roundi(hx + 1.0 + side * 1.5), ey, eye)
	elif side > 0.8:
		c.put(roundi(hx + 2.5), roundi(hy + 0.5), Color("#2b1d18"))

	# --- Front shield ---
	if shield and not behind and side < 0.5:
		_shield(c, shield_pos, p["tunic"], side)

	# --- Tools, weapons, carried items ---
	if tool != "":
		if not behind:
			_tool(c, hand, dir_v, tool, pull)
		_arm_to(c, near_shoulder, hand, tunic[1] if not has_mail else mail[2], skin[2])
		if tool == "hoe" and theta < -0.85:
			_soil_puff(c, hand + dir_v.normalized() * 12.0 + Vector2(-dir_v.y, dir_v.x).normalized() * 3.0, frame)
		var two_handed := tool in ["axe", "pick", "hammer", "hoe", "greatsword", "pike", "crossbow", "gun", "petard", "blunderbuss", "musket", "rifle", "assault_rifle", "machine_gun", "bazooka"] or (tool == "bow" and pull > 0.0)
		if side < 0.3 and two_handed and not shield:
			var other := hand + Vector2(-1, 1)
			if tool == "bow":
				other = hand - fwd * pull - Vector2(0, 0)
			_arm_to(c, Vector2(body_cx - torso_w * 0.5, shoulder_y + 2.0), other, tunic[2] if not has_mail else mail[2], skin[2])
		elif side < 0.3 and not shield:
			_arm(c, Vector2(body_cx - torso_w * 0.5 - 0.6, shoulder_y + 1.5), -0.6, tunic[2] if not has_mail else mail[2], skin[2])
		return
	if carry == "food" and behind:
		c.shaded_blob(body_cx, shoulder_y + 3.0, 5.0, 5.0, PixelCanvas.ramp(Color("#c9b285"), 4, 0.4))
	if carry == "wood":
		var l0 := Vector2(body_cx - 7.0 + side * 2.0, shoulder_y + 0.5 + side * 1.0)
		var l1 := Vector2(body_cx + 6.0 + side * 3.0, shoulder_y - 1.5 - side * 1.0)
		c.thick_line(l0.x, l0.y, l1.x, l1.y, 3.4, Color("#7a5230"))
		c.thick_line(l0.x, l0.y - 1.0, l1.x, l1.y - 1.0, 1.0, Color("#9c6c40"))
		c.ellipse(l1.x, l1.y, 1.8, 1.8, Color("#d6b07a"))
		_arm_to(c, near_shoulder, Vector2(body_cx + side * 2.0, shoulder_y - 1.0), tunic[1], skin[2])
		return
	if carry == "gold" or carry == "stone" or carry == "basket_low":
		var bp := Vector2(body_cx + side * 3.0, hip_y - 3.0) if carry != "basket_low" else Vector2(body_cx + side * 4.0, fy - 3.0)
		if not behind:
			_basket(c, bp, carry)
		_arm_to(c, near_shoulder, bp + Vector2(1, -2), tunic[1], skin[2])
		if side < 0.3:
			_arm_to(c, Vector2(body_cx - torso_w * 0.5, shoulder_y + 2.0), bp + Vector2(-2, -2), tunic[2], skin[2])
		elif carry == "basket_low":
			_arm_to(c, near_shoulder + Vector2(-2, 0), bp + Vector2(3.0 + sin(phase * 2.0), 0), tunic[0], skin[1])
		return

	# --- Plain arms ---
	if side > 0.3:
		_arm(c, Vector2(body_cx + torso_w * 0.15, shoulder_y + 1.5), -swing * 3.5 * side, tunic[1], skin[2])
	else:
		var arm_lift := swing * 1.0
		_arm(c, Vector2(body_cx - torso_w * 0.5 - 0.6, shoulder_y + 1.5), -0.6, tunic[2], skin[2], arm_lift)
		_arm(c, Vector2(body_cx + torso_w * 0.5 - 0.2, shoulder_y + 1.5), 0.6, tunic[1], skin[1], -arm_lift)


static func _arm(c: PixelCanvas, shoulder: Vector2, swing_x: float, sleeve: Color, hand: Color, lift: float = 0.0) -> void:
	var elbow := shoulder + Vector2(swing_x * 0.5, 4.0 - lift * 0.5)
	var wrist := shoulder + Vector2(swing_x, 8.0 - lift)
	c.thick_line(shoulder.x, shoulder.y, elbow.x, elbow.y, 2.6, sleeve)
	c.thick_line(elbow.x, elbow.y, wrist.x, wrist.y, 2.2, sleeve)
	c.ellipse(wrist.x, wrist.y + 0.5, 1.3, 1.3, hand)


static func _arm_to(c: PixelCanvas, shoulder: Vector2, hand: Vector2, sleeve: Color, skin: Color) -> void:
	var elbow := (shoulder + hand) * 0.5 + Vector2(0, 1)
	c.thick_line(shoulder.x, shoulder.y, elbow.x, elbow.y, 2.6, sleeve)
	c.thick_line(elbow.x, elbow.y, hand.x, hand.y, 2.2, sleeve)
	c.ellipse(hand.x, hand.y, 1.3, 1.3, skin)


static func _shield(c: PixelCanvas, at: Vector2, team: Color, side: float) -> void:
	var r := PixelCanvas.ramp(team, 4, 0.5)
	var w := lerpf(4.5, 2.2, side)
	c.ellipse(at.x, at.y, w + 1.0, 5.5, Color("#6e4a2c"))
	c.ellipse(at.x, at.y, w, 4.6, r[2])
	c.ellipse(at.x - w * 0.3, at.y - 1.5, w * 0.4, 1.6, r[3])
	c.put(roundi(at.x), roundi(at.y), METAL)


## Clods of earth flung up where the hoe bites into the furrow.
static func _soil_puff(c: PixelCanvas, at: Vector2, frame: int) -> void:
	var k := float(frame % 3)
	for o in [Vector2(-3.0, -1.5 - k), Vector2(2.0, -2.5 - k * 0.5), Vector2(4.0, -0.5), Vector2(-1.0, 0.5)]:
		c.rect(roundi(at.x + o.x), roundi(at.y + o.y), 2, 2, SOIL)
	c.rect(roundi(at.x), roundi(at.y - 4.0 - k), 2, 1, SOIL_LIGHT)
	c.put(roundi(at.x - 4.0), roundi(at.y - 3.5 - k), SOIL_LIGHT)


## Tool or weapon held at `hand`, pointing along `dir` (screen space).
static func _tool(c: PixelCanvas, hand: Vector2, dir: Vector2, tool: String, pull: float = 0.0) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector2(0, -1)
	var perp := Vector2(-d.y, d.x)
	match tool:
		"axe", "pick", "hammer":
			var length := 10.0 if tool != "hammer" else 6.0
			var butt := hand - d * 2.0
			var tip := hand + d * length
			c.thick_line(butt.x, butt.y, tip.x, tip.y, 1.6, Color("#8a5a32"))
			if tool == "axe":
				c.polygon(PackedVector2Array([tip - d, tip + perp * 4.0 - d * 2.5, tip + perp * 4.5 + d * 1.5, tip + d]), METAL)
				c.put(roundi((tip + perp * 4.0).x), roundi((tip + perp * 4.0).y), METAL_DARK)
			elif tool == "pick":
				c.thick_line((tip - perp * 5.0).x, (tip - perp * 5.0 + d).y, (tip + perp * 5.0).x, (tip + perp * 5.0 + d).y, 1.6, METAL)
			else:
				c.thick_line((tip - perp * 2.5).x, (tip - perp * 2.5).y, (tip + perp * 2.5).x, (tip + perp * 2.5).y, 2.6, METAL_DARK)
		"hoe":
			# Long ash handle with a flat iron blade bent back towards the farmer.
			var butt_h := hand - d * 3.0
			var end := hand + d * 12.0
			c.thick_line(butt_h.x, butt_h.y, end.x, end.y, 1.4, Color("#9a6a3c"))
			# Wide plate: two strokes side by side, bright cutting edge.
			var bl := end + perp * 4.5 - d * 1.0
			c.thick_line(end.x, end.y, bl.x, bl.y, 2.6, METAL_DARK)
			c.thick_line(end.x - d.x * 1.5, end.y - d.y * 1.5, bl.x - d.x * 1.5, bl.y - d.y * 1.5, 1.6, METAL_DARK)
			c.put(roundi(bl.x), roundi(bl.y), METAL)
			c.put(roundi(bl.x - d.x), roundi(bl.y - d.y), METAL)
		"sword":
			var guard := hand + d * 1.5
			var tip2 := hand + d * 12.0
			c.thick_line(hand.x - d.x * 2.0, hand.y - d.y * 2.0, guard.x, guard.y, 1.6, Color("#5b3b22"))
			c.thick_line((guard - perp * 2.5).x, (guard - perp * 2.5).y, (guard + perp * 2.5).x, (guard + perp * 2.5).y, 1.4, Color("#d8b25a"))
			c.thick_line(guard.x, guard.y, tip2.x, tip2.y, 1.7, METAL)
			c.put(roundi(tip2.x), roundi(tip2.y), Color.WHITE)
		"spear", "pike", "javelin":
			var long: Array = {"spear": [8.0, 12.0], "pike": [11.0, 17.0], "javelin": [5.0, 8.0]}[tool]
			var back := hand - d * float(long[0])
			var front := hand + d * float(long[1])
			c.thick_line(back.x, back.y, front.x, front.y, 1.4 if tool != "javelin" else 1.1, Color("#8a5a32"))
			var hw := 1.6 if tool != "javelin" else 1.1
			c.polygon(PackedVector2Array([front - perp * hw, front + d * (4.0 if tool != "javelin" else 3.0), front + perp * hw]), METAL)
		"greatsword":
			var g2 := hand + d * 2.0
			var tip3 := hand + d * 16.0
			c.thick_line(hand.x - d.x * 3.5, hand.y - d.y * 3.5, g2.x, g2.y, 1.6, Color("#5b3b22"))
			c.thick_line((g2 - perp * 3.5).x, (g2 - perp * 3.5).y, (g2 + perp * 3.5).x, (g2 + perp * 3.5).y, 1.5, Color("#d8b25a"))
			c.thick_line(g2.x, g2.y, tip3.x, tip3.y, 2.2, METAL)
			c.thick_line(g2.x + perp.x * 0.4, g2.y + perp.y * 0.4, tip3.x, tip3.y, 0.9, Color("#e6ebef"))
		"petard":
			var keg := hand + d * 2.5
			var staves := PixelCanvas.ramp(Color("#7a5230"), 3, 0.45)
			c.ellipse(keg.x, keg.y, 4.2, 4.8, staves[1])
			c.ellipse(keg.x - 1.2, keg.y - 1.0, 1.6, 3.0, staves[2])
			c.rect(roundi(keg.x - 4), roundi(keg.y - 2), 8, 1, METAL_DARK)
			c.rect(roundi(keg.x - 4), roundi(keg.y + 2), 8, 1, METAL_DARK)
			c.put(roundi(keg.x + 1), roundi(keg.y - 5), Color("#3a2a1c"))
			c.put(roundi(keg.x + 2), roundi(keg.y - 6), Color("#ffd35a"))
		"staff":
			var foot := hand - d * 9.0
			var top2 := hand + d * 9.0
			c.thick_line(foot.x, foot.y, top2.x, top2.y, 1.4, Color("#8a5a32"))
			c.ellipse(top2.x, top2.y, 1.8, 1.8, Color("#c9a26b"))
			c.put(roundi(top2.x), roundi(top2.y - 1), Color("#fff6c8"))
		"crossbow":
			var stock0 := hand - d * 3.0
			var nose := hand + d * 6.0
			c.thick_line(stock0.x, stock0.y, nose.x, nose.y, 1.8, Color("#7a5230"))
			var l1 := nose - d * 1.0 + perp * 4.5
			var l2 := nose - d * 1.0 - perp * 4.5
			c.line(roundi(nose.x), roundi(nose.y), roundi(l1.x), roundi(l1.y), METAL_DARK)
			c.line(roundi(nose.x), roundi(nose.y), roundi(l2.x), roundi(l2.y), METAL_DARK)
			var sn := hand + d * (1.5 - pull)
			c.line(roundi(l1.x), roundi(l1.y), roundi(sn.x), roundi(sn.y), Color("#e8e1d0"))
			c.line(roundi(l2.x), roundi(l2.y), roundi(sn.x), roundi(sn.y), Color("#e8e1d0"))
		"grenade":
			if pull > 0.5:
				var g := hand + d * 1.5
				c.ellipse(g.x, g.y, 2.0, 2.0, Color("#2a2d33"))
				c.put(roundi(g.x + 1), roundi(g.y - 2), Color("#ffd35a"))
		"assault_rifle", "machine_gun":
			var mg := tool == "machine_gun"
			var butt3 := hand - d * (4.0 if not mg else 5.0)
			var muzzle3 := hand + d * (11.0 if not mg else 13.0)
			c.thick_line(butt3.x, butt3.y, hand.x, hand.y, 2.2, Color("#3a3d33") if mg else Color("#5b4a32"))
			c.thick_line(hand.x, hand.y, muzzle3.x, muzzle3.y, 2.0 if mg else 1.4, Color("#2f3238"))
			# Magazine under the receiver (box mag / ammunition belt).
			var mag := hand + d * 2.0
			c.rect(roundi(mag.x), roundi(mag.y + 1), 2, 3 if not mg else 2, Color("#2a2d33"))
			if mg:
				var belt := mag + Vector2(-2, 2)
				c.line(roundi(mag.x), roundi(mag.y + 2), roundi(belt.x), roundi(belt.y + 2), Color("#c9a24a"))
				var bip := hand + d * 9.0
				c.line(roundi(bip.x), roundi(bip.y), roundi(bip.x - 1), roundi(bip.y + 4), Color("#2a2d33"))
				c.line(roundi(bip.x), roundi(bip.y), roundi(bip.x + 1), roundi(bip.y + 4), Color("#2a2d33"))
			if pull > 0.5:
				var fl3 := muzzle3 + d * 2.0
				c.ellipse(fl3.x, fl3.y, 1.0 + pull * 0.7, 0.8 + pull * 0.5, Color("#ffd35a"))
				c.ellipse(fl3.x, fl3.y, 0.5 + pull * 0.3, 0.5 + pull * 0.2, Color("#fff6c8"))
		"bazooka":
			var rear := hand - d * 8.0
			var mouth := hand + d * 9.0
			c.thick_line(rear.x, rear.y - 2.0, mouth.x, mouth.y - 2.0, 3.2, Color("#55603e"))
			c.thick_line(rear.x, rear.y - 3.0, mouth.x, mouth.y - 3.0, 1.0, Color("#77845a"))
			c.ellipse(mouth.x, mouth.y - 2.0, 1.8, 1.8, Color("#2a2d33"))
			c.rect(roundi(hand.x), roundi(hand.y - 1), 1, 3, Color("#2a2d33"))
			if pull > 0.5:
				# Rocket leaves the tube; backblast smoke behind the shooter.
				c.ellipse(mouth.x + d.x * 3.0, mouth.y - 2.0 + d.y * 3.0, 1.6 + pull * 0.6, 1.2 + pull * 0.4, Color("#ffd35a"))
				c.ellipse(rear.x - d.x * 4.0, rear.y - 2.0 - d.y * 4.0, 2.5 + pull, 2.0 + pull * 0.6, Color(0.85, 0.85, 0.86, 0.8))
				c.ellipse(rear.x - d.x * 2.0, rear.y - 2.0, 1.4, 1.2, Color("#f08a2a"))
		"gun", "blunderbuss", "musket", "rifle":
			var spec: Array = {"gun": [4.0, 11.0, 1.8], "blunderbuss": [4.0, 8.0, 2.0], "musket": [5.0, 14.0, 1.5], "rifle": [5.0, 13.0, 1.3]}[tool]
			var butt2 := hand - d * float(spec[0])
			var muzzle := hand + d * float(spec[1])
			c.thick_line(butt2.x, butt2.y, hand.x, hand.y, 2.2, Color("#6e4a2c"))
			c.thick_line(hand.x, hand.y, muzzle.x, muzzle.y, float(spec[2]), Color("#4b5058") if tool != "musket" else Color("#5f646c"))
			c.put(roundi(muzzle.x), roundi(muzzle.y), Color("#2a2d33"))
			if tool == "blunderbuss":
				c.ellipse(muzzle.x, muzzle.y, 1.8, 1.8, Color("#8a6a3a"))
			elif tool == "musket":
				var bay := muzzle + d * 4.0
				c.line(roundi(muzzle.x), roundi(muzzle.y), roundi(bay.x), roundi(bay.y), METAL)
			if pull > 0.5:
				var fl := muzzle + d * 2.5
				c.ellipse(fl.x, fl.y, 1.0 + pull * 0.8, 1.0 + pull * 0.6, Color("#ffd35a"))
				c.ellipse(fl.x, fl.y, 0.6 + pull * 0.4, 0.6 + pull * 0.3, Color("#fff6c8"))
				c.ellipse(fl.x + d.x * 3.0, fl.y - 2.0 - pull, 1.5 + pull, 1.2 + pull * 0.6, Color(0.82, 0.82, 0.84, 0.75))
		"bow":
			var up := Vector2(0, -1)
			var top := hand + up * 7.0 + d * 1.0
			var bot := hand - up * 7.0 + d * 1.0
			var mid := hand + d * 3.0
			c.line(roundi(top.x), roundi(top.y), roundi(mid.x), roundi(mid.y), Color("#7a5230"))
			c.line(roundi(mid.x), roundi(mid.y), roundi(bot.x), roundi(bot.y), Color("#7a5230"))
			var nock := hand - d * maxf(pull, 0.0)
			c.line(roundi(top.x), roundi(top.y), roundi(nock.x), roundi(nock.y), Color("#e8e1d0"))
			c.line(roundi(nock.x), roundi(nock.y), roundi(bot.x), roundi(bot.y), Color("#e8e1d0"))
			if pull > 0.5:
				c.line(roundi(nock.x), roundi(nock.y), roundi((hand + d * 6.0).x), roundi((hand + d * 6.0).y), Color("#c9a26b"))


static func _basket(c: PixelCanvas, at: Vector2, content: String) -> void:
	var wicker := PixelCanvas.ramp(Color("#a57a45"), 3, 0.4)
	c.rect(roundi(at.x - 4), roundi(at.y - 2), 8, 5, wicker[1])
	c.rect(roundi(at.x - 4), roundi(at.y - 2), 8, 1, wicker[2])
	for x in range(-4, 4, 2):
		c.put(roundi(at.x + x), roundi(at.y), wicker[0])
	var top := Color("#e3b02a") if content == "gold" else (Color("#9aa1a8") if content == "stone" else Color("#c52f4b"))
	c.ellipse(at.x - 1.5, at.y - 3.0, 2.0, 1.5, top)
	c.ellipse(at.x + 1.5, at.y - 3.0, 2.0, 1.5, top.lightened(0.15))

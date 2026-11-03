extends RefCounted
## Procedural aircraft painter: biplanes (fighter, bomber) and the observation
## balloon. Models are projected like ships (f forward, r right in tiles; z up in
## px) around the frame anchor; the game lifts the sprite to the unit's altitude
## and keeps the shadow on the ground. params "model": biplane_fighter,
## biplane_bomber, observation_balloon, jet_fighter, jet_bomber (Military Age:
## swept wings, afterburner glow). Animations: idle/walk (propeller spin,
## balloon sway), attack (muzzle flash / bomb release), die (SheetBuilder "crash").

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")
const SheetBuilder := preload("res://tools/art/sheet_builder.gd")

var c: PixelCanvas
var origin := Vector2.ZERO
var fdir := Vector2.ZERO
var rdir := Vector2.ZERO


static func build_sheet(layout: Dictionary, params: Dictionary) -> Image:
	return SheetBuilder.build(layout, params, paint)


static func paint(canvas: PixelCanvas, p: Dictionary, dir: int, anim: String, frame: int, frames: int, feet: Vector2i) -> void:
	var s = load("res://tools/art/air_art.gd").new()
	s.c = canvas
	s.origin = Vector2(feet)
	var a := SheetBuilder.dir_angle(dir)
	s.fdir = Vector2(sin(a) + 2.0 * cos(a), 2.0 * cos(a) - sin(a)).normalized()
	s.rdir = Vector2(-s.fdir.y, s.fdir.x)
	match String(p.get("model", "biplane_fighter")):
		"jet_fighter":
			s._jet(p, anim, frame, frames, false)
		"jet_bomber":
			s._jet(p, anim, frame, frames, true)
		"observation_balloon":
			s._balloon(p, frame, frames)
		"biplane_bomber":
			s._biplane(p, anim, frame, frames, true)
		_:
			s._biplane(p, anim, frame, frames, false)


func scr(f: float, r: float, z: float) -> Vector2:
	var g := fdir * f + rdir * r
	return origin + Vector2((g.x - g.y) * 32.0, (g.x + g.y) * 16.0 - z)


func beam(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var p := scr(a.x, a.y, a.z)
	var q := scr(b.x, b.y, b.z)
	c.thick_line(p.x, p.y, q.x, q.y, w, col)


func wing(f0: float, f1: float, span: float, z: float, col: Color, edge: Color) -> void:
	c.polygon(PackedVector2Array([scr(f0, -span, z), scr(f1, -span, z), scr(f1, span, z), scr(f0, span, z)]), col)
	var a := scr(f1, -span, z)
	var b := scr(f1, span, z)
	c.line(roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y), edge)


func _biplane(p: Dictionary, anim: String, frame: int, frames: int, bomber: bool) -> void:
	var body := PixelCanvas.ramp(Color("#a89a6a") if not bomber else Color("#7d7a5a"), 4, 0.5)
	var team := PixelCanvas.ramp(Color(p["tunic"]), 4, 0.5)
	var length := 0.34 if not bomber else 0.46
	var span := 0.42 if not bomber else 0.62
	var phase := TAU * float(frame) / float(maxi(frames, 1))
	var bank := sin(phase) * 0.6
	# Lower wing, fuselage, upper wing, struts — far to near.
	wing(-0.02, 0.1 if not bomber else 0.14, span, 0.0 + bank, body[1], body[0])
	beam(Vector3(-length, 0, 2 + bank), Vector3(length, 0, 3 + bank), 4.0 if not bomber else 5.5, body[2])
	beam(Vector3(-length, 0, 3.5 + bank), Vector3(length, 0, 4.5 + bank), 1.2, body[3])
	# Tail: stabiliser and fin with the team colour.
	wing(-length - 0.04, -length + 0.06, 0.14 if not bomber else 0.2, 3.0 + bank, body[1], body[0])
	beam(Vector3(-length + 0.02, 0, 3 + bank), Vector3(-length - 0.02, 0, 10 + bank), 2.0, team[2])
	if bomber:
		for k in 2:
			var bp := scr(-0.05 + k * 0.14, 0, 0 + bank)
			if not (anim == "attack" and float(frame) / frames > 0.3 and k == 0):
				c.ellipse(bp.x, bp.y + 1, 1.6, 1.2, Color("#2a2d33"))
		for sgn in [-1.0, 1.0]:
			var eng := Vector3(0.12, sgn * 0.26, 1.5 + bank)
			beam(eng, eng + Vector3(0.1, 0, 0), 3.0, Color("#4b5058"))
	wing(0.0, 0.12 if not bomber else 0.16, span, 7.0 + bank, body[2], body[0])
	for sgn2 in [-1.0, 1.0]:
		beam(Vector3(0.05, sgn2 * span * 0.7, 0.5 + bank), Vector3(0.05, sgn2 * span * 0.7, 7 + bank), 1.0, body[0])
		# Team roundels on the upper wing tips.
		var rp := scr(0.06, sgn2 * span * 0.75, 7.2 + bank)
		c.ellipse(rp.x, rp.y, 2.2, 1.3, team[2])
		c.put(roundi(rp.x), roundi(rp.y), Color("#efe3c8"))
	# Cockpit and pilot.
	var ck := scr(-0.08, 0, 6 + bank)
	c.ellipse(ck.x, ck.y, 1.8, 1.4, Color("#2a1d14"))
	c.put(roundi(ck.x), roundi(ck.y - 2), Color("#5b3b22"))
	# Propellers: alternate blade and blur so the spin reads in motion.
	var props: Array = [Vector3(length + 0.03, 0, 2.5 + bank)]
	if bomber:
		props = [Vector3(0.24, -0.26, 1.5 + bank), Vector3(0.24, 0.26, 1.5 + bank)]
	for pv in props:
		var hub := scr(pv.x, pv.y, pv.z)
		var blade := (scr(pv.x, pv.y + 0.12, pv.z) - hub).normalized() * 5.0
		if frame % 2 == 0:
			c.line(roundi(hub.x - blade.x), roundi(hub.y - blade.y - 2), roundi(hub.x + blade.x), roundi(hub.y + blade.y + 2), Color("#3a2618"))
		else:
			c.ellipse(hub.x, hub.y, 3.0, 4.5, Color(0.85, 0.85, 0.8, 0.45))
		c.put(roundi(hub.x), roundi(hub.y), Color("#c9a24a"))
	if anim == "attack" and not bomber and frame % 2 == 0:
		var muzzle := scr(length + 0.12, 0.05, 4 + bank)
		c.ellipse(muzzle.x, muzzle.y, 1.6, 1.2, Color("#ffd35a"))


## Swept-wing jet: wings and tailplane as flat polygons, fuselage beam, team fin,
## canopy and a flickering exhaust; the bomber has two engine pods and bombs.
func _jet(p: Dictionary, anim: String, frame: int, frames: int, bomber: bool) -> void:
	var body := PixelCanvas.ramp(Color("#8a9298") if not bomber else Color("#6f7a6a"), 4, 0.5)
	var team := PixelCanvas.ramp(Color(p["tunic"]), 4, 0.5)
	var length := 0.42 if not bomber else 0.6
	var span := 0.38 if not bomber else 0.66
	var sweep := 0.2 if not bomber else 0.16
	var bank := sin(TAU * float(frame) / float(maxi(frames, 1))) * 0.5
	var z := 3.0 + bank
	# Main wing: root chord at mid-fuselage, tips swept back.
	var root_f := 0.08 if not bomber else 0.12
	var root_b := -0.14 if not bomber else -0.16
	for sgn in [-1.0, 1.0]:
		var poly := PackedVector2Array([scr(root_f, 0, z), scr(root_f - sweep, sgn * span, z + 1.0), scr(root_f - sweep - 0.08, sgn * span, z + 1.0), scr(root_b, sgn * 0.04, z)])
		c.polygon(poly, body[1])
		var e0 := scr(root_f, 0, z)
		var e1 := scr(root_f - sweep, sgn * span, z + 1.0)
		c.line(roundi(e0.x), roundi(e0.y), roundi(e1.x), roundi(e1.y), body[3])
		var tip := scr(root_f - sweep - 0.04, sgn * span * 0.92, z + 1.2)
		c.ellipse(tip.x, tip.y, 1.8, 1.0, team[2])
	if bomber:
		for sgn2 in [-1.0, 1.0]:
			var pod := Vector3(0.02, sgn2 * 0.28, z - 1.5)
			beam(pod - Vector3(0.14, 0, 0), pod + Vector3(0.1, 0, 0), 3.4, Color("#4b5058"))
			var noz := scr(pod.x - 0.15, pod.y, pod.z)
			c.ellipse(noz.x, noz.y, 1.6, 1.4, Color("#ffb04a") if frame % 2 == 0 else Color("#ff7a2a"))
		var drop := anim == "attack" and float(frame) / frames > 0.3
		for k in 3:
			if drop and k < 2:
				continue
			var bp := scr(-0.06 + k * 0.09, 0, z - 3.0)
			c.ellipse(bp.x, bp.y + 1, 1.5, 1.1, Color("#2a2d33"))
	# Tailplane, fuselage, fin.
	for sgn3 in [-1.0, 1.0]:
		c.polygon(PackedVector2Array([scr(-length + 0.12, 0, z + 1), scr(-length + 0.02, sgn3 * span * 0.38, z + 1.5), scr(-length - 0.02, sgn3 * span * 0.38, z + 1.5), scr(-length, 0, z + 1)]), body[1])
	beam(Vector3(-length, 0, z + 1), Vector3(length, 0, z + 1.5), 4.4 if not bomber else 6.0, body[2])
	beam(Vector3(-length, 0, z + 3), Vector3(length * 0.8, 0, z + 3.4), 1.2, body[3])
	beam(Vector3(length * 0.9, 0, z + 1.4), Vector3(length + 0.08, 0, z + 1.2), 2.0, body[1])
	c.polygon(PackedVector2Array([scr(-length + 0.16, 0, z + 3), scr(-length + 0.01, 0, z + 14), scr(-length - 0.04, 0, z + 14), scr(-length, 0, z + 2)]), team[2])
	var ck := scr(length * 0.55, 0, z + 4.2)
	c.ellipse(ck.x, ck.y, 2.6 if not bomber else 3.2, 1.5, Color("#2a4058"))
	c.put(roundi(ck.x - 1), roundi(ck.y - 1), Color("#9ac0e0"))
	# Exhaust: alternating afterburner glow so the engine reads alive.
	var ex := scr(-length - 0.03, 0, z + 1.2)
	c.ellipse(ex.x, ex.y, 1.8, 1.6, Color("#2a2d33"))
	if not bomber:
		c.ellipse(ex.x - (scr(1, 0, 0) - scr(0, 0, 0)).normalized().x * 3.0, ex.y, 1.6 + (frame % 2), 1.2, Color("#ffb04a"))
	if anim == "attack" and not bomber and frame % 2 == 0:
		for sgn4 in [-1.0, 1.0]:
			var mz := scr(length * 0.7, sgn4 * 0.06, z + 0.5)
			c.ellipse(mz.x, mz.y, 1.5, 1.1, Color("#ffd35a"))


func _balloon(p: Dictionary, frame: int, frames: int) -> void:
	var cloth := PixelCanvas.ramp(Color("#d8cfb8"), 4, 0.45)
	var team := PixelCanvas.ramp(Color(p["tunic"]), 4, 0.5)
	var sway := sin(TAU * float(frame) / float(maxi(frames, 1))) * 1.2
	var cx := origin.x + sway
	var top := origin.y - 22.0
	c.shaded_blob(cx, top, 13.0, 17.0, cloth)
	# Team-coloured gores.
	for k in [-6, 0, 6]:
		for y in range(-15, 16):
			var w := 13.0 * sqrt(maxf(0.0, 1.0 - pow(y / 17.0, 2.0)))
			var x := cx + float(k) * w / 13.0
			if c.is_solid(roundi(x), roundi(top + y)):
				c.put(roundi(x), roundi(top + y), team[2] if k == 0 else team[1])
	var basket := Vector2(origin.x + sway * 0.5, origin.y + 6.0)
	for sgn in [-1.0, 1.0]:
		c.line(roundi(cx + sgn * 6.0), roundi(top + 14.0), roundi(basket.x + sgn * 3.0), roundi(basket.y - 2.0), Color("#5b3b22"))
	c.rect(roundi(basket.x - 4), roundi(basket.y - 2), 8, 5, Color("#8a5a32"))
	c.rect(roundi(basket.x - 4), roundi(basket.y - 2), 8, 1, Color("#c9a26b"))
	c.put(roundi(basket.x - 1), roundi(basket.y - 3), Color("#e2ad80"))

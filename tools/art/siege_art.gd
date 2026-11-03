extends RefCounted
## Procedural siege painter. Small 3D models (frames, wheels, arms, barrels)
## projected isometrically for each drawn direction. params "model" selects:
## catapult (default), mangonel, battering_ram, scorpion, bombard_cannon, trebuchet.
## Local model space: f = forward (tiles), r = right (tiles), z = up (px).

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")
const SheetBuilder := preload("res://tools/art/sheet_builder.gd")

## Arm angle (degrees from pointing backwards-flat) per attack frame.
const ARM_KEYS := [8, 8, 60, 118, 118, 80, 40, 8]
## Ram log swing (tiles along f) over the attack cycle.
const RAM_KEYS := [0.0, -0.12, -0.2, -0.08, 0.22, 0.3, 0.12, 0.0]
## Scorpion string draw (tiles) - drawn back, released mid-cycle.
const BOLT_PULL := [0.0, 0.06, 0.12, 0.16, 0.16, 0.0, 0.0, 0.0, 0.0, 0.0]
## Bombard recoil (tiles) and muzzle flash intensity.
const RECOIL := [0.0, 0.0, 0.0, -0.14, -0.1, -0.06, -0.03, -0.01, 0.0, 0.0]
const BLAST := [0.0, 0.0, 0.0, 3.0, 2.0, 1.0, 0.4, 0.0, 0.0, 0.0]
## Trebuchet arm angle (degrees; 90 = long end straight up) over the throw.
const TREB_KEYS := [-35, -35, -22, 15, 60, 100, 122, 112, 85, 45, 10, -20, -32, -35]

var c: PixelCanvas
var origin := Vector2.ZERO
var fdir := Vector2.ZERO
var rdir := Vector2.ZERO


static func build_sheet(layout: Dictionary, params: Dictionary) -> Image:
	return SheetBuilder.build(layout, params, paint)


static func paint(canvas: PixelCanvas, p: Dictionary, dir: int, anim: String, frame: int, frames: int, feet: Vector2i) -> void:
	var s = load("res://tools/art/siege_art.gd").new()
	s.c = canvas
	s.origin = Vector2(feet) + Vector2(0, -4)
	s.fdir = grid_dir(dir)
	s.rdir = Vector2(-s.fdir.y, s.fdir.x)
	s._draw_model(p, anim, frame, frames)


## Grid-space facing for a painted row: inverts the screen projection of the
## row's angle (0 = screen south, PI/2 = screen east).
static func grid_dir(dir: int) -> Vector2:
	var a := SheetBuilder.dir_angle(dir)
	var sx := sin(a)
	var sy := cos(a)
	return Vector2(sx + 2.0 * sy, 2.0 * sy - sx).normalized()


func scr(f: float, r: float, z: float) -> Vector2:
	var g := fdir * f + rdir * r
	return origin + Vector2((g.x - g.y) * 32.0, (g.x + g.y) * 16.0 - z)


func beam(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var p := scr(a.x, a.y, a.z)
	var q := scr(b.x, b.y, b.z)
	c.thick_line(p.x, p.y, q.x, q.y, w, col)


func poly3(pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for q in pts:
		out.append(scr(q.x, q.y, q.z))
	c.polygon(out, col)


## Draws wheels at `pos` in back-to-front order; returns the front ones still to draw.
func _wheels_back(pos: Array, roll: float, wood: Array[Color], dark: Color, iron: Color, scale: float = 1.0) -> Array:
	pos.sort_custom(func(a, b): return scr(a.x, a.y, 0).y < scr(b.x, b.y, 0).y)
	var half := pos.size() / 2
	for i in half:
		_wheel(pos[i], roll, wood, dark, iron, scale)
	return pos.slice(half)


func _draw_model(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	match String(p.get("model", "catapult")):
		"battering_ram":
			_draw_ram(p, anim, frame, frames)
			return
		"scorpion":
			_draw_scorpion(p, anim, frame, frames)
			return
		"bombard_cannon":
			_draw_bombard(p, anim, frame, frames)
			return
		"trebuchet":
			_draw_trebuchet(p, anim, frame, frames)
			return
		"trade_cart":
			_draw_trade_cart(p, anim, frame, frames)
			return
		"field_cannon":
			_draw_field_cannon(p, anim, frame, frames)
			return
		"mortar":
			_draw_mortar(p, anim, frame, frames)
			return
	var heavy: bool = p.get("model", "") == "mangonel"
	var wood := PixelCanvas.ramp(Color("#7a5232") if heavy else Color("#8d6139"), 4, 0.5)
	var dark := Color("#4a3020")
	var iron := Color("#6c737c")
	var team := Color(p["tunic"])
	var roll := float(frame) / maxf(frames, 1) * TAU if anim == "walk" else 0.0
	var arm_deg: float = SheetBuilder.sample(ARM_KEYS, frame, frames) if anim == "attack" else 8.0

	# Wheels sorted back-to-front by screen depth.
	var wheels := []
	for wf in [-0.3, 0.3]:
		for wr in [-0.3, 0.3]:
			wheels.append(Vector3(wf, wr, 5))
	wheels.sort_custom(func(a, b): return scr(a.x, a.y, 0).y < scr(b.x, b.y, 0).y)
	for i in 2:
		_wheel(wheels[i], roll, wood, dark, iron)

	# Base frame.
	for r in [-0.2, 0.2]:
		beam(Vector3(-0.45, r, 8), Vector3(0.45, r, 8), 3.0, wood[1])
	for f in [-0.38, 0.0, 0.38]:
		beam(Vector3(f, -0.22, 9), Vector3(f, 0.22, 9), 2.4, wood[2])
	# Team pennant on the rear.
	var pole := scr(-0.42, 0.2, 9)
	c.line(roundi(pole.x), roundi(pole.y), roundi(pole.x), roundi(pole.y) - 14, dark)
	c.rect(roundi(pole.x) + 1, roundi(pole.y) - 14, 5, 3, team)

	# Uprights and crossbar.
	for r in [-0.16, 0.16]:
		beam(Vector3(0.12, r, 8), Vector3(0.12, r, 26 if not heavy else 30), 2.6 if not heavy else 3.2, wood[3] if r < 0 else wood[1])
		if heavy:
			beam(Vector3(0.4, r, 8), Vector3(0.12, r, 28), 2.0, wood[1])
	beam(Vector3(0.12, -0.2, 26 if not heavy else 30), Vector3(0.12, 0.2, 26 if not heavy else 30), 2.6, wood[2])
	if heavy:
		# Iron-banded frame and a team cloth over the crossbar.
		for f2 in [-0.3, 0.3]:
			beam(Vector3(f2, -0.22, 9), Vector3(f2, 0.22, 9), 1.2, iron)
		poly3([Vector3(0.12, -0.2, 30), Vector3(0.12, 0.2, 30), Vector3(0.14, 0.2, 22), Vector3(0.14, -0.2, 22)], team)

	# Throwing arm.
	var pivot := Vector3(-0.12, 0.0, 11)
	var a := deg_to_rad(arm_deg)
	var length := 0.42 if not heavy else 0.5
	var tip := Vector3(pivot.x - cos(a) * length, 0.0, pivot.z + sin(a) * length * 48.0)
	beam(pivot, tip, 2.4, wood[2])
	# Bucket and stone (stone only while loaded).
	var tp := scr(tip.x, tip.y, tip.z)
	c.ellipse(tp.x, tp.y, 3.2, 2.2, dark)
	if arm_deg < 50.0:
		var rr := 2.6 if not heavy else 3.2
		c.shaded_blob(tp.x, tp.y - 2.0, rr, rr * 0.92, PixelCanvas.ramp(Color("#8f8a80"), 3, 0.5))
	# Torsion bundle at the pivot.
	var pv := scr(pivot.x, 0.0, pivot.z)
	c.ellipse(pv.x, pv.y, 3.0, 2.0, Color("#c9b285"))

	for i in range(2, 4):
		_wheel(wheels[i], roll, wood, dark, iron)


func _wheel(w: Vector3, roll: float, wood: Array[Color], dark: Color, iron: Color, scale: float = 1.0) -> void:
	var center := scr(w.x, w.y, w.z)
	var fs := scr(1, 0, 0) - scr(0, 0, 0)
	var squash := clampf(absf(fs.x) / fs.length(), 0.3, 1.0)
	var rx := 5.0 * squash * scale
	var ry := 5.0 * scale
	c.ellipse(center.x, center.y, rx + 1.0, ry + 1.0, iron)
	c.ellipse(center.x, center.y, rx, ry, wood[1])
	for k in 3:
		var ang := roll + k * PI / 3.0
		var d := Vector2(cos(ang) * rx, sin(ang) * ry)
		c.line(roundi(center.x - d.x), roundi(center.y - d.y), roundi(center.x + d.x), roundi(center.y + d.y), dark)
	c.put(roundi(center.x), roundi(center.y), iron)


# --- Battering ram: hide-covered shed on four wheels with a swinging log ------------

func _draw_ram(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	var wood := PixelCanvas.ramp(Color("#7a5232"), 4, 0.5)
	var hide := PixelCanvas.ramp(Color("#8a6a48"), 4, 0.45)
	var dark := Color("#4a3020")
	var iron := Color("#6c737c")
	var roll := float(frame) / maxf(frames, 1) * TAU if anim == "walk" else 0.0
	var swing := SheetBuilder.sample(RAM_KEYS, frame, frames) if anim == "attack" else 0.0
	var front := _wheels_back([Vector3(-0.32, -0.26, 5), Vector3(-0.32, 0.26, 5), Vector3(0.32, -0.26, 5), Vector3(0.32, 0.26, 5)], roll, wood, dark, iron)
	for r in [-0.22, 0.22]:
		beam(Vector3(-0.5, r, 8), Vector3(0.5, r, 8), 3.0, wood[1])
	for f in [-0.42, 0.42]:
		for r in [-0.22, 0.22]:
			beam(Vector3(f, r, 8), Vector3(f, r, 22), 2.2, wood[2])
	# The log hangs inside the shed and pokes out of the front.
	beam(Vector3(-0.42 + swing, 0, 15), Vector3(0.6 + swing, 0, 15), 4.6, wood[1])
	beam(Vector3(-0.42 + swing, 0, 16.5), Vector3(0.6 + swing, 0, 16.5), 1.4, wood[3])
	var head := scr(0.62 + swing, 0, 15)
	c.ellipse(head.x, head.y, 3.4, 3.2, iron)
	c.put(roundi(head.x - 1), roundi(head.y - 1), Color("#b9c0c8"))
	# Roof slopes, the far one first; the lit one is lighter.
	var slopes := [-1.0, 1.0]
	slopes.sort_custom(func(a, b): return scr(0, a * 0.2, 26).y < scr(0, b * 0.2, 26).y)
	for sgn in slopes:
		var lit := (scr(0, sgn, 0) - scr(0, 0, 0)).x < 0.0
		poly3([Vector3(-0.52, sgn * 0.3, 21), Vector3(0.52, sgn * 0.3, 21), Vector3(0.52, 0, 32), Vector3(-0.52, 0, 32)], hide[2] if lit else hide[1])
		for k in range(1, 7):
			var f := -0.52 + k * 0.15
			beam(Vector3(f, sgn * 0.3, 21), Vector3(f, 0, 32), 1.0, hide[0])
	beam(Vector3(-0.52, 0, 32), Vector3(0.52, 0, 32), 1.6, dark)
	var pole := scr(-0.45, 0, 32)
	c.line(roundi(pole.x), roundi(pole.y), roundi(pole.x), roundi(pole.y) - 10, dark)
	c.rect(roundi(pole.x) + 1, roundi(pole.y) - 10, 5, 3, Color(p["tunic"]))
	for w in front:
		_wheel(w, roll, wood, dark, iron)


# --- Scorpion: giant crossbow on a two-wheeled stand ---------------------------------

func _draw_scorpion(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	var wood := PixelCanvas.ramp(Color("#8d6139"), 4, 0.5)
	var dark := Color("#4a3020")
	var iron := Color("#6c737c")
	var roll := float(frame) / maxf(frames, 1) * TAU if anim == "walk" else 0.0
	var pull := SheetBuilder.sample(BOLT_PULL, frame, frames) if anim == "attack" else 0.0
	var loaded := anim != "attack" or pull > 0.01 or float(frame) / frames < 0.25
	var front := _wheels_back([Vector3(-0.15, -0.25, 6), Vector3(-0.15, 0.25, 6)], roll, wood, dark, iron, 1.15)
	beam(Vector3(-0.15, 0, 8), Vector3(-0.6, 0, 2), 2.6, wood[1])
	beam(Vector3(-0.15, -0.25, 6), Vector3(-0.15, 0.25, 6), 2.0, dark)
	beam(Vector3(0.0, 0, 7), Vector3(0.0, 0, 17), 2.4, wood[2])
	beam(Vector3(-0.32, 0, 17), Vector3(0.42, 0, 18.5), 2.6, wood[2])
	var nock := Vector3(0.12 - pull * 1.6, 0, 18.5)
	for sgn in [-1.0, 1.0]:
		var tip := Vector3(0.18 - pull * 0.4, sgn * 0.36, 19.5)
		beam(Vector3(0.32, sgn * 0.04, 18.5), tip, 1.8, wood[0])
		beam(tip, nock, 0.8, Color("#e8e1d0"))
	c.ellipse(scr(0.32, 0, 18.5).x, scr(0.32, 0, 18.5).y, 2.4, 2.2, iron)
	if loaded:
		beam(nock, Vector3(0.62, 0, 19), 1.2, Color("#9a6a3c"))
		var bt := scr(0.62, 0, 19)
		c.put(roundi(bt.x), roundi(bt.y), Color("#c9d0d6"))
	for w in front:
		_wheel(w, roll, wood, dark, iron, 1.15)
	var pole := scr(-0.5, 0, 4)
	c.line(roundi(pole.x), roundi(pole.y), roundi(pole.x), roundi(pole.y) - 12, dark)
	c.rect(roundi(pole.x) + 1, roundi(pole.y) - 12, 5, 3, Color(p["tunic"]))


# --- Bombard cannon: iron tube on a wooden carriage ----------------------------------

func _draw_bombard(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	var wood := PixelCanvas.ramp(Color("#7a5232"), 4, 0.5)
	var metal := PixelCanvas.ramp(Color("#55595f"), 4, 0.5)
	var dark := Color("#3a2618")
	var iron := Color("#6c737c")
	var roll := float(frame) / maxf(frames, 1) * TAU if anim == "walk" else 0.0
	var recoil := SheetBuilder.sample(RECOIL, frame, frames, false) if anim == "attack" else 0.0
	var blast := SheetBuilder.sample(BLAST, frame, frames, false) if anim == "attack" else 0.0
	var front := _wheels_back([Vector3(0.0, -0.3, 7), Vector3(0.0, 0.3, 7)], roll, wood, dark, iron, 1.4)
	beam(Vector3(0.0 + recoil, 0, 8), Vector3(-0.65 + recoil, 0, 1), 3.2, wood[1])
	for r in [-0.13, 0.13]:
		beam(Vector3(-0.22 + recoil, r, 9), Vector3(0.25 + recoil, r, 12), 2.6, wood[2])
	beam(Vector3(-0.22 + recoil, 0, 12), Vector3(0.62 + recoil, 0, 15.5), 6.0, metal[1])
	beam(Vector3(-0.22 + recoil, 0, 14), Vector3(0.62 + recoil, 0, 17.5), 1.6, metal[3])
	for k in 3:
		var f := -0.05 + k * 0.22 + recoil
		var band := scr(f, 0, 13.5 + k * 1.2)
		c.ellipse(band.x, band.y, 1.6, 3.4, metal[0])
	var muzzle := scr(0.64 + recoil, 0, 15.6)
	c.ellipse(muzzle.x, muzzle.y, 2.8, 2.8, dark)
	if blast > 0.3:
		var ahead := scr(0.85, 0, 16) - muzzle
		var fl := muzzle + ahead * 0.6
		c.ellipse(fl.x, fl.y, 2.0 + blast, 1.6 + blast * 0.8, Color("#ffd35a"))
		c.ellipse(fl.x, fl.y, 1.0 + blast * 0.5, 0.8 + blast * 0.4, Color("#fff6c8"))
	if anim == "attack" and float(frame) / frames > 0.35:
		var t := float(frame) / frames
		var sm := muzzle + (scr(0.9, 0, 18) - muzzle) * t + Vector2(0, -t * 8.0)
		c.ellipse(sm.x, sm.y, 2.5 + t * 3.0, 2.0 + t * 2.0, Color(0.84, 0.84, 0.86, 0.8 - t * 0.5))
	for w in front:
		_wheel(w, roll, wood, dark, iron, 1.4)
	var pole := scr(-0.6 + recoil, 0, 2)
	c.line(roundi(pole.x), roundi(pole.y), roundi(pole.x), roundi(pole.y) - 12, dark)
	c.rect(roundi(pole.x) + 1, roundi(pole.y) - 12, 5, 3, Color(p["tunic"]))


# --- Trebuchet: A-frames, pivoting arm, counterweight box and sling -------------------

func _draw_trebuchet(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	var wood := PixelCanvas.ramp(Color("#8d6139"), 4, 0.5)
	var dark := Color("#4a3020")
	var iron := Color("#6c737c")
	var roll := float(frame) / maxf(frames, 1) * TAU if anim == "walk" else 0.0
	var a_deg := SheetBuilder.sample(TREB_KEYS, frame, frames, false) if anim == "attack" else -35.0
	var released := anim == "attack" and float(frame) / frames > 0.4
	var front := _wheels_back([Vector3(-0.6, -0.4, 4), Vector3(-0.6, 0.4, 4), Vector3(0.6, -0.4, 4), Vector3(0.6, 0.4, 4)], roll, wood, dark, iron, 0.75)
	for r in [-0.36, 0.36]:
		beam(Vector3(-0.72, r, 5), Vector3(0.72, r, 5), 3.0, wood[1])
	for f in [-0.6, 0.0, 0.6]:
		beam(Vector3(f, -0.36, 6), Vector3(f, 0.36, 6), 2.4, wood[2])
	var pivot := Vector3(0.0, 0.0, 62.0)
	# Far A-frame first (by screen depth of its side).
	var sides := [-0.32, 0.32]
	sides.sort_custom(func(x, y): return scr(0, x, 30).y < scr(0, y, 30).y)
	var a := deg_to_rad(a_deg)
	var long_end := Vector3(-cos(a) * 0.85, 0, pivot.z + sin(a) * 0.85 * 36.0)
	var short_end := Vector3(cos(a) * 0.28, 0, pivot.z - sin(a) * 0.28 * 36.0)
	for i in 2:
		var r: float = sides[i]
		beam(Vector3(-0.48, r, 6), Vector3(0, r, pivot.z), 3.0, wood[1] if i == 0 else wood[3])
		beam(Vector3(0.48, r, 6), Vector3(0, r, pivot.z), 3.0, wood[1] if i == 0 else wood[2])
		beam(Vector3(-0.3, r, 24), Vector3(0.3, r, 24), 1.8, wood[1])
		if i == 0:
			# Arm, counterweight and sling sit between the frames.
			beam(Vector3(0, -0.34, pivot.z), Vector3(0, 0.34, pivot.z), 2.2, iron)
			beam(short_end, long_end, 2.8, wood[2])
			var cw := scr(short_end.x, 0, short_end.z - 9)
			var ce := scr(short_end.x, 0, short_end.z)
			c.line(roundi(ce.x), roundi(ce.y), roundi(cw.x), roundi(cw.y), dark)
			c.rect(roundi(cw.x - 5), roundi(cw.y - 2), 11, 9, wood[0])
			c.rect(roundi(cw.x - 5), roundi(cw.y - 2), 11, 2, iron)
			c.rect(roundi(cw.x - 4), roundi(cw.y + 2), 9, 1, wood[2])
			var le := scr(long_end.x, 0, long_end.z)
			var sling_end: Vector2
			if a_deg < 95.0:
				sling_end = le + Vector2(0, 12.0 if a_deg < 30.0 else 7.0)
			else:
				sling_end = le + (le - scr(pivot.x, 0, pivot.z)).normalized() * 9.0
			c.line(roundi(le.x), roundi(le.y), roundi(sling_end.x), roundi(sling_end.y), Color("#c9b285"))
			if not released:
				c.shaded_blob(sling_end.x, sling_end.y, 3.0, 2.8, PixelCanvas.ramp(Color("#8f8a80"), 3, 0.5))
	var top := scr(0, sides[1], pivot.z)
	c.line(roundi(top.x), roundi(top.y), roundi(top.x), roundi(top.y) - 12, dark)
	c.rect(roundi(top.x) + 1, roundi(top.y) - 12, 6, 4, Color(p["tunic"]))
	for w in front:
		_wheel(w, roll, wood, dark, iron, 0.75)


# --- Trade cart: covered two-wheeled wagon pulled by a mule ---------------------------

func _draw_trade_cart(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	var wood := PixelCanvas.ramp(Color("#8d6139"), 4, 0.5)
	var mule := PixelCanvas.ramp(Color("#7d6650"), 4, 0.5)
	var cloth := PixelCanvas.ramp(Color(p["tunic"]).lerp(Color("#e8dcc0"), 0.45), 4, 0.45)
	var dark := Color("#3a2618")
	var iron := Color("#6c737c")
	var walking := anim == "walk"
	var phase := float(frame) / maxf(frames, 1) * TAU
	var roll := phase if walking else 0.0
	var front_wheels := _wheels_back([Vector3(-0.12, -0.28, 6), Vector3(-0.12, 0.28, 6)], roll, wood, dark, iron, 1.2)
	# Mule ahead of the cart (drawn first when it is behind on screen).
	var mule_behind := scr(0.55, 0, 0).y < scr(-0.12, 0, 0).y
	if mule_behind:
		_mule(mule, phase, walking)
	beam(Vector3(-0.45, 0, 10), Vector3(0.2, 0, 10), 7.0, wood[1])
	for r in [-0.12, 0.12]:
		beam(Vector3(0.15, r, 10), Vector3(0.48, r, 12), 1.2, wood[0])
	# Arched canopy in team-tinted canvas, with a sack of goods at the back.
	for k in 5:
		var f := -0.42 + k * 0.14
		var top := scr(f, 0, 25)
		var l := scr(f, -0.22, 13)
		var r2 := scr(f, 0.22, 13)
		c.thick_line(l.x, l.y, top.x, top.y, 3.2, cloth[2 if k % 2 == 0 else 1])
		c.thick_line(top.x, top.y, r2.x, r2.y, 3.2, cloth[1 if k % 2 == 0 else 0])
	var sack := scr(-0.5, 0, 12)
	c.shaded_blob(sack.x, sack.y, 3.2, 3.0, PixelCanvas.ramp(Color("#c9b285"), 4, 0.4))
	c.put(roundi(sack.x), roundi(sack.y - 3), Color("#e3b02a"))
	if not mule_behind:
		_mule(mule, phase, walking)
	for w in front_wheels:
		_wheel(w, roll, wood, dark, iron, 1.2)


func _mule(coat: Array[Color], phase: float, walking: bool) -> void:
	var bob := sin(phase * 2.0) * 0.8 if walking else 0.0
	for k in 4:
		var f := 0.42 if k < 2 else 0.7
		var r := -0.06 if k % 2 == 0 else 0.06
		var sw := sin(phase + (0.0 if k in [0, 3] else PI)) * 0.05 if walking else 0.0
		beam(Vector3(f, r, 9), Vector3(f + sw, r, 0), 1.6, coat[0 if r < 0 else 1])
	var rump := scr(0.42, 0, 11 + bob)
	var chest := scr(0.72, 0, 11 + bob)
	c.shaded_blob(rump.x, rump.y, 4.0, 3.6, coat)
	c.shaded_blob((rump.x + chest.x) * 0.5, (rump.y + chest.y) * 0.5, 4.0, 3.4, coat)
	c.shaded_blob(chest.x, chest.y, 3.8, 3.6, coat)
	var head := scr(0.9, 0, 17 + bob)
	c.thick_line(chest.x, chest.y - 1, head.x, head.y, 2.6, coat[2])
	c.shaded_blob(head.x, head.y, 2.2, 2.0, coat)
	c.put(roundi(head.x - 1), roundi(head.y - 3), coat[0])
	c.put(roundi(head.x + 1), roundi(head.y - 3), coat[0])


# --- Field cannon: long bronze barrel on big spoked wheels ---------------------------------

func _draw_field_cannon(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	var wood := PixelCanvas.ramp(Color("#6e4a2c"), 4, 0.5)
	var bronze := PixelCanvas.ramp(Color("#a8803a"), 4, 0.5)
	var dark := Color("#2a1d14")
	var iron := Color("#4b5058")
	var roll := float(frame) / maxf(frames, 1) * TAU if anim == "walk" else 0.0
	var recoil := SheetBuilder.sample(RECOIL, frame, frames, false) if anim == "attack" else 0.0
	var blast := SheetBuilder.sample(BLAST, frame, frames, false) if anim == "attack" else 0.0
	var front := _wheels_back([Vector3(0.0, -0.26, 8), Vector3(0.0, 0.26, 8)], roll, wood, dark, iron, 1.6)
	beam(Vector3(0.0 + recoil, 0, 9), Vector3(-0.6 + recoil, 0, 1), 3.0, wood[1])
	beam(Vector3(-0.15 + recoil, 0, 11), Vector3(0.62 + recoil, 0, 13), 3.6, bronze[1])
	beam(Vector3(-0.15 + recoil, 0, 12.4), Vector3(0.62 + recoil, 0, 14.4), 1.0, bronze[3])
	var muzzle := scr(0.64 + recoil, 0, 13)
	c.ellipse(muzzle.x, muzzle.y, 2.2, 2.2, bronze[0])
	if blast > 0.3:
		c.ellipse(muzzle.x + (scr(1, 0, 0) - scr(0, 0, 0)).normalized().x * 4.0, muzzle.y, 1.8 + blast, 1.4 + blast * 0.8, Color("#ffd35a"))
	if anim == "attack" and float(frame) / frames > 0.35:
		var t := float(frame) / frames
		c.ellipse(muzzle.x, muzzle.y - t * 9.0, 2.5 + t * 4.0, 2.0 + t * 2.5, Color(0.84, 0.84, 0.86, 0.75 - t * 0.5))
	for w in front:
		_wheel(w, roll, wood, dark, iron, 1.6)
	var pole := scr(-0.58 + recoil, 0, 1)
	c.line(roundi(pole.x), roundi(pole.y), roundi(pole.x), roundi(pole.y) - 12, dark)
	c.rect(roundi(pole.x) + 1, roundi(pole.y) - 12, 5, 3, Color(p["tunic"]))


# --- Mortar: squat iron tube on a timber bed, aimed high ------------------------------------

func _draw_mortar(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	var wood := PixelCanvas.ramp(Color("#6e4a2c"), 4, 0.5)
	var metal := PixelCanvas.ramp(Color("#4b5058"), 4, 0.5)
	var t := float(frame) / maxf(frames, 1) if anim == "attack" else 0.0
	var kick := -2.0 if anim == "attack" and t > 0.3 and t < 0.5 else 0.0
	for k in 3:
		beam(Vector3(-0.3, -0.22 + k * 0.22, 3), Vector3(0.3, -0.22 + k * 0.22, 3), 4.0, wood[1 + k % 2])
	beam(Vector3(-0.3, -0.26, 6), Vector3(0.3, -0.26, 6), 2.2, wood[3])
	var base := Vector3(-0.08, 0, 8 + kick)
	var mouth := Vector3(0.12, 0, 22 + kick)
	beam(base, mouth, 8.0, metal[1])
	beam(base + Vector3(-0.02, 0, 1), mouth + Vector3(-0.02, 0, 1), 2.0, metal[3])
	var mp := scr(mouth.x, mouth.y, mouth.z)
	c.ellipse(mp.x, mp.y, 3.6, 2.4, Color("#1c1412"))
	if anim == "attack" and t > 0.3:
		c.ellipse(mp.x, mp.y - 3.0 - t * 12.0, 3.0 + t * 5.0, 2.5 + t * 3.0, Color(0.84, 0.84, 0.86, 0.8 - t * 0.5))
		if t < 0.5:
			c.ellipse(mp.x, mp.y - 2, 2.5, 2.0, Color("#ffd35a"))
	var pole := scr(-0.3, 0.22, 3)
	c.line(roundi(pole.x), roundi(pole.y), roundi(pole.x), roundi(pole.y) - 12, Color("#2a1d14"))
	c.rect(roundi(pole.x) + 1, roundi(pole.y) - 12, 5, 3, Color(p["tunic"]))

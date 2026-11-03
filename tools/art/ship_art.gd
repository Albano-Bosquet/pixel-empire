extends RefCounted
## Procedural ship painter. A hull outline is extruded from the waterline to
## the deck and projected isometrically for each drawn direction, then masts,
## team-coloured sails, oars, deck cargo and weapons are added.
## params "model": fishing_ship, transport_ship, war_galley, fire_ship,
## demolition_ship, cannon_galleon. Local space: f forward (tiles), r right (tiles), z up (px).
## Animations: idle (bobbing), walk (bobbing + wake + oars), attack, die
## (SheetBuilder "sink": the hull tilts and slips under the waterline).

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")
const SheetBuilder := preload("res://tools/art/sheet_builder.gd")

## Hull length/beam (tiles), freeboard (px), masts, sail size (px) per model.
const MODELS := {
	"fishing_ship": {"len": 0.46, "beam": 0.17, "deck": 6.0, "masts": [0.05], "sail": [12.0, 16.0], "lateen": true},
	"transport_ship": {"len": 0.62, "beam": 0.27, "deck": 8.0, "masts": [0.0], "sail": [16.0, 20.0]},
	"war_galley": {"len": 0.72, "beam": 0.21, "deck": 8.0, "masts": [0.05], "sail": [16.0, 22.0], "oars": 6},
	"fire_ship": {"len": 0.62, "beam": 0.19, "deck": 7.0, "masts": [-0.1], "sail": [13.0, 16.0], "oars": 4},
	"demolition_ship": {"len": 0.42, "beam": 0.2, "deck": 5.0, "masts": [], "sail": [0.0, 0.0]},
	"cannon_galleon": {"len": 0.84, "beam": 0.3, "deck": 12.0, "masts": [-0.28, 0.22], "sail": [18.0, 24.0]},
	"ironclad": {"len": 0.9, "beam": 0.3, "deck": 6.0, "masts": [], "sail": [0.0, 0.0], "hull": "#4b5058"},
}
const GUN_FLASH := [0.0, 0.0, 0.0, 3.0, 2.0, 1.0, 0.4, 0.0, 0.0, 0.0]

var c: PixelCanvas
var origin := Vector2.ZERO
var fdir := Vector2.ZERO
var rdir := Vector2.ZERO


static func build_sheet(layout: Dictionary, params: Dictionary) -> Image:
	return SheetBuilder.build(layout, params, paint)


static func paint(canvas: PixelCanvas, p: Dictionary, dir: int, anim: String, frame: int, frames: int, feet: Vector2i) -> void:
	var s = load("res://tools/art/ship_art.gd").new()
	s.c = canvas
	s.origin = Vector2(feet)
	var a := SheetBuilder.dir_angle(dir)
	s.fdir = Vector2(sin(a) + 2.0 * cos(a), 2.0 * cos(a) - sin(a)).normalized()
	s.rdir = Vector2(-s.fdir.y, s.fdir.x)
	s._draw(p, anim, frame, frames)


func scr(f: float, r: float, z: float) -> Vector2:
	var g := fdir * f + rdir * r
	return origin + Vector2((g.x - g.y) * 32.0, (g.x + g.y) * 16.0 - z)


func beam(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var p := scr(a.x, a.y, a.z)
	var q := scr(b.x, b.y, b.z)
	c.thick_line(p.x, p.y, q.x, q.y, w, col)


## Hull outline at a height: pointed bow (+f), rounded stern (-f).
func _outline(m: Dictionary, z: float, inset: float = 0.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var L: float = m["len"] - inset
	var W: float = m["beam"] - inset
	var n := 16
	for i in n:
		var t := TAU * i / n
		var f := cos(t) * L
		var r := sin(t) * W
		if f > 0.0:
			r *= 1.0 - pow(f / L, 2.2) * 0.85  # taper to the bow
		out.append(Vector3(f, r, z))
	return out


func _draw(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	var model: String = p.get("model", "war_galley")
	var m: Dictionary = MODELS[model]
	var wood := PixelCanvas.ramp(Color(m.get("hull", "#7a5232" if model != "demolition_ship" else "#6a4a2c")), 5, 0.5)
	var team := PixelCanvas.ramp(Color(p["tunic"]), 4, 0.5)
	var sailc := PixelCanvas.ramp(Color("#efe3c8"), 4, 0.4)
	var phase := TAU * float(frame) / float(maxi(frames, 1))
	var moving := anim == "walk"
	var bob := sin(phase) * (1.0 if not moving else 0.6)
	var deck: float = m["deck"]

	# Water contact: foam ring and, when sailing, a wake behind the stern.
	var foam := Color(0.88, 0.95, 1.0, 0.55)
	for q in _outline(m, 0.0, -0.05):
		var sp := scr(q.x, q.y, 0)
		c.put(roundi(sp.x), roundi(sp.y + 1), foam)
	if moving:
		for k in 3:
			var back: float = -float(m["len"]) - 0.12 - k * 0.14
			var w := 0.08 + k * 0.06
			var a1 := scr(back, -w, 0)
			var a2 := scr(back, w, 0)
			if (frame + k) % 2 == 0:
				c.line(roundi(a1.x), roundi(a1.y), roundi(a2.x), roundi(a2.y), Color(0.88, 0.95, 1.0, 0.5 - k * 0.12))

	# Hull sides: quads between waterline and deck, far ones first.
	var low := _outline(m, -2.0 + bob)
	var high := _outline(m, deck + bob)
	var quads := []
	for i in low.size():
		var j := (i + 1) % low.size()
		var mid := (low[i] + low[j]) * 0.5
		quads.append({"i": i, "j": j, "depth": scr(mid.x, mid.y, 0).y})
	quads.sort_custom(func(a, b): return a["depth"] < b["depth"])
	for qd in quads:
		var i: int = qd["i"]
		var j: int = qd["j"]
		var nrm := (scr(high[j].x, high[j].y, 0) - scr(high[i].x, high[i].y, 0)).orthogonal()
		var lit := clampf(0.5 - nrm.normalized().x * 0.35 - nrm.normalized().y * 0.2, 0.0, 0.99)
		var col: Color = wood[clampi(int(lit * 4.0), 0, 4)]
		c.polygon(PackedVector2Array([scr(low[i].x, low[i].y, low[i].z), scr(low[j].x, low[j].y, low[j].z),
			scr(high[j].x, high[j].y, high[j].z), scr(high[i].x, high[i].y, high[i].z)]), col)
	# Team-coloured strake just under the gunwale.
	for i in high.size():
		var j2 := (i + 1) % high.size()
		var p0 := scr(high[i].x, high[i].y, high[i].z - 2.0)
		var p1 := scr(high[j2].x, high[j2].y, high[j2].z - 2.0)
		if (p0.y + p1.y) * 0.5 > scr(0, 0, deck + bob).y:
			c.line(roundi(p0.x), roundi(p0.y), roundi(p1.x), roundi(p1.y), team[1])
	# Deck planks.
	var deck_pts := PackedVector2Array()
	for q2 in _outline(m, deck + bob, 0.03):
		deck_pts.append(scr(q2.x, q2.y, q2.z))
	c.polygon(deck_pts, wood[3])
	for k in range(-4, 5):
		var f2: float = k * float(m["len"]) / 5.0
		var d1 := scr(f2, -float(m["beam"]) * 0.7, deck + bob)
		var d2 := scr(f2, float(m["beam"]) * 0.7, deck + bob)
		c.line(roundi(d1.x), roundi(d1.y), roundi(d2.x), roundi(d2.y), wood[2])

	# Oars (galleys): sweep with the walk cycle.
	var oars := int(m.get("oars", 0))
	for k in oars:
		var f3: float = -float(m["len"]) * 0.5 + float(m["len"]) * k / maxf(1.0, oars - 1)
		var sw := sin(phase + k * 0.4) * 0.12 if moving else 0.0
		for sgn in [-1.0, 1.0]:
			beam(Vector3(f3, sgn * float(m["beam"]) * 0.8, deck + bob - 1), Vector3(f3 + sw, sgn * (float(m["beam"]) + 0.2), 1.0), 1.0, wood[1])

	# Model-specific deck details.
	match model:
		"fishing_ship":
			var nt := scr(-0.25, 0.0, deck + bob + 2)
			for k in 4:
				c.line(roundi(nt.x - 4 + k * 2), roundi(nt.y - 2), roundi(nt.x - 2 + k * 2), roundi(nt.y + 2), Color("#c9c2b0"))
			beam(Vector3(-0.1, 0, deck + bob), Vector3(-0.42, float(m["beam"]) + 0.12, 0.0), 1.0, Color("#c9c2b0"))
		"transport_ship":
			for cr in [Vector2(-0.3, -0.08), Vector2(-0.3, 0.1), Vector2(0.3, 0.0)]:
				var cp := scr(cr.x, cr.y, deck + bob + 3)
				c.rect(roundi(cp.x - 2), roundi(cp.y - 3), 5, 5, wood[1])
				c.rect(roundi(cp.x - 2), roundi(cp.y - 3), 5, 1, wood[4])
		"war_galley":
			for k in 3:
				var ap := scr(-0.3 + k * 0.25, 0.0, deck + bob + 4)
				c.ellipse(ap.x, ap.y, 1.4, 2.2, team[2])
				c.put(roundi(ap.x), roundi(ap.y - 3), Color("#e2ad80"))
		"demolition_ship":
			for k in 3:
				var bp := scr(-0.18 + k * 0.16, 0.0, deck + bob + 3)
				c.ellipse(bp.x, bp.y, 3.0, 3.4, Color("#6e4a2c"))
				c.rect(roundi(bp.x - 3), roundi(bp.y - 1), 6, 1, Color("#3a2618"))
			var fz := scr(0.12, 0, deck + bob + 8)
			c.put(roundi(fz.x), roundi(fz.y), Color("#ffd35a") if frame % 2 == 0 else Color("#f08a2a"))
		"ironclad":
			# Funnel with a team band and drifting smoke, a gun turret forward.
			var fz := deck + bob
			beam(Vector3(-0.15, 0, fz), Vector3(-0.15, 0, fz + 16), 5.0, Color("#2a2d33"))
			var band := scr(-0.15, 0, fz + 12)
			c.rect(roundi(band.x - 2), roundi(band.y), 5, 2, team[2])
			var sm := scr(-0.2, 0, fz + 20 + float(frame % 4))
			c.ellipse(sm.x - frame % 4, sm.y, 3.0 + (frame % 4) * 0.5, 2.2, Color(0.3, 0.3, 0.32, 0.6))
			var tur := scr(0.35, 0, fz + 3)
			c.ellipse(tur.x, tur.y, 5.0, 3.5, Color("#3a3e44"))
			beam(Vector3(0.35, 0, fz + 4), Vector3(0.7, 0, fz + 4), 2.0, Color("#2a2d33"))
			if anim == "attack" and frame % 5 == 3:
				var mz := scr(0.75, 0, fz + 4)
				c.ellipse(mz.x, mz.y, 2.5, 2.0, Color("#ffd35a"))
		"cannon_galleon":
			for k in 4:
				for sgn2 in [-1.0, 1.0]:
					var gp := scr(-0.45 + k * 0.28, sgn2 * float(m["beam"]) * 0.95, deck * 0.55 + bob)
					c.rect(roundi(gp.x - 1), roundi(gp.y - 1), 2, 2, Color("#1c1412"))
			# Raised stern castle.
			beam(Vector3(-0.7, -0.18, deck + bob + 4), Vector3(-0.7, 0.18, deck + bob + 4), 3.0, wood[2])

	# Masts and sails (sails face across the hull, bellied forward).
	var sw2: float = m["sail"][0]
	var sh: float = m["sail"][1]
	for mf in m["masts"]:
		var foot := Vector3(mf, 0, deck + bob)
		var top := Vector3(mf, 0, deck + bob + sh + 10)
		beam(foot, top, 1.6, wood[0])
		var half := sw2 / 64.0
		if m.get("lateen", false):
			c.polygon(PackedVector2Array([scr(mf + 0.02, 0, deck + bob + 3), scr(mf + 0.02, 0, deck + bob + sh + 8), scr(mf + 0.28, 0, deck + bob + 4)]), team[2])
			continue
		var belly := 0.06 if moving else 0.03
		var corners := [Vector3(mf + belly, -half, deck + bob + 6), Vector3(mf + belly, half, deck + bob + 6),
			Vector3(mf, half, deck + bob + 6 + sh), Vector3(mf, -half, deck + bob + 6 + sh)]
		var pts := PackedVector2Array()
		for q3 in corners:
			pts.append(scr(q3.x, q3.y, q3.z))
		c.polygon(pts, sailc[2])
		# Team stripe across the sail.
		var s1 := scr(mf + belly * 0.5, -half, deck + bob + 6 + sh * 0.45)
		var s2 := scr(mf + belly * 0.5, half, deck + bob + 6 + sh * 0.45)
		c.thick_line(s1.x, s1.y, s2.x, s2.y, 3.0, team[2])
		beam(Vector3(mf, -half - 0.02, deck + bob + 6 + sh), Vector3(mf, half + 0.02, deck + bob + 6 + sh), 1.2, wood[1])
		var flag := scr(top.x, 0, top.z)
		c.rect(roundi(flag.x), roundi(flag.y), 4, 2, team[3])

	# Weapons in action.
	if anim == "attack":
		var t := float(frame) / maxf(frames, 1)
		match model:
			"fire_ship":
				var bow := scr(float(m["len"]) + 0.05, 0, deck + bob + 2)
				var ahead := scr(float(m["len"]) + 0.4, 0, deck + bob) - bow
				for k in 4:
					var fp := bow + ahead * (0.25 * k + 0.15 * sin(phase * 2.0 + k))
					c.ellipse(fp.x, fp.y, 2.5 - k * 0.4, 2.0 - k * 0.3, [Color("#fff6c8"), Color("#ffd35a"), Color("#f08a2a"), Color("#c0392b")][k])
			"cannon_galleon":
				var fl := SheetBuilder.sample(GUN_FLASH, frame, frames, false)
				if fl > 0.3:
					var port := scr(0.0, float(m["beam"]) + 0.05, deck * 0.55 + bob)
					c.ellipse(port.x, port.y, 1.5 + fl, 1.2 + fl * 0.7, Color("#ffd35a"))
				if t > 0.35:
					var sm := scr(0.0, float(m["beam"]) + 0.2 + t * 0.3, deck + bob + t * 10.0)
					c.ellipse(sm.x, sm.y, 2.5 + t * 3.0, 2.0 + t * 2.0, Color(0.84, 0.84, 0.86, 0.75 - t * 0.5))
			"war_galley":
				var bp2 := scr(0.1, 0.0, deck + bob + 6)
				c.put(roundi(bp2.x), roundi(bp2.y), Color("#e8e1d0"))
	elif model == "fire_ship":
		var br := scr(float(m["len"]) * 0.7, 0, deck + bob + 3)
		c.ellipse(br.x, br.y, 2.0, 1.6, Color("#4b5058"))
		c.put(roundi(br.x), roundi(br.y - 2), Color("#ffd35a") if frame % 2 == 0 else Color("#f08a2a"))

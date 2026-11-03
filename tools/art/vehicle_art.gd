extends RefCounted
## Procedural armoured-vehicle painter (Military Age): light tank, heavy tank and
## self-propelled gun. Models are convex prisms (hull, tracks, turret) projected
## like the siege painter (f forward, r right in tiles; z up in px); only the
## faces turned towards the camera are drawn, shaded with the building light.
## params "model": light_tank (default), heavy_tank, self_propelled_gun; "tunic"
## is the team colour (turret band, pennant). Animations: idle, walk (tread
## links scroll, exhaust puffs), attack (recoil, muzzle flash, smoke); "die" is
## SheetBuilder's "wreck" style.

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")
const SheetBuilder := preload("res://tools/art/sheet_builder.gd")
const SiegeArt := preload("res://tools/art/siege_art.gd")

## Same light as the building painter (grid x, grid y, up).
const LIGHT := Vector3(-0.35, 0.55, 0.75)
## Pixels of height that count as one tile when computing face normals.
const Z_PER_TILE := 24.0
## Gun recoil (tiles) and muzzle flash over the attack cycle.
const RECOIL := [0.0, 0.0, -0.12, -0.08, -0.05, -0.03, -0.01, 0.0, 0.0, 0.0]
const BLAST := [0.0, 0.0, 3.0, 1.8, 0.8, 0.2, 0.0, 0.0, 0.0, 0.0]

## Per-model dimensions: hull length/width/height, track width/height, turret
## box and gun (length, width, elevation in px per tile).
const MODELS := {
	"light_tank": {"len": 0.42, "wid": 0.22, "hull": 9.0, "track_w": 0.09, "track_h": 7.0,
		"turret": [-0.16, 0.12, 0.15, 7.0], "gun": [0.42, 1.6, 0.0], "base": "#66704a"},
	"heavy_tank": {"len": 0.56, "wid": 0.28, "hull": 11.0, "track_w": 0.11, "track_h": 9.0,
		"turret": [-0.22, 0.16, 0.2, 10.0], "gun": [0.6, 2.6, 0.0], "base": "#5a6448", "skirt": true},
	"self_propelled_gun": {"len": 0.54, "wid": 0.27, "hull": 9.0, "track_w": 0.1, "track_h": 8.0,
		"turret": [-0.5, -0.02, 0.24, 11.0], "gun": [0.78, 2.4, 14.0], "base": "#7a7050", "open_top": true},
}

var c: PixelCanvas
var origin := Vector2.ZERO
var fdir := Vector2.ZERO
var rdir := Vector2.ZERO


static func build_sheet(layout: Dictionary, params: Dictionary) -> Image:
	return SheetBuilder.build(layout, params, paint)


static func paint(canvas: PixelCanvas, p: Dictionary, dir: int, anim: String, frame: int, frames: int, feet: Vector2i) -> void:
	var s = load("res://tools/art/vehicle_art.gd").new()
	s.c = canvas
	s.origin = Vector2(feet) + Vector2(0, -2)
	s.fdir = SiegeArt.grid_dir(dir)
	s.rdir = Vector2(-s.fdir.y, s.fdir.x)
	s._draw(p, anim, frame, frames)


func scr(f: float, r: float, z: float) -> Vector2:
	var g := fdir * f + rdir * r
	return origin + Vector2((g.x - g.y) * 32.0, (g.x + g.y) * 16.0 - z)


func _grid(q: Vector3) -> Vector3:
	var g := fdir * q.x + rdir * q.y
	return Vector3(g.x, g.y, q.z / Z_PER_TILE)


## Eight-corner prism: bottom rectangle f0..f1 x r0..r1 at z0, top inset by
## `front`/`back` along f and `side` along r at z1.
func prism(f0: float, f1: float, r0: float, r1: float, z0: float, z1: float, front: float = 0.0, back: float = 0.0, side: float = 0.0) -> Array:
	var b := [Vector3(f0, r0, z0), Vector3(f1, r0, z0), Vector3(f1, r1, z0), Vector3(f0, r1, z0)]
	var t := [Vector3(f0 + back, r0 + side, z1), Vector3(f1 - front, r0 + side, z1), Vector3(f1 - front, r1 - side, z1), Vector3(f0 + back, r1 - side, z1)]
	var faces := [t, b]
	for i in 4:
		var j := (i + 1) % 4
		faces.append([b[i], b[j], t[j], t[i]])
	return faces


## Draws the camera-facing faces of a convex solid with a 5-step shade ramp.
## Returns the screen polygons drawn, keyed by face index (for decals).
func solid(faces: Array, ramp: Array[Color]) -> Dictionary:
	var centre := Vector3.ZERO
	var n := 0
	for f in faces:
		for q in f:
			centre += _grid(q)
			n += 1
	centre /= float(n)
	var view := Vector3(1.0, 1.0, 32.0 / Z_PER_TILE)
	var drawn := {}
	for i in faces.size():
		var f: Array = faces[i]
		var g0 := _grid(f[0])
		var nrm := (_grid(f[1]) - g0).cross(_grid(f[f.size() - 1]) - g0)
		if nrm.length_squared() < 0.0000001:
			continue
		var fc := Vector3.ZERO
		for q in f:
			fc += _grid(q)
		fc /= float(f.size())
		if nrm.dot(fc - centre) < 0.0:
			nrm = -nrm
		if nrm.dot(view) <= 0.0:
			continue
		var lum := clampf(nrm.normalized().dot(LIGHT.normalized()) * 0.5 + 0.5, 0.0, 0.999)
		var poly := PackedVector2Array()
		for q in f:
			poly.append(scr(q.x, q.y, q.z))
		c.polygon(poly, ramp[floori(lum * ramp.size())])
		drawn[i] = poly
	return drawn


func beam(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var p := scr(a.x, a.y, a.z)
	var q := scr(b.x, b.y, b.z)
	c.thick_line(p.x, p.y, q.x, q.y, w, col)


## One track: dark prism with road wheels and scrolling links on the outer face.
func _track(m: Dictionary, sgn: float, roll: float, near: bool) -> void:
	var L: float = m["len"] + 0.04
	var w: float = m["track_w"]
	var h: float = m["track_h"]
	var r0: float = sgn * m["wid"]
	var r1: float = r0 + sgn * w
	solid(prism(-L, L, minf(r0, r1), maxf(r0, r1), 0.0, h, 0.08, 0.06), PixelCanvas.ramp(Color("#3a3c38"), 5, 0.5))
	if not near:
		return
	var outer := r1
	var links := 9 + int(L * 10.0)
	for k in links:
		var f := -L + fposmod(float(k) / links * 2.0 * L + roll * 0.12, 2.0 * L)
		var a := scr(f, outer, 1.0)
		var b := scr(f, outer, h - 1.0)
		c.line(roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y), Color("#262724"))
	var wheels := 4 if L < 0.5 else 5
	for k in wheels:
		var wf := lerpf(-L + 0.08, L - 0.08, float(k) / (wheels - 1))
		var wp := scr(wf, outer, h * 0.45)
		c.ellipse(wp.x, wp.y, h * 0.32, h * 0.32, Color("#55574f"))
		c.put(roundi(wp.x), roundi(wp.y), Color("#8a8c84"))
	if m.get("skirt", false):
		var sk := r1 + sgn * 0.01
		solid(prism(-L + 0.04, L - 0.06, minf(sk, sk + sgn * 0.015), maxf(sk, sk + sgn * 0.015), h * 0.55, h + 2.0), PixelCanvas.ramp(Color(m["base"]), 5, 0.5))


func _draw(p: Dictionary, anim: String, frame: int, frames: int) -> void:
	var model := String(p.get("model", "light_tank"))
	var m: Dictionary = MODELS.get(model, MODELS["light_tank"])
	var body := PixelCanvas.ramp(Color(m["base"]), 5, 0.5)
	var team := PixelCanvas.ramp(Color(p["tunic"]), 4, 0.5)
	var roll := float(frame) / maxf(frames, 1) * TAU if anim == "walk" else 0.0
	var recoil := SheetBuilder.sample(RECOIL, frame, frames, false) if anim == "attack" else 0.0
	var blast := SheetBuilder.sample(BLAST, frame, frames, false) if anim == "attack" else 0.0
	var L: float = m["len"]
	var W: float = m["wid"]
	var th: float = m["track_h"]
	var hz: float = th - 2.0 + m["hull"]

	# Far track, hull, near track: the near track overlaps the hull's lower edge.
	var near_sgn := 1.0 if scr(0, 1, 0).y > scr(0, -1, 0).y else -1.0
	_track(m, -near_sgn, roll, false)
	solid(prism(-L, L, -W, W, th - 3.0, hz, 0.16, 0.06, 0.03), body)
	# Engine deck grille and exhaust at the rear.
	var deck0 := scr(-L + 0.1, -W * 0.5, hz)
	var deck1 := scr(-L + 0.1, W * 0.5, hz)
	c.line(roundi(deck0.x), roundi(deck0.y), roundi(deck1.x), roundi(deck1.y), body[0])
	if anim == "walk" and frame % 4 < 2:
		var ex := scr(-L - 0.04, W * 0.6, hz)
		c.ellipse(ex.x - 1, ex.y - 3 - frame % 4, 2.0, 1.6, Color(0.3, 0.3, 0.32, 0.55))
	_track(m, near_sgn, roll, true)

	# Turret (or the casemate of the self-propelled gun) and the gun.
	var tb: Array = m["turret"]
	var tz := hz + float(tb[3])
	var gun: Array = m["gun"]
	var mount := Vector3(float(tb[1]) - 0.02 + recoil, 0.0, hz + float(tb[3]) * 0.55)
	var muzzle := mount + Vector3(float(gun[0]), 0.0, float(gun[0]) * float(gun[2]))
	var gun_front := (fdir.x + fdir.y) > 0.0
	if not gun_front:
		_gun(mount, muzzle, gun, body, model)
	var tfaces := prism(float(tb[0]), float(tb[1]), -float(tb[2]), float(tb[2]), hz, tz, 0.07, 0.03, 0.04)
	var tdrawn := solid(tfaces, body)
	# Team band around the turret's visible side faces.
	for i in tdrawn:
		if i < 2:
			continue
		var f: Array = tfaces[i]
		var z0 := hz + float(tb[3]) * 0.35
		var z1 := hz + float(tb[3]) * 0.62
		var band := PackedVector2Array()
		for q in [f[0], f[1]]:
			band.append(scr(q.x, q.y, z0))
		for q in [f[1], f[0]]:
			band.append(scr(q.x, q.y, z1))
		c.polygon(band, team[1] if i % 2 == 0 else team[2])
	if m.get("open_top", false):
		# Open fighting compartment: dark interior and the crew's helmets.
		var inner := PackedVector2Array()
		for q in [Vector3(float(tb[0]) + 0.06, -float(tb[2]) + 0.07, tz), Vector3(float(tb[1]) - 0.1, -float(tb[2]) + 0.07, tz), Vector3(float(tb[1]) - 0.1, float(tb[2]) - 0.07, tz), Vector3(float(tb[0]) + 0.06, float(tb[2]) - 0.07, tz)]:
			inner.append(scr(q.x, q.y, q.z))
		c.polygon(inner, Color("#24261f"))
		for cr in [-0.08, 0.08]:
			var hp := scr(float(tb[0]) + 0.16, cr, tz + 1.0)
			c.ellipse(hp.x, hp.y, 1.8, 1.3, Color("#55603e"))
	else:
		# Commander's hatch.
		var hatch := scr(float(tb[0]) + 0.08, -float(tb[2]) * 0.4, tz)
		c.ellipse(hatch.x, hatch.y, 2.4, 1.4, body[1])
		c.put(roundi(hatch.x), roundi(hatch.y), body[3])
	if gun_front:
		_gun(mount, muzzle, gun, body, model)
	# Radio antenna with a team pennant.
	var ant := scr(float(tb[0]) + 0.04, float(tb[2]) * 0.6, tz)
	c.line(roundi(ant.x), roundi(ant.y), roundi(ant.x), roundi(ant.y) - 13, Color("#2a2d33"))
	c.rect(roundi(ant.x) + 1, roundi(ant.y) - 13, 4, 2, team[2])

	if blast > 0.3:
		var mp := scr(muzzle.x + 0.08, 0.0, muzzle.z)
		c.ellipse(mp.x, mp.y, 1.8 + blast, 1.4 + blast * 0.7, Color("#ffd35a"))
		c.ellipse(mp.x, mp.y, 0.8 + blast * 0.4, 0.8 + blast * 0.3, Color("#fff6c8"))
	if anim == "attack" and float(frame) / frames > 0.25:
		var t := float(frame) / frames
		var sp := scr(muzzle.x, 0.0, muzzle.z)
		c.ellipse(sp.x, sp.y - t * 8.0, 2.5 + t * 4.0, 2.0 + t * 2.5, Color(0.84, 0.84, 0.86, 0.75 - t * 0.55))


func _gun(mount: Vector3, muzzle: Vector3, gun: Array, body: Array[Color], model: String) -> void:
	beam(mount, muzzle, float(gun[1]) + 1.0, body[0])
	beam(mount + Vector3(0, 0, 0.6), muzzle + Vector3(0, 0, 0.6), maxf(1.0, float(gun[1]) - 0.4), body[2])
	if model == "heavy_tank":
		# Muzzle brake.
		beam(muzzle - Vector3(0.05, 0, 0), muzzle, float(gun[1]) + 2.4, body[0])
	var mp := scr(muzzle.x, muzzle.y, muzzle.z)
	c.put(roundi(mp.x), roundi(mp.y), Color("#16181a"))

extends RefCounted
## Isometric building painter. Buildings are composed from 3D primitives
## (boxes, hip/gable/pyramid roofs, doors, windows, crenellations) that are
## rasterised with per-pixel procedural materials and a fixed top-left light,
## then outlined like every other sprite.
##
## Local space: x, y in tiles from the footprint's top corner (0..size),
## z in pixels upwards. Screen: sx = cx + (x - y) * 32, sy = cy + (x + y - size) * 16 - z,
## where (cx, cy) is the footprint centre in the canvas = the sprite anchor.
##
## Construction stages re-run the same recipe with `z_cap` (height limit) or
## `sweep_cap` (diagonal limit, flat buildings): cut walls show their inner
## faces and a fresh top rim, half-laid roofs show bare rafters, scaffolding
## rises with the walls and stacks of materials sit on the site early on.

const PixelCanvas := preload("res://tools/art/pixel_canvas.gd")

const LIGHT := Vector3(-0.35, 0.55, 0.75)
const TOP_MARGIN := 8

const RAMPS := {
	"stone": ["#9a9184", 6], "stone_dark": ["#878891", 6], "plaster": ["#e4d4ae", 5],
	"timber": ["#5b3b22", 4], "planks": ["#8d6139", 5], "roof_red": ["#b0503a", 6],
	"roof_thatch": ["#c9a052", 6], "roof_slate": ["#5f6d80", 6], "roof_shingle": ["#7f5536", 6],
	"door": ["#57381f", 4], "glass": ["#22303f", 3], "pad": ["#8d7556", 4], "hay": ["#d8b75a", 4],
	"awning": ["#e8dcc0", 5], "awning_dark": ["#b8402e", 5], "gold_ore": ["#d9a82a", 4],
	"roof_gold": ["#d9a82a", 6], "logs": ["#7a5232", 5], "brick": ["#9a5040", 6], "concrete": ["#a29f94", 6],
	"runway": ["#7d8a5a", 4], "steel": ["#7c848a", 6], "olive": ["#66704a", 5], "sandbag": ["#b8a070", 4],
	"tarmac": ["#5f6366", 4],
}

var c: PixelCanvas
var size := 2
var cx := 0.0
var cy := 0.0
var _ramps: Dictionary = {}
var meta := {"flags": [], "smoke": [], "sails": null}
var main_box := {}
## Construction clipping (INF = complete building).
var z_cap := INF
var sweep_cap := INF
## Highest geometry z painted (set by the full-body pass, drives stage caps).
var max_z := 0.0
## Per-pixel nearness (x + y + z / 16, larger = closer to the camera) of the
## opaque geometry painted so far, so recipes need not be ordered back to front.
var zbuf := PackedFloat32Array()


## Builds all buildings in buildings_stats.json. Returns
## {name: {"canvas", "anchor", "meta"}} including `<id>_stage_<k>` (k = 1..stages)
## construction frames and the `<id>_foundation` site.
## construction: render_sprites.json "construction" ({"stages", "materials_until"}).
static func build_all(defs: Dictionary, construction: Dictionary = {}) -> Dictionary:
	var out := {}
	var script: GDScript = load("res://tools/art/building_art.gd")
	var stages := int(construction.get("stages", 8))
	var materials_until := float(construction.get("materials_until", 0.5))
	for id in defs:
		var style: String = defs[id].get("art", {}).get("style", id)
		var s: int = defs[id]["size"]
		var h := _height_for(style)
		var body = script.new()
		body._begin(s, h)
		body.call("_paint_" + style)
		body._finish_body()
		out[id] = {"canvas": body.c, "anchor": Vector2i(roundi(body.cx), roundi(body.cy)), "meta": body.meta}
		if defs[id].get("wall", false):
			# Half-tile arms joining a wall piece to each neighbour (Building.WALL_ARMS).
			for key in ["px", "nx", "py", "ny"]:
				var arm = script.new()
				arm._begin(s, h)
				arm._paint_wall_arm("logs" if style == "palisade_wall" else "stone", key)
				arm.c.outline(0.62)
				out["%s_arm_%s" % [id, key]] = {"canvas": arm.c, "anchor": Vector2i(roundi(arm.cx), roundi(arm.cy)), "meta": {}}
		var flat: bool = body.max_z < 12.0
		for k in range(1, stages + 1):
			var frac := float(k) / float(stages)
			var st = script.new()
			st._begin(s, h)
			if flat:
				st.sweep_cap = frac * 2.0 * s
			else:
				# Linear in height so every stage adds a visible slice of the building.
				st.z_cap = body.max_z * frac if k < stages else body.max_z + 1.0
			st.call("_paint_" + style)
			if not flat:
				if frac <= materials_until + 0.001:
					st._paint_materials(1.0 - frac / maxf(materials_until, 0.01))
				var top: float = st.z_cap
				st.z_cap = INF
				st._paint_scaffold(body.main_box, minf(top + 8.0, float(body.main_box.get("h", 30)) + 10.0))
			st.c.outline(0.6)
			out["%s_stage_%d" % [id, k]] = {"canvas": st.c, "anchor": Vector2i(roundi(st.cx), roundi(st.cy)), "meta": {}}
		var fd = script.new()
		fd._begin(s, 24)
		fd._paint_foundation()
		out[id + "_foundation"] = {"canvas": fd.c, "anchor": Vector2i(roundi(fd.cx), roundi(fd.cy)), "meta": {}}
	return out


static func _height_for(style: String) -> int:
	return {"farm": 20, "town_center": 120, "house": 64, "mill": 96, "storehouse": 60, "barracks": 84,
		"archery_range": 70, "stable": 74, "blacksmith": 90, "tower": 150, "castle": 150, "siege_workshop": 84, "lumber_camp": 60, "mining_camp": 60,
		"market": 110, "university": 130, "outpost": 110, "bombard_tower": 130, "monastery": 130,
		"wonder": 200, "palisade_wall": 50, "stone_wall": 60, "gate": 70, "dock": 70, "foundry": 130, "airfield": 90,
		"flak_fort": 60, "military_base": 96, "tank_factory": 130, "air_base": 100}.get(style, 90)


func _begin(s: int, height: int) -> void:
	size = s
	var w := s * 64 + 24
	var hh := s * 32 + height + TOP_MARGIN + 12
	c = PixelCanvas.new(w, hh)
	zbuf.resize(w * hh)
	zbuf.fill(-INF)
	cx = w * 0.5
	cy = TOP_MARGIN + height + s * 16
	for k in RAMPS:
		_ramps[k] = PixelCanvas.ramp(Color(RAMPS[k][0]), RAMPS[k][1], 0.5)


func _finish_body() -> void:
	c.outline(0.62)
	_ground_shadow()


# --- projection & rasterisation ---------------------------------------------

func scr(p: Vector3) -> Vector2:
	return Vector2(cx + (p.x - p.y) * 32.0, cy + (p.x + p.y - size) * 16.0 - p.z)


## Point in anchor-relative pixel coordinates (for metadata such as flags).
func rel(p: Vector3) -> Array:
	var s := scr(p)
	return [roundi(s.x - cx), roundi(s.y - cy)]


static func _hash(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


func _shade(kind: String, v: float, x: int, y: int) -> Color:
	var r: Array = _ramps[kind]
	var n := r.size()
	v += (PixelCanvas.bayer(x, y) - 0.5) * 0.14
	return r[clampi(int(v * n), 0, n - 1)]


func _lum(n: Vector3) -> float:
	return 0.45 + 0.55 * maxf(0.0, n.normalized().dot(LIGHT.normalized()))


func tri(a: Vector3, b: Vector3, d: Vector3, mat: Callable) -> void:
	var sa := scr(a)
	var sb := scr(b)
	var sd := scr(d)
	var minx := floori(minf(sa.x, minf(sb.x, sd.x)))
	var maxx := ceili(maxf(sa.x, maxf(sb.x, sd.x)))
	var miny := floori(minf(sa.y, minf(sb.y, sd.y)))
	var maxy := ceili(maxf(sa.y, maxf(sb.y, sd.y)))
	var den := (sb.y - sd.y) * (sa.x - sd.x) + (sd.x - sb.x) * (sa.y - sd.y)
	if absf(den) < 0.0001:
		return
	max_z = maxf(max_z, maxf(a.z, maxf(b.z, d.z)))
	var capped := z_cap < INF or sweep_cap < INF
	if z_cap < INF and minf(a.z, minf(b.z, d.z)) > z_cap:
		return
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var px := x + 0.5
			var py := y + 0.5
			var w1 := ((sb.y - sd.y) * (px - sd.x) + (sd.x - sb.x) * (py - sd.y)) / den
			var w2 := ((sd.y - sa.y) * (px - sd.x) + (sa.x - sd.x) * (py - sd.y)) / den
			var w3 := 1.0 - w1 - w2
			if w1 < -0.001 or w2 < -0.001 or w3 < -0.001:
				continue
			var pp := a * w1 + b * w2 + d * w3
			if capped and (pp.z > z_cap + 0.01 or pp.x + pp.y > sweep_cap):
				continue
			if not c.inside(x, y):
				continue
			# Coplanar decals (doors, windows, eave shadows) pass the small tolerance.
			var depth := pp.x + pp.y + pp.z / 16.0
			var zi := y * c.w + x
			if depth < zbuf[zi] - 0.004:
				continue
			var col: Color = mat.call(pp, x, y)
			if col.a > 0.0:
				c.put(x, y, col)
				if col.a >= 0.999:
					zbuf[zi] = depth


func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, mat: Callable) -> void:
	tri(a, b, d, mat)
	tri(a, d, e, mat)


# --- materials ----------------------------------------------------------------
## Each factory returns Callable(p: Vector3, x: int, y: int) -> Color.
## `axis` selects the along-wall coordinate: "x" for left (+y) faces, "y" for right (+x) faces.

func wall_mat(kind: String, axis: String, lum: float) -> Callable:
	return func(p: Vector3, x: int, y: int) -> Color:
		var u := (p.x if axis == "x" else p.y) * 32.0
		var v := p.z
		var tex := 0.0
		var ramp := kind
		match kind:
			"brick":
				var brow := floori(v / 3.0)
				var boff := (brow % 2) * 3.0
				tex = (_hash(brow, floorf((u + boff) / 6.0)) - 0.5) * 0.18
				if fposmod(v, 3.0) < 0.8 or fposmod(u + boff, 6.0) < 0.8:
					tex -= 0.22
			"steel", "olive":
				# Corrugated sheet: vertical ribs.
				tex = (_hash(floorf(u / 3.0), floorf(v / 9.0)) - 0.5) * 0.06
				if fposmod(u, 3.0) < 1.0:
					tex -= 0.16
			"concrete":
				tex = (_hash(floorf(u / 2.0), floorf(v / 2.0)) - 0.5) * 0.08
				if fposmod(v, 14.0) < 0.8:
					tex -= 0.15
			"stone", "stone_dark":
				var row := floori(v / 6.0)
				var off := (row % 2) * 6.0
				var col := floori((u + off) / 12.0)
				tex = (_hash(row, col) - 0.5) * 0.22
				if fposmod(v, 6.0) < 1.0 or fposmod(u + off, 12.0) < 1.0:
					tex -= 0.28
			"plaster":
				# Timber framing over plaster.
				var beam := fposmod(u, 18.0) < 2.0 or v < 2.5 or fposmod(v, 22.0) > 20.0
				var diag := absf(fposmod(u, 18.0) - fposmod(v, 18.0)) < 1.2 and fposmod(v, 22.0) < 18.0
				if beam or diag:
					ramp = "timber"
					tex = -0.05
				else:
					tex = (_hash(floorf(u / 3.0), floorf(v / 3.0)) - 0.5) * 0.08
			"planks":
				var plank := floori(u / 5.0)
				tex = (_hash(plank, 3.0) - 0.5) * 0.25
				if fposmod(u, 5.0) < 1.0:
					tex -= 0.3
				if fposmod(v + plank * 7.0, 26.0) < 1.0:
					tex -= 0.2
		# Ambient occlusion where the wall meets the ground.
		if v < 5.0:
			tex -= (1.0 - v / 5.0) * 0.16
		return _shade(ramp, lum + tex, x, y)


func roof_mat(kind: String, lum: float) -> Callable:
	return func(p: Vector3, x: int, y: int) -> Color:
		var z := p.z
		var along := (p.x - p.y) * 32.0
		var tex := 0.0
		match kind:
			"roof_red", "roof_slate":
				var row := floori(z / 4.0)
				var off := (row % 2) * 3.0
				tex = (_hash(row, floorf((along + off) / 6.0)) - 0.5) * 0.16
				if fposmod(z, 4.0) < 1.0:
					tex -= 0.3
				elif fposmod(along + off, 6.0) < 1.0:
					tex -= 0.12
			"roof_gold":
				# Gilded scale tiles with a bright glint on some of them.
				var grow := floori(z / 5.0)
				var goff := (grow % 2) * 2.5
				var tile := _hash(grow, floorf((along + goff) / 5.0))
				tex = (tile - 0.5) * 0.24
				if fposmod(z, 5.0) < 1.0:
					tex -= 0.32
				elif fposmod(along + goff, 5.0) < 1.0:
					tex -= 0.16
				elif tile > 0.86 and fposmod(z, 5.0) > 3.0:
					tex += 0.3
			"steel", "olive":
				tex = (_hash(floorf(along / 3.0), 1.0) - 0.5) * 0.06
				if fposmod(along, 3.0) < 1.0:
					tex -= 0.18
			"roof_thatch":
				tex = (_hash(floorf(along / 2.0), floorf(z / 7.0)) - 0.5) * 0.3
				if fposmod(z, 7.0) < 1.0:
					tex -= 0.2
			"awning":
				# Striped market cloth: alternate cream and red bands along the eave.
				var band := floori(fposmod(along, 1000.0) / 6.0) % 2
				var kk := "awning" if band == 0 else "awning_dark"
				return _shade(kk, lum + (_hash(floorf(along / 2.0), floorf(z / 3.0)) - 0.5) * 0.08, x, y)
			"roof_shingle":
				var row2 := floori(z / 5.0)
				tex = (_hash(row2, floorf((along + row2 * 2.0) / 4.0)) - 0.5) * 0.25
				if fposmod(z, 5.0) < 1.0:
					tex -= 0.3
		return _shade(kind, lum + tex, x, y)


func flat_mat(kind: String, lum: float, noise: float = 0.1) -> Callable:
	return func(p: Vector3, x: int, y: int) -> Color:
		var tex := (_hash(floorf(p.x * 9.0), floorf(p.y * 9.0)) - 0.5) * noise
		if noise > 0.0 and (kind == "stone" or kind == "stone_dark"):
			# Paving slabs in staggered rows, so roofs and terraces are not flat fills.
			var row := floori(p.y * 6.0)
			var su := p.x * 4.0 + (row % 2) * 0.5
			tex = (_hash(row, floorf(su)) - 0.5) * 0.2 - 0.06
			if fposmod(p.y * 6.0, 1.0) < 0.14 or fposmod(su, 1.0) < 0.08:
				tex -= 0.22
		return _shade(kind, lum + tex, x, y)


# --- primitives -----------------------------------------------------------------

## Axis-aligned box; draws the faces visible from the camera.
func box(x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, kind: String, top_kind: String = "") -> void:
	var cut := z_cap < INF and z_cap > z0 and z_cap < z1
	if cut and x1 - x0 > 0.3 and y1 - y0 > 0.3:
		# Unfinished walls: the inside of the back walls shows through the open top.
		var zc := z_cap
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, zc), Vector3(x0, y0, zc), wall_mat(kind, "x", 0.5))
		quad(Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x0, y0, zc), Vector3(x0, y1, zc), wall_mat(kind, "y", 0.4))
	if top_kind != "":
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), flat_mat(top_kind, 0.95))
	quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), wall_mat(kind, "x", 0.82))
	quad(Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), wall_mat(kind, "y", 0.58))
	if cut:
		_wall_rim(x0, y0, x1, y1, z_cap, kind)


## Fresh top course of a wall cut by the construction cap (a ring, open inside).
func _wall_rim(x0: float, y0: float, x1: float, y1: float, z: float, kind: String) -> void:
	var t := minf(0.09, minf(x1 - x0, y1 - y0) * 0.5)
	var ramp := "timber" if kind == "plaster" else kind
	quad(Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z), func(p: Vector3, x: int, y: int) -> Color:
		var edge := minf(minf(p.x - x0, p.y - y0), minf(x1 - p.x, y1 - p.y))
		if edge > t:
			return Color(0, 0, 0, 0)
		return _shade(ramp, 0.98 + (_hash(floorf(p.x * 10.0), floorf(p.y * 10.0)) - 0.5) * 0.1, x, y))


## Hip roof (ridge along `axis`); `gable` makes vertical end walls instead of hips.
## A square eave with ridge_len 0 gives a pyramid.
func roof(x0: float, y0: float, x1: float, y1: float, z: float, rise: float, kind: String,
		axis: String = "x", overhang: float = 0.15, gable: bool = false, gable_wall: String = "plaster") -> void:
	_eave_shadow(x0, y0, x1, y1, z, overhang)
	var a := Vector3(x0 - overhang, y0 - overhang, z)
	var b := Vector3(x1 + overhang, y0 - overhang, z)
	var cc := Vector3(x1 + overhang, y1 + overhang, z)
	var d := Vector3(x0 - overhang, y1 + overhang, z)
	var r1: Vector3
	var r2: Vector3
	if axis == "x":
		var ym := (a.y + d.y) * 0.5
		var inset := 0.0 if gable else (d.y - a.y) * 0.5
		r1 = Vector3(a.x + inset, ym, z + rise)
		r2 = Vector3(b.x - inset, ym, z + rise)
		if r2.x < r1.x:
			r1.x = (a.x + b.x) * 0.5
			r2.x = r1.x
		_face(a, b, r2, r1, kind)  # back (-y)
		if not gable:
			_face3(a, r1, d, kind)  # left end (-x)
		_face(d, cc, r2, r1, kind)  # front (+y)
		if gable:
			tri(Vector3(b.x - overhang, b.y + overhang, z), Vector3(cc.x - overhang, cc.y - overhang, z), r2 - Vector3(overhang, 0, 0), wall_mat(gable_wall, "y", 0.58))
		else:
			_face3(b, cc, r2, kind)  # right end (+x)
	else:
		var xm := (a.x + b.x) * 0.5
		var inset2 := 0.0 if gable else (b.x - a.x) * 0.5
		r1 = Vector3(xm, a.y + inset2, z + rise)
		r2 = Vector3(xm, d.y - inset2, z + rise)
		if r2.y < r1.y:
			r1.y = (a.y + d.y) * 0.5
			r2.y = r1.y
		_face(a, d, r2, r1, kind)  # left (-x)
		if not gable:
			_face3(a, b, r1, kind)  # back end (-y)
		_face(b, cc, r2, r1, kind)  # right (+x)
		if gable:
			tri(Vector3(d.x + overhang, d.y - overhang, z), Vector3(cc.x - overhang, cc.y - overhang, z), r2 - Vector3(0, overhang, 0), wall_mat(gable_wall, "x", 0.82))
		else:
			_face3(d, cc, r2, kind)  # front end (+y)
	if z_cap < INF and z_cap > z and z_cap < z + rise:
		_rafters(a, b, cc, d, r1, r2)


## Bare roof frame above the construction cap: rafters from each eave corner
## and along the long sides to the ridge, plus the ridge beam.
func _rafters(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, r1: Vector3, r2: Vector3) -> void:
	var col := PixelCanvas.ramp(Color("#9a6a3c"), 3, 0.4)
	var pairs := [[a, r1], [d, r1], [b, r2], [cc, r2]]
	for i in range(1, 4):
		var f := i / 4.0
		var rr := r1.lerp(r2, f)
		pairs.append([a.lerp(b, f), rr])
		pairs.append([d.lerp(cc, f), rr])
	for pr in pairs:
		var p0: Vector3 = pr[0]
		var p1: Vector3 = pr[1]
		# Only the part above the laid courses.
		var t0 := clampf((z_cap - p0.z) / maxf(0.001, p1.z - p0.z), 0.0, 1.0)
		var s0 := scr(p0.lerp(p1, t0))
		var s1 := scr(p1)
		c.thick_line(s0.x, s0.y, s1.x, s1.y, 1.6, col[1])
	var q1 := scr(r1)
	var q2 := scr(r2)
	c.thick_line(q1.x, q1.y, q2.x, q2.y, 2.0, col[2])


## Soft shadow cast by the eave on the front (+y) and right (+x) walls.
func _eave_shadow(x0: float, y0: float, x1: float, y1: float, z: float, overhang: float) -> void:
	var depth := 3.0 + overhang * 20.0
	var shadow := func(p: Vector3, x: int, y: int) -> Color:
		var k := clampf((p.z - (z - depth)) / depth, 0.0, 1.0)
		if PixelCanvas.bayer(x, y) > 0.35 + k * 0.6:
			return Color(0, 0, 0, 0)
		return Color(0.06, 0.05, 0.12, 0.30)
	quad(Vector3(x0, y1, z - depth), Vector3(x1, y1, z - depth), Vector3(x1, y1, z), Vector3(x0, y1, z), shadow)
	quad(Vector3(x1, y1, z - depth), Vector3(x1, y0, z - depth), Vector3(x1, y0, z), Vector3(x1, y1, z), shadow)


func _face(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, kind: String) -> void:
	var n := _normal(p0, p1, p2)
	quad(p0, p1, p2, p3, roof_mat(kind, _lum(n)))


func _face3(p0: Vector3, p1: Vector3, p2: Vector3, kind: String) -> void:
	tri(p0, p1, p2, roof_mat(kind, _lum(_normal(p0, p1, p2))))


func _normal(p0: Vector3, p1: Vector3, p2: Vector3) -> Vector3:
	var s := Vector3(1, 1, 1.0 / 32.0)
	var n := ((p1 - p0) * s).cross((p2 - p0) * s)
	return -n if n.z < 0.0 else n


## Door on the left (+y) face at y, spanning u0..u1 along x.
func door_l(y: float, u0: float, u1: float, z0: float, h: float) -> void:
	quad(Vector3(u0 - 0.04, y, z0), Vector3(u1 + 0.04, y, z0), Vector3(u1 + 0.04, y, z0 + h + 2), Vector3(u0 - 0.04, y, z0 + h + 2), flat_mat("timber", 0.4, 0.0))
	quad(Vector3(u0, y, z0), Vector3(u1, y, z0), Vector3(u1, y, z0 + h), Vector3(u0, y, z0 + h), wall_mat("planks", "x", 0.45))


func door_r(x: float, v0: float, v1: float, z0: float, h: float) -> void:
	quad(Vector3(x, v1 + 0.04, z0), Vector3(x, v0 - 0.04, z0), Vector3(x, v0 - 0.04, z0 + h + 2), Vector3(x, v1 + 0.04, z0 + h + 2), flat_mat("timber", 0.3, 0.0))
	quad(Vector3(x, v1, z0), Vector3(x, v0, z0), Vector3(x, v0, z0 + h), Vector3(x, v1, z0 + h), wall_mat("planks", "y", 0.35))


func window_l(y: float, u0: float, u1: float, z0: float, h: float) -> void:
	quad(Vector3(u0 - 0.03, y, z0 - 1), Vector3(u1 + 0.03, y, z0 - 1), Vector3(u1 + 0.03, y, z0 + h + 1), Vector3(u0 - 0.03, y, z0 + h + 1), flat_mat("timber", 0.55, 0.0))
	quad(Vector3(u0, y, z0), Vector3(u1, y, z0), Vector3(u1, y, z0 + h), Vector3(u0, y, z0 + h), _glass())
	var um := (u0 + u1) * 0.5
	quad(Vector3(um - 0.012, y, z0), Vector3(um + 0.012, y, z0), Vector3(um + 0.012, y, z0 + h), Vector3(um - 0.012, y, z0 + h), flat_mat("timber", 0.55, 0.0))


func window_r(x: float, v0: float, v1: float, z0: float, h: float) -> void:
	quad(Vector3(x, v1 + 0.03, z0 - 1), Vector3(x, v0 - 0.03, z0 - 1), Vector3(x, v0 - 0.03, z0 + h + 1), Vector3(x, v1 + 0.03, z0 + h + 1), flat_mat("timber", 0.4, 0.0))
	quad(Vector3(x, v1, z0), Vector3(x, v0, z0), Vector3(x, v0, z0 + h), Vector3(x, v1, z0 + h), _glass())


func _glass() -> Callable:
	return func(p: Vector3, x: int, y: int) -> Color:
		var hi := fposmod(p.z, 6.0) > 4.5
		return _shade("glass", 0.75 if hi else 0.35, x, y)


## Crenellations along the visible top edges of a box.
func battlements(x0: float, y0: float, x1: float, y1: float, z: float, kind: String = "stone", step: float = 0.22, h: float = 6.0) -> void:
	var t := 0.12
	var n := maxi(1, int((x1 - x0) / step))
	for i in n:
		if i % 2 == 0:
			box(x0 + i * step, y0, x0 + (i + 1) * step, y0 + t, z, z + h, kind, kind)
	n = maxi(1, int((y1 - y0) / step))
	for i in n:
		if i % 2 == 0:
			box(x0, y0 + i * step, x0 + t, y0 + (i + 1) * step, z, z + h, kind, kind)
	n = maxi(1, int((x1 - x0) / step))
	for i in n:
		if i % 2 == 0:
			box(x0 + i * step, y1 - t, x0 + (i + 1) * step, y1, z, z + h, kind, kind)
	n = maxi(1, int((y1 - y0) / step))
	for i in n:
		if i % 2 == 0:
			box(x1 - t, y0 + i * step, x1, y0 + (i + 1) * step, z, z + h, kind, kind)


## Packed-dirt pad with a stone kerb under the whole footprint.
func pad(inset: float = 0.05) -> void:
	var s := float(size)
	quad(Vector3(inset, inset, 0), Vector3(s - inset, inset, 0), Vector3(s - inset, s - inset, 0), Vector3(inset, s - inset, 0), func(p: Vector3, x: int, y: int) -> Color:
		var edge := minf(minf(p.x - inset, p.y - inset), minf(s - inset - p.x, s - inset - p.y))
		if edge < 0.09:
			return _shade("stone", 0.7 + (_hash(floorf(p.x * 6.0), floorf(p.y * 6.0)) - 0.5) * 0.3, x, y)
		return _shade("pad", 0.62 + (_hash(floorf(p.x * 12.0), floorf(p.y * 12.0)) - 0.5) * 0.25, x, y))


func flag_at(p: Vector3) -> void:
	meta["flags"].append(rel(p))


func smoke_at(p: Vector3) -> void:
	meta["smoke"].append(rel(p))


func _ground_shadow() -> void:
	var s := float(size)
	var col := Color(0.03, 0.05, 0.10, 0.28)
	var poly := PackedVector2Array([scr(Vector3(s, 0, 0)) + Vector2(10, 2), scr(Vector3(s, s, 0)) + Vector2(10, 5), scr(Vector3(0, s, 0)) + Vector2(6, 4), scr(Vector3(s * 0.5, s, 0))])
	var tmp := PixelCanvas.new(c.w, c.h)
	tmp.polygon(poly, Color.WHITE)
	for y in c.h:
		for x in c.w:
			if tmp.is_solid(x, y) and c.get_px(x, y).a == 0.0 and not (PixelCanvas.bayer(x, y) > 0.5 and not tmp.is_solid(x + 2, y + 1)):
				c.put(x, y, col)


# --- building recipes -----------------------------------------------------------

func _paint_house() -> void:
	pad()
	var x0 := 0.3
	var y0 := 0.35
	var x1 := 1.75
	var y1 := 1.7
	box(x0, y0, x1, y1, 0, 5, "stone")
	box(x0, y0, x1, y1, 5, 26, "plaster")
	main_box = {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "h": 26}
	door_l(y1, 0.55, 0.85, 3, 15)
	window_l(y1, 1.15, 1.45, 13, 8)
	window_r(x1, 0.65, 0.95, 13, 8)
	window_r(x1, 1.2, 1.45, 13, 8)
	box(1.25, 0.55, 1.45, 0.75, 26, 52, "stone", "stone")
	smoke_at(Vector3(1.35, 0.65, 54))
	roof(x0, y0, x1, y1, 26, 24, "roof_thatch", "x", 0.18, true)


func _paint_town_center() -> void:
	pad()
	# Back tower.
	box(0.45, 0.45, 1.45, 1.45, 0, 70, "stone")
	battlements(0.45, 0.45, 1.45, 1.45, 70)
	roof(0.45, 0.45, 1.45, 1.45, 70, 34, "roof_red", "x", 0.12)
	flag_at(Vector3(0.95, 0.95, 104))
	window_r(1.45, 0.8, 1.05, 48, 10)
	# Main hall.
	var x0 := 0.6
	var y0 := 1.3
	var x1 := 3.55
	var y1 := 3.55
	box(x0, y0, x1, y1, 0, 34, "stone")
	box(1.4, 0.6, 3.4, 1.4, 0, 34, "stone")
	main_box = {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "h": 34}
	door_l(y1, 1.65, 2.35, 4, 22)
	window_l(y1, 0.85, 1.2, 16, 10)
	window_l(y1, 2.75, 3.1, 16, 10)
	window_r(x1, 1.6, 1.95, 16, 10)
	window_r(x1, 2.5, 2.85, 16, 10)
	window_r(3.4, 0.8, 1.1, 16, 10)
	roof(1.4, 0.6, 3.4, 1.4, 34, 26, "roof_red", "x", 0.15)
	roof(x0, y0, x1, y1, 34, 38, "roof_red", "y", 0.18)
	box(2.9, 1.9, 3.15, 2.15, 50, 78, "stone", "stone")
	smoke_at(Vector3(3.02, 2.02, 80))
	flag_at(Vector3(2.07, 2.42, 74))


func _paint_mill() -> void:
	pad()
	box(0.4, 0.4, 1.7, 1.7, 0, 6, "stone")
	box(0.5, 0.5, 1.6, 1.6, 6, 52, "planks")
	main_box = {"x0": 0.5, "y0": 0.5, "x1": 1.6, "y1": 1.6, "h": 52}
	door_l(1.6, 0.8, 1.15, 6, 16)
	window_r(1.6, 0.85, 1.1, 32, 8)
	roof(0.5, 0.5, 1.6, 1.6, 52, 30, "roof_shingle", "x", 0.12)
	meta["sails"] = rel(Vector3(1.6, 1.6, 50))
	# Grain sacks.
	for i in 2:
		c.shaded_blob(scr(Vector3(1.85, 0.75 + i * 0.25, 0)).x, scr(Vector3(1.85, 0.75 + i * 0.25, 0)).y - 4, 4, 4, _ramps["hay"])


func _paint_storehouse() -> void:
	pad()
	box(0.3, 0.3, 1.7, 1.3, 0, 28, "planks")
	main_box = {"x0": 0.3, "y0": 0.3, "x1": 1.7, "y1": 1.3, "h": 28}
	door_l(1.3, 0.6, 1.1, 0, 18)
	roof(0.3, 0.3, 1.7, 1.3, 28, 16, "roof_shingle", "x", 0.16, true, "planks")
	# Log stack and ore crate in the yard.
	for i in 3:
		box(0.35 + i * 0.02, 1.45, 1.05, 1.58, i * 4.0, i * 4.0 + 4.0, "planks", "pad")
	box(1.3, 1.45, 1.65, 1.75, 0, 9, "planks", "stone_dark")


func _paint_barracks() -> void:
	pad()
	var x0 := 0.35
	var y0 := 0.5
	var x1 := 2.7
	var y1 := 2.3
	box(x0, y0, x1, y1, 0, 8, "stone")
	box(x0, y0, x1, y1, 8, 34, "plaster")
	main_box = {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "h": 34}
	door_l(y1, 1.25, 1.75, 4, 20)
	window_l(y1, 0.6, 0.9, 16, 9)
	window_l(y1, 2.1, 2.4, 16, 9)
	window_r(x1, 0.8, 1.1, 16, 9)
	window_r(x1, 1.6, 1.9, 16, 9)
	roof(x0, y0, x1, y1, 34, 30, "roof_red", "x", 0.18)
	flag_at(Vector3(1.5, 1.4, 68))
	# Weapon rack in the yard.
	for i in 4:
		var bx := 0.5 + i * 0.12
		c.line(roundi(scr(Vector3(bx, 2.6, 0)).x), roundi(scr(Vector3(bx, 2.6, 0)).y), roundi(scr(Vector3(bx, 2.6, 16)).x), roundi(scr(Vector3(bx, 2.6, 16)).y), Color("#6f6f78"))
	box(0.4, 2.55, 1.0, 2.62, 10, 12, "planks")


func _paint_archery_range() -> void:
	pad()
	box(0.3, 0.3, 2.7, 1.2, 0, 26, "planks")
	main_box = {"x0": 0.3, "y0": 0.3, "x1": 2.7, "y1": 1.2, "h": 26}
	door_l(1.2, 1.2, 1.8, 0, 18)
	roof(0.3, 0.3, 2.7, 1.2, 26, 18, "roof_thatch", "x", 0.16, true, "planks")
	flag_at(Vector3(2.5, 0.4, 56))
	# Targets.
	for i in 2:
		var p := scr(Vector3(1.0 + i * 1.1, 2.4, 10))
		box(0.95 + i * 1.1, 2.38, 1.05 + i * 1.1, 2.45, 0, 8, "planks")
		c.ellipse(p.x, p.y - 4, 7, 7, Color("#e9dcc0"))
		c.ellipse(p.x, p.y - 4, 5, 5, Color("#c0392b"))
		c.ellipse(p.x, p.y - 4, 3, 3, Color("#e9dcc0"))
		c.ellipse(p.x, p.y - 4, 1.5, 1.5, Color("#c0392b"))


func _paint_stable() -> void:
	pad()
	box(0.3, 0.4, 2.7, 1.9, 0, 28, "planks")
	main_box = {"x0": 0.3, "y0": 0.4, "x1": 2.7, "y1": 1.9, "h": 28}
	for i in 3:
		door_l(1.9, 0.5 + i * 0.75, 0.95 + i * 0.75, 0, 17)
	window_r(2.7, 0.8, 1.2, 14, 7)
	roof(0.3, 0.4, 2.7, 1.9, 28, 24, "roof_thatch", "x", 0.2)
	flag_at(Vector3(1.5, 1.15, 56))
	# Hay bales.
	box(2.2, 2.2, 2.6, 2.6, 0, 8, "plaster", "hay")
	box(2.3, 2.3, 2.55, 2.55, 8, 15, "plaster", "hay")


func _paint_blacksmith() -> void:
	pad()
	box(0.4, 0.4, 2.6, 2.1, 0, 32, "stone_dark")
	main_box = {"x0": 0.4, "y0": 0.4, "x1": 2.6, "y1": 2.1, "h": 32}
	door_l(2.1, 1.1, 1.7, 0, 22)
	window_r(2.6, 0.8, 1.1, 14, 9)
	window_r(2.6, 1.5, 1.8, 14, 9)
	roof(0.4, 0.4, 2.6, 2.1, 32, 26, "roof_slate", "x", 0.15)
	box(2.0, 0.6, 2.35, 0.95, 40, 80, "stone_dark", "stone_dark")
	smoke_at(Vector3(2.17, 0.77, 82))
	# Anvil.
	box(0.8, 2.4, 1.05, 2.55, 0, 6, "stone_dark", "stone_dark")
	box(0.72, 2.37, 1.13, 2.58, 6, 9, "stone_dark", "stone_dark")


func _paint_tower() -> void:
	pad(0.02)
	box(0.15, 0.15, 0.85, 0.85, 0, 96, "stone")
	main_box = {"x0": 0.15, "y0": 0.15, "x1": 0.85, "y1": 0.85, "h": 96}
	box(0.1, 0.1, 0.9, 0.9, 96, 104, "stone", "stone")
	battlements(0.1, 0.1, 0.9, 0.9, 104, "stone", 0.16, 6)
	roof(0.25, 0.25, 0.75, 0.75, 104, 26, "roof_slate", "x", 0.04)
	for z in [30, 60]:
		window_l(0.85, 0.45, 0.55, z, 10)
		window_r(0.85, 0.45, 0.55, z, 10)
	door_l(0.85, 0.38, 0.62, 0, 16)
	flag_at(Vector3(0.5, 0.5, 130))


func _paint_castle() -> void:
	pad()
	var k := "stone_dark"
	# Back towers and back walls.
	box(0.1, 0.1, 0.9, 0.9, 0, 66, k, k)
	battlements(0.1, 0.1, 0.9, 0.9, 66, k, 0.16)
	box(0.9, 0.3, 3.1, 0.7, 0, 46, k, k)
	battlements(0.9, 0.3, 3.1, 0.7, 46, k, 0.2)
	box(0.3, 0.9, 0.7, 3.1, 0, 46, k, k)
	battlements(0.3, 0.9, 0.7, 3.1, 46, k, 0.2)
	box(3.1, 0.1, 3.9, 0.9, 0, 66, k, k)
	battlements(3.1, 0.1, 3.9, 0.9, 66, k, 0.16)
	box(0.1, 3.1, 0.9, 3.9, 0, 66, k, k)
	battlements(0.1, 3.1, 0.9, 3.9, 66, k, 0.16)
	# Keep.
	box(1.2, 1.2, 2.8, 2.8, 0, 96, k, k)
	main_box = {"x0": 1.2, "y0": 1.2, "x1": 2.8, "y1": 2.8, "h": 96}
	battlements(1.2, 1.2, 2.8, 2.8, 96, k, 0.2)
	window_l(2.8, 1.7, 1.9, 60, 12)
	window_l(2.8, 2.2, 2.4, 60, 12)
	window_r(2.8, 1.7, 1.9, 60, 12)
	window_r(2.8, 2.2, 2.4, 60, 12)
	flag_at(Vector3(2.0, 2.0, 128))
	# Front walls and front tower.
	box(0.9, 3.3, 3.1, 3.7, 0, 46, k, k)
	battlements(0.9, 3.3, 3.1, 3.7, 46, k, 0.2)
	door_l(3.7, 1.6, 2.4, 0, 30)
	box(3.3, 0.9, 3.7, 3.1, 0, 46, k, k)
	battlements(3.3, 0.9, 3.7, 3.1, 46, k, 0.2)
	box(3.1, 3.1, 3.9, 3.9, 0, 66, k, k)
	battlements(3.1, 3.1, 3.9, 3.9, 66, k, 0.16)
	window_l(3.9, 3.4, 3.6, 40, 10)
	window_r(3.9, 3.4, 3.6, 40, 10)
	flag_at(Vector3(3.5, 3.5, 92))
	flag_at(Vector3(0.5, 0.5, 92))


func _paint_siege_workshop() -> void:
	pad()
	var x0 := 0.3
	var y0 := 0.3
	var x1 := 2.7
	var y1 := 1.65
	box(x0, y0, x1, y1, 0, 6, "stone_dark")
	box(x0, y0, x1, y1, 6, 36, "planks")
	main_box = {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "h": 36}
	door_l(y1, 0.65, 1.75, 0, 28)
	window_r(x1, 0.7, 1.0, 20, 8)
	window_r(x1, 1.2, 1.45, 20, 8)
	roof(x0, y0, x1, y1, 36, 22, "roof_shingle", "x", 0.18, true, "planks")
	flag_at(Vector3(2.5, 0.5, 62))
	# Yard: a spare wheel leaning on a sawhorse, cut beams and a winch post.
	var wc := scr(Vector3(2.2, 2.25, 10))
	c.ellipse(wc.x, wc.y, 7, 9, Color("#3a2618"))
	c.ellipse(wc.x, wc.y, 5.5, 7.5, Color("#8d6139"))
	for k in 3:
		var ang := k * PI / 3.0
		c.line(roundi(wc.x - cos(ang) * 5), roundi(wc.y - sin(ang) * 7), roundi(wc.x + cos(ang) * 5), roundi(wc.y + sin(ang) * 7), Color("#3a2618"))
	for i in 3:
		box(0.4 + i * 0.03, 2.0, 1.4, 2.12, i * 3.5, i * 3.5 + 3.5, "planks", "pad")
	box(1.65, 2.45, 1.75, 2.55, 0, 26, "planks", "planks")
	box(1.6, 2.4, 2.0, 2.6, 24, 27, "planks", "planks")


## Open timber shed on posts with log stacks and a sawhorse.
func _paint_lumber_camp() -> void:
	pad()
	for p in [Vector2(0.35, 0.35), Vector2(1.65, 0.35), Vector2(0.35, 1.2), Vector2(1.65, 1.2)]:
		box(p.x, p.y, p.x + 0.1, p.y + 0.1, 0, 26, "planks", "planks")
	box(0.3, 0.3, 1.75, 0.42, 0, 22, "planks")
	main_box = {"x0": 0.3, "y0": 0.3, "x1": 1.75, "y1": 1.3, "h": 26}
	roof(0.3, 0.3, 1.75, 1.3, 26, 14, "roof_shingle", "x", 0.14, true, "planks")
	for i in 3:
		box(0.45 + i * 0.03, 0.55, 1.55, 0.7, i * 4.0, i * 4.0 + 4.0, "planks", "pad")
	for i in 2:
		box(0.4, 1.5 + i * 0.16, 1.2, 1.64 + i * 0.16, 0, 4.5, "planks", "pad")
	box(1.4, 1.55, 1.48, 1.85, 0, 8, "planks", "planks")
	box(1.36, 1.5, 1.52, 1.9, 8, 9.5, "planks", "planks")


## Stone-footed hut with an ore cart and heaps of gold and stone.
func _paint_mining_camp() -> void:
	pad()
	box(0.3, 0.3, 1.4, 1.2, 0, 8, "stone")
	box(0.3, 0.3, 1.4, 1.2, 8, 24, "planks")
	main_box = {"x0": 0.3, "y0": 0.3, "x1": 1.4, "y1": 1.2, "h": 24}
	door_l(1.2, 0.6, 0.95, 0, 16)
	roof(0.3, 0.3, 1.4, 1.2, 24, 14, "roof_shingle", "x", 0.14, true, "planks")
	var heap := scr(Vector3(1.65, 0.6, 0))
	c.shaded_blob(heap.x, heap.y - 4, 8, 5, _ramps["stone"])
	var heap2 := scr(Vector3(1.55, 1.45, 0))
	c.shaded_blob(heap2.x, heap2.y - 4, 7, 5, _ramps["gold_ore"])
	box(0.45, 1.45, 0.95, 1.75, 4, 11, "planks", "stone_dark")
	for wx in [0.55, 0.85]:
		var w := scr(Vector3(wx, 1.75, 4))
		c.ellipse(w.x, w.y, 2.5, 3.5, Color("#3a2618"))


## Central hall with a tiled roof surrounded by striped market stalls and crates.
func _paint_market() -> void:
	pad()
	box(1.2, 1.2, 2.8, 2.8, 0, 8, "stone")
	box(1.2, 1.2, 2.8, 2.8, 8, 40, "plaster")
	main_box = {"x0": 1.2, "y0": 1.2, "x1": 2.8, "y1": 2.8, "h": 40}
	door_l(2.8, 1.7, 2.3, 4, 22)
	window_r(2.8, 1.5, 1.8, 22, 9)
	window_r(2.8, 2.2, 2.5, 22, 9)
	roof(1.2, 1.2, 2.8, 2.8, 40, 34, "roof_red", "x", 0.16)
	flag_at(Vector3(2.0, 2.0, 78))
	# Stalls: posts and striped awnings around the hall.
	for st in [Vector4(0.25, 0.3, 1.05, 0.9), Vector4(2.95, 0.3, 3.75, 0.9), Vector4(0.25, 3.05, 1.05, 3.65),
			Vector4(2.95, 3.05, 3.75, 3.65), Vector4(0.25, 1.5, 0.9, 2.5), Vector4(3.1, 1.5, 3.75, 2.5)]:
		for p in [Vector2(st.x, st.w - 0.06), Vector2(st.z - 0.06, st.w - 0.06)]:
			box(p.x, p.y, p.x + 0.06, p.y + 0.06, 0, 18, "planks", "planks")
		box(st.x, st.y, st.z, st.w, 0, 7, "planks", "hay")
		roof(st.x, st.y, st.z, st.w, 18, 8, "awning", "x", 0.08, true, "planks")
	for cr in [Vector2(1.1, 3.25), Vector2(1.35, 3.4), Vector2(2.7, 0.75)]:
		box(cr.x, cr.y, cr.x + 0.2, cr.y + 0.2, 0, 7, "planks", "planks")


## Stone college with a tall slate roof, a bell tower and many windows.
func _paint_university() -> void:
	pad()
	var x0 := 0.35
	var y0 := 0.5
	var x1 := 2.7
	var y1 := 2.45
	box(x0, y0, x1, y1, 0, 46, "stone")
	main_box = {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "h": 46}
	door_l(y1, 1.25, 1.75, 0, 24)
	for u in [0.6, 0.95, 2.05, 2.4]:
		window_l(y1, u, u + 0.18, 22, 14)
	for v in [0.8, 1.2, 1.6, 2.0]:
		window_r(x1, v, v + 0.18, 22, 14)
	roof(x0, y0, x1, y1, 46, 30, "roof_slate", "x", 0.16)
	box(0.5, 0.6, 1.0, 1.1, 46, 92, "stone", "stone")
	window_r(1.0, 0.75, 0.95, 72, 12)
	roof(0.5, 0.6, 1.0, 1.1, 92, 22, "roof_slate", "x", 0.06)
	flag_at(Vector3(0.75, 0.85, 114))


## Wooden lookout platform on stilts with a brazier.
func _paint_outpost() -> void:
	pad(0.02)
	for p in [Vector2(0.18, 0.18), Vector2(0.74, 0.18), Vector2(0.18, 0.74), Vector2(0.74, 0.74)]:
		box(p.x, p.y, p.x + 0.08, p.y + 0.08, 0, 62, "planks", "planks")
	main_box = {"x0": 0.18, "y0": 0.18, "x1": 0.82, "y1": 0.82, "h": 62}
	box(0.12, 0.12, 0.88, 0.88, 62, 66, "planks", "planks")
	box(0.12, 0.84, 0.88, 0.88, 66, 74, "planks")
	box(0.84, 0.12, 0.88, 0.88, 66, 74, "planks")
	roof(0.2, 0.2, 0.8, 0.8, 80, 16, "roof_thatch", "x", 0.06)
	for p in [Vector2(0.2, 0.2), Vector2(0.72, 0.72)]:
		box(p.x, p.y, p.x + 0.06, p.y + 0.06, 66, 80, "planks", "planks")
	var fire := scr(Vector3(0.5, 0.5, 70))
	c.ellipse(fire.x, fire.y, 2.5, 2.0, Color("#ffd35a"))
	c.put(roundi(fire.x), roundi(fire.y) - 2, Color("#f08a2a"))
	smoke_at(Vector3(0.5, 0.5, 74))


## Squat gunpowder tower: thick stone drum with a cannon in the battlements.
func _paint_bombard_tower() -> void:
	pad(0.02)
	box(0.1, 0.1, 0.9, 0.9, 0, 78, "stone_dark")
	main_box = {"x0": 0.1, "y0": 0.1, "x1": 0.9, "y1": 0.9, "h": 78}
	box(0.05, 0.05, 0.95, 0.95, 78, 86, "stone_dark", "stone_dark")
	battlements(0.05, 0.05, 0.95, 0.95, 86, "stone_dark", 0.16, 7)
	for z in [28, 54]:
		window_l(0.9, 0.42, 0.58, z, 8)
		window_r(0.9, 0.42, 0.58, z, 8)
	door_l(0.9, 0.38, 0.62, 0, 16)
	# Plain lines ignore z_cap: the cannon is only mounted once the parapet is laid.
	if z_cap > 88.0:
		var muzzle := scr(Vector3(0.95, 0.95, 90))
		var breech := scr(Vector3(0.55, 0.55, 88))
		c.thick_line(breech.x, breech.y, muzzle.x, muzzle.y, 4.0, Color("#4b5058"))
		c.ellipse(muzzle.x, muzzle.y, 2.2, 2.2, Color("#2a2d33"))
	flag_at(Vector3(0.3, 0.3, 112))


## Pointed log post (palisades).
func _log_post(x: float, y: float, w: float, h: float) -> void:
	box(x - w, y - w, x + w, y + w, 0, h, "logs", "logs")
	roof(x - w, y - w, x + w, y + w, h, 6, "roof_shingle", "x", 0.0)


## Half-tile wall arm from the tile centre towards one neighbour.
## kind: "logs" (palisade posts) or "stone" (crenellated stone wall).
func _paint_wall_arm(kind: String, key: String) -> void:
	var along_x := key == "px" or key == "nx"
	var a := 0.5
	var b := 1.02 if key in ["px", "py"] else -0.02
	var lo := minf(a, b)
	var hi := maxf(a, b)
	if kind == "logs":
		var n := 4
		for i in n:
			var t := lo + (hi - lo) * (i + 0.5) / n
			if along_x:
				_log_post(t, 0.5, 0.065, 26.0 + float(i % 2) * 3.0)
			else:
				_log_post(0.5, t, 0.065, 26.0 + float(i % 2) * 3.0)
		return
	if along_x:
		box(lo, 0.34, hi, 0.66, 0, 30, "stone", "stone")
		battlements(lo, 0.34, hi, 0.66, 30, "stone", 0.12, 5)
	else:
		box(0.34, lo, 0.66, hi, 0, 30, "stone", "stone")
		battlements(0.34, lo, 0.66, hi, 30, "stone", 0.12, 5)


func _paint_palisade_wall() -> void:
	pad(0.2)
	for p in [Vector2(0.4, 0.4), Vector2(0.6, 0.4), Vector2(0.4, 0.6), Vector2(0.6, 0.6)]:
		_log_post(p.x, p.y, 0.08, 30.0 + (3.0 if p.x > 0.5 else 0.0))
	main_box = {"x0": 0.3, "y0": 0.3, "x1": 0.7, "y1": 0.7, "h": 30}


func _paint_stone_wall() -> void:
	pad(0.18)
	box(0.26, 0.26, 0.74, 0.74, 0, 36, "stone", "stone")
	battlements(0.26, 0.26, 0.74, 0.74, 36, "stone", 0.12, 6)
	main_box = {"x0": 0.26, "y0": 0.26, "x1": 0.74, "y1": 0.74, "h": 36}


## Gatehouse: a tall stone block with a timber door on both visible faces.
func _paint_gate() -> void:
	pad(0.05)
	box(0.12, 0.12, 0.88, 0.88, 0, 46, "stone", "stone")
	main_box = {"x0": 0.12, "y0": 0.12, "x1": 0.88, "y1": 0.88, "h": 46}
	battlements(0.1, 0.1, 0.9, 0.9, 46, "stone", 0.14, 6)
	door_l(0.88, 0.3, 0.7, 0, 26)
	door_r(0.88, 0.3, 0.7, 0, 26)
	flag_at(Vector3(0.5, 0.5, 66))


## Monastery: long nave with a red roof, a round window and a bell tower.
func _paint_monastery() -> void:
	pad()
	var x0 := 0.4
	var y0 := 1.0
	var x1 := 2.65
	var y1 := 2.3
	box(x0, y0, x1, y1, 0, 6, "stone")
	box(x0, y0, x1, y1, 6, 40, "plaster")
	main_box = {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "h": 40}
	door_r(x1, 1.45, 1.85, 6, 22)
	for u in [0.7, 1.2, 1.7, 2.2]:
		window_l(y1, u, u + 0.14, 18, 14)
	var rw := scr(Vector3(x1, 1.65, 34))
	c.ellipse(rw.x, rw.y, 3.5, 4.0, Color("#3a2618"))
	c.ellipse(rw.x, rw.y, 2.4, 2.8, Color("#c9a24a"))
	c.put(roundi(rw.x), roundi(rw.y), Color("#4a7ac0"))
	roof(x0, y0, x1, y1, 40, 30, "roof_red", "x", 0.16, true, "plaster")
	box(0.45, 0.3, 1.15, 1.0, 0, 92, "stone")
	window_r(1.15, 0.5, 0.75, 70, 14)
	window_l(1.0, 0.65, 0.9, 70, 14)
	roof(0.45, 0.3, 1.15, 1.0, 92, 34, "roof_slate", "x", 0.08)
	flag_at(Vector3(0.8, 0.65, 128))
	# Cloister garden.
	for p in [Vector2(2.0, 0.45), Vector2(2.4, 0.6)]:
		var g := scr(Vector3(p.x, p.y, 0))
		c.shaded_blob(g.x, g.y - 4, 6, 5, PixelCanvas.ramp(Color("#4f8a3a"), 4, 0.5))


## Wonder: three stepped stone terraces crowned by a golden pyramid, with
## gold-capped towers at the four corners. Gilded cornices, pilasters and
## front stairs break up the big flat faces.
func _paint_wonder() -> void:
	pad()
	for p in [Vector2(0.15, 0.15), Vector2(4.15, 0.15), Vector2(0.15, 4.15), Vector2(4.15, 4.15)]:
		box(p.x, p.y, p.x + 0.7, p.y + 0.7, 0, 78, "stone")
		_cornice(p.x, p.y, p.x + 0.7, p.y + 0.7, 78)
		window_l(p.y + 0.7, p.x + 0.25, p.x + 0.45, 50, 12)
		window_r(p.x + 0.7, p.y + 0.25, p.y + 0.45, 50, 12)
		roof(p.x, p.y, p.x + 0.7, p.y + 0.7, 78, 30, "roof_gold", "x", 0.06)
	box(0.6, 0.6, 4.4, 4.4, 0, 30, "stone", "stone")
	_cornice(0.6, 0.6, 4.4, 4.4, 30)
	for u in [0.85, 1.55, 1.95, 3.05, 3.45]:
		box(u, 4.4, u + 0.1, 4.46, 0, 27, "stone_dark", "stone_dark")
		box(4.4, u, 4.46, u + 0.1, 0, 27, "stone_dark", "stone_dark")
	window_l(4.4, 1.1, 1.35, 10, 12)
	window_l(4.4, 3.65, 3.9, 10, 12)
	window_r(4.4, 1.1, 1.35, 10, 12)
	window_r(4.4, 3.65, 3.9, 10, 12)
	box(1.2, 1.2, 3.8, 3.8, 30, 62, "stone_dark", "stone")
	_cornice(1.2, 1.2, 3.8, 3.8, 62)
	for u in [1.6, 2.2, 2.8, 3.3]:
		window_l(3.8, u, u + 0.18, 40, 14)
		window_r(3.8, u, u + 0.18, 40, 14)
	box(1.8, 1.8, 3.2, 3.2, 62, 94, "stone")
	_cornice(1.8, 1.8, 3.2, 3.2, 94)
	window_l(3.2, 2.4, 2.6, 72, 12)
	window_r(3.2, 2.4, 2.6, 72, 12)
	main_box = {"x0": 0.6, "y0": 0.6, "x1": 4.4, "y1": 4.4, "h": 94}
	# Front stairs up to both gates.
	for i in 3:
		var d := 0.22 - i * 0.07
		box(2.05, 4.4, 2.95, 4.4 + d, 0, 2.0 + i * 2.0, "stone", "stone")
		box(4.4, 2.05, 4.4 + d, 2.95, 0, 2.0 + i * 2.0, "stone", "stone")
	door_l(4.4, 2.2, 2.8, 6, 22)
	door_r(4.4, 2.2, 2.8, 6, 22)
	roof(1.8, 1.8, 3.2, 3.2, 94, 60, "roof_gold", "x", 0.1)
	flag_at(Vector3(2.5, 2.5, 156))


## Gilded moulding just below a terrace's top edge.
func _cornice(x0: float, y0: float, x1: float, y1: float, z: float) -> void:
	box(x0 - 0.03, y0 - 0.03, x1 + 0.03, y1 + 0.03, z - 3.0, z, "roof_gold", "stone")


## Dock: plank deck on piles over the water, a net shed, a crane and barrels.
func _paint_dock() -> void:
	var s := float(size)
	for p in [Vector2(0.15, 0.15), Vector2(s - 0.25, 0.15), Vector2(0.15, s - 0.25), Vector2(s - 0.25, s - 0.25),
			Vector2(s * 0.5, s - 0.25), Vector2(s - 0.25, s * 0.5)]:
		box(p.x, p.y, p.x + 0.1, p.y + 0.1, -6, 4, "logs", "logs")
	box(0.1, 0.1, s - 0.1, s - 0.1, 2, 6, "planks", "planks")
	main_box = {"x0": 0.4, "y0": 0.4, "x1": 1.6, "y1": 1.3, "h": 28}
	box(0.4, 0.4, 1.6, 1.3, 6, 28, "planks")
	door_l(1.3, 0.75, 1.15, 6, 16)
	roof(0.4, 0.4, 1.6, 1.3, 28, 14, "roof_shingle", "x", 0.12, true, "planks")
	# Crane at the water corner with a hanging rope.
	box(2.3, 2.3, 2.4, 2.4, 6, 44, "logs", "logs")
	var top := scr(Vector3(2.35, 2.35, 44))
	var arm := scr(Vector3(2.85, 2.85, 42))
	c.thick_line(top.x, top.y, arm.x, arm.y, 1.6, Color("#5b3b22"))
	c.line(roundi(arm.x), roundi(arm.y), roundi(arm.x), roundi(arm.y) + 16, Color("#c9b285"))
	for p2 in [Vector2(2.0, 0.6), Vector2(2.2, 0.75), Vector2(0.6, 2.2)]:
		var bp := scr(Vector3(p2.x, p2.y, 6))
		c.ellipse(bp.x, bp.y - 3, 3.0, 3.5, Color("#6e4a2c"))
		c.rect(roundi(bp.x - 3), roundi(bp.y - 4), 6, 1, Color("#3a2618"))
	flag_at(Vector3(1.5, 0.5, 52))


## Artillery foundry: brick works with twin smoking chimneys and a cast barrel outside.
func _paint_foundry() -> void:
	pad()
	box(0.3, 0.5, 2.7, 2.3, 0, 40, "brick")
	main_box = {"x0": 0.3, "y0": 0.5, "x1": 2.7, "y1": 2.3, "h": 40}
	door_l(2.3, 1.0, 1.8, 0, 26)
	for v in [0.8, 1.3, 1.8]:
		window_r(2.7, v, v + 0.25, 20, 12)
	roof(0.3, 0.5, 2.7, 2.3, 40, 18, "roof_slate", "x", 0.12, true, "brick")
	for p in [Vector2(0.6, 0.7), Vector2(2.1, 0.7)]:
		box(p.x, p.y, p.x + 0.3, p.y + 0.3, 40, 96, "brick", "brick")
		smoke_at(Vector3(p.x + 0.15, p.y + 0.15, 98))
	var b0 := scr(Vector3(0.6, 2.65, 4))
	var b1 := scr(Vector3(1.8, 2.65, 6))
	c.thick_line(b0.x, b0.y, b1.x, b1.y, 4.0, Color("#a8803a"))
	flag_at(Vector3(1.5, 1.4, 70))


## Airfield: a mown runway with a dashed centre line, a big hangar and a windsock.
func _paint_airfield() -> void:
	var s := float(size)
	quad(Vector3(0.05, 0.05, 0), Vector3(s - 0.05, 0.05, 0), Vector3(s - 0.05, s - 0.05, 0), Vector3(0.05, s - 0.05, 0), flat_mat("pad", 0.55))
	quad(Vector3(0.2, 2.2, 0.5), Vector3(s - 0.1, 2.2, 0.5), Vector3(s - 0.1, 3.4, 0.5), Vector3(0.2, 3.4, 0.5), func(p: Vector3, x: int, y: int) -> Color:
		if absf(p.y - 2.8) < 0.04 and fposmod(p.x * 4.0, 1.0) < 0.55:
			return _shade("plaster", 0.95, x, y)
		return _shade("runway", 0.6 + (_hash(floorf(p.x * 10.0), floorf(p.y * 10.0)) - 0.5) * 0.15, x, y))
	box(0.3, 0.3, 2.3, 1.8, 0, 30, "planks")
	main_box = {"x0": 0.3, "y0": 0.3, "x1": 2.3, "y1": 1.8, "h": 30}
	door_l(1.8, 0.6, 2.0, 0, 26)
	roof(0.3, 0.3, 2.3, 1.8, 30, 22, "roof_slate", "y", 0.08, true, "planks")
	box(2.8, 0.4, 3.4, 1.0, 0, 44, "concrete", "concrete")
	window_r(3.4, 0.55, 0.85, 34, 8)
	window_l(1.0, 2.9, 3.25, 34, 8)
	flag_at(Vector3(3.6, 1.7, 40))


## Flak fort: a low concrete emplacement ringed with sandbags and twin AA guns.
func _paint_flak_fort() -> void:
	pad()
	box(0.2, 0.2, 1.8, 1.8, 0, 18, "concrete", "concrete")
	main_box = {"x0": 0.2, "y0": 0.2, "x1": 1.8, "y1": 1.8, "h": 18}
	battlements(0.2, 0.2, 1.8, 1.8, 18, "hay", 0.14, 4)
	for g in [Vector2(0.65, 0.65), Vector2(1.35, 1.35)]:
		box(g.x - 0.12, g.y - 0.12, g.x + 0.12, g.y + 0.12, 18, 24, "stone_dark", "stone_dark")
		# Plain lines ignore z_cap: barrels go up only on a finished gun mount.
		if z_cap < 24.0:
			continue
		for k in [-0.05, 0.05]:
			var a := scr(Vector3(g.x + k, g.y - k, 24))
			var b := scr(Vector3(g.x + 0.25 + k, g.y - 0.25 - k, 44))
			c.thick_line(a.x, a.y, b.x, b.y, 1.6, Color("#2a2d33"))
	door_l(1.8, 0.8, 1.2, 0, 12)
	flag_at(Vector3(1.6, 0.4, 40))


## Military base: concrete headquarters with a radio mast, a corrugated-steel
## barracks hut and a sandbag line in the yard.
func _paint_military_base() -> void:
	pad()
	# Headquarters on the left half, the hut on the back-right corner: kept
	# apart on screen so the hut never covers the HQ facade.
	var x0 := 0.25
	var y0 := 0.85
	var x1 := 1.5
	var y1 := 2.1
	box(x0, y0, x1, y1, 0, 42, "concrete", "concrete")
	main_box = {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "h": 42}
	battlements(x0, y0, x1, y1, 42, "concrete", 0.3, 3)
	door_l(y1, 0.7, 1.05, 0, 18)
	for u in [0.38, 1.17]:
		window_l(y1, u, u + 0.2, 10, 7)
	for u2 in [0.38, 0.78, 1.17]:
		window_l(y1, u2, u2 + 0.2, 28, 7)
	for v in [1.05, 1.65]:
		window_r(x1, v, v + 0.22, 10, 7)
		window_r(x1, v, v + 0.22, 28, 7)
	# Radio mast: plain lines ignore z_cap, so it only goes up on the finished roof.
	if z_cap > 86.0:
		var m0 := scr(Vector3(0.5, 1.1, 44))
		var m1 := scr(Vector3(0.5, 1.1, 86))
		c.line(roundi(m0.x), roundi(m0.y), roundi(m1.x), roundi(m1.y), Color("#3a3d42"))
		for k in 3:
			var cr := scr(Vector3(0.5, 1.1, 56 + k * 10))
			c.line(roundi(cr.x - 3 + k), roundi(cr.y), roundi(cr.x + 3 - k), roundi(cr.y), Color("#3a3d42"))
	box(2.0, 0.25, 2.75, 1.4, 0, 18, "olive")
	roof(2.0, 0.25, 2.75, 1.4, 18, 10, "olive", "y", 0.05, true, "olive")
	door_r(2.75, 0.5, 0.85, 0, 12)
	window_r(2.75, 1.05, 1.25, 7, 6)
	window_l(1.4, 2.15, 2.4, 7, 6)
	battlements(1.85, 1.85, 2.75, 2.75, 0, "sandbag", 0.12, 5)
	flag_at(Vector3(1.3, 1.0, 74))


## Tank factory: brick assembly hall under a saw-tooth steel roof, a tall
## chimney, a wide vehicle door and a concrete apron with oil drums.
func _paint_tank_factory() -> void:
	var s := float(size)
	quad(Vector3(0.05, 0.05, 0), Vector3(s - 0.05, 0.05, 0), Vector3(s - 0.05, s - 0.05, 0), Vector3(0.05, s - 0.05, 0), flat_mat("concrete", 0.5, 0.12))
	box(0.3, 0.3, 3.1, 2.5, 0, 46, "brick")
	main_box = {"x0": 0.3, "y0": 0.3, "x1": 3.1, "y1": 2.5, "h": 46}
	for i in 3:
		var x0 := 0.3 + i * (2.8 / 3.0)
		roof(x0, 0.3, x0 + 2.8 / 3.0, 2.5, 46, 18, "steel", "y", 0.03, true, "brick")
	door_l(2.5, 1.0, 2.3, 0, 32)
	for u in [0.45, 2.55]:
		window_l(2.5, u, u + 0.3, 24, 10)
	for v in [0.6, 1.2, 1.8]:
		window_r(3.1, v, v + 0.3, 24, 10)
	box(3.3, 0.45, 3.6, 0.75, 0, 112, "brick", "brick")
	smoke_at(Vector3(3.45, 0.6, 114))
	for d in [Vector2(3.3, 2.9), Vector2(3.55, 3.05), Vector2(3.35, 3.25)]:
		box(d.x, d.y, d.x + 0.16, d.y + 0.16, 0, 9, "olive", "stone_dark")
	box(0.4, 2.9, 0.9, 3.5, 0, 7, "planks", "planks")
	flag_at(Vector3(0.6, 0.5, 86))


## Air base: tarmac with a marked runway, a corrugated hangar and a concrete
## control tower with a glazed cab.
func _paint_air_base() -> void:
	var s := float(size)
	quad(Vector3(0.05, 0.05, 0), Vector3(s - 0.05, 0.05, 0), Vector3(s - 0.05, s - 0.05, 0), Vector3(0.05, s - 0.05, 0), flat_mat("tarmac", 0.6, 0.08))
	quad(Vector3(0.15, 2.45, 0.5), Vector3(s - 0.1, 2.45, 0.5), Vector3(s - 0.1, 3.55, 0.5), Vector3(0.15, 3.55, 0.5), func(p: Vector3, x: int, y: int) -> Color:
		if absf(p.y - 3.0) < 0.035 and fposmod(p.x * 4.0, 1.0) < 0.5:
			return _shade("plaster", 0.98, x, y)
		if absf(p.y - 2.5) < 0.025 or absf(p.y - 3.5) < 0.025:
			return _shade("sandbag", 0.9, x, y)
		return _shade("tarmac", 0.4 + (_hash(floorf(p.x * 10.0), floorf(p.y * 10.0)) - 0.5) * 0.1, x, y))
	box(0.3, 0.3, 2.5, 2.0, 0, 28, "steel")
	main_box = {"x0": 0.3, "y0": 0.3, "x1": 2.5, "y1": 2.0, "h": 28}
	roof(0.3, 0.3, 2.5, 2.0, 28, 20, "steel", "y", 0.06, true, "steel")
	door_l(2.0, 0.55, 2.25, 0, 24)
	box(2.95, 0.4, 3.5, 0.95, 0, 54, "concrete", "concrete")
	box(2.88, 0.33, 3.57, 1.02, 54, 64, "concrete")
	window_l(1.02, 2.92, 3.53, 56, 6)
	window_r(3.57, 0.37, 0.98, 56, 6)
	box(2.84, 0.29, 3.61, 1.06, 64, 66, "concrete", "concrete")
	window_r(3.5, 0.55, 0.8, 30, 8)
	flag_at(Vector3(3.7, 1.7, 44))


func _paint_farm() -> void:
	var s := float(size)
	var soil := PixelCanvas.ramp(Color("#7a5a38"), 4, 0.4)
	var crop := PixelCanvas.ramp(Color("#9cbf4a"), 4, 0.5)
	var wheat := PixelCanvas.ramp(Color("#d9b85a"), 4, 0.5)
	quad(Vector3(0.05, 0.05, 0), Vector3(s - 0.05, 0.05, 0), Vector3(s - 0.05, s - 0.05, 0), Vector3(0.05, s - 0.05, 0), func(p: Vector3, x: int, y: int) -> Color:
		var row := fposmod(p.x * 8.0, 1.0)
		if row < 0.45:
			return soil[1 + int(_hash(floorf(p.x * 8.0), floorf(p.y * 10.0)) * 2.0)]
		var ramp: Array[Color] = wheat if p.y > s * 0.5 else crop
		var v := 0.45 + (_hash(floorf(p.x * 16.0), floorf(p.y * 16.0)) - 0.5) * 0.5 + (row - 0.45)
		return ramp[clampi(int(v * 4.0), 0, 3)])
	# Fence posts along the visible edges.
	for i in range(0, int(s * 4) + 1):
		var t := i / 4.0
		for p in [Vector3(t, s - 0.05, 0), Vector3(s - 0.05, t, 0)]:
			var q := scr(p)
			c.rect(roundi(q.x), roundi(q.y) - 5, 1, 5, Color("#6e4a2c"))
	main_box = {"x0": 0.1, "y0": 0.1, "x1": s - 0.1, "y1": s - 0.1, "h": 6}


# --- construction stages ---------------------------------------------------------

func _paint_foundation() -> void:
	pad()
	var s := float(size)
	var stake := Color("#6e4a2c")
	for p in [Vector3(0.15, 0.15, 0), Vector3(s - 0.15, 0.15, 0), Vector3(s - 0.15, s - 0.15, 0), Vector3(0.15, s - 0.15, 0)]:
		var q := scr(p)
		c.rect(roundi(q.x), roundi(q.y) - 9, 2, 10, stake)
	var corners := [Vector3(0.15, 0.15, 6), Vector3(s - 0.15, 0.15, 6), Vector3(s - 0.15, s - 0.15, 6), Vector3(0.15, s - 0.15, 6)]
	for i in 4:
		var a := scr(corners[i])
		var b := scr(corners[(i + 1) % 4])
		c.line(roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y), Color("#e8dcc0"))
	c.outline(0.55)


## Stacked logs and dressed stone at the front corners of the site;
## `amount` (0..1) shrinks the stacks as construction uses them up.
func _paint_materials(amount: float) -> void:
	var s := float(size)
	var saved := z_cap
	z_cap = INF
	var layers := maxi(1, roundi(1.0 + amount * 2.0))
	var lx := s - 0.42
	var ly := s - 0.12
	for i in layers:
		box(lx - 0.02 * i, ly - 0.06, lx + 0.32 - 0.02 * i, ly, i * 3.5, i * 3.5 + 3.5, "planks", "pad")
	var bx := 0.12
	var by := s - 0.32
	for i in maxi(1, roundi(amount * 3.0)):
		var ox := 0.11 * (i % 2)
		var oy := 0.11 * float(i / 2)
		box(bx + ox, by + oy, bx + 0.1 + ox, by + 0.1 + oy, 0, 5, "stone", "stone")
	z_cap = saved


func _paint_scaffold(mb: Dictionary, height: float = -1.0) -> void:
	if mb.is_empty():
		return
	var pole := Color("#8a5f38")
	var plank := Color("#b08550")
	var x0: float = mb["x0"] - 0.08
	var y0: float = mb["y0"] - 0.08
	var x1: float = mb["x1"] + 0.08
	var y1: float = mb["y1"] + 0.08
	var h: float = mb["h"] + 10.0 if height < 0.0 else height
	if h < 8.0:
		return
	for p in [Vector3(x0, y1, 0), Vector3(x1, y1, 0), Vector3(x1, y0, 0), Vector3((x0 + x1) * 0.5, y1, 0), Vector3(x1, (y0 + y1) * 0.5, 0)]:
		var a := scr(p)
		var b := scr(p + Vector3(0, 0, h))
		c.thick_line(a.x, a.y, b.x, b.y, 2.0, pole)
	var z := 10.0
	while z < h:
		for seg in [[Vector3(x0, y1, z), Vector3(x1, y1, z)], [Vector3(x1, y1, z), Vector3(x1, y0, z)]]:
			var a2 := scr(seg[0])
			var b2 := scr(seg[1])
			c.thick_line(a2.x, a2.y, b2.x, b2.y, 2.0, plank)
		z += 14.0
	# Diagonal braces on the front faces.
	var d1 := scr(Vector3(x0, y1, 0))
	var d2 := scr(Vector3((x0 + x1) * 0.5, y1, h * 0.6))
	c.line(roundi(d1.x), roundi(d1.y), roundi(d2.x), roundi(d2.y), pole)
	var d3 := scr(Vector3(x1, y0, 0))
	var d4 := scr(Vector3(x1, (y0 + y1) * 0.5, h * 0.6))
	c.line(roundi(d3.x), roundi(d3.y), roundi(d4.x), roundi(d4.y), pole)


# --- animated overlays -------------------------------------------------------------

## Team flag frames: pole + waving cloth. Returns {name: {canvas, anchor}}.
static func flags(colors: Array, frames: int = 4) -> Dictionary:
	var out := {}
	for slot in colors.size():
		var base := Color(colors[slot]["primary"])
		var r := PixelCanvas.ramp(base, 4, 0.5)
		for f in frames:
			var c := PixelCanvas.new(16, 24)
			c.rect(2, 2, 1, 22, Color("#5b3b22"))
			c.put(2, 1, Color("#d8b25a"))
			for x in range(3, 15):
				var wave := sin((x - 3) * 0.6 - f * TAU / frames) * 1.4 * (x - 3) / 12.0
				var top := 3 + roundi(wave)
				for y in range(top, top + 7):
					var idx := 2 if (y - top) < 3 else 1
					if wave > 0.6:
						idx -= 1
					c.put(x, y, r[clampi(idx + (1 if x < 6 else 0), 0, 3)])
			c.outline(0.6)
			out["flag_%d_%d" % [slot, f]] = {"canvas": c, "anchor": Vector2i(2, 23)}
	return out


## Windmill sail frames (4-fold symmetric, so 8 frames cover a quarter turn).
static func sails(frames: int = 8) -> Dictionary:
	var out := {}
	var wood := Color("#6e4a2c")
	var cloth := Color("#efe3c8")
	for f in frames:
		var c := PixelCanvas.new(64, 64)
		var base_a := f * (PI * 0.5) / frames
		for k in 4:
			var a := base_a + k * PI * 0.5
			var dir := Vector2(cos(a), sin(a) * 0.85)
			var perp := Vector2(-dir.y, dir.x)
			var center := Vector2(32, 32)
			var pts := PackedVector2Array([center + dir * 6 + perp * 1, center + dir * 29 + perp * 1, center + dir * 29 + perp * 7, center + dir * 9 + perp * 7])
			c.polygon(pts, cloth)
			for t in range(8, 29, 5):
				var p0 := center + dir * t + perp
				var p1 := center + dir * t + perp * 7
				c.line(roundi(p0.x), roundi(p0.y), roundi(p1.x), roundi(p1.y), Color("#b9a27c"))
			c.thick_line(center.x, center.y, (center + dir * 30).x, (center + dir * 30).y, 1.6, wood)
		c.ellipse(32, 32, 3, 3, Color("#4a3020"))
		c.outline(0.6)
		out["sails_%d" % f] = {"canvas": c, "anchor": Vector2i(32, 32)}
	return out

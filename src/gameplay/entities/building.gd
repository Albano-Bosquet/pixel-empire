class_name Building
extends Entity
## A placed structure with a square footprint (buildings_stats.json).
##
## State table (design/game-brief.md MVP item 3; architecture.md §5):
##   FOUNDATION -> CONSTRUCTING  first builder adds progress
##   CONSTRUCTING -> COMPLETE    progress reaches 1.0 (emits `completed`)
##   any -> destroyed            hp <= 0 (Stage 3)
## While not COMPLETE the building shows pre-rendered construction stages
## (`<id>_stage_<k>`, render_sprites.json "construction"): walls rise, the roof
## frame is laid, scaffolding climbs. Consecutive stages crossfade, and dust
## puffs while villagers work and when a stage is reached.

signal completed(building: Building)
## Farms only: emitted once when the food runs out.
signal depleted(building: Building)

enum State { FOUNDATION, CONSTRUCTING, COMPLETE }

const ATLAS_TEX := "res://assets/sprites/buildings/buildings_atlas.png"
const ATLAS_JSON := "res://assets/sprites/buildings/buildings_atlas.json"
const FLAG_FRAMES := 4
const FLAG_FPS := 6.0
const SAIL_FRAMES := 8
## Wall pieces ("wall": true) connect to neighbours with half-tile arm sprites
## `<id>_arm_<key>`; arms pointing at the camera (px, py, pxpy) draw in front
## of the post, the rest behind it. Diagonal arms only link pieces that touch at a corner and
## share no orthogonal neighbour (BuildingSystem.refresh_wall_links).
const WALL_ARMS := {"px": Vector2i(1, 0), "nx": Vector2i(-1, 0), "py": Vector2i(0, 1), "ny": Vector2i(0, -1),
		"pxpy": Vector2i(1, 1), "nxny": Vector2i(-1, -1), "pxny": Vector2i(1, -1), "nxpy": Vector2i(-1, 1)}
const SAIL_FPS := 7.0

static var _atlas: Dictionary = {}
static var _tex: Texture2D
static var _img: Image

var state: State = State.FOUNDATION
var origin := Vector2i.ZERO
var size := 1
var progress := 0.0
## Training queue: unit ids; production_time is the front item's elapsed seconds.
var queue: Array[String] = []
var production_time := 0.0
var rally_point := Vector2.INF
var rally_target: Entity = null
var color_slot := 0
## Builders that worked on this building during the current tick (reset by the economy system).
var builders_this_tick := 0

## Farms: food left (farm_food when complete). Gathered like a resource node.
var amount := 0.0
var resource_type := "food"

var _body := Sprite2D.new()
## Next construction stage, faded in over the current one.
var _stage_next := Sprite2D.new()
var _foundation := Sprite2D.new()
var _stages := 8
var _stage_shown := -1
var _arms: Dictionary = {}
## Holder of the x-ray silhouettes (child of _body; created on first use).
var _xray: Node2D
var _dust: CPUParticles2D
var _puff: CPUParticles2D
## Seconds of "builders are working" left (refreshed by add_progress).
var _build_activity := 0.0
var _flags: Array[Sprite2D] = []
var _sails: Sprite2D
var _smoke: Array[CPUParticles2D] = []
var _fires: Array[CPUParticles2D] = []
## Defensive fire cooldown (CombatSystem).
var attack_timer := 0.0
var _body_rect := Rect2()
var _body_anchor := Vector2.ZERO
var _anim_time := 0.0


static func atlas_entry(name: String) -> Dictionary:
	if _atlas.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
		if raw is Dictionary:
			_atlas = raw
		_tex = load(ATLAS_TEX)
	return _atlas.get(name, {})


static func atlas_texture() -> Texture2D:
	atlas_entry("")
	return _tex


## CPU copy of the atlas for per-pixel picking (loaded on first use).
static func _atlas_image() -> Image:
	if _img == null and atlas_texture() != null:
		_img = atlas_texture().get_image()
	return _img


## Picks on the ground footprint or on an opaque pixel of a visible sprite, so
## clicks on the transparent corners of the iso artwork fall through to the
## ground or to the building behind.
func hit_test(world: Vector2) -> bool:
	if footprint().has_point(Iso.tile_of(Iso.world_to_grid(world))):
		return true
	var img := _atlas_image()
	if img == null:
		return global_pick_rect().has_point(world)
	var local := world - position
	for c in get_children():
		var sp := c as Sprite2D
		if sp == null or not sp.is_visible_in_tree() or sp.modulate.a < 0.5:
			continue
		var p := (local - sp.position - sp.offset).floor()
		if Rect2(Vector2.ZERO, sp.region_rect.size).has_point(p):
			var px := Vector2i(sp.region_rect.position + p)
			if img.get_pixelv(px).a > 0.5:
				return true
	return false


## Draw helper for UI/ghosts: region rect and anchor of a building sprite.
static func sprite_region(name: String) -> Dictionary:
	var e := atlas_entry(name)
	if e.is_empty():
		return {"rect": Rect2(0, 0, 1, 1), "anchor": Vector2.ZERO}
	var r: Array = e["rect"]
	var a: Array = e["anchor"]
	return {"rect": Rect2(r[0], r[1], r[2], r[3]), "anchor": Vector2(a[0], a[1])}


func setup(id: String, building_def: Dictionary, player_id: int, slot: int, at_origin: Vector2i, complete: bool) -> void:
	kind = Kind.BUILDING
	type_id = id
	def = building_def
	owner_id = player_id
	color_slot = slot
	size = int(def.get("size", 1))
	origin = at_origin
	max_hp = int(def.get("max_hp", 100))
	shadow_sprite = ""
	ring_sprite = ""
	_stages = maxi(1, int(_construction().get("stages", 8)))
	_add_sprite(_foundation, id + "_foundation")
	_add_sprite(_body, id)
	_add_sprite(_stage_next, id)
	var reg := sprite_region(id)
	_body_rect = reg["rect"]
	_body_anchor = reg["anchor"]
	pick_rect = Rect2(-_body_anchor, _body_rect.size).grow(-6)
	if def.get("walkable", false):
		z_index = -35  # flat fields render under units walking across them
	set_grid_pos(Vector2(origin) + Vector2(size, size) * 0.5)
	_build_overlays()
	_build_fires()
	_build_dust()
	damaged.connect(func(_e: Entity, _a: Entity, _n: int) -> void: _update_fires())
	if complete:
		progress = 1.0
		hp = max_hp
		amount = float(def.get("farm_food", 0))
		_set_state(State.COMPLETE)
	else:
		hp = 1
		_set_state(State.FOUNDATION)


func _add_sprite(sp: Sprite2D, name: String) -> void:
	var reg := sprite_region(name)
	sp.texture = atlas_texture()
	sp.region_enabled = true
	sp.region_rect = reg["rect"]
	sp.centered = false
	sp.offset = -reg["anchor"]
	add_child(sp)


func _build_overlays() -> void:
	var meta: Dictionary = atlas_entry(type_id).get("meta", {})
	for f in meta.get("flags", []):
		var sp := Sprite2D.new()
		_add_sprite(sp, "flag_%d_0" % color_slot)
		sp.position = Vector2(f[0], f[1])
		_flags.append(sp)
	if meta.get("sails") != null:
		_sails = Sprite2D.new()
		_add_sprite(_sails, "sails_0")
		var s: Array = meta["sails"]
		_sails.position = Vector2(s[0], s[1])
	for p in meta.get("smoke", []):
		var ps := CPUParticles2D.new()
		ps.position = Vector2(p[0], p[1])
		ps.amount = 10
		ps.lifetime = 2.6
		ps.direction = Vector2(0.35, -1)
		ps.spread = 12.0
		ps.gravity = Vector2(4, -6)
		ps.initial_velocity_min = 6.0
		ps.initial_velocity_max = 10.0
		ps.scale_amount_min = 2.0
		ps.scale_amount_max = 3.0
		var grad := Gradient.new()
		grad.set_color(0, Color(0.85, 0.85, 0.85, 0.75))
		grad.set_color(1, Color(0.6, 0.6, 0.65, 0.0))
		ps.color_ramp = grad
		ps.emitting = false
		add_child(ps)
		_smoke.append(ps)


func _build_fires() -> void:
	# Flames sit on the roof: between 40% and 70% of the visible height.
	var top := visual_top()
	var spread := size * 12.0
	for p in [Vector2(-spread * 0.5, top * 0.55), Vector2(spread * 0.6, top * 0.42), Vector2(0, top * 0.7)]:
		var ps := CPUParticles2D.new()
		ps.position = p
		ps.amount = 12 + size * 6
		ps.lifetime = 0.9
		ps.direction = Vector2(0, -1)
		ps.spread = 18.0
		ps.gravity = Vector2(0, -30)
		ps.initial_velocity_min = 8.0
		ps.initial_velocity_max = 18.0
		ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		ps.emission_rect_extents = Vector2(4 + size * 3, 3)
		ps.scale_amount_min = 2.0
		ps.scale_amount_max = 5.0
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.92, 0.45, 1.0))
		grad.add_point(0.35, Color(0.98, 0.45, 0.12, 0.95))
		grad.set_color(grad.get_point_count() - 1, Color(0.18, 0.16, 0.16, 0.0))
		ps.lifetime = 1.4
		ps.color_ramp = grad
		ps.emitting = false
		add_child(ps)
		_fires.append(ps)


func _construction() -> Dictionary:
	return GameData.sprites.get("construction", {})


## Work dust at the base of the site and a burst when a stage is reached.
func _build_dust() -> void:
	var extent := Vector2(size * 22.0, size * 9.0)
	_dust = _dust_emitter(6 + size * 3, 0.9, extent)
	_puff = _dust_emitter(int(_construction().get("stage_puff_particles", 14)) + size * 4, 0.8, extent)
	_puff.one_shot = true
	_puff.explosiveness = 0.85


func _dust_emitter(n: int, life: float, extent: Vector2) -> CPUParticles2D:
	var ps := CPUParticles2D.new()
	ps.amount = maxi(1, n)
	ps.lifetime = life
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ps.emission_rect_extents = extent
	ps.direction = Vector2(0, -1)
	ps.spread = 70.0
	ps.gravity = Vector2(0, 14)
	ps.initial_velocity_min = 6.0
	ps.initial_velocity_max = 16.0
	ps.scale_amount_min = 1.5
	ps.scale_amount_max = 3.5
	var grad := Gradient.new()
	grad.set_color(0, Color(0.86, 0.78, 0.62, 0.7))
	grad.set_color(1, Color(0.75, 0.68, 0.55, 0.0))
	ps.color_ramp = grad
	ps.emitting = false
	add_child(ps)
	return ps


## Burning effect scales with damage below burn_below_hp_fraction.
func _update_fires() -> void:
	var frac := float(hp) / maxf(1.0, max_hp)
	var threshold := float(GameData.combat.get("burn_below_hp_fraction", 0.5))
	for i in _fires.size():
		_fires[i].emitting = state == State.COMPLETE and frac < threshold * (1.0 - i * 0.3)


## True while the building shows flames (GameAudio loops a fire crackle).
func is_burning() -> bool:
	return not _fires.is_empty() and _fires[0].emitting


## Offset from the anchor to the top of the visible artwork (pixels, negative y).
func visual_top() -> float:
	return float(atlas_entry(type_id).get("meta", {}).get("top", -_body_anchor.y))


## Arrow spawn point: two thirds up the building.
func top_offset() -> Vector2:
	return Vector2(0, visual_top() * 0.66)


func is_farm() -> bool:
	return def.has("farm_food")


## Shows the arms towards neighbouring wall pieces (links: key -> bool).
## Arms appear once this piece is complete.
func set_wall_links(links: Dictionary) -> void:
	for key in WALL_ARMS:
		var want: bool = links.get(key, false)
		if want and not _arms.has(key):
			var sp := Sprite2D.new()
			_add_sprite(sp, "%s_arm_%s" % [type_id, key])
			if key not in ["px", "py", "pxpy"]:
				move_child(sp, _foundation.get_index() + 1)
			_arms[key] = sp
		elif not want and _arms.has(key):
			_arms[key].queue_free()
			_arms.erase(key)
	_update_arms()


func _update_arms() -> void:
	for key in _arms:
		_arms[key].visible = state == State.COMPLETE


## Screen-space (world) rectangle of the body sprite, or an empty rect while
## only the foundation shows.
func body_rect() -> Rect2:
	if not _body.visible:
		return Rect2()
	return Rect2(position + _body.offset, _body.region_rect.size)


## Shows silhouettes of the bodies behind this building (OcclusionXray), each
## {"sprite": Sprite2D, "at": world position of that sprite's node, "tint": Color}.
## They live under the body sprite, which clips them to its opaque pixels.
func set_xray(items: Array, material: Material) -> void:
	if items.is_empty() and _xray == null:
		return
	if _xray == null:
		_xray = Node2D.new()
		_body.add_child(_xray)
	var pool := _xray.get_children()
	for i in items.size():
		var sp: Sprite2D
		if i < pool.size():
			sp = pool[i]
		else:
			sp = Sprite2D.new()
			sp.centered = false
			sp.material = material
			_xray.add_child(sp)
		var src: Sprite2D = items[i]["sprite"]
		sp.texture = src.texture
		sp.region_enabled = src.region_enabled
		sp.region_rect = src.region_rect
		sp.hframes = src.hframes
		sp.vframes = src.vframes
		sp.frame = src.frame
		sp.flip_h = src.flip_h
		sp.offset = src.offset
		sp.position = items[i]["at"] + src.position - position
		sp.modulate = items[i]["tint"]
		sp.visible = true
	for i in range(items.size(), pool.size()):
		pool[i].visible = false
	_body.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW if not items.is_empty() else CanvasItem.CLIP_CHILDREN_DISABLED


## Farm harvesting API (mirrors ResourceNode).
func is_depleted() -> bool:
	return not is_farm() or not is_complete() or amount <= 0.0


func remaining() -> int:
	return ceili(amount)


func take(wanted: float) -> float:
	if is_depleted():
		return 0.0
	var got := minf(wanted, amount)
	amount -= got
	if amount <= 0.0:
		amount = 0.0
		depleted.emit(self)
	return got


func is_complete() -> bool:
	return state == State.COMPLETE


func footprint() -> Rect2i:
	return Rect2i(origin, Vector2i(size, size))


## Closest point of the footprint to `p` (grid space); distance to it is the reach test.
func closest_point(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, origin.x, origin.x + size), clampf(p.y, origin.y, origin.y + size))


## Drop-off test; ships use "ship_drop_off" (docks), land workers "drop_off".
func accepts(resource: String, by_ship: bool = false) -> bool:
	return is_complete() and def.get("ship_drop_off" if by_ship else "drop_off", []).has(resource)


## Adds construction progress (0..1 fraction). HP grows proportionally.
func add_progress(work: float) -> void:
	if state == State.COMPLETE:
		return
	if state == State.FOUNDATION:
		_set_state(State.CONSTRUCTING)
	var before := progress
	progress = minf(1.0, progress + work)
	if work > 0.0:
		_build_activity = float(_construction().get("dust_seconds", 0.35))
	hp = mini(max_hp, hp + roundi((progress - before) * (max_hp - 1)))
	_update_reveal()
	if progress >= 1.0:
		hp = max_hp
		amount = float(def.get("farm_food", 0))
		_set_state(State.COMPLETE)
		_puff.restart()
		completed.emit(self)
		EventBus.sound_at.emit("building_done", position)


func _set_state(s: State) -> void:
	state = s
	_foundation.visible = s != State.COMPLETE
	_body.visible = s != State.FOUNDATION
	for f in _flags:
		f.visible = s == State.COMPLETE
	_update_arms()
	if _sails:
		_sails.visible = s == State.COMPLETE
	for ps in _smoke:
		ps.emitting = s == State.COMPLETE
	_update_reveal()
	queue_redraw()


## Current construction frame (0 = bare site, 1.._stages = stage sprites) and
## the fade towards the next one, from `progress`.
static func stage_at(p: float, stages: int, fade_start: float) -> Dictionary:
	var sp := clampf(p, 0.0, 1.0) * stages
	var idx := mini(floori(sp), stages)
	var local := sp - idx
	var fade := 0.0
	if idx < stages and local > fade_start:
		fade = smoothstep(fade_start, 1.0, local)
	return {"index": idx, "fade": fade}


## Shows the construction stage for the current progress.
func _update_reveal() -> void:
	if state == State.COMPLETE:
		_show_region(_body, type_id)
		_body.modulate.a = 1.0
		_stage_next.visible = false
		_stage_shown = -1
		return
	var st := stage_at(progress, _stages, float(_construction().get("fade_start", 0.55)))
	var idx: int = st["index"]
	if idx != _stage_shown:
		if _stage_shown >= 0 and idx > _stage_shown and _puff:
			_puff.restart()
		_stage_shown = idx
		if idx > 0:
			_show_region(_body, "%s_stage_%d" % [type_id, idx])
		_show_region(_stage_next, "%s_stage_%d" % [type_id, mini(idx + 1, _stages)])
	# Set every update: _set_state shows the body on FOUNDATION -> CONSTRUCTING
	# while it still holds the finished sprite, before stage 1 is reached.
	_body.visible = idx > 0
	var fade: float = st["fade"]
	_stage_next.visible = fade > 0.0
	_stage_next.modulate.a = fade


func _show_region(sp: Sprite2D, name: String) -> void:
	var reg := sprite_region(name)
	sp.region_rect = reg["rect"]
	sp.offset = -reg["anchor"]


## Called every frame by BuildingSystem for cosmetic animation.
func animate(delta: float) -> void:
	since_damaged += delta
	if state != State.COMPLETE:
		_build_activity -= delta
		_dust.emitting = _build_activity > 0.0 and state == State.CONSTRUCTING
		return
	if _dust.emitting:
		_dust.emitting = false
	_anim_time += delta
	var ff := int(_anim_time * FLAG_FPS) % FLAG_FRAMES
	for f in _flags:
		f.region_rect = sprite_region("flag_%d_%d" % [color_slot, ff])["rect"]
	if _sails:
		_sails.region_rect = sprite_region("sails_%d" % (int(_anim_time * SAIL_FPS) % SAIL_FRAMES))["rect"]


func _draw() -> void:
	if selected:
		# Footprint diamond outline as the selection indicator.
		var s := float(size)
		var pts := PackedVector2Array()
		for p in [Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s), Vector2(-s, -s)]:
			pts.append(Iso.grid_to_world(p * 0.5))
		draw_polyline(pts, ring_color, 1.0)
	if rally_point != Vector2.INF and selected:
		var rp := Iso.grid_to_world(rally_point) - position
		draw_line(Vector2.ZERO, rp, Color(1, 1, 1, 0.35), 1.0)
		var flag := sprite_region("flag_%d_0" % color_slot)
		draw_texture_rect_region(atlas_texture(), Rect2(rp - flag["anchor"], flag["rect"].size), flag["rect"])

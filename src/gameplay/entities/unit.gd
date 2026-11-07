class_name Unit
extends Entity
## A mobile unit. Holds state; behaviour is driven by UnitSystem.
##
## Two layers: locomotion `state` (below) and an optional economic `task`
## driven by EconomySystem (gather / build / repair / drop; see its header).
## Locomotion state table (docs/architecture/architecture.md §5):
##   IDLE   -> MOVING  on await_path() (path requested) or order_path() with a non-empty path
##   MOVING -> IDLE    on arrival, path exhausted, empty path result, or stop()

enum State { IDLE, MOVING }

## Animations whose tool strikes make a sound (audio_settings.json "work").
const WORK_ANIMS := ["chop", "mine", "build", "farm", "forage"]

var state: State = State.IDLE
var speed := 1.5
var radius := 0.22
var sight := 4
var path := PackedVector2Array()
var path_index := 0
## True while a path request is queued in UnitSystem.
var path_pending := false
var velocity := Vector2.ZERO
## Drawn direction (Iso index); turns towards `facing_target` one step at a time.
var facing := 0
var facing_target := 0
var stuck_time := 0.0
## Economic task, e.g. {"type": "gather", "node": ResourceNode, "phase": "to_node"}; empty = none.
var task: Dictionary = {}
var carry_type := ""
var carry_amount := 0.0
## Animation played while standing still and working ("" = idle).
var work_anim := ""
var is_worker := false
var color_slot := 0
## Cached from `def`: the per-tick loops read these for every unit.
var naval := false
var loiter := false
## Ticks an undisturbed standing unit skips its separation check (UnitSystem).
var rest_ticks := 0

var range_bonus := 0.0

# --- Naval (NavalSystem) ---
## Transport this unit is riding in (null on land).
var aboard: Unit = null
## Passengers of a transport ship.
var cargo: Array[Unit] = []

# --- Air (AirSystem) ---
## Shots left before rearming (-1 = unlimited).
var ammo := -1
## Flying height in pixels (0 for ground and sea units).
var altitude := 0.0
## Pixels below `altitude` the plane currently flies (attack dives, AirSystem).
var flight_dip := 0.0
## Speed multiplier while flying (faster in a dive, slower in the climb).
var air_speed_factor := 1.0
## Last flight velocity (tiles/s); planes keep it between two legs (UnitSystem).
var cruise := Vector2.ZERO

# --- Combat (driven by CombatSystem) ---
## Current attack target; null when not fighting.
var target: Entity = null
## Where an auto-engaged unit returns after a fight (INF = no guard post).
var guard_pos := Vector2.INF
## Attack-move destination (INF = none): engage enemies met on the way.
var attack_move_goal := Vector2.INF
## "aggressive" (chase), "defensive" (short chase), "stand" (never move to attack).
var stance := "aggressive"
var attack_timer := 0.0
var hit_timer := -1.0
var repath_timer := 0.0
var corpse_timer := 0.0
## While > 0 the current one-shot animation (attack) is not interrupted.
var anim_lock := 0.0
var last_progress_dist := INF

var _sprite := Sprite2D.new()
var _layout: Dictionary
var _anim_rows: Dictionary = {}  # anim name -> {"row": int, "frames": int, "fps": float}
var _anim := ""
var _frame_w := 48
var _anchor := Vector2(24, 44)
var _anim_time := 0.0
var _turn_time := 0.0
## Last work-animation cycle that made a sound (tool strikes, see _work_sound).
var _work_cycle := -1
# The playing animation, cached from _anim_rows (0 frames = none).
var _row := 0
var _frames := 0
var _fps := 1.0
var _is_work_anim := false
var _is_walk_anim := false
# What the sprite shows now: its setters redraw even when nothing changes.
var _shown_frame := -1
var _shown_flip := false
var _walk_rate_min := 0.35
var _walk_rate_max := 1.4
var _turn_step := 0.025
# World positions of the last two simulation ticks: the simulation runs slower
# than the screen, so `position` blends between them on every drawn frame.
var _glide_from := Vector2.ZERO
var _glide_to := Vector2.ZERO
## Physics tick of the last glide_to(); -1 = not gliding.
var _glide_tick := -1


func setup(id: String, unit_def: Dictionary, player_id: int, color_slot_arg: int, at: Vector2) -> void:
	kind = Kind.UNIT
	type_id = id
	def = unit_def
	owner_id = player_id
	color_slot = color_slot_arg
	max_hp = int(def.get("max_hp", 10))
	hp = max_hp
	speed = float(def.get("speed", 1.5))
	radius = float(def.get("radius", 0.22))
	sight = int(def.get("sight", 4))
	is_worker = bool(def.get("worker", false))
	naval = bool(def.get("naval", false))
	loiter = bool(def.get("loiter", false))
	_walk_rate_min = float(GameData.movement.get("walk_anim_min_rate", 0.35))
	_walk_rate_max = float(GameData.movement.get("walk_anim_max_rate", 1.4))
	_turn_step = 1.0 / maxf(1.0, float(GameData.movement.get("turn_steps_per_second", 40.0)))
	var sprite_id: String = def.get("sprite", id)
	_layout = SpriteLibrary.unit_layout(sprite_id)
	shadow_sprite = _layout.get("shadow", "shadow_s")
	ring_sprite = _layout.get("ring", "ring_s")
	var fs: Array = _layout.get("frame_size", [48, 48])
	var anchor: Array = _layout.get("anchor", [24, 44])
	var anims: Dictionary = _layout.get("animations", {})
	var directions := int(GameData.sprites.get("directions", 5))
	var max_frames := 1
	var ai := 0
	for a in anims:
		_anim_rows[a] = {"row": ai * directions, "frames": int(anims[a]["frames"]), "fps": float(anims[a]["fps"])}
		max_frames = maxi(max_frames, int(anims[a]["frames"]))
		ai += 1
	_sprite.texture = SpriteLibrary.unit_sheet(sprite_id, color_slot_arg)
	_sprite.hframes = max_frames
	_sprite.vframes = ai * directions
	_frame_w = fs[0]
	_anchor = Vector2(anchor[0], anchor[1])
	_sprite.centered = false
	_sprite.offset = Vector2(-anchor[0], -anchor[1])
	add_child(_sprite)
	pick_rect = Rect2(-10, -34, 20, 36)
	ammo = int(def.get("ammo", -1))
	altitude = float(def.get("altitude", 0.0))
	if altitude > 0.0:
		# Aircraft: the sprite flies above its ground shadow and over buildings.
		_sprite.position.y = -altitude
		pick_rect = Rect2(-16, -altitude - 20, 32, 34)
		z_index = 30
	set_grid_pos(at)
	play("idle")
	_anim_time = randf() * 2.0
	facing = randi() % Iso.DIR_COUNT
	facing_target = facing


## Places the unit at once (spawning, teleports, host snapshots).
func set_grid_pos(g: Vector2) -> void:
	super.set_grid_pos(g)
	_glide_tick = -1


## Moves the unit during a simulation tick. Its drawn `position` catches up
## smoothly on the following frames (see _glide).
func glide_to(g: Vector2) -> void:
	var tick := Engine.get_physics_frames()
	if tick != _glide_tick:
		_glide_from = position if _glide_tick < 0 else _glide_to
		_glide_tick = tick
	grid_pos = g
	_glide_to = Iso.grid_to_world(g)


## Blends the drawn position across the last tick; it rests once a tick passes
## without movement. Rounded, so sprites stay on whole pixels.
func _glide() -> void:
	if _glide_tick < 0:
		return
	if Engine.get_physics_frames() == _glide_tick:
		position = _glide_from.lerp(_glide_to, Engine.get_physics_interpolation_fraction()).round()
	else:
		position = _glide_to.round()
		_glide_tick = -1


## Marks the unit as moving while its path request waits in the queue.
func await_path() -> void:
	path_pending = true
	state = State.MOVING


func order_path(new_path: PackedVector2Array) -> void:
	path_pending = false
	path = new_path
	path_index = 0
	stuck_time = 0.0
	last_progress_dist = INF
	state = State.MOVING if not path.is_empty() else State.IDLE


func stop() -> void:
	path_pending = false
	path = PackedVector2Array()
	path_index = 0
	velocity = Vector2.ZERO
	state = State.IDLE


func final_destination() -> Vector2:
	if path.is_empty():
		return grid_pos
	return path[path.size() - 1]


## True while the unit has a live, non-dead target.
func has_target() -> bool:
	return is_instance_valid(target) and not target.dead


func is_military() -> bool:
	return bool(def.get("auto_attack", false))


func attack_range() -> float:
	var r := float(def.get("attack_range", 0.0))
	return r + range_bonus if r > 0.5 else r


## Owned animals show a small team-coloured collar ring (their sheet has no team colour).
func _draw() -> void:
	super._draw()
	if def.has("animal") and owner_id != GAIA and not dead:
		var c: Color = Color(GameData.player_color(color_slot).get("primary", "#ffffff"))
		draw_arc(Vector2(0, -2), 6.0, 0.0, TAU, 14, Color(c, 0.85), 1.0)


## Switches sides (monk conversion, herding): new owner and team colours, all orders dropped.
func change_owner(player_id: int, slot: int) -> void:
	owner_id = player_id
	color_slot = slot
	_sprite.texture = SpriteLibrary.unit_sheet(def.get("sprite", type_id), slot)
	stop()
	target = null
	task = {}
	work_anim = ""
	guard_pos = grid_pos
	attack_move_goal = Vector2.INF
	selected = false
	queue_redraw()


## Requests a facing; the sprite turns there smoothly through the in-between directions.
func face(dir: int) -> void:
	facing_target = posmod(dir, Iso.DIR_COUNT)


## Plays `anim` from its first frame and locks it for one full cycle
## (`with_sound` false replays an attack cycle silently, e.g. a strafing plane).
func play_once(anim: String, with_sound: bool = true) -> void:
	if not _anim_rows.has(anim):
		return
	_use_anim(anim)
	_anim_time = 0.0
	anim_lock = float(_frames) / maxf(1.0, _fps)
	if anim == "attack" and with_sound:
		EventBus.sound_at.emit(SoundRules.attack_key(GameData.audio, type_id, def), position)


## Switches to the death animation (holds its last frame).
func die() -> void:
	set_grid_pos(grid_pos)  # the body settles exactly where the unit fell
	EventBus.sound_at.emit(SoundRules.death_key(GameData.audio, def), position)
	stop()
	target = null
	task = {}
	work_anim = ""
	selected = false
	play_once("die")
	anim_lock = INF
	shadow_sprite = ""
	var back := Entity.corpse_sort_back()
	if altitude > 0.0:
		# Shot down: the wreck falls to the ground while the crash frames play.
		var tw := create_tween()
		tw.tween_property(_sprite, "position:y", back, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			z_index = 0
			position.y -= back)
	else:
		sort_back(_sprite, back)
	queue_redraw()


func body_sprite() -> Sprite2D:
	return _sprite


## Sheet frame index of the last death frame in the current facing.
func final_death_frame() -> int:
	var info: Dictionary = _anim_rows.get("die", _anim_rows.get("idle", {}))
	if info.is_empty():
		return _sprite.frame
	var sd := Iso.sheet_direction(facing)
	return (int(info["row"]) + sd.x) * _sprite.hframes + int(info["frames"]) - 1


## Current height of the sprite above its shadow (cruise altitude minus any dive).
func flight_height() -> float:
	return maxf(0.0, altitude - flight_dip)


func has_anim(anim: String) -> bool:
	return _anim_rows.has(anim)


func play(anim: String) -> void:
	if anim != _anim and _anim_rows.has(anim):
		_use_anim(anim)
		_anim_time = 0.0
		_work_cycle = -1


func _use_anim(anim: String) -> void:
	_anim = anim
	var info: Dictionary = _anim_rows[anim]
	_row = info["row"]
	_frames = info["frames"]
	_fps = info["fps"]
	_is_work_anim = anim in WORK_ANIMS
	_is_walk_anim = anim == "walk" or anim.begins_with("carry_")


## Advances the animation; called by UnitSystem every frame. With `drawn` false
## (off screen or under the fog) time and sounds advance but the sprite is left alone.
func animate(delta: float, drawn: bool = true) -> void:
	_glide()
	var rate := 1.0
	if _is_walk_anim and speed > 0.0:
		# Stride follows ground speed so feet do not slide when slowing or crowding.
		rate = clampf(velocity.length() / speed, _walk_rate_min, _walk_rate_max)
	_anim_time += delta * rate
	anim_lock -= delta
	_turn(delta)
	since_damaged += delta
	if _frames == 0:
		return
	if not dead and (_is_work_anim or (naval and state == State.IDLE and task.get("type", "") == "gather")):
		_work_sound()
	if not drawn:
		return
	var sd := Iso.sheet_direction(facing)
	var frame := int(_anim_time * _fps) % _frames
	if dead:
		frame = mini(int(_anim_time * _fps), _frames - 1)
	frame += (_row + sd.x) * _sprite.hframes
	if frame != _shown_frame:
		_shown_frame = frame
		_sprite.frame = frame
	if altitude > 0.0 and not dead:
		_sprite.position.y = -flight_height() + sin(_anim_time * 2.2) * 1.5
	var flip := sd.y == 1
	if flip != _shown_flip:
		_shown_flip = flip
		_sprite.flip_h = flip
		# Mirroring happens inside the frame rect, so mirror the anchor too.
		_sprite.offset.x = -(_frame_w - _anchor.x) if flip else -_anchor.x


func _turn(delta: float) -> void:
	if facing == facing_target:
		_turn_time = 0.0
		return
	_turn_time += delta
	while _turn_time >= _turn_step and facing != facing_target:
		_turn_time -= _turn_step
		facing = posmod(facing + signi(Iso.direction_delta(facing, facing_target)), Iso.DIR_COUNT)


## Emits the work sound once per animation cycle, at the strike frame
## ("at" = fraction of the cycle, "every" = only every n-th cycle).
func _work_sound() -> void:
	var farming: bool = task.get("type", "") == "gather" and task.get("kind", "") == "food" and _anim == "build"
	var entry := SoundRules.work_entry(GameData.audio, "fish" if def.get("naval", false) else _anim, farming)
	if entry.is_empty():
		return
	var period := float(_frames) / maxf(1.0, _fps) if _is_work_anim else 2.0
	var cycle := floori(_anim_time / period - float(entry.get("at", 0.5)))
	if cycle < 0 or cycle == _work_cycle:
		return
	_work_cycle = cycle
	if cycle % maxi(1, int(entry.get("every", 1))) == 0:
		EventBus.sound_at.emit(String(entry.get("sound", "")), position)

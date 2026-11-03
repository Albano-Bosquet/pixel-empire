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


## Switches sides (monk conversion): new owner and team colours, all orders dropped.
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


## Plays `anim` from its first frame and locks it for one full cycle.
func play_once(anim: String) -> void:
	if not _anim_rows.has(anim):
		return
	_anim = anim
	_anim_time = 0.0
	var info: Dictionary = _anim_rows[anim]
	anim_lock = float(info["frames"]) / maxf(1.0, info["fps"])


## Switches to the death animation (holds its last frame).
func die() -> void:
	stop()
	target = null
	task = {}
	work_anim = ""
	selected = false
	play_once("die")
	anim_lock = INF
	shadow_sprite = ""
	z_index = -1
	if altitude > 0.0:
		# Shot down: the wreck falls to the ground while the crash frames play.
		z_index = 30
		var tw := create_tween()
		tw.tween_property(_sprite, "position:y", 0.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: z_index = -1)
	queue_redraw()


func has_anim(anim: String) -> bool:
	return _anim_rows.has(anim)


func play(anim: String) -> void:
	if anim != _anim and _anim_rows.has(anim):
		_anim = anim
		_anim_time = 0.0


## Advances the sprite animation; called by UnitSystem every frame.
func animate(delta: float) -> void:
	var rate := 1.0
	if (_anim == "walk" or _anim.begins_with("carry_")) and speed > 0.0:
		# Stride follows ground speed so feet do not slide when slowing or crowding.
		rate = clampf(velocity.length() / speed, float(GameData.movement.get("walk_anim_min_rate", 0.35)),
				float(GameData.movement.get("walk_anim_max_rate", 1.4)))
	_anim_time += delta * rate
	anim_lock -= delta
	_turn(delta)
	since_damaged += delta
	var info: Dictionary = _anim_rows.get(_anim, {})
	if info.is_empty():
		return
	var sd := Iso.sheet_direction(facing)
	var frame := int(_anim_time * info["fps"]) % int(info["frames"])
	if dead:
		frame = mini(int(_anim_time * info["fps"]), int(info["frames"]) - 1)
	_sprite.frame = (int(info["row"]) + sd.x) * _sprite.hframes + frame
	if altitude > 0.0 and not dead:
		_sprite.position.y = -altitude + sin(_anim_time * 2.2) * 1.5
	_sprite.flip_h = sd.y == 1
	# Mirroring happens inside the frame rect, so mirror the anchor too.
	_sprite.offset.x = -(_frame_w - _anchor.x) if _sprite.flip_h else -_anchor.x


func _turn(delta: float) -> void:
	if facing == facing_target:
		_turn_time = 0.0
		return
	var step_time := 1.0 / maxf(1.0, float(GameData.movement.get("turn_steps_per_second", 40.0)))
	_turn_time += delta
	while _turn_time >= step_time and facing != facing_target:
		_turn_time -= step_time
		facing = posmod(facing + signi(Iso.direction_delta(facing, facing_target)), Iso.DIR_COUNT)

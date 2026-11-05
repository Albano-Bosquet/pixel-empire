class_name CombatSystem
extends Node
## Real-time combat (design/game-brief.md MVP item 4).
##
## Per-unit combat state (fields on Unit):
##   no target --(enemy seen while idle/attack-moving, or attacked, or ordered)--> target
##   target: out of range -> chase (repath every 0.5 s); in range -> stop, face, swing
##           when attack_timer <= 0 (melee damage lands melee_hit_delay later;
##           ranged spawns a projectile).
##   target lost/dead/leashed -> resume attack-move goal, else walk back to guard_pos.
## Stances: aggressive (chase up to sight + leash_extra), defensive (sight / 2),
## stand (attack only what is already in range).
## Damage: max(1, attack - armor[attack_type]) + bonuses vs target classes.
## Siege rules (units_stats.json): "attack_targets" restricts what a unit may attack
## (rams, trebuchets, petards); "pierce_line" bolts hit every enemy along their line;
## "self_destruct" units (petards) explode with area damage on their first hit.
## Data: units_stats.json, buildings_stats.json (attack), combat_settings.json.

var projectiles: Array = []

## Team of each player id (0 = no team). Set by Game.start from the match
## config; players sharing a non-zero team are allies (no fighting, shared
## vision, they win together).
static var teams: Dictionary = {}

var _game: Game
var _cfg: Dictionary
var _scan_timer := 0.0
var _near: Array = []
var _attack_notice := {}


func setup(game: Game, combat_cfg: Dictionary) -> void:
	_game = game
	_cfg = combat_cfg


## Damage dealt by an attacker definition to `target` (never below 1).
static func compute_damage(attack: int, attack_type: String, bonuses: Dictionary, target: Entity) -> int:
	var dmg := maxi(1, attack - target.armor(attack_type))
	for cls in target.classes():
		dmg += int(bonuses.get(cls, 0))
	return dmg


## Melee swing damage against a building: scaled by "melee_building_damage_mult"
## unless the attacker has a class in "melee_building_exempt_classes" (rams, ships, animals).
static func melee_building_damage(dmg: int, attacker_classes: Array, combat_cfg: Dictionary) -> int:
	for cls in combat_cfg.get("melee_building_exempt_classes", []):
		if attacker_classes.has(cls):
			return dmg
	return maxi(1, roundi(dmg * float(combat_cfg.get("melee_building_damage_mult", 1.0))))


## True if a unit definition may attack `target` ("attack_targets" lists allowed classes; empty = any).
static func can_target(attacker_def: Dictionary, target: Entity) -> bool:
	# Melee cannot cross the shoreline: land melee never hits ships, ship melee never hits land units.
	var melee := float(attacker_def.get("attack_range", 0.0)) <= 0.5
	if melee and target is Unit and bool(target.def.get("naval", false)) != bool(attacker_def.get("naval", false)):
		return false
	# Aircraft: only ranged attackers reach them; ground-only bombers never shoot back.
	var flying: bool = target is Unit and bool(target.def.get("air", false))
	if flying and (melee or attacker_def.get("ground_only", false)):
		return false
	var allowed: Array = attacker_def.get("attack_targets", [])
	if allowed.is_empty():
		return true
	for cls in target.classes():
		if allowed.has(cls):
			return true
	return false


## Distance from grid point `p` to the segment a-b (scorpion bolt line test).
static func distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Players `a` and `b` (ids) are on the same side.
static func are_allies(a: int, b: int) -> bool:
	if a == b:
		return true
	var ta := int(teams.get(a, 0))
	return ta != 0 and ta == int(teams.get(b, 0))


static func is_enemy(a: Entity, b: Entity) -> bool:
	if a.owner_id == Entity.GAIA or b.owner_id == Entity.GAIA:
		return a.owner_id != b.owner_id and (Wildlife.is_hostile_animal(a) or Wildlife.is_hostile_animal(b))
	return not are_allies(a.owner_id, b.owner_id)


## Whether damage from player `owner` (splash, bolts) hurts entity `e`.
static func hurts(owner: int, e: Entity) -> bool:
	if e.owner_id == Entity.GAIA:
		return owner != Entity.GAIA and Wildlife.is_animal(e)
	return owner != Entity.GAIA and not are_allies(owner, e.owner_id)


# --- Orders -------------------------------------------------------------------

func order_attack(units: Array[Unit], target: Entity) -> void:
	for u in units:
		if not _can_attack(u) or not can_target(u.def, target):
			continue
		_game.economy.clear_task(u)
		u.target = target
		u.guard_pos = Vector2.INF
		u.attack_move_goal = Vector2.INF
		u.repath_timer = 0.0


func order_attack_move(units: Array[Unit], goal: Vector2) -> void:
	for u in units:
		if not _can_attack(u):
			continue
		_game.economy.clear_task(u)
		u.target = null
		u.guard_pos = Vector2.INF
		u.attack_move_goal = goal
		_game.unit_system.request_path(u, goal)


## A plain move cancels fighting; the destination becomes the new guard post.
func on_move_ordered(u: Unit, destination: Vector2) -> void:
	u.target = null
	u.attack_move_goal = Vector2.INF
	u.guard_pos = destination


func _can_attack(u: Unit) -> bool:
	return u.is_alive() and int(u.def.get("attack_damage", 0)) > 0 and u.ammo != 0


# --- Tick ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_scan_timer -= delta
	var scan := _scan_timer <= 0.0
	if scan:
		_scan_timer = float(_cfg.get("scan_interval", 0.4))
	for u in _game.unit_system.units:
		if u.dead:
			continue
		u.attack_timer -= delta
		u.repath_timer -= delta
		if u.hit_timer >= 0.0:
			u.hit_timer -= delta
			if u.hit_timer < 0.0:
				_land_melee(u)
		if u.target != null or is_instance_valid(u.target):
			_fight(u)
		elif scan and u.is_military() and u.state == Unit.State.IDLE or scan and u.attack_move_goal != Vector2.INF:
			_acquire(u)
			if not u.has_target() and u.attack_move_goal != Vector2.INF and u.state == Unit.State.IDLE:
				u.attack_move_goal = Vector2.INF
				u.guard_pos = u.grid_pos
	_buildings_fire(delta)
	_move_projectiles(delta)


func _fight(u: Unit) -> void:
	if not is_instance_valid(u.target):
		_lose_target(u)
		return
	var t := u.target
	if not is_instance_valid(t) or t.dead or not (is_enemy(u, t) or WildlifeSystem.is_hunting(u, t)) or not _game.fog.is_visible(u.owner_id, t) or not can_target(u.def, t):
		_lose_target(u)
		return
	# Leash for auto-engaged units.
	if u.guard_pos != Vector2.INF and u.stance != "stand":
		var leash := u.sight + float(_cfg.get("leash_extra", 4.0))
		if u.stance == "defensive":
			leash = u.sight * 0.5
		if u.grid_pos.distance_to(u.guard_pos) > leash:
			_lose_target(u)
			return
	var dist := _distance(u, t)
	var rng := u.attack_range()
	if u.altitude > 0.0 and u.def.get("loiter", false):
		_fight_air(u, t, dist, rng)
		return
	var reach := rng + (0.25 if rng <= 0.5 else 0.0)
	if t is Building and rng <= 0.5:
		# Approach tiles can be diagonal to a footprint corner (unit centre ~0.47 tiles
		# beyond its radius); melee must still reach from there.
		reach += float(_cfg.get("melee_building_reach_extra", 0.3))
	var min_rng := float(u.def.get("min_range", 0.0))
	if dist <= reach and dist >= min_rng:
		if u.state == Unit.State.MOVING:
			u.stop()
		_face(u, _aim_point(u, t))
		if u.attack_timer <= 0.0:
			_start_attack(u, t)
	elif u.stance == "stand" and u.guard_pos != Vector2.INF:
		_lose_target(u)
	elif u.repath_timer <= 0.0:
		u.repath_timer = 0.5
		var goal := _aim_point(u, t)
		if u.altitude > 0.0:
			# Aircraft close in directly over whatever is in the way.
			_game.unit_system.request_path(u, goal)
			return
		if dist < min_rng:
			goal = u.grid_pos + (u.grid_pos - goal).normalized() * (min_rng - dist + 0.5)
		elif t is Building:
			goal = _game.nav(u).approach(t.footprint(), u.grid_pos)
			if goal == Vector2.INF:
				_lose_target(u)
				return
		_game.unit_system.request_path(u, goal)


## Aircraft never hover over a target: AirSystem flies dive-and-climb passes
## over it and they fire whenever the pass brings it within range.
func _fight_air(u: Unit, t: Entity, dist: float, rng: float) -> void:
	var point := _aim_point(u, t)
	_game.air.attack_run(u, point, rng)
	if dist > rng + 0.25 or not _game.air.nose_on(u, point):
		return
	if u.def.get("attack_anim_loop", false) and u.anim_lock <= 0.0:
		u.play_once("attack", false)
	if u.attack_timer <= 0.0:
		_start_attack(u, t)


func _lose_target(u: Unit) -> void:
	u.target = null
	u.hit_timer = -1.0
	if u.attack_move_goal != Vector2.INF:
		_game.unit_system.request_path(u, u.attack_move_goal)
	elif u.guard_pos != Vector2.INF and u.grid_pos.distance_to(u.guard_pos) > float(_cfg.get("guard_return_distance", 1.5)):
		_game.unit_system.request_path(u, u.guard_pos)
	elif u.state == Unit.State.MOVING:
		u.stop()


func _start_attack(u: Unit, t: Entity) -> void:
	if u.ammo == 0:
		return
	u.attack_timer = float(u.def.get("attack_cooldown", 2.0))
	u.play_once("attack")
	if u.ammo > 0:
		u.ammo -= 1
		if u.ammo == 0:
			_game.air.out_of_ammo.call_deferred(u)
	if u.def.has("projectile"):
		_spawn_projectile(u, t, u.def["projectile"], _attack_of(u), u.def.get("attack_type", "pierce"), u.def.get("bonuses", {}), float(u.def.get("area_radius", 0.0)), Vector2.ZERO, bool(u.def.get("pierce_line", false)))
	else:
		u.hit_timer = float(_cfg.get("melee_hit_delay", 0.35))


## Base attack plus flat technology bonus ("attack_add" modifier, Stage 4).
func _attack_of(u: Unit) -> int:
	return int(u.def.get("attack_damage", 1)) + u.attack_bonus


func _land_melee(u: Unit) -> void:
	if not is_instance_valid(u.target):
		return
	var t := u.target
	if t == null or not is_instance_valid(t) or t.dead:
		return
	if _distance(u, t) > u.attack_range() + 0.6:
		return
	if u.def.get("self_destruct", false):
		_explode(u, _aim_point(u, t))
		return
	var dmg := compute_damage(_attack_of(u), u.def.get("attack_type", "melee"), u.def.get("bonuses", {}), t)
	if t is Building:
		dmg = melee_building_damage(dmg, u.classes(), _cfg)
	_apply(t, dmg, u)
	_game.fx.burst(t.position + Vector2(0, -14), "blood" if t is Unit else "chips", SoundRules.melee_hit_key(GameData.audio, u.type_id, u.def, t is Building))


## Petard blast: area damage to enemies (units and buildings) around `where`, then the sapper dies.
func _explode(u: Unit, where: Vector2) -> void:
	var dmg := _attack_of(u)
	var area := float(u.def.get("area_radius", 1.0))
	_game.fx.burst(Iso.grid_to_world(where) + Vector2(0, -8), "debris", "none")
	_game.fx.burst(Iso.grid_to_world(where) + Vector2(0, -8), "flash", "explosion")
	_area_damage(where, area, dmg, u.def.get("attack_type", "melee"), u.def.get("bonuses", {}), u.owner_id, u)
	if u.is_alive():
		u.take_damage(u.hp, null)


## Finds the best visible enemy within sight (units before buildings, nearest first).
func _acquire(u: Unit) -> void:
	if not _can_attack(u):
		return  # e.g. an aircraft out of ammunition heading home
	var best: Entity = null
	var best_d := INF
	var sight := float(u.sight)
	if u.stance == "stand":
		sight = maxf(u.attack_range() + 0.5, 1.0)
	_near.clear()
	_game.unit_system.units_near(u.grid_pos, sight, _near)
	for o in _near:
		if o.dead or not is_enemy(u, o) or not _game.fog.is_visible(u.owner_id, o) or not can_target(u.def, o):
			continue
		if Wildlife.is_animal(o) and not Wildlife.is_predator(o):
			continue  # soldiers never wander off chasing sheep and deer
		var d: float = u.grid_pos.distance_to(o.grid_pos)
		if d <= sight and d < best_d:
			best_d = d
			best = o
	if best == null and u.is_military() and not Wildlife.is_animal(u):
		for b in _game.buildings.buildings:
			if b.dead or not is_enemy(u, b) or not _game.fog.is_visible(u.owner_id, b) or not can_target(u.def, b):
				continue
			var d2 := u.grid_pos.distance_to(b.closest_point(u.grid_pos))
			if d2 <= sight and d2 < best_d:
				best_d = d2
				best = b
	if best != null:
		u.target = best
		if u.guard_pos == Vector2.INF and u.attack_move_goal == Vector2.INF:
			u.guard_pos = u.grid_pos
		u.repath_timer = 0.0


## Damaged units fight back (military always; villagers if `retaliate`).
func _on_damaged(e: Entity, attacker: Entity, _amount: int) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.dead:
		return
	if e.owner_id != Entity.GAIA and not provoked(e, attacker):
		_notify_attack(e)
	if e is Unit:
		var u: Unit = e
		if not u.has_target() and u.task.is_empty() and _can_attack(u) and can_target(u.def, attacker) and (u.is_military() or _cfg.get("retaliate", true)) and u.stance != "stand":
			u.target = attacker
			if u.guard_pos == Vector2.INF:
				u.guard_pos = u.grid_pos


## True when `victim` took the hit in a fight its own side started, so it is no
## "under attack" alert: the victim was attacking or hunting `attacker`, the attacker
## is on the victim's own side (villagers butchering a herded sheep), or it is wild
## game (boar, deer), which only strikes back when hunted.
## Predators and other players' units attacking unprovoked return false.
static func provoked(victim: Entity, attacker: Entity) -> bool:
	if attacker.owner_id == victim.owner_id:
		return true
	if Wildlife.is_animal(attacker) and attacker.owner_id == Entity.GAIA and not Wildlife.is_predator(attacker):
		return true
	if victim is Unit:
		var u: Unit = victim
		return u.target == attacker or WildlifeSystem.is_hunting(u, attacker)
	return false


func _notify_attack(e: Entity) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_attack_notice.get(e.owner_id, -99999)) > 15000:
		_attack_notice[e.owner_id] = now
		EventBus.notify.emit(e.owner_id, "You are under attack!")
	EventBus.under_attack.emit(e.owner_id, e.grid_pos)


func _apply(t: Entity, dmg: int, attacker: Entity) -> void:
	t.take_damage(dmg, attacker)


## Wires an entity's damage/death signals into combat (called on spawn).
func track(e: Entity) -> void:
	e.damaged.connect(_on_damaged)
	e.killed.connect(_on_killed)


func _on_killed(e: Entity, attacker: Entity) -> void:
	EventBus.entity_killed.emit(e, attacker)
	if e.owner_id != Entity.GAIA:
		var victim := _game.player(e.owner_id)
		victim.stats["units_lost" if e is Unit else "buildings_lost"] += 1
	if attacker != null and is_instance_valid(attacker) and attacker.owner_id != Entity.GAIA:
		_game.player(attacker.owner_id).stats["kills"] += 1
	if e is Unit:
		_game.kill_unit(e)
	elif e is Building:
		_game.fx.burst(e.position + Vector2(0, -20), "debris")
		_game.buildings.destroy(e)


# --- Defensive buildings ------------------------------------------------------

func _buildings_fire(delta: float) -> void:
	for b in _game.buildings.buildings:
		var atk: Dictionary = b.def.get("attack", {})
		if atk.is_empty() or not b.is_complete() or b.dead:
			continue
		b.attack_timer -= delta
		if b.attack_timer > 0.0:
			continue
		var rng := float(atk.get("range", 6))
		_near.clear()
		var center := b.grid_pos
		_game.unit_system.units_near(center, rng + b.size * 0.5, _near)
		var best: Unit = null
		var best_d := INF
		var only: Array = atk.get("targets", [])
		for o in _near:
			if o.dead or not is_enemy(b, o) or not _game.fog.is_visible(b.owner_id, o):
				continue
			if not only.is_empty() and not o.classes().any(func(c): return only.has(c)):
				continue
			var d: float = o.grid_pos.distance_to(b.closest_point(o.grid_pos))
			if d <= rng and d < best_d:
				best_d = d
				best = o
		if best == null:
			continue
		b.attack_timer = float(atk.get("cooldown", 2.0))
		# Guns point at the aircraft as drawn (lifted by its altitude), not at its ground spot.
		b.aim_at(Iso.world_to_grid(best.position - Vector2(0, best.flight_height())))
		EventBus.sound_at.emit(String(GameData.audio.get("attack_by_projectile", {}).get(atk.get("projectile", "arrow"), "bow")), b.position + b.top_offset())
		for i in int(atk.get("arrows", 1)):
			_spawn_projectile(b, best, String(atk.get("projectile", "arrow")), int(atk.get("damage", 3)) + b.attack_bonus, String(atk.get("type", "pierce")), atk.get("bonuses", {}), 0.0, Vector2(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)))


# --- Projectiles ----------------------------------------------------------------

func _spawn_projectile(src: Entity, t: Entity, kind: String, dmg: int, attack_type: String, bonuses: Dictionary, area: float, jitter: Vector2 = Vector2.ZERO, line: bool = false) -> void:
	var start := src.grid_pos + jitter
	var start_h: float = (18.0 + (src as Unit).flight_height()) if src is Unit else -src.top_offset().y
	var end_h: float = (10.0 + (t as Unit).flight_height()) if t is Unit else 10.0
	if kind == "bomb":
		end_h = 0.0
	var dest: Vector2 = t.grid_pos if not (t is Building) else t.closest_point(src.grid_pos)
	if line:
		# The bolt keeps flying past its target and hits everything on the way.
		dest += (dest - start).normalized() * float(_cfg.get("line_overshoot", 2.0))
	projectiles.append({
		"kind": kind, "from": start, "pos": start, "start_h": start_h, "dest": dest, "target": t,
		"homing": kind == "arrow", "speed": float(_cfg.get("projectile_speeds", {}).get(kind, 8.0)),
		"arc": float(_cfg.get("arc_height_px", {}).get(kind, 10.0)), "damage": dmg, "type": attack_type,
		"bonuses": bonuses, "area": area, "owner": src.owner_id, "src": src, "t": 0.0, "line": line, "end_h": end_h,
		"screen": Iso.grid_to_world(start) - Vector2(0, start_h), "screen_dir": Vector2.RIGHT,
	})
	_game.fx.projectiles = projectiles


func _move_projectiles(delta: float) -> void:
	if projectiles.is_empty():
		return
	var keep: Array = []
	for pr in projectiles:
		var t: Entity = Iso.alive(pr["target"])
		if pr["homing"] and is_instance_valid(t) and not t.dead:
			pr["dest"] = t.grid_pos if not (t is Building) else t.closest_point(pr["from"])
		var total: float = maxf(0.2, (pr["dest"] - pr["from"]).length())
		pr["t"] += delta * pr["speed"] / total
		var k: float = minf(pr["t"], 1.0)
		var prev: Vector2 = pr["screen"]
		pr["pos"] = pr["from"].lerp(pr["dest"], k)
		var h: float = lerpf(pr["start_h"], float(pr.get("end_h", 10.0)), k) + sin(k * PI) * pr["arc"] * clampf(total / 4.0, 0.4, 2.0)
		pr["screen"] = Iso.grid_to_world(pr["pos"]) - Vector2(0, h)
		var d: Vector2 = pr["screen"] - prev
		if d.length_squared() > 0.01:
			pr["screen_dir"] = d.normalized()
		if pr["t"] >= 1.0:
			_impact(pr)
		else:
			keep.append(pr)
	projectiles = keep
	_game.fx.projectiles = projectiles


func _impact(pr: Dictionary) -> void:
	var src: Entity = Iso.alive(pr["src"])
	var where: Vector2 = pr["dest"]
	if pr.get("line", false):
		var a: Vector2 = pr["from"]
		var width := float(_cfg.get("line_hit_width", 0.35))
		_near.clear()
		_game.unit_system.units_near((a + where) * 0.5, a.distance_to(where) * 0.5 + width, _near)
		for o in _near:
			if not o.dead and hurts(int(pr["owner"]), o) and distance_to_segment(o.grid_pos, a, where) <= width + o.radius:
				_apply(o, compute_damage(pr["damage"], pr["type"], pr["bonuses"], o), src)
				_game.fx.burst(o.position + Vector2(0, -12), "blood")
		return
	if pr["area"] > 0.0:
		_game.fx.burst(Iso.grid_to_world(where), "dust", SoundRules.impact_key(GameData.audio, String(pr["kind"])))
		_area_damage(where, pr["area"], pr["damage"], pr["type"], pr["bonuses"], pr["owner"], src)
		return
	var t: Entity = Iso.alive(pr["target"])
	if t != null and not t.dead:
		_apply(t, compute_damage(pr["damage"], pr["type"], pr["bonuses"], t), src)
		_game.fx.burst(t.position + Vector2(0, -12), "hit")


func _area_damage(where: Vector2, area: float, dmg: int, attack_type: String, bonuses: Dictionary, owner: int, src: Entity) -> void:
	_near.clear()
	_game.unit_system.units_near(where, area + 0.5, _near)
	for o in _near.duplicate():
		if not o.dead and hurts(owner, o) and o.grid_pos.distance_to(where) <= area:
			_apply(o, compute_damage(dmg, attack_type, bonuses, o), src)
	for b in _game.buildings.buildings.duplicate():
		if not b.dead and hurts(owner, b) and b.closest_point(where).distance_to(where) <= area:
			_apply(b, compute_damage(dmg, attack_type, bonuses, b), src)


# --- Geometry -------------------------------------------------------------------

func _distance(u: Unit, t: Entity) -> float:
	if t is Building:
		return u.grid_pos.distance_to(t.closest_point(u.grid_pos)) - u.radius
	var r: float = t.radius if t is Unit else 0.3
	return u.grid_pos.distance_to(t.grid_pos) - u.radius - r


func _aim_point(u: Unit, t: Entity) -> Vector2:
	return t.closest_point(u.grid_pos) if t is Building else t.grid_pos


func _face(u: Unit, p: Vector2) -> void:
	var d := p - u.grid_pos
	if d.length_squared() > 0.0001:
		u.face(Iso.direction_index(d))

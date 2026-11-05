class_name MapGenerator
extends RefCounted
## Procedural map generation (design/game-brief.md, MVP item 1).
## Pure function of (config, size, seed, player count, map type): same inputs, same map.
## Map types (map_generation.json "map_types"):
##   continental — noise terrain, hidden land corridors join every start through
##                 the centre; only allies get a visible road between them.
##   coast       — an inland sea fills the centre; a land ring joins the starts
##                 (a visible road only between allies).
##   islands     — every player on an island of their own (ships needed to meet).
## Every type: the inside of big mountains is a PLATEAU reached by RAMPs.
##   desert      — continental layout ("layout": "continental") where dry land is
##                 dune sand (DESERT), forests are scarce and lakes read as oases.
## Fish shoals are placed on open water for every type.
## Example:
##   var map := MapGenerator.new(GameData.map_gen, GameData.resource_nodes).generate(96, 1234, 2, "islands")

const T := MapData.Terrain
## A mountain tile is plateau only if all of these tiles are mountain too. The
## extra south offsets keep walkable ground clear of the wall the shader paints
## over the tiles at a cliff's camera-facing foot.
const PLATEAU_RIM: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]
## Directions a ramp may leave a plateau, camera-facing ones first.
const RAMP_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

var cfg: Dictionary
var resource_defs: Dictionary
var _rng := RandomNumberGenerator.new()
var _map: MapData
var _reserved: PackedByteArray  # tiles that must stay free: 1 = start area, 2 = road or corridor
var _type := "continental"
## Land/sea layout the type follows: continental, coast or islands.
var _layout := "continental"
var _type_cfg: Dictionary = {}
var _start_angle := NAN


func _init(config: Dictionary, resource_node_defs: Dictionary = {}) -> void:
	cfg = config
	resource_defs = resource_node_defs


## `teams[i]` is player i's team (0 = none); only allies get a road between
## their starts, so roads never give away an enemy's position.
func generate(size: int, map_seed: int, player_count: int, map_type: String = "continental", teams: Array = []) -> MapData:
	_rng.seed = map_seed
	_map = MapData.new(size, size, map_seed)
	_reserved.resize(size * size)
	_reserved.fill(0)
	_type = map_type if cfg.get("map_types", {}).has(map_type) else "continental"
	_type_cfg = cfg.get("map_types", {}).get(_type, {})
	_layout = String(_type_cfg.get("layout", _type))
	_build_fields(map_seed)
	if _layout != "continental":
		# Water maps fix the start angle first so the landmass can follow it.
		var shape_rng := RandomNumberGenerator.new()
		shape_rng.seed = map_seed + 31337
		_start_angle = shape_rng.randf() * TAU
		_shape_water(maxi(player_count, 1), shape_rng)
	_classify_terrain()
	_place_starts(maxi(player_count, 1))
	if _layout == "continental":
		_carve_roads(teams)
	elif _layout == "coast":
		_carve_ring_road(teams)
	_place_trees()
	_place_player_resources()
	_place_start_woods()
	_place_extra_resources()
	_place_fish()
	_open_plateaus()
	_place_decor()
	return _map


## Bends the normalised elevation field into the map type's land/sea layout.
func _shape_water(count: int, shape_rng: RandomNumberGenerator) -> void:
	var w := float(_map.width)
	var center := Vector2(_map.width, _map.height) * 0.5
	var ring := float(cfg.get("start_ring_radius", 0.33)) * w
	var starts: Array[Vector2] = []
	for p in count:
		var a := _start_angle + TAU * p / count
		starts.append(center + Vector2(cos(a), sin(a)) * (ring if count > 1 else 0.0))
	var islets: Array[Vector2] = []
	for k in int(_type_cfg.get("extra_islands", 0)):
		var a2 := _start_angle + TAU * (k + 0.5) / maxi(1, int(_type_cfg.get("extra_islands", 0)))
		islets.append(center + Vector2(cos(a2), sin(a2)) * ring * shape_rng.randf_range(0.2, 0.9))
	for y in _map.height:
		for x in _map.width:
			var i := y * _map.width + x
			var p2 := Vector2(x + 0.5, y + 0.5)
			var e := _map.elevation[i]
			if _layout == "coast":
				# Inland sea in the middle, guaranteed land along the start ring.
				var dc := p2.distance_to(center) / w
				var sea := 1.0 - smoothstep(float(_type_cfg.get("sea_radius", 0.2)) * 0.6, float(_type_cfg.get("sea_radius", 0.2)), dc)
				var ring_d := absf(p2.distance_to(center) - ring) / w
				var land := 1.0 - smoothstep(0.0, float(_type_cfg.get("land_ring_width", 0.12)), ring_d)
				e = e - sea * float(_type_cfg.get("sea_depth", 0.55)) + land * float(_type_cfg.get("land_ring_boost", 0.18))
			else:
				# Islands: low sea everywhere, raised discs under each start and a few islets.
				var r := float(_type_cfg.get("island_radius", 0.17)) * w
				var lift := 0.0
				for s in starts:
					lift = maxf(lift, 1.0 - smoothstep(r * 0.7, r, p2.distance_to(s)))
				for s2 in islets:
					lift = maxf(lift, (1.0 - smoothstep(r * 0.25, r * 0.45, p2.distance_to(s2))) * 0.85)
				e = lerpf(float(_type_cfg.get("sea_floor", 0.12)), 0.34 + e * 0.5, lift)
			_map.elevation[i] = clampf(e, 0.0, 1.0)


# --- Terrain fields ---------------------------------------------------------

func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.frequency = frequency / float(_map.width)
	return n


func _build_fields(map_seed: int) -> void:
	var e_noise := _noise(map_seed, float(cfg.get("elevation_frequency", 2.4)), 5)
	var m_noise := _noise(map_seed + 7919, float(cfg.get("moisture_frequency", 3.2)), 4)
	var e_min := INF
	var e_max := -INF
	var m_min := INF
	var m_max := -INF
	for y in _map.height:
		for x in _map.width:
			var i := y * _map.width + x
			var e := e_noise.get_noise_2d(x, y)
			var m := m_noise.get_noise_2d(x, y)
			_map.elevation[i] = e
			_map.moisture[i] = m
			e_min = minf(e_min, e)
			e_max = maxf(e_max, e)
			m_min = minf(m_min, m)
			m_max = maxf(m_max, m)
	for i in _map.elevation.size():
		_map.elevation[i] = inverse_lerp(e_min, e_max, _map.elevation[i])
		_map.moisture[i] = inverse_lerp(m_min, m_max, _map.moisture[i])


## A generation value, overridden per map type when the type sets it.
func _param(key: String, default: float) -> float:
	return float(_type_cfg.get(key, cfg.get(key, default)))


func _classify_terrain() -> void:
	var dirt_noise := _noise(_map.seed + 104729, 6.0, 2)
	var desert_m := _param("desert_moisture", -1.0)
	var forest_m := _param("forest_moisture", 0.6)
	for y in _map.height:
		for x in _map.width:
			var i := y * _map.width + x
			var e := _map.elevation[i]
			var m := _map.moisture[i]
			var t: int
			if e < cfg.get("deep_water_level", 0.24):
				t = T.DEEP_WATER
			elif e < cfg.get("water_level", 0.31):
				t = T.WATER
			elif e < _param("beach_level", 0.345):
				t = T.SAND
			elif e > cfg.get("mountain_level", 0.76):
				t = T.MOUNTAIN
			elif e > cfg.get("rocky_level", 0.70):
				t = T.ROCKY
			elif m > forest_m:
				t = T.FOREST
			elif m < desert_m:
				t = T.DESERT
			elif m < cfg.get("meadow_moisture", 0.38):
				t = T.MEADOW
			else:
				t = T.GRASS
			if (t == T.GRASS or t == T.MEADOW) and dirt_noise.get_noise_2d(x, y) * 0.5 + 0.5 > cfg.get("dirt_patch_threshold", 0.74):
				t = T.DIRT
			_map.terrain[i] = t


# --- Starts and roads -------------------------------------------------------

func _place_starts(count: int) -> void:
	var center := Vector2(_map.width, _map.height) * 0.5
	var radius := float(cfg.get("start_ring_radius", 0.33)) * _map.width
	var base_angle := _rng.randf() * TAU
	if not is_nan(_start_angle):
		base_angle = _start_angle
	var clear_r: int = cfg.get("start_clear_radius", 7)
	var dirt_r: int = cfg.get("start_dirt_radius", 3)
	for p in count:
		var a := base_angle + TAU * p / count
		var pos := center + Vector2(cos(a), sin(a)) * (radius if count > 1 else 0.0)
		var t := Vector2i(clampi(roundi(pos.x), clear_r + 2, _map.width - clear_r - 3), clampi(roundi(pos.y), clear_r + 2, _map.height - clear_r - 3))
		_map.start_positions.append(t)
		for dy in range(-clear_r - 2, clear_r + 3):
			for dx in range(-clear_r - 2, clear_r + 3):
				var n := t + Vector2i(dx, dy)
				if not _map.in_bounds(n):
					continue
				var d := Vector2(dx, dy).length()
				if d <= dirt_r:
					_map.set_terrain(n, T.DIRT)
				elif d <= clear_r:
					var cur := _map.get_terrain(n)
					if cur in [T.DEEP_WATER, T.WATER, T.MOUNTAIN, T.FOREST, T.ROCKY]:
						_map.set_terrain(n, T.GRASS)
				elif d <= clear_r + 2:
					var cur2 := _map.get_terrain(n)
					if cur2 in [T.DEEP_WATER, T.WATER, T.MOUNTAIN]:
						_map.set_terrain(n, T.SAND if cur2 != T.MOUNTAIN else T.ROCKY)
				if d <= clear_r + 1:
					_reserved[_map.index(n)] = 1


## Allied start pairs (indices into start_positions) that get a visible road:
## each team's starts chained in player order. Enemies never share a road, so
## a road can never lead a player to an enemy base.
func _allied_pairs(teams: Array) -> Array:
	var by_team := {}
	for i in mini(teams.size(), _map.start_positions.size()):
		var team := int(teams[i])
		if team != 0:
			by_team.get_or_add(team, []).append(i)
	var pairs := []
	for team in by_team:
		var members: Array = by_team[team]
		for k in members.size() - 1:
			pairs.append([members[k], members[k + 1]])
	return pairs


## Marks one road/corridor tile. A visible road paints PATH; a hidden corridor
## keeps the natural look and only makes the tile passable (water becomes a
## sand ford, mountain a rocky pass) and keeps trees and mines off it, so every
## start stays reachable by land without a trail pointing at it.
func _carve_tile(t: Vector2i, visible: bool) -> void:
	if not _map.in_bounds(t):
		return
	var cur := _map.get_terrain(t)
	if cur == T.DEEP_WATER or cur == T.WATER:
		_map.set_terrain(t, T.SAND)
	elif visible and cur != T.DIRT:
		_map.set_terrain(t, T.PATH)
	elif cur == T.MOUNTAIN:
		_map.set_terrain(t, T.ROCKY)
	_reserved[_map.index(t)] = 2


## A wobbly line from `from` to `to` (tile space), carved by _carve_tile.
func _carve_line(from: Vector2, to: Vector2, visible: bool) -> void:
	var pos := from
	var heading := (to - pos).normalized()
	var guard := 0
	while pos.distance_to(to) > 1.5 and guard < _map.width * 4:
		guard += 1
		var to_target := (to - pos).normalized()
		heading = (heading + to_target * 0.35 + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))).normalized()
		pos += heading * 0.7
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			_carve_tile(Vector2i(floori(pos.x), floori(pos.y)) + o, visible)


## Continental maps: hidden corridors from each start to the map centre keep
## every start connected by land; only allies get a dirt road between them.
func _carve_roads(teams: Array) -> void:
	var center := Vector2(_map.width, _map.height) * 0.5
	for s in _map.start_positions:
		_carve_line(Vector2(s) + Vector2(0.5, 0.5), center, false)
	for pair in _allied_pairs(teams):
		var a := Vector2(_map.start_positions[pair[0]]) + Vector2(0.5, 0.5)
		var b := Vector2(_map.start_positions[pair[1]]) + Vector2(0.5, 0.5)
		_carve_line(a, b, true)


## Coast maps: a hidden corridor along the start ring links every start to its
## neighbours around the inland sea; allies get a visible road along the
## shorter arc between their starts.
func _carve_ring_road(teams: Array) -> void:
	var center := Vector2(_map.width, _map.height) * 0.5
	var ring := float(cfg.get("start_ring_radius", 0.33)) * _map.width
	var steps := roundi(TAU * ring * 1.6)
	var count := _map.start_positions.size()
	var visible_steps := {}
	for pair in _allied_pairs(teams):
		var i0 := int(pair[0]) * steps / count
		var span := (int(pair[1]) - int(pair[0])) * steps / count
		if span > steps / 2:
			span -= steps
		for k in range(0, span + signi(span), signi(span) if span != 0 else 1):
			visible_steps[posmod(i0 + k, steps)] = true
	for i in steps:
		var a := _start_angle + TAU * i / steps
		var pos := center + Vector2(cos(a), sin(a)) * ring
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			_carve_tile(Vector2i(floori(pos.x), floori(pos.y)) + o, visible_steps.has(i))


# --- Objects ----------------------------------------------------------------

func _free(t: Vector2i) -> bool:
	return _map.in_bounds(t) and _map.walkable(t) and _reserved[_map.index(t)] == 0


func _cluster_tile_ok(t: Vector2i, start: Vector2i) -> bool:
	if _free(t):
		return true
	if start.x < 0 or not _map.in_bounds(t) or not _map.walkable(t) or _reserved[_map.index(t)] == 2:
		return false
	return Vector2(t - start).length() >= float(cfg.get("start_resource_min_dist", 4.5))


func _add_resource(type: String, t: Vector2i) -> void:
	var def: Dictionary = resource_defs.get(type, {})
	var variants: int = def.get("sprites", ["x"]).size()
	_map.resource_spawns.append({"type": type, "tile": t, "variant": _rng.randi() % maxi(variants, 1)})
	_map.set_blocked(t, true)


func _place_trees() -> void:
	var forest_density: float = cfg.get("forest_tree_density", 0.78)
	var lone_density: float = cfg.get("lone_tree_density", 0.018)
	var pine_e: float = cfg.get("pine_elevation", 0.56)
	for y in _map.height:
		for x in _map.width:
			var t := Vector2i(x, y)
			if not _free(t):
				continue
			var ter := _map.get_terrain(t)
			var tree := "tree_pine" if _map.elevation[_map.index(t)] > pine_e or ter == T.ROCKY else "tree_oak"
			if ter == T.FOREST:
				if _rng.randf() < forest_density:
					_add_resource(tree, t)
			elif (ter == T.GRASS or ter == T.MEADOW or ter == T.ROCKY) and _rng.randf() < lone_density:
				# Outside forests trees come as small groves, never alone.
				_place_cluster(tree, t, _rng.randi_range(int(cfg.get("grove_size_min", 3)), int(cfg.get("grove_size_max", 6))))


## Grows a clump of `size` nodes of `type` around `around`. Without
## `allow_partial`, a spot with no room for the whole clump places nothing and
## returns false, so the caller can try another spot.
## A player's start clumps pass that player's `start` tile: they may grow into
## the start's reserved ring (never roads or corridors, never within start_resource_min_dist).
func _place_cluster(type: String, around: Vector2i, size: int, allow_partial := true, start := Vector2i(-1, -1)) -> bool:
	if not _cluster_tile_ok(around, start):
		return false
	var cluster: Array[Vector2i] = [around]
	var frontier: Array[Vector2i] = [around]
	var tries := 0
	# Tiles stay within the radius of a disc holding `size` tiles plus
	# "cluster_radius_slack" (per type in "cluster_radius_slack_by_type"), so
	# clusters grow as clumps, not snakes; a larger slack gives looser clumps.
	var slack := float(cfg.get("cluster_radius_slack_by_type", {}).get(type, cfg.get("cluster_radius_slack", 0.6)))
	var max_r := sqrt(size / PI) + slack
	while cluster.size() < size and not frontier.is_empty() and tries < size * 30:
		tries += 1
		var base: Vector2i = frontier[_rng.randi() % frontier.size()]
		var n: Vector2i = base + [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][_rng.randi() % 4]
		if Vector2(n - around).length() <= max_r and _cluster_tile_ok(n, start) and not cluster.has(n):
			cluster.append(n)
			frontier.append(n)
	if cluster.size() < size and not allow_partial:
		return false
	for t in cluster:
		_add_resource(type, t)
	return true


func _place_player_resources() -> void:
	var rules: Dictionary = cfg.get("player_resources", {})
	for s in _map.start_positions:
		for type in rules:
			var r: Dictionary = rules[type]
			for c in int(r.get("clusters", 1)):
				# First 40 spots must fit the whole clump; later ones accept a partial one.
				for attempt in 80:
					var a := _rng.randf() * TAU
					var d := _rng.randf_range(r.get("min_dist", 6), r.get("max_dist", 10))
					var t := s + Vector2i(roundi(cos(a) * d), roundi(sin(a) * d))
					if _map.in_bounds(t) and _place_cluster(type, t, int(r.get("cluster_size", 4)), attempt >= 40, s):
						break


## Water maps: guaranteed woodlands per start ("start_woods" in the map type),
## since small islands may hold too few natural forests.
func _place_start_woods() -> void:
	var woods: Dictionary = _type_cfg.get("start_woods", {})
	if woods.is_empty():
		return
	for s in _map.start_positions:
		for c in int(woods.get("clusters", 2)):
			for attempt in 40:
				var a := _rng.randf() * TAU
				var d := _rng.randf_range(float(woods.get("min_dist", 9)), float(woods.get("max_dist", 13)))
				var t := s + Vector2i(roundi(cos(a) * d), roundi(sin(a) * d))
				if _map.in_bounds(t) and _place_cluster("tree_oak", t, int(woods.get("cluster_size", 22))):
					break


func _place_extra_resources() -> void:
	var per: Dictionary = cfg.get("extra_resource_clusters_per_100_tiles_side", {})
	for type in per:
		var count := roundi(float(per[type]) * _map.width / 100.0)
		for i in count:
			for attempt in 120:
				var t := Vector2i(_rng.randi_range(4, _map.width - 5), _rng.randi_range(4, _map.height - 5))
				var far := true
				for s in _map.start_positions:
					if Vector2(s).distance_to(Vector2(t)) < 14.0:
						far = false
				if far and _place_cluster(type, t, _rng.randi_range(int(cfg.get("extra_cluster_size_min", 3)), int(cfg.get("extra_cluster_size_max", 6))), attempt >= 60):
					break


## Fish shoals in open water (cluster per fish_shoals_per_100_tiles_side).
func _place_fish() -> void:
	var count := roundi(float(cfg.get("fish_shoals_per_100_tiles_side", 6)) * float(_type_cfg.get("fish_multiplier", 1.0)) * _map.width / 100.0)
	for i in count:
		for attempt in 80:
			var t := Vector2i(_rng.randi_range(2, _map.width - 3), _rng.randi_range(2, _map.height - 3))
			if not _fish_ok(t):
				continue
			var n := _rng.randi_range(2, 4)
			var placed := 0
			for o in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2), Vector2i(-2, 1)]:
				if placed >= n:
					break
				if _fish_ok(t + o):
					_add_resource("fish", t + o)
					placed += 1
			break


## Fish need water all around (ships reach them from any side) and no other blocker.
func _fish_ok(t: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := t + Vector2i(dx, dy)
			if not _map.in_bounds(n) or not MapData.terrain_navigable(_map.get_terrain(n)) or _map.is_blocked(n):
				return false
	return true


## Turns the inside of big mountains into walkable PLATEAU reached by RAMP cuts
## through the remaining cliff rim. Runs after every resource is placed and on
## its own random stream, so it never moves anything else on a seeded map. A
## mountain too thin for a plateau, or with no reachable foot for a ramp, stays solid.
func _open_plateaus() -> void:
	var inner := PackedByteArray()
	inner.resize(_map.terrain.size())
	for y in _map.height:
		for x in _map.width:
			if _plateau_inner(Vector2i(x, y)):
				inner[_map.index(Vector2i(x, y))] = 1
	var reach := _reachable_from_starts()
	var rng := RandomNumberGenerator.new()
	rng.seed = _map.seed + 65537
	var min_tiles := int(cfg.get("plateau_min_tiles", 12))
	var seen := PackedByteArray()
	seen.resize(_map.terrain.size())
	for y in _map.height:
		for x in _map.width:
			var i := _map.index(Vector2i(x, y))
			if inner[i] == 0 or seen[i] != 0:
				continue
			var tiles := _flood_plateau(Vector2i(x, y), inner, seen)
			if tiles.size() < min_tiles:
				continue
			var ramps := _pick_ramps(tiles, inner, reach, rng)
			if ramps.is_empty():
				continue
			for t in tiles:
				_map.set_terrain(t, T.PLATEAU)
			for ramp in ramps:
				for t in ramp["cells"]:
					_map.set_terrain(t, T.RAMP)


func _plateau_inner(t: Vector2i) -> bool:
	if _map.get_terrain(t) != T.MOUNTAIN:
		return false
	for off in PLATEAU_RIM:
		var n := t + off
		if not _map.in_bounds(n) or _map.get_terrain(n) != T.MOUNTAIN:
			return false
	return true


## Tiles a walker can reach from any start (1 in the returned mask).
func _reachable_from_starts() -> PackedByteArray:
	var reach := PackedByteArray()
	reach.resize(_map.terrain.size())
	var queue: Array[Vector2i] = []
	for s in _map.start_positions:
		reach[_map.index(s)] = 1
		queue.append(s)
	var head := 0
	while head < queue.size():
		var t := queue[head]
		head += 1
		for d in RAMP_DIRS:
			var n := t + d
			if _map.walkable(n) and reach[_map.index(n)] == 0:
				reach[_map.index(n)] = 1
				queue.append(n)
	return reach


func _flood_plateau(from: Vector2i, inner: PackedByteArray, seen: PackedByteArray) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [from]
	seen[_map.index(from)] = 1
	var head := 0
	while head < tiles.size():
		var t := tiles[head]
		head += 1
		for d in RAMP_DIRS:
			var n := t + d
			if _map.in_bounds(n) and inner[_map.index(n)] != 0 and seen[_map.index(n)] == 0:
				seen[_map.index(n)] = 1
				tiles.append(n)
	return tiles


## Chooses this plateau's ramps: camera-facing when one exists, spread apart.
func _pick_ramps(tiles: Array[Vector2i], inner: PackedByteArray, reach: PackedByteArray, rng: RandomNumberGenerator) -> Array:
	var candidates := []
	for t in tiles:
		for k in RAMP_DIRS.size():
			var ramp := _ramp_from(t, RAMP_DIRS[k], inner, reach)
			if not ramp.is_empty():
				ramp["south"] = k < 2
				candidates.append(ramp)
	if candidates.is_empty():
		return []
	var south := candidates.filter(func(c): return c["south"])
	var pool: Array = south if not south.is_empty() else candidates
	var chosen: Array = [pool[rng.randi() % pool.size()]]
	var wanted := clampi(tiles.size() / maxi(1, int(cfg.get("plateau_tiles_per_ramp", 70))), 1, int(cfg.get("plateau_max_ramps", 3)))
	var spacing := float(cfg.get("plateau_ramp_spacing", 14.0))
	while chosen.size() < wanted:
		var best := {}
		var best_d := spacing
		for c in candidates:
			var d := INF
			for r in chosen:
				d = minf(d, Vector2(c["foot"] - r["foot"]).length())
			if d >= best_d:
				best_d = d
				best = c
		if best.is_empty():
			break
		chosen.append(best)
	return chosen


## The straight cut from plateau tile `t` through the rim in direction `dir`,
## "ramp_half_width" tiles to each side, ending on reachable ground. Empty if
## the rim is too thick or the cut does not land there.
func _ramp_from(t: Vector2i, dir: Vector2i, inner: PackedByteArray, reach: PackedByteArray) -> Dictionary:
	var side := Vector2i(dir.y, dir.x)
	var half := int(cfg.get("ramp_half_width", 1))
	var cells: Array[Vector2i] = []
	var p := t + dir
	if not _map.in_bounds(p) or inner[_map.index(p)] != 0:
		return {}
	for step in int(cfg.get("ramp_max_length", 6)):
		if not _map.in_bounds(p):
			return {}
		if _map.get_terrain(p) != T.MOUNTAIN:
			return {"cells": cells, "foot": p} if reach[_map.index(p)] != 0 and not cells.is_empty() else {}
		if inner[_map.index(p)] != 0:
			return {}
		for w in range(-half, half + 1):
			var c := p + side * w
			if not _map.in_bounds(c) or _map.get_terrain(c) != T.MOUNTAIN:
				return {}
			cells.append(c)
		p += dir
	return {}


## Ground life: every terrain draws from its "decor_sprites" list. A noise field
## gathers it into patches, where tiles are denser and use "decor_patch_sprites"
## (flower beds, mushroom rings) instead of an even sprinkle. Runs last, so its
## random draws never move anything that matters to play.
func _place_decor() -> void:
	var density: float = cfg.get("decor_density", 0.12)
	var threshold := float(cfg.get("decor_patch_threshold", 0.56))
	var boost := float(cfg.get("decor_patch_boost", 2.2))
	var rock_keep := float(cfg.get("decor_rock_keep", 1.0))
	var patches := _noise(_map.seed + 271, float(cfg.get("decor_patch_frequency", 9.0)), 2)
	var names: Array = T.keys()
	var lists: Dictionary = cfg.get("decor_sprites", {})
	var patch_lists: Dictionary = cfg.get("decor_patch_sprites", {})
	for y in _map.height:
		for x in _map.width:
			var t := Vector2i(x, y)
			if _map.is_blocked(t):
				continue
			var key := String(names[_map.get_terrain(t)]).to_lower()
			var in_patch: bool = patches.get_noise_2d(x, y) * 0.5 + 0.5 > threshold and patch_lists.has(key)
			if _rng.randf() >= density * (boost if in_patch else 1.0):
				continue
			var list: Array = patch_lists[key] if in_patch else lists.get(key, [])
			if list.is_empty():
				continue
			var sprite := String(list[_rng.randi() % list.size()])
			# Loose rocks stay rare: only this share of the ones rolled is kept.
			if sprite.begins_with("pebble") or sprite.begins_with("stone"):
				if _rng.randf() >= rock_keep:
					continue
			var jitter := Vector2(_rng.randf_range(0.2, 0.8), _rng.randf_range(0.2, 0.8))
			_map.decor.append({"sprite": sprite, "pos": Vector2(t) + jitter, "tall": sprite.begins_with("shrub")})

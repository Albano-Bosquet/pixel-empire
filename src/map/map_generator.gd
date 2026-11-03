class_name MapGenerator
extends RefCounted
## Procedural map generation (design/game-brief.md, MVP item 1).
## Pure function of (config, size, seed, player count, map type): same inputs, same map.
## Map types (map_generation.json "map_types"):
##   continental — noise terrain, roads join every start through the centre.
##   coast       — an inland sea fills the centre; a land ring joins the starts.
##   islands     — every player on an island of their own (ships needed to meet).
## Fish shoals are placed on open water for every type.
## Example:
##   var map := MapGenerator.new(GameData.map_gen, GameData.resource_nodes).generate(96, 1234, 2, "islands")

const T := MapData.Terrain

var cfg: Dictionary
var resource_defs: Dictionary
var _rng := RandomNumberGenerator.new()
var _map: MapData
var _reserved: PackedByteArray  # tiles that must stay free (start areas, roads)
var _type := "continental"
var _type_cfg: Dictionary = {}
var _start_angle := NAN


func _init(config: Dictionary, resource_node_defs: Dictionary = {}) -> void:
	cfg = config
	resource_defs = resource_node_defs


func generate(size: int, map_seed: int, player_count: int, map_type: String = "continental") -> MapData:
	_rng.seed = map_seed
	_map = MapData.new(size, size, map_seed)
	_reserved.resize(size * size)
	_reserved.fill(0)
	_type = map_type if cfg.get("map_types", {}).has(map_type) else "continental"
	_type_cfg = cfg.get("map_types", {}).get(_type, {})
	_build_fields(map_seed)
	if _type != "continental":
		# Water maps fix the start angle first so the landmass can follow it.
		var shape_rng := RandomNumberGenerator.new()
		shape_rng.seed = map_seed + 31337
		_start_angle = shape_rng.randf() * TAU
		_shape_water(maxi(player_count, 1), shape_rng)
	_classify_terrain()
	_place_starts(maxi(player_count, 1))
	if _type == "continental":
		_carve_roads()
	elif _type == "coast":
		_carve_ring_road()
	_place_trees()
	_place_player_resources()
	_place_start_woods()
	_place_extra_resources()
	_place_fish()
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
			if _type == "coast":
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


func _classify_terrain() -> void:
	var dirt_noise := _noise(_map.seed + 104729, 6.0, 2)
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
			elif e < cfg.get("beach_level", 0.345):
				t = T.SAND
			elif e > cfg.get("mountain_level", 0.76):
				t = T.MOUNTAIN
			elif e > cfg.get("rocky_level", 0.70):
				t = T.ROCKY
			elif m > cfg.get("forest_moisture", 0.6):
				t = T.FOREST
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


## Wobbly dirt roads from each start to the map centre. They guarantee every
## start is connected by land (roads ford rivers and cut mountain passes).
func _carve_roads() -> void:
	var center := Vector2(_map.width, _map.height) * 0.5
	for s in _map.start_positions:
		var pos := Vector2(s) + Vector2(0.5, 0.5)
		var heading := (center - pos).normalized()
		var guard := 0
		while pos.distance_to(center) > 1.5 and guard < _map.width * 4:
			guard += 1
			var to_center := (center - pos).normalized()
			heading = (heading + to_center * 0.35 + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))).normalized()
			pos += heading * 0.7
			for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var t: Vector2i = Vector2i(floori(pos.x), floori(pos.y)) + o
				if not _map.in_bounds(t):
					continue
				var cur := _map.get_terrain(t)
				if cur == T.DEEP_WATER or cur == T.WATER:
					_map.set_terrain(t, T.SAND)
				elif cur != T.DIRT:
					_map.set_terrain(t, T.PATH)
				_reserved[_map.index(t)] = 1


## Coast maps: a road along the start ring links every start to its neighbours
## around the inland sea (fords water, cuts mountains, keeps forests out).
func _carve_ring_road() -> void:
	var center := Vector2(_map.width, _map.height) * 0.5
	var ring := float(cfg.get("start_ring_radius", 0.33)) * _map.width
	var steps := roundi(TAU * ring * 1.6)
	for i in steps:
		var a := _start_angle + TAU * i / steps
		var pos := center + Vector2(cos(a), sin(a)) * ring
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var t: Vector2i = Vector2i(floori(pos.x), floori(pos.y)) + o
			if not _map.in_bounds(t):
				continue
			var cur := _map.get_terrain(t)
			if cur == T.DEEP_WATER or cur == T.WATER:
				_map.set_terrain(t, T.SAND)
			elif cur != T.DIRT:
				_map.set_terrain(t, T.PATH)
			_reserved[_map.index(t)] = 1


# --- Objects ----------------------------------------------------------------

func _free(t: Vector2i) -> bool:
	return _map.in_bounds(t) and _map.walkable(t) and _reserved[_map.index(t)] == 0


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
			var p := 0.0
			if ter == T.FOREST:
				p = forest_density
			elif ter == T.GRASS or ter == T.MEADOW or ter == T.ROCKY:
				p = lone_density
			if _rng.randf() < p:
				var e := _map.elevation[_map.index(t)]
				_add_resource("tree_pine" if e > pine_e or ter == T.ROCKY else "tree_oak", t)


func _place_cluster(type: String, around: Vector2i, size: int) -> bool:
	if not _free(around):
		return false
	var cluster: Array[Vector2i] = [around]
	var frontier: Array[Vector2i] = [around]
	var tries := 0
	while cluster.size() < size and not frontier.is_empty() and tries < size * 12:
		tries += 1
		var base: Vector2i = frontier[_rng.randi() % frontier.size()]
		var n: Vector2i = base + [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][_rng.randi() % 4]
		if _free(n) and not cluster.has(n):
			cluster.append(n)
			frontier.append(n)
	for t in cluster:
		_add_resource(type, t)
	return true


func _place_player_resources() -> void:
	var rules: Dictionary = cfg.get("player_resources", {})
	for s in _map.start_positions:
		for type in rules:
			var r: Dictionary = rules[type]
			for c in int(r.get("clusters", 1)):
				for attempt in 40:
					var a := _rng.randf() * TAU
					var d := _rng.randf_range(r.get("min_dist", 6), r.get("max_dist", 10))
					var t := s + Vector2i(roundi(cos(a) * d), roundi(sin(a) * d))
					if _map.in_bounds(t) and _reserved_ok_for_start_resource(t) and _place_cluster(type, t, int(r.get("cluster_size", 4))):
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


## Player resources sit at the edge of the cleared start area, so they may use
## reserved start tiles but never road tiles.
func _reserved_ok_for_start_resource(t: Vector2i) -> bool:
	if _map.get_terrain(t) == T.PATH:
		return false
	_reserved[_map.index(t)] = 0
	return true


func _place_extra_resources() -> void:
	var per: Dictionary = cfg.get("extra_resource_clusters_per_100_tiles_side", {})
	for type in per:
		var count := roundi(float(per[type]) * _map.width / 100.0)
		for i in count:
			for attempt in 60:
				var t := Vector2i(_rng.randi_range(4, _map.width - 5), _rng.randi_range(4, _map.height - 5))
				var far := true
				for s in _map.start_positions:
					if Vector2(s).distance_to(Vector2(t)) < 14.0:
						far = false
				if far and _place_cluster(type, t, _rng.randi_range(3, 6)):
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


func _place_decor() -> void:
	var density: float = cfg.get("decor_density", 0.12)
	var crag_density: float = cfg.get("mountain_crag_density", 0.55)
	for y in _map.height:
		for x in _map.width:
			var t := Vector2i(x, y)
			var ter := _map.get_terrain(t)
			var jitter := Vector2(_rng.randf_range(0.2, 0.8), _rng.randf_range(0.2, 0.8))
			if ter == T.MOUNTAIN:
				if _rng.randf() < crag_density:
					_map.decor.append({"sprite": "crag_%d" % (_rng.randi() % 4), "pos": Vector2(t) + jitter, "tall": true})
				continue
			if _map.is_blocked(t) or _rng.randf() >= density:
				continue
			var sprite := ""
			match ter:
				T.GRASS:
					sprite = ["tuft_0", "tuft_1", "tuft_2", "shrub_0", "pebble_0"][_rng.randi() % 5]
				T.MEADOW:
					sprite = ["flowers_0", "flowers_1", "tuft_1", "tuft_2"][_rng.randi() % 4]
				T.FOREST:
					sprite = ["mushroom_0", "shrub_1", "tuft_0"][_rng.randi() % 3]
				T.DIRT, T.ROCKY, T.SAND:
					sprite = ["pebble_0", "pebble_1", "pebble_2"][_rng.randi() % 3]
			if sprite != "":
				_map.decor.append({"sprite": sprite, "pos": Vector2(t) + jitter, "tall": sprite.begins_with("shrub")})

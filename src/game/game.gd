class_name Game
extends Node2D
## One match: owns the map, pathfinder, players and entity registry, builds the
## scene graph and wires the systems together (architecture.md §3).
## Example:
##   var game := Game.new(); add_child(game)
##   game.start({"mode": "sandbox", "size": "small", "seed": 42})

var config: Dictionary
var map: MapData
var pathfinder: Pathfinder
## Ships move on this grid (water open, land solid).
var naval_pathfinder: Pathfinder
var players: Array[PlayerState] = []
var local_player := 1

var terrain: TerrainRenderer
var decor: DecorLayer
var ground_fx: GroundFx
var entities_root: Node2D
var overlay: SelectionOverlay
var camera: RtsCamera
var systems: Node
var unit_system: UnitSystem
var selection: SelectionSystem
var commands: CommandSystem
var buildings: BuildingSystem
var economy: EconomySystem
var production: ProductionSystem
var placement: PlacementController
var combat: CombatSystem
var techs: TechSystem
var market: MarketSystem
var monks: MonkSystem
var naval: NavalSystem
var air: AirSystem
var victory: VictorySystem
var fog: FogSystem
var fx: FxLayer
var ai_players: Array[AIPlayer] = []
var world: Node2D
var hud: Hud

var _static_at: Dictionary = {}
## entity_id -> Entity for every unit, building and resource node (orders and
## network snapshots refer to entities by id).
var _entities: Dictionary = {}
var orders: OrderRouter
## Multiplayer state sync (null in single player).
var replicator: Replicator
var _next_id := 1


## config keys: mode ("sandbox" | "skirmish"), size (name in map_generation.json
## or int), seed (int, 0 = random), players (Array of {name, ai}),
## difficulty ("easy" | "normal" | "hard"), fog (bool, default true),
## victory ("conquest" | "town_center"), showcase (bool: title-screen backdrop,
## no HUD, no input, no victory checks).
func start(cfg: Dictionary) -> void:
	config = cfg
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var gen_cfg: Dictionary = GameData.map_gen
	var size_v: Variant = cfg.get("size", gen_cfg.get("default_size", "small"))
	var size: int = size_v if size_v is int else int(gen_cfg.get("sizes", {}).get(size_v, 96))
	var map_seed: int = cfg.get("seed", 0)
	if map_seed == 0:
		map_seed = randi() % 1000000 + 1
	var player_defs: Array = cfg.get("players", [{"name": tr("Player"), "ai": false}])
	if cfg.get("mode", "sandbox") == "skirmish" and player_defs.size() < 2:
		player_defs.append({"name": tr("Computer"), "ai": true})

	seed(map_seed)  # reproducible matches: global randomness follows the map seed
	map = MapGenerator.new(gen_cfg, GameData.resource_nodes).generate(size, map_seed, player_defs.size(), String(cfg.get("map_type", gen_cfg.get("default_map_type", "continental"))))
	pathfinder = Pathfinder.new(map)
	naval_pathfinder = Pathfinder.new(map, true)
	for i in player_defs.size():
		players.append(PlayerState.new(i + 1, player_defs[i].get("name", tr("Player %d") % (i + 1)), i, player_defs[i].get("ai", false), GameData.players.get("starting_resources", {})))

	local_player = int(cfg.get("local_player", 1))
	_build_scene()
	_spawn_resources()
	_spawn_tall_decor()
	if cfg.get("net", false):
		replicator = Replicator.new()
		replicator.name = "Replicator"
		add_child(replicator)
		replicator.setup(self)
	if cfg.get("replica", false):
		_make_replica()
	for p in players:
		if cfg.get("replica", false):
			break
		_spawn_start_buildings(p)
		_spawn_start_units(p)
	for p in players:
		if cfg.get("replica", false):
			break
		if p.is_ai:
			var ai := AIPlayer.new()
			ai.name = "AI_%d" % p.id
			systems.add_child(ai)
			ai.setup(self, p, String(cfg.get("difficulty", "normal")))
			ai_players.append(ai)
	fog.update_now()
	camera.focus_world(Iso.grid_to_world(Iso.tile_center(map.start_positions[local_player - 1])))
	if cfg.get("showcase", false):
		_make_showcase()
	else:
		hud.setup(self)
	EventBus.game_started.emit(self)
	print("Game started: seed=%d size=%d players=%d entities=%d" % [map_seed, size, players.size(), _next_id - 1])


func _build_scene() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	terrain = TerrainRenderer.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	terrain.build(map)
	decor = DecorLayer.new()
	decor.name = "Decor"
	decor.z_index = -50
	world.add_child(decor)
	decor.build(map)
	ground_fx = GroundFx.new()
	ground_fx.name = "GroundFx"
	ground_fx.z_index = -40
	world.add_child(ground_fx)
	entities_root = Node2D.new()
	entities_root.name = "Entities"
	entities_root.y_sort_enabled = true
	world.add_child(entities_root)
	fx = FxLayer.new()
	fx.name = "Fx"
	world.add_child(fx)
	overlay = SelectionOverlay.new()
	overlay.name = "Overlay"
	world.add_child(overlay)
	overlay.setup(self)

	camera = RtsCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.configure(Iso.map_world_rect(map.width, map.height), GameData.camera)
	camera.make_current()

	systems = Node.new()
	systems.name = "Systems"
	add_child(systems)
	unit_system = UnitSystem.new()
	unit_system.name = "UnitSystem"
	systems.add_child(unit_system)
	unit_system.setup(map, pathfinder, GameData.movement, naval_pathfinder)
	selection = SelectionSystem.new()
	selection.name = "SelectionSystem"
	systems.add_child(selection)
	selection.setup(self)
	orders = OrderRouter.new()
	orders.name = "OrderRouter"
	systems.add_child(orders)
	orders.setup(self)
	commands = CommandSystem.new()
	commands.name = "CommandSystem"
	systems.add_child(commands)
	commands.setup(self, GameData.movement)
	buildings = BuildingSystem.new()
	buildings.name = "BuildingSystem"
	systems.add_child(buildings)
	buildings.setup(self, GameData.economy)
	economy = EconomySystem.new()
	economy.name = "EconomySystem"
	systems.add_child(economy)
	economy.setup(self, GameData.economy)
	production = ProductionSystem.new()
	production.name = "ProductionSystem"
	systems.add_child(production)
	production.setup(self, GameData.economy)
	techs = TechSystem.new()
	techs.name = "TechSystem"
	systems.add_child(techs)
	techs.setup(self)
	market = MarketSystem.new()
	market.name = "MarketSystem"
	systems.add_child(market)
	market.setup(self, GameData.economy.get("market", {}))
	air = AirSystem.new()
	air.name = "AirSystem"
	systems.add_child(air)
	air.setup(self, GameData.combat.get("air", {}))
	naval = NavalSystem.new()
	naval.name = "NavalSystem"
	systems.add_child(naval)
	naval.setup(self, GameData.combat.get("naval", {}))
	monks = MonkSystem.new()
	monks.name = "MonkSystem"
	systems.add_child(monks)
	monks.setup(self, GameData.combat.get("monk", {}))
	combat = CombatSystem.new()
	combat.name = "CombatSystem"
	systems.add_child(combat)
	combat.setup(self, GameData.combat)
	fog = FogSystem.new()
	fog.name = "FogSystem"
	systems.add_child(fog)
	fog.setup(self, GameData.combat, bool(config.get("fog", true)))
	victory = VictorySystem.new()
	victory.name = "VictorySystem"
	systems.add_child(victory)
	victory.setup(self, GameData.rules, String(config.get("victory", GameData.rules.get("default_victory", "conquest"))))
	# Added after the systems so it receives unhandled input first.
	placement = PlacementController.new()
	placement.name = "Placement"
	add_child(placement)
	placement.setup(self)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)


## Recreates the HUD (e.g. after a language change); keeps the selection.
func rebuild_hud() -> void:
	var keep: Array = selection.selected.duplicate()
	remove_child(hud)
	hud.free()
	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)
	EventBus.selection_changed.emit(keep)


func _spawn_resources() -> void:
	for s in map.resource_spawns:
		var node := ResourceNode.new()
		node.entity_id = _alloc_id()
		node.setup(s["type"], GameData.resource_node(s["type"]), s["tile"], s["variant"])
		register_entity(node)
		entities_root.add_child(node)
		_static_at[s["tile"]] = node
		node.depleted.connect(_on_resource_depleted)


func _spawn_tall_decor() -> void:
	for d in map.decor:
		if not d["tall"]:
			continue
		var r := SpriteLibrary.prop(d["sprite"])
		var sp := Sprite2D.new()
		sp.texture = SpriteLibrary.props_texture()
		sp.region_enabled = true
		sp.region_rect = r["rect"]
		sp.centered = false
		sp.offset = -r["anchor"]
		sp.position = Iso.grid_to_world(d["pos"]).round()
		entities_root.add_child(sp)


func _spawn_start_buildings(p: PlayerState) -> void:
	var start := map.start_positions[p.id - 1]
	for type_id in GameData.players.get("starting_buildings", []):
		var s: int = GameData.building(type_id).get("size", 1)
		var origin := start - Vector2i(s / 2, s / 2)
		if buildings.placement_error(type_id, origin) == "":
			buildings.place(type_id, p.id, origin, true)


func _spawn_start_units(p: PlayerState) -> void:
	var start := map.start_positions[p.id - 1]
	var units: Dictionary = GameData.players.get("starting_units", {"villager": 3})
	var total := 0
	for id in units:
		total += int(units[id])
	var i := 0
	for id in units:
		for k in int(units[id]):
			var a := TAU * i / maxi(total, 1) + 0.6
			spawn_unit(id, p.id, Iso.tile_center(start) + Vector2(cos(a), sin(a)) * 3.4)
			i += 1


## Creates a unit for `player_id` at grid position `at` (nearest walkable spot).
func spawn_unit(unit_id: String, player_id: int, at: Vector2) -> Unit:
	var pf := nav_for(GameData.unit(unit_id))
	var t := pf.nearest_walkable(Iso.tile_of(at), 10)
	if t.x < 0:
		return null
	var pos := at if t == Iso.tile_of(at) else Iso.tile_center(t)
	var u := Unit.new()
	u.entity_id = _alloc_id()
	u.setup(unit_id, GameData.unit(unit_id), player_id, player(player_id).color_slot, pos)
	register_entity(u)
	entities_root.add_child(u)
	unit_system.register(u)
	combat.track(u)
	techs.apply_unit(u)
	if fog != null and player_id != local_player:
		u.visible = fog.is_visible(local_player, u)
	EventBus.entity_spawned.emit(u)
	return u


## Removes a dead unit from the simulation; its corpse lingers then is freed.
func kill_unit(u: Unit) -> void:
	u.die()
	economy.clear_task(u)
	unit_system.retire(u, float(GameData.combat.get("corpse_seconds", 6.0)))
	selection.prune.call_deferred()


## Title-screen backdrop: no HUD, no player input, no victory checks.
func _make_showcase() -> void:
	hud.visible = false
	camera.input_enabled = false
	for n in [selection, commands, placement]:
		n.set_process_unhandled_input(false)
	victory.set_physics_process(false)
	set_process_unhandled_key_input(false)


## The live entity with `id`, or null.
func entity(id: int) -> Entity:
	var e: Variant = _entities.get(id)
	if e == null or not is_instance_valid(e):
		return null
	return e


func register_entity(e: Entity) -> void:
	_entities[e.entity_id] = e


func alloc_id() -> int:
	return _alloc_id()


func _alloc_id() -> int:
	_next_id += 1
	return _next_id - 1


func player(id: int) -> PlayerState:
	return players[id - 1]


func local_state() -> PlayerState:
	return player(local_player)


func population_cap(player_id: int) -> int:
	return buildings.population_cap(player_id)


## Technology multiplier for a villager's gather rate (PlayerState.modifiers).
func gather_multiplier(player_id: int, resource: String) -> float:
	return player(player_id).modifier("gather_" + resource)


func register_static(t: Vector2i, e: Entity) -> void:
	_static_at[t] = e


## Multiplayer client: the host simulates, this machine only draws snapshots.
func _make_replica() -> void:
	unit_system.simulate = false
	for n in [economy, production, combat, victory, market, monks, naval, air]:
		n.set_physics_process(false)


## Creates a unit mirrored from the host (keeps the host's entity id).
func spawn_replica_unit(id: int, unit_id: String, player_id: int, at: Vector2) -> Unit:
	if player(player_id) == null:
		return null
	var u := Unit.new()
	u.entity_id = id
	u.setup(unit_id, GameData.unit(unit_id), player_id, player(player_id).color_slot, at)
	register_entity(u)
	entities_root.add_child(u)
	unit_system.register(u)
	return u


## The grid a unit with definition `unit_def` moves on (ships: water grid).
func nav_for(unit_def: Dictionary) -> Pathfinder:
	return naval_pathfinder if unit_def.get("naval", false) else pathfinder


func nav(u: Unit) -> Pathfinder:
	return nav_for(u.def)


## Re-reads a tile into both the land and the water grids.
func refresh_nav(t: Vector2i) -> void:
	pathfinder.refresh_tile(t)
	naval_pathfinder.refresh_tile(t)


func unregister_static(t: Vector2i) -> void:
	_static_at.erase(t)


## A depleted node frees its tile; trees leave a stump decoration.
func _on_resource_depleted(node: ResourceNode) -> void:
	var t := node.tile()
	_static_at.erase(t)
	map.set_blocked(t, false)
	refresh_nav(t)
	EventBus.resource_depleted.emit(node)
	if node.resource_type == "wood":
		var r := SpriteLibrary.prop("stump_0")
		var sp := Sprite2D.new()
		sp.texture = SpriteLibrary.props_texture()
		sp.region_enabled = true
		sp.region_rect = r["rect"]
		sp.centered = false
		sp.offset = -r["anchor"]
		sp.position = node.position
		entities_root.add_child(sp)
	EventBus.entity_removed.emit(node)
	node.queue_free()
	selection.prune.call_deferred()


func population(player_id: int) -> int:
	var n := 0
	for u in unit_system.units:
		if u.owner_id == player_id:
			n += 1
	return n


func static_entity_at(t: Vector2i) -> Entity:
	return _static_at.get(t, null)


func world_from_screen(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


func screen_from_world(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


## Developer shortcuts: F8 toggles fog of war, F9 spawns 10 villagers at the cursor.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		fog.set_enabled(not fog.enabled)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		var g := Iso.world_to_grid(get_global_mouse_position())
		for i in 10:
			spawn_unit("villager", local_player, g + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)))

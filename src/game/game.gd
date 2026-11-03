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
var xray: OcclusionXray
## Food carcasses on the map (pruned of freed ones by OcclusionXray).
var carcasses: Array = []
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
var wildlife: WildlifeSystem
var victory: VictorySystem
var fog: FogSystem
var fx: FxLayer
var ai_players: Array[AIPlayer] = []
var world: Node2D
var hud: Hud
## Positional sound, ambience and music of this match.
var audio: GameAudio
## Day/night cycle (cosmetic; GameAudio follows it).
var day_night: DayNight
var ambient_life: AmbientLife

var _static_at: Dictionary = {}
## entity_id -> Entity for every unit, building and resource node (orders and
## network snapshots refer to entities by id).
var _entities: Dictionary = {}
var orders: OrderRouter
## Multiplayer state sync (null in single player).
var replicator: Replicator
var _next_id := 1
## Grid positions of tree stumps (saves).
var stumps: Array = []
var _autosave_timer := 0.0


## config keys: mode ("sandbox" | "skirmish"), size (name in map_generation.json
## or int), seed (int, 0 = random), players (Array of {name, ai, difficulty,
## team}), difficulty ("easy" | "normal" | "hard", default for AIs without
## one), fog (bool, default true), victory ("conquest" | "town_center"),
## showcase (bool: title-screen backdrop, no HUD, no input, no victory checks).
## Match options (MatchConfig): resources (preset id), start_age (int),
## population (int limit), speed (preset id), reveal ("normal" | "explored" |
## "visible"), animals (wildlife preset id), day_night (bool).
func start(cfg: Dictionary) -> void:
	var save: Dictionary = cfg.get("save", {})
	if not save.is_empty():
		# Loading: the saved config regenerates the same map; the save fills it.
		cfg = save["config"].duplicate(true)
		cfg["save"] = save
		cfg["local_player"] = int(save.get("local_player", 1))
	config = cfg
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var gen_cfg: Dictionary = GameData.map_gen
	var size_v: Variant = cfg.get("size", gen_cfg.get("default_size", "small"))
	var size: int = size_v if size_v is int else int(gen_cfg.get("sizes", {}).get(size_v, 96))
	var map_seed: int = cfg.get("seed", 0)
	if map_seed == 0:
		map_seed = randi() % 1000000 + 1
	config["seed"] = map_seed
	var player_defs: Array = cfg.get("players", [{"name": tr("Player"), "ai": false}])
	if cfg.get("mode", "sandbox") == "skirmish" and player_defs.size() < 2:
		player_defs.append({"name": tr("Computer"), "ai": true})

	seed(map_seed)  # reproducible matches: global randomness follows the map seed
	map = MapGenerator.new(gen_cfg, GameData.resource_nodes).generate(size, map_seed, player_defs.size(), String(cfg.get("map_type", gen_cfg.get("default_map_type", "continental"))))
	pathfinder = Pathfinder.new(map)
	naval_pathfinder = Pathfinder.new(map, true)
	var stock: Dictionary = MatchConfig.starting_resources(String(cfg.get("resources", GameData.rules.get("default_starting_resources", "standard"))))
	if not save.is_empty():
		players = SaveGame.make_players(save)
	else:
		for i in player_defs.size():
			var ps := PlayerState.new(i + 1, player_defs[i].get("name", tr("Player %d") % (i + 1)), i, player_defs[i].get("ai", false), stock)
			ps.age = int(cfg.get("start_age", 0))
			ps.team = int(player_defs[i].get("team", 0))
			players.append(ps)
	CombatSystem.teams = {}
	for p0 in players:
		CombatSystem.teams[p0.id] = p0.team

	local_player = int(cfg.get("local_player", 1))
	_build_scene()
	if not save.is_empty():
		_next_id = maxi(_next_id, int(save.get("next_id", 1)))
	if cfg.has("population"):
		buildings.max_population = int(cfg["population"])
	if String(cfg.get("reveal", "normal")) == "explored":
		fog.pending_reveal = true
	if not cfg.get("showcase", false):
		Engine.time_scale = MatchConfig.speed_scale(String(cfg.get("speed", "normal")))
	if save.is_empty():
		_spawn_resources()
	_spawn_tall_decor()
	if cfg.get("net", false):
		replicator = Replicator.new()
		replicator.name = "Replicator"
		add_child(replicator)
		replicator.setup(self)
	if cfg.get("replica", false):
		_make_replica()
	if not save.is_empty():
		SaveGame.restore_world(self, save)
	for p in players:
		if cfg.get("replica", false) or not save.is_empty():
			break
		_spawn_start_buildings(p)
		_spawn_start_units(p)
	if not cfg.get("replica", false) and not cfg.get("showcase", false) and save.is_empty():
		var animals: Dictionary = GameData.rules.get("wild_animals_menu", {})
		wildlife.spawn_initial(float(animals.get(String(cfg.get("animals", GameData.rules.get("default_wild_animals", "normal"))), 1.0)))
	for p in players:
		if cfg.get("replica", false):
			break
		if p.is_ai:
			var ai := AIPlayer.new()
			ai.name = "AI_%d" % p.id
			systems.add_child(ai)
			ai.setup(self, p, String(player_defs[p.id - 1].get("difficulty", cfg.get("difficulty", "normal"))))
			ai_players.append(ai)
	if not save.is_empty():
		SaveGame.restore_ai(self, save)
		for p1 in players:
			if p1.is_ai and p1.defeated:
				for ai2 in ai_players:
					if ai2.player == p1:
						ai2.set_physics_process(false)
	fog.update_now()
	camera.focus_world(Iso.grid_to_world(Iso.tile_center(map.start_positions[local_player - 1])))
	if not save.is_empty():
		camera.position = save.get("camera", {}).get("pos", camera.position)
		camera.set_zoom_index(int(save.get("camera", {}).get("zoom", camera.zoom_index)))
	if cfg.get("showcase", false):
		_make_showcase()
	else:
		hud.setup(self)
	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(self, GameData.ambience, bool(cfg.get("day_night", true)) and not cfg.get("showcase", false))
	if not save.is_empty():
		day_night.time = float(save.get("day_night", day_night.time))
	ambient_life = AmbientLife.new()
	ambient_life.name = "AmbientLife"
	world.add_child(ambient_life)
	ambient_life.setup(self, GameData.ambience, day_night)
	audio = GameAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(self)
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
	xray = OcclusionXray.new()
	xray.name = "OcclusionXray"
	add_child(xray)
	xray.setup(self, GameData.sprites.get("xray", {}))

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
	wildlife = WildlifeSystem.new()
	wildlife.name = "WildlifeSystem"
	systems.add_child(wildlife)
	wildlife.setup(self, GameData.wildlife)
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
		spawn_resource_node(s["type"], s["tile"], s["variant"])


## Creates a resource node on `tile` (`amount` < 0 = full; `id` > 0 when loading).
func spawn_resource_node(type_id: String, tile: Vector2i, variant: int, amount: float = -1.0, id: int = 0) -> ResourceNode:
	var node := ResourceNode.new()
	node.entity_id = id if id > 0 else _alloc_id()
	node.setup(type_id, GameData.resource_node(type_id), tile, variant)
	if amount >= 0.0:
		node.amount = amount
		node.hp = ceili(amount)
	register_entity(node)
	entities_root.add_child(node)
	_static_at[tile] = node
	node.depleted.connect(_on_resource_depleted)
	return node


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
## `id` > 0 keeps a saved entity id (loading).
func spawn_unit(unit_id: String, player_id: int, at: Vector2, id: int = 0) -> Unit:
	var pf := nav_for(GameData.unit(unit_id))
	var t := pf.nearest_walkable(Iso.tile_of(at), 10)
	if t.x < 0:
		return null
	var pos := at if t == Iso.tile_of(at) else Iso.tile_center(t)
	var u := Unit.new()
	u.entity_id = id if id > 0 else _alloc_id()
	u.setup(unit_id, GameData.unit(unit_id), player_id, color_slot_of(player_id), pos)
	register_entity(u)
	entities_root.add_child(u)
	unit_system.register(u)
	combat.track(u)
	if u.def.has("animal"):
		u.damaged.connect(func(e: Entity, a: Entity, _n: int) -> void: wildlife.on_damaged(e, a))
	techs.apply_unit(u)
	if fog != null and player_id != local_player:
		u.visible = fog.is_visible(local_player, u)
	EventBus.entity_spawned.emit(u)
	return u


## Removes a dead unit from the simulation; its corpse lingers then is freed.
func kill_unit(u: Unit) -> void:
	u.die()
	economy.clear_task(u)
	unit_system.retire(u, float(GameData.combat.get("corpse_seconds", 5.0)), float(GameData.combat.get("corpse_fade_seconds", 5.0)))
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


## The player with `id` (1-based), or null for Gaia (0) and unknown ids.
func player(id: int) -> PlayerState:
	if id < 1 or id > players.size():
		return null
	return players[id - 1]


## Team colour slot of a player id (Gaia uses slot 0; animals ignore it).
func color_slot_of(pid: int) -> int:
	var p := player(pid)
	return p.color_slot if p != null else 0


## Leaves a food carcass where `animal` died (non-blocking; villagers gather it).
## `id` > 0 keeps the host's entity id on network replicas.
func spawn_carcass(animal: Unit, amount: float, id: int = 0) -> ResourceNode:
	var node := ResourceNode.new()
	node.entity_id = id if id > 0 else _alloc_id()
	node.setup_carcass(animal, amount)
	register_entity(node)
	entities_root.add_child(node)
	carcasses.append(node)
	var t := node.tile()
	if not _static_at.has(t):
		_static_at[t] = node
	node.depleted.connect(_on_resource_depleted)
	return node


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
	if player(player_id) == null and player_id != Entity.GAIA:
		return null
	var u := Unit.new()
	u.entity_id = id
	u.setup(unit_id, GameData.unit(unit_id), player_id, color_slot_of(player_id), at)
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
	if _static_at.get(t) == node:
		_static_at.erase(t)
	if not node.def.get("carcass", false):
		map.set_blocked(t, false)
		refresh_nav(t)
	EventBus.resource_depleted.emit(node)
	if node.resource_type == "wood" and not node.def.get("carcass", false):
		EventBus.sound_at.emit("tree_fall", node.position)
		add_stump(node.grid_pos)
	EventBus.entity_removed.emit(node)
	if node.def.get("carcass", false):
		# The last scraps fade away instead of vanishing.
		node.selectable = false
		node.selected = false
		node.dead = true
		var tw := node.create_tween()
		tw.tween_property(node, "modulate:a", 0.0, float(GameData.combat.get("carcass_fade_seconds", 1.5)))
		tw.tween_callback(node.queue_free)
	else:
		node.queue_free()
	selection.prune.call_deferred()


## Leaves a tree stump decoration at grid position `g`.
func add_stump(g: Vector2) -> void:
	stumps.append(g)
	var r := SpriteLibrary.prop("stump_0")
	var sp := Sprite2D.new()
	sp.texture = SpriteLibrary.props_texture()
	sp.region_enabled = true
	sp.region_rect = r["rect"]
	sp.centered = false
	sp.offset = -r["anchor"]
	sp.position = Iso.grid_to_world(g).round()
	entities_root.add_child(sp)


## Single player: saves to `slot` (quick save, autosave). Returns OK or an Error.
func save_to(slot: String, title: String = "") -> int:
	if Net.is_networked() or config.get("showcase", false) or victory.over:
		return ERR_UNAVAILABLE
	var err := SaveGame.write(slot, SaveGame.capture(self), title)
	EventBus.notify.emit(local_player, "Game saved" if err == OK else "Could not save the game")
	return err


func _process(delta: float) -> void:
	if config.get("showcase", false) or Net.is_networked():
		return
	var minutes := float(GameData.rules.get("autosave_minutes", 5.0))
	if minutes <= 0.0:
		return
	_autosave_timer += delta
	if _autosave_timer >= minutes * 60.0:
		_autosave_timer = 0.0
		save_to("autosave", tr("Autosave"))


func population(player_id: int) -> int:
	var n := 0
	for u in unit_system.units:
		if u.owner_id == player_id and not u.def.has("animal"):
			n += 1
	return n


func static_entity_at(t: Vector2i) -> Entity:
	return _static_at.get(t, null)


func world_from_screen(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


func screen_from_world(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


## F5 quick-saves. Developer shortcuts: F8 toggles fog of war, F9 spawns 10 villagers at the cursor.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		save_to("quicksave", tr("Quick save"))
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		fog.set_enabled(not fog.enabled)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		var g := Iso.world_to_grid(get_global_mouse_position())
		for i in 10:
			spawn_unit("villager", local_player, g + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)))

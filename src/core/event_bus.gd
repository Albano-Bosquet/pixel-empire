extends Node
## Global typed signals for cross-system communication (gameplay -> UI, etc.).
## Systems emit; UI and observers connect. No state lives here.

@warning_ignore_start("unused_signal")
signal selection_changed(entities: Array)
signal resources_changed(player_id: int, resources: Dictionary)
signal entity_spawned(entity: Node)
signal entity_removed(entity: Node)
signal move_ordered(grid_pos: Vector2, units: Array)
signal game_started(game: Node)
signal notify(player_id: int, text: String)
signal population_changed(player_id: int)
signal production_changed(building: Node)
signal age_changed(player_id: int, age: int)
signal tech_researched(player_id: int, tech_id: String)
signal player_defeated(player_id: int)
signal game_over(winner_ids: Array)
signal pause_requested
signal under_attack(player_id: int, where: Vector2)
signal entity_killed(entity: Node, attacker: Node)
## A resource node ran out (host -> replicas).
signal resource_depleted(entity: Node)
## Networked match paused / resumed by any player.
signal net_paused(paused: bool)
@warning_ignore_restore("unused_signal")

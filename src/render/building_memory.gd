class_name BuildingMemory
extends Node
## Fog memory of other players' buildings for the local player (design/game-brief.md
## MVP item 1, fog of war). A building appears once actually seen. When it leaves
## sight it is hidden and a still snapshot of its last seen look takes its place, so
## construction, damage or destruction out of sight stay unknown until seen again.
## A snapshot of a building destroyed out of sight lingers until its ground is seen.
## Example: if game.fog.memory.remembers(building): ...

var _game: Game
var _seen: Dictionary = {}    # entity_id -> true: buildings the local player has seen
var _ghosts: Dictionary = {}  # entity_id -> {"node", "building" (null once gone), "origin", "size", "owner"}


func setup(game: Game) -> void:
	_game = game
	EventBus.entity_removed.connect(_on_removed)


## Counts `b` as already seen (restoring a save, which keeps no memory).
func mark_seen(b: Building) -> void:
	_seen[b.entity_id] = true


## Whether `b` is out of sight but shown from memory (still a valid target).
func remembers(b: Entity) -> bool:
	return b != null and _ghosts.has(b.entity_id) and _ghosts[b.entity_id]["building"] == b


## Remembered footprints for the minimap: [{"origin", "size", "owner"}].
func ghosts() -> Array:
	return _ghosts.values()


## Updates what the local player `pid` is shown, after a fog pass.
func refresh(pid: int, fog: FogSystem) -> void:
	for b in _game.buildings.buildings:
		if b.owner_id == pid:
			continue
		var id := b.entity_id
		if not fog.enabled or fog.is_visible(pid, b):
			_seen[id] = true
			b.visible = true
			_drop(id)
		elif b.owner_id == Entity.GAIA:
			b.visible = fog.is_explored(pid, Iso.tile_of(b.grid_pos))
		else:
			b.visible = false
			if _seen.has(id) and not _ghosts.has(id):
				var node := b.memory_snapshot()
				_game.entities_root.add_child(node)
				_ghosts[id] = {"node": node, "building": b, "origin": b.origin, "size": b.size, "owner": b.owner_id}
	for id in _ghosts.keys():
		var g: Dictionary = _ghosts[id]
		if g["building"] == null and (not fog.enabled or _ground_seen(pid, fog, g)):
			_drop(id)


func _ground_seen(pid: int, fog: FogSystem, g: Dictionary) -> bool:
	var o: Vector2i = g["origin"]
	for y in range(o.y, o.y + int(g["size"])):
		for x in range(o.x, o.x + int(g["size"])):
			if fog.is_tile_visible(pid, Vector2i(x, y)):
				return true
	return false


func _drop(id: int) -> void:
	if _ghosts.has(id):
		_ghosts[id]["node"].queue_free()
		_ghosts.erase(id)


func _on_removed(e: Node) -> void:
	if not (e is Building):
		return
	var id: int = e.entity_id
	_seen.erase(id)
	if _ghosts.has(id):
		_ghosts[id]["building"] = null

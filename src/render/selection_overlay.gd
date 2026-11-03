class_name SelectionOverlay
extends Node2D
## Draws health bars above selected entities, on top of all world sprites.

const BAR_W := 20.0
const BAR_H := 3.0
const BAR_OFFSET := Vector2(0, -40)

var _selection: Array = []
var _game: Game
var _bar_seconds := 3.0


func _ready() -> void:
	z_index = 50
	EventBus.selection_changed.connect(func(list: Array) -> void: _selection = list.duplicate())


func setup(game: Game) -> void:
	_game = game
	_bar_seconds = float(GameData.combat.get("damaged_bar_seconds", 3.0))


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var shown: Array = _selection.duplicate()
	if _game:
		for u in _game.unit_system.units:
			if u.since_damaged < _bar_seconds and u.visible and not shown.has(u):
				shown.append(u)
		for b in _game.buildings.buildings:
			if b.since_damaged < _bar_seconds and b.visible and not shown.has(b):
				shown.append(b)
	for e in shown:
		if not is_instance_valid(e) or e.kind == Entity.Kind.RESOURCE or e.dead:
			continue
		var head_y: float = e.visual_top() if e is Building else e.pick_rect.position.y
		var top: Vector2 = e.position + Vector2(-BAR_W * 0.5, head_y - 6.0)
		var frac := clampf(float(e.hp) / maxf(1.0, e.max_hp), 0.0, 1.0)
		draw_rect(Rect2(top - Vector2(1, 1), Vector2(BAR_W + 2, BAR_H + 2)), Color(0.05, 0.05, 0.07, 0.85))
		var col := Color("#5fd35a") if frac > 0.5 else (Color("#e8c53a") if frac > 0.25 else Color("#e0483c"))
		draw_rect(Rect2(top, Vector2(roundf(BAR_W * frac), BAR_H)), col)
		draw_rect(Rect2(top, Vector2(roundf(BAR_W * frac), 1)), col.lightened(0.35))

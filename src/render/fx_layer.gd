class_name FxLayer
extends Node2D
## Pixel particle bursts (hits, blood, dust, debris) and projectile drawing.
## Particles are plain dictionaries updated and drawn here (no node per particle).
## Projectiles are owned by CombatSystem; it hands this layer its live list.

const KINDS := {
	"hit": {"count": 5, "colors": ["#fff6c8", "#ffd35a"], "speed": 40.0, "life": 0.25, "size": 1, "gravity": 0.0},
	"blood": {"count": 6, "colors": ["#8a1c1c", "#b0302a"], "speed": 30.0, "life": 0.45, "size": 1, "gravity": 90.0},
	"dust": {"count": 12, "colors": ["#a8957a", "#8c7a62", "#c9b79a"], "speed": 22.0, "life": 0.7, "size": 2, "gravity": -8.0},
	"chips": {"count": 3, "colors": ["#c9a26b", "#8a5f38"], "speed": 26.0, "life": 0.4, "size": 1, "gravity": 80.0},
	"flash": {"count": 16, "colors": ["#fff6c8", "#ffd35a", "#f08a2a"], "speed": 70.0, "life": 0.35, "size": 2, "gravity": -20.0},
	"smoke": {"count": 8, "colors": ["#d8d8dc", "#b8b8c0"], "speed": 12.0, "life": 1.1, "size": 2, "gravity": -12.0},
	"heal": {"count": 5, "colors": ["#c8ffb8", "#ffffff", "#7be36a"], "speed": 14.0, "life": 0.8, "size": 1, "gravity": -30.0},
	"holy": {"count": 9, "colors": ["#fff6c8", "#ffe27a", "#ffffff"], "speed": 22.0, "life": 0.9, "size": 1, "gravity": -24.0},
	"debris": {"count": 40, "colors": ["#a8957a", "#6b5a48", "#8a857d", "#4a3426"], "speed": 55.0, "life": 1.2, "size": 2, "gravity": 40.0},
}

## Emitted for every burst (the multiplayer host forwards them to clients).
signal burst_emitted(world_pos: Vector2, kind: String)

var projectiles: Array = []
var _parts: Array[Dictionary] = []
var _rock: Dictionary = {}


func _ready() -> void:
	z_index = 45


func burst(world_pos: Vector2, kind: String) -> void:
	burst_emitted.emit(world_pos, kind)
	var k: Dictionary = KINDS.get(kind, KINDS["hit"])
	for i in int(k["count"]):
		var a := randf() * TAU
		var sp := float(k["speed"]) * randf_range(0.4, 1.0)
		_parts.append({
			"p": world_pos + Vector2(randf_range(-2, 2), randf_range(-2, 2)),
			"v": Vector2(cos(a), sin(a) * 0.6 - 0.5) * sp,
			"life": float(k["life"]) * randf_range(0.6, 1.0),
			"col": Color(k["colors"][i % k["colors"].size()]),
			"size": int(k["size"]),
			"g": float(k["gravity"]),
		})


func _process(delta: float) -> void:
	if _parts.is_empty() and projectiles.is_empty():
		return
	for p in _parts:
		p["life"] -= delta
		p["v"].y += p["g"] * delta
		p["p"] += p["v"] * delta
	_parts = _parts.filter(func(p): return p["life"] > 0.0)
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		var s: int = p["size"]
		var col: Color = p["col"]
		col.a = clampf(p["life"] * 3.0, 0.0, 1.0)
		draw_rect(Rect2(p["p"].round(), Vector2(s, s)), col)
	for pr in projectiles:
		var pos: Vector2 = pr["screen"]
		match String(pr["kind"]):
			"rock", "boulder":
				if _rock.is_empty():
					_rock = SpriteLibrary.prop("rock")
				SpriteLibrary.draw_prop(self, "rock", pos.round())
				if pr["kind"] == "boulder":
					SpriteLibrary.draw_prop(self, "rock", pos.round() + Vector2(2, 1))
			"cannonball":
				draw_circle(pos.round(), 2.2, Color("#2a2d33"))
				draw_rect(Rect2(pos.round() - Vector2(1, 1), Vector2(1, 1)), Color("#8a9098"))
			"ballista_bolt":
				var dbb: Vector2 = pr["screen_dir"]
				draw_line((pos - dbb * 14.0).round(), pos.round(), Color("#6e4a2c"), 2.0)
				draw_rect(Rect2(pos.round() - Vector2(1, 1), Vector2(2.5, 2.5)), Color("#c9d0d6"))
			"bullet":
				var db: Vector2 = pr["screen_dir"]
				draw_line((pos - db * 7.0).round(), pos.round(), Color(1.0, 0.92, 0.6, 0.55), 1.0)
				draw_rect(Rect2(pos.round() - Vector2(0.5, 0.5), Vector2(1.5, 1.5)), Color("#2a2d33"))
			"shot", "flak":
				for k in 3:
					draw_rect(Rect2(pos.round() + Vector2((k - 1) * 2, (k % 2) * 2), Vector2(1, 1)), Color("#2a2d33") if pr["kind"] == "shot" else Color("#ffd35a"))
			"grenade", "mortar_shell", "bomb":
				var rr := 2.0 if pr["kind"] == "grenade" else 3.0
				draw_circle(pos.round(), rr, Color("#2a2d33"))
				draw_rect(Rect2(pos.round() + Vector2(0, -rr - 1), Vector2(1, 1)), Color("#ffd35a"))
			"bolt", "javelin":
				var dj: Vector2 = pr["screen_dir"]
				var lj := 7.0 if pr["kind"] == "bolt" else 13.0
				var tj := (pos - dj * lj).round()
				draw_line(tj, pos.round(), Color("#6e4a2c"), 1.5 if pr["kind"] == "javelin" else 1.0)
				draw_rect(Rect2(pos.round() - Vector2(0.5, 0.5), Vector2(2, 2)), Color("#c9d0d6"))
			_:
				var d: Vector2 = pr["screen_dir"]
				var tail := (pos - d * 10.0).round()
				draw_line(tail, pos.round(), Color("#5b3b22"), 1.0)
				draw_rect(Rect2(pos.round() - Vector2(0.5, 0.5), Vector2(1.5, 1.5)), Color("#d7dde2"))
				draw_rect(Rect2(tail - Vector2(0.5, 0.5), Vector2(1, 1)), Color("#f0ece0"))

class_name EndScreen
extends CanvasLayer
## Victory / defeat screen with per-player statistics (PlayerState.stats).
## Buttons emit signals; Main decides what to do (UI owns no game state).

signal continue_pressed
signal restart_pressed
signal menu_pressed

const STAT_ROWS := [
	["Result", "result"], ["Age reached", "age"], ["Food gathered", "food"], ["Wood gathered", "wood"],
	["Gold gathered", "gold"], ["Stone gathered", "stone"], ["Units trained", "units_trained"],
	["Units lost", "units_lost"], ["Kills", "kills"], ["Buildings built", "buildings_built"],
	["Buildings lost", "buildings_lost"], ["Technologies", "techs"],
]


var _again: Button


## Multiplayer matches cannot be restarted from here.
func set_networked() -> void:
	if _again:
		_again.visible = false


func show_results(game: Game, winners: Array) -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UiStyle.dimmer(0.6))
	var pv: Array = UiStyle.centered_panel(root, 640)
	var v: VBoxContainer = pv[1]
	var won := winners.has(game.local_player)
	var sandbox := game.players.size() == 1
	var heading := tr("Victory!") if won else (tr("Game over") if sandbox else tr("Defeat"))
	v.add_child(UiStyle.title(heading, 54))
	var secs := int(game.victory.elapsed)
	var sub := UiStyle.label(tr("%s  ·  %02d:%02d") % [tr(GameData.rules["victory_conditions"][game.victory.condition]["display_name"]), secs / 60, secs % 60], 16, UiStyle.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var grid := GridContainer.new()
	grid.columns = game.players.size() + 1
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	grid.add_child(UiStyle.label(""))
	for p in game.players:
		grid.add_child(UiStyle.label(p.name, 18, p.color().lightened(0.25)))
	for row in STAT_ROWS:
		grid.add_child(UiStyle.label(tr(row[0]), 15, UiStyle.TEXT_DIM))
		for p in game.players:
			grid.add_child(UiStyle.label(_stat(p, row[1], winners), 15))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	if won and not sandbox:
		var cont := UiStyle.button(tr("Keep playing"), 170)
		cont.pressed.connect(func() -> void:
			continue_pressed.emit()
			queue_free())
		buttons.add_child(cont)
	var again := UiStyle.button(tr("Play again"), 170)
	_again = again
	again.pressed.connect(func() -> void: restart_pressed.emit())
	buttons.add_child(again)
	var menu := UiStyle.button(tr("Main menu"), 170)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(menu)
	again.grab_focus()


static func _stat(p: PlayerState, key: String, winners: Array) -> String:
	match key:
		"result":
			return TranslationServer.translate("Winner") if winners.has(p.id) else (TranslationServer.translate("Defeated") if p.defeated else "-")
		"age":
			return TranslationServer.translate(Hud.AGE_NAMES[p.age])
		"food", "wood", "gold", "stone":
			return str(p.stats["gathered"].get(key, 0))
		"techs":
			return str(p.researched.size())
	return str(p.stats.get(key, 0))

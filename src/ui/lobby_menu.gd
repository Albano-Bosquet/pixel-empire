class_name LobbyMenu
extends CanvasLayer
## Multiplayer screen (opened from the title menu).
##   Connect view: player name, "Host a game", join by IP (LAN or VPN address,
##   optional ":port"), and games found on the local network.
##   Lobby view: player slots (host can add AI and remove slots), the host's
##   map settings, ready toggle, chat, Start (host, when everyone is ready).
## All state lives in the Net autoload; this screen only displays it and
## forwards button presses.

signal closed

var _root: Control
var _connect_view: VBoxContainer
var _lobby_view: VBoxContainer
var _name: LineEdit
var _ip: LineEdit
var _status: Label
var _found_box: VBoxContainer
var _slots_box: VBoxContainer
var _addresses: Label
var _chat_log: RichTextLabel
var _chat_line: LineEdit
var _ready_toggle: CheckButton
var _start: Button
var _settings_box: GridContainer
var _map_type: OptionButton
var _size: OptionButton
var _victory: OptionButton
var _fog: CheckButton
var _seed: LineEdit
var _ai_diff: OptionButton
var _add_ai: Button


func _ready() -> void:
	layer = 30
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.add_child(UiStyle.dimmer(0.6))
	var pv: Array = UiStyle.centered_panel(_root, 760)
	var v: VBoxContainer = pv[1]
	v.add_child(UiStyle.title(tr("Multiplayer"), 40))
	_connect_view = VBoxContainer.new()
	_connect_view.add_theme_constant_override("separation", 8)
	v.add_child(_connect_view)
	_lobby_view = VBoxContainer.new()
	_lobby_view.add_theme_constant_override("separation", 8)
	v.add_child(_lobby_view)
	_status = UiStyle.label("", 14, Color("#f0c96a"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	_build_connect()
	_build_lobby()
	Net.lobby_changed.connect(_refresh)
	Net.connection_failed.connect(func(r: String) -> void: _set_status(r))
	Net.session_ended.connect(func(r: String) -> void:
		_set_status(r)
		_refresh())
	Net.chat_received.connect(_on_chat)
	Net.games_found.connect(_on_found)
	Net.match_started.connect(func(_c: Dictionary) -> void: _close())
	Net.browse(true)
	_refresh()


func _build_connect() -> void:
	var row := HBoxContainer.new()
	row.add_child(UiStyle.label(tr("Your name"), 16, UiStyle.TEXT_DIM))
	_name = LineEdit.new()
	_name.text = OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else tr("Player")
	_name.custom_minimum_size = Vector2(260, 34)
	row.add_child(_name)
	_connect_view.add_child(row)
	var host_btn := UiStyle.button(tr("Host a game"), 700)
	host_btn.pressed.connect(func() -> void:
		var err := Net.host(_name.text)
		_set_status(err if err != "" else tr("Game open on port %d. Share one of your addresses below.") % Net.port())
		_refresh())
	_connect_view.add_child(host_btn)
	var jrow := HBoxContainer.new()
	jrow.add_child(UiStyle.label(tr("Host IP"), 16, UiStyle.TEXT_DIM))
	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.1.20  ·  26.x.x.x (Radmin)  ·  10.8.0.1 (OpenVPN)"
	_ip.custom_minimum_size = Vector2(420, 34)
	jrow.add_child(_ip)
	var join_btn := UiStyle.button(tr("Join"), 160)
	join_btn.pressed.connect(func() -> void: _join(_ip.text))
	jrow.add_child(join_btn)
	_connect_view.add_child(jrow)
	_connect_view.add_child(UiStyle.label(tr("Games on your network:"), 15, UiStyle.TEXT_DIM))
	_found_box = VBoxContainer.new()
	_connect_view.add_child(_found_box)
	var back := UiStyle.button(tr("Back"), 700)
	back.pressed.connect(_close)
	_connect_view.add_child(back)


func _build_lobby() -> void:
	_addresses = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	_addresses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_view.add_child(_addresses)
	_slots_box = VBoxContainer.new()
	_lobby_view.add_child(_slots_box)
	var ai_row := HBoxContainer.new()
	_ai_diff = UiStyle.option(GameData.rules.get("difficulties_menu", ["easy", "normal", "hard"]).map(func(d): return tr(String(d).capitalize())), 1)
	ai_row.add_child(_ai_diff)
	_add_ai = UiStyle.button(tr("Add computer player"), 260)
	_add_ai.pressed.connect(func() -> void:
		Net.host_add_ai(GameData.rules.get("difficulties_menu", ["easy", "normal", "hard"])[_ai_diff.selected]))
	ai_row.add_child(_add_ai)
	_lobby_view.add_child(ai_row)
	_settings_box = GridContainer.new()
	_settings_box.columns = 4
	_settings_box.add_theme_constant_override("h_separation", 10)
	var rules: Dictionary = GameData.rules
	var types: Array = rules.get("map_types_menu", ["continental"])
	_map_type = UiStyle.option(types.map(func(t): return tr(String(GameData.map_gen.get("map_types", {}).get(t, {}).get("display_name", t)))))
	var sizes: Array = rules.get("map_sizes_menu", ["small"])
	_size = UiStyle.option(sizes.map(func(s): return tr(String(s).capitalize())), maxi(0, sizes.find("small")))
	var vcs: Array = rules.get("victory_conditions", {}).keys()
	_victory = UiStyle.option(vcs.map(func(k): return tr(rules["victory_conditions"][k]["display_name"])))
	_fog = CheckButton.new()
	_fog.button_pressed = true
	_fog.text = tr("Fog of war")
	_seed = LineEdit.new()
	_seed.placeholder_text = tr("random seed")
	for pair in [[tr("Map type"), _map_type], [tr("Size"), _size], [tr("Victory"), _victory], [tr("Seed"), _seed]]:
		_settings_box.add_child(UiStyle.label(pair[0], 14, UiStyle.TEXT_DIM))
		_settings_box.add_child(pair[1])
	_settings_box.add_child(_fog)
	_lobby_view.add_child(_settings_box)
	for c in [_map_type, _size, _victory]:
		(c as OptionButton).item_selected.connect(func(_i: int) -> void: _push_settings())
	_fog.toggled.connect(func(_b: bool) -> void: _push_settings())
	_seed.text_changed.connect(func(_t: String) -> void: _push_settings())
	_chat_log = RichTextLabel.new()
	_chat_log.custom_minimum_size = Vector2(700, 110)
	_chat_log.scroll_following = true
	_lobby_view.add_child(_chat_log)
	_chat_line = LineEdit.new()
	_chat_line.placeholder_text = tr("Chat (Enter to send)")
	_chat_line.text_submitted.connect(func(t: String) -> void:
		Net.send_chat(t)
		_chat_line.text = "")
	_lobby_view.add_child(_chat_line)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	_ready_toggle = CheckButton.new()
	_ready_toggle.text = tr("Ready")
	_ready_toggle.toggled.connect(func(on: bool) -> void: Net.set_ready(on))
	brow.add_child(_ready_toggle)
	_start = UiStyle.button(tr("Start match"), 220)
	_start.pressed.connect(func() -> void:
		var err := Net.host_start()
		if err != "":
			_set_status(err))
	brow.add_child(_start)
	var leave := UiStyle.button(tr("Leave"), 160)
	leave.pressed.connect(func() -> void:
		Net.leave()
		_set_status("")
		_refresh())
	brow.add_child(leave)
	_lobby_view.add_child(brow)


func _join(text: String) -> void:
	var ip := text.strip_edges()
	var port := -1
	if ip.count(":") == 1:
		port = int(ip.get_slice(":", 1))
		ip = ip.get_slice(":", 0)
	if ip == "":
		_set_status(tr("Type the host's IP address"))
		return
	var err := Net.join(_name.text, ip, port)
	_set_status(err if err != "" else tr("Connecting to %s...") % ip)


func _push_settings() -> void:
	if not Net.is_host():
		return
	var rules: Dictionary = GameData.rules
	var seed_text := _seed.text.strip_edges()
	Net.host_set_settings({
		"map_type": rules.get("map_types_menu", ["continental"])[_map_type.selected],
		"size": rules.get("map_sizes_menu", ["small"])[_size.selected],
		"victory": rules.get("victory_conditions", {}).keys()[_victory.selected],
		"fog": _fog.button_pressed,
		"seed": int(seed_text) if seed_text.is_valid_int() else (seed_text.hash() & 0x7fffffff if seed_text != "" else 0),
	})


func _refresh() -> void:
	var in_lobby := Net.is_networked() and not Net.slots.is_empty()
	_connect_view.visible = not in_lobby
	_lobby_view.visible = in_lobby
	if not in_lobby:
		return
	var host := Net.is_host()
	_addresses.text = (tr("Your addresses (share one): ") + ", ".join(Net.local_ips()) + "  ·  " + tr("port") + " %d" % Net.port()) if host else tr("Connected. Waiting for the host to start.")
	for c in _slots_box.get_children():
		c.queue_free()
	var colors: Array = GameData.players.get("colors", [])
	for i in Net.slots.size():
		var s: Dictionary = Net.slots[i]
		var row := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(18, 18)
		sw.color = Color(colors[i % colors.size()]["primary"]) if not colors.is_empty() else Color.WHITE
		row.add_child(sw)
		var tag := tr("computer") if s["ai"] else (tr("ready") if s["ready"] else tr("not ready"))
		row.add_child(UiStyle.label("  %s  —  %s" % [s["name"], tag], 16, UiStyle.TEXT if s["ready"] else UiStyle.TEXT_DIM))
		if host and i > 0:
			var rm := UiStyle.button(tr("Remove"), 110)
			var idx := i
			rm.pressed.connect(func() -> void: Net.host_remove_slot(idx))
			row.add_child(rm)
		_slots_box.add_child(row)
	_add_ai.visible = host
	_ai_diff.visible = host
	_start.visible = host
	_start.disabled = not Net.all_ready()
	_ready_toggle.visible = not host
	for c in [_map_type, _size, _victory, _fog]:
		c.set("disabled", not host)
	_seed.editable = host
	if not host:
		var ms: Dictionary = Net.match_settings
		var rules: Dictionary = GameData.rules
		_map_type.select(maxi(0, rules.get("map_types_menu", []).find(ms.get("map_type", "continental"))))
		_size.select(maxi(0, rules.get("map_sizes_menu", []).find(ms.get("size", "small"))))
		_victory.select(maxi(0, rules.get("victory_conditions", {}).keys().find(ms.get("victory", "conquest"))))
		_fog.set_pressed_no_signal(bool(ms.get("fog", true)))


func _on_found(list: Array) -> void:
	for c in _found_box.get_children():
		c.queue_free()
	if list.is_empty():
		_found_box.add_child(UiStyle.label(tr("(none found - type the IP above)"), 14, UiStyle.TEXT_DIM))
		return
	for g in list:
		var b := UiStyle.button("%s  —  %s  (%d/%d)" % [g.get("name", "?"), g.get("ip", "?"), int(g.get("players", 1)), int(g.get("max", 4))], 700)
		var addr := "%s:%d" % [g.get("ip", ""), int(g.get("port", Net.port()))]
		b.pressed.connect(func() -> void: _join(addr))
		_found_box.add_child(b)


func _on_chat(from: String, text: String) -> void:
	if _chat_log:
		_chat_log.append_text(("[color=#f0c96a]%s[/color]\n" % text) if from == "" else "[b]%s:[/b] %s\n" % [from, text])


func _set_status(text: String) -> void:
	_status.text = Loc.text(text)


func _close() -> void:
	Net.browse(false)
	closed.emit()
	queue_free()

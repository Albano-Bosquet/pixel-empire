class_name LobbyMenu
extends CanvasLayer
## Multiplayer screen (opened from the title menu).
##   Connect view: player name; Online (through the relay, no ports to open):
##   create a game, join with its code, open online games; Local network / VPN:
##   "Host a game", join by IP (optional ":port"), games found on the network.
##   Lobby view: up to 8 player slots (host adds computer players, sets
##   difficulties and teams, removes slots; each player may pick their own
##   team), the host's match options (MatchSettingsForm), ready toggle, chat,
##   Start (host, when everyone is ready).
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
var _code: LineEdit
var _online_box: VBoxContainer
var _slots_list: PlayerSlotsList
var _addresses: Label
var _chat_log: RichTextLabel
var _chat_line: LineEdit
var _ready_toggle: CheckButton
var _start: Button
var _form: MatchSettingsForm
var _ai_diff: OptionButton
var _add_ai: Button


func _ready() -> void:
	layer = 30
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.add_child(UiStyle.dimmer(0.6))
	var pv: Array = UiStyle.centered_panel(_root, 1060)
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
	Net.online_games_found.connect(_on_online_found)
	Net.match_started.connect(func(_c: Dictionary) -> void: _close())
	Net.browse(true)
	Net.browse_online()
	_refresh()


func _build_connect() -> void:
	var row := HBoxContainer.new()
	row.add_child(UiStyle.label(tr("Your name"), 16, UiStyle.TEXT_DIM))
	_name = LineEdit.new()
	_name.text = OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else tr("Player")
	_name.custom_minimum_size = Vector2(260, 34)
	row.add_child(_name)
	_connect_view.add_child(row)
	_build_online()
	_connect_view.add_child(UiStyle.label(tr("Local network or VPN"), 18, UiStyle.GOLD))
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


func _build_online() -> void:
	_connect_view.add_child(UiStyle.label(tr("Online (no ports or firewall to set up)"), 18, UiStyle.GOLD))
	var create := UiStyle.button(tr("Create online game"), 700)
	create.pressed.connect(func() -> void:
		var err := Net.host_online(_name.text)
		_set_status(err if err != "" else tr("Opening an online game... (the server may take up to a minute to wake up)")))
	_connect_view.add_child(create)
	var crow := HBoxContainer.new()
	crow.add_child(UiStyle.label(tr("Game code"), 16, UiStyle.TEXT_DIM))
	_code = LineEdit.new()
	_code.placeholder_text = "K7QX2"
	_code.max_length = 8
	_code.custom_minimum_size = Vector2(200, 34)
	_code.text_submitted.connect(func(_t: String) -> void: _join_code(_code.text))
	crow.add_child(_code)
	var join := UiStyle.button(tr("Join"), 160)
	join.pressed.connect(func() -> void: _join_code(_code.text))
	crow.add_child(join)
	var refresh := UiStyle.button(tr("Refresh list"), 200)
	refresh.pressed.connect(func() -> void:
		_set_status("")
		Net.browse_online())
	crow.add_child(refresh)
	_connect_view.add_child(crow)
	_online_box = VBoxContainer.new()
	_connect_view.add_child(_online_box)


func _join_code(code: String) -> void:
	var err := Net.join_online(_name.text, code)
	_set_status(err if err != "" else tr("Connecting to game %s... (the server may take up to a minute to wake up)") % code.strip_edges().to_upper())


func _on_online_found(list: Array) -> void:
	for c in _online_box.get_children():
		c.queue_free()
	if list.is_empty():
		_online_box.add_child(UiStyle.label(tr("(no open online games - create one or type a code)"), 14, UiStyle.TEXT_DIM))
		return
	for g in list:
		var code := String(g.get("code", ""))
		var b := UiStyle.button("%s  —  %s  (%d/%d)" % [g.get("name", "?"), code, int(g.get("players", 1)), int(g.get("max", 8))], 700)
		b.pressed.connect(func() -> void: _join_code(code))
		_online_box.add_child(b)


func _build_lobby() -> void:
	_addresses = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	_addresses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_view.add_child(_addresses)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	_lobby_view.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 540
	cols.add_child(left)
	_slots_list = PlayerSlotsList.new()
	_slots_list.editable = func(i: int) -> bool: return Net.is_host() or Net.player_of_peer(multiplayer.get_unique_id()) == i + 1
	_slots_list.removable = func(i: int) -> bool: return Net.is_host() and i > 0
	_slots_list.team_changed.connect(func(i: int, t: int) -> void:
		if Net.is_host():
			Net.host_set_slot(i, "team", t)
		else:
			Net.request_team(t))
	_slots_list.difficulty_changed.connect(func(i: int, d: String) -> void: Net.host_set_slot(i, "difficulty", d))
	_slots_list.remove_requested.connect(func(i: int) -> void: Net.host_remove_slot(i))
	left.add_child(_slots_list)
	var ai_row := HBoxContainer.new()
	_ai_diff = UiStyle.option(GameData.rules.get("difficulties_menu", ["easy", "normal", "hard"]).map(func(d): return tr(String(d).capitalize())), 1)
	ai_row.add_child(_ai_diff)
	_add_ai = UiStyle.button(tr("Add computer player"), 260)
	_add_ai.pressed.connect(func() -> void:
		Net.host_add_ai(GameData.rules.get("difficulties_menu", ["easy", "normal", "hard"])[_ai_diff.selected]))
	ai_row.add_child(_add_ai)
	left.add_child(ai_row)
	_form = MatchSettingsForm.new()
	cols.add_child(_form)
	_form.changed.connect(func(settings: Dictionary) -> void:
		if Net.is_host():
			Net.host_set_settings(settings))
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


func _refresh() -> void:
	var in_lobby := Net.is_networked() and not Net.slots.is_empty()
	_connect_view.visible = not in_lobby
	_lobby_view.visible = in_lobby
	if not in_lobby:
		return
	var host := Net.is_host()
	if Net.online_code != "":
		_addresses.text = (tr("Online game code: %s  (share it; it also shows in the online list)") if host else tr("Online game %s. Waiting for the host to start.")) % Net.online_code
	else:
		_addresses.text = (tr("Your addresses (share one): ") + ", ".join(Net.local_ips()) + "  ·  " + tr("port") + " %d" % Net.port()) if host else tr("Connected. Waiting for the host to start.")
	var shown := []
	for i in Net.slots.size():
		var sl: Dictionary = Net.slots[i].duplicate()
		sl["you"] = Net.player_of_peer(multiplayer.get_unique_id()) == i + 1 if Net.is_networked() else false
		sl["ready"] = sl["ai"] or sl["ready"]
		shown.append(sl)
	_slots_list.show_slots(shown)
	_add_ai.visible = host
	_add_ai.disabled = Net.slots.size() >= int(Net.settings.get("max_players", 8))
	_ai_diff.visible = host
	_start.visible = host
	_start.disabled = not Net.all_ready()
	_ready_toggle.visible = not host
	_form.set_editable(host)
	if not host:
		_form.set_settings(Net.match_settings)


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

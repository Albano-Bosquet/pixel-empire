extends Node
## Multiplayer session for LAN and VPNs (Radmin, OpenVPN, Hamachi, ZeroTier...):
## the host listens on a UDP port (ENet) and others join by typing its IP.
## Autoload "Net" so its RPCs live at the same node path on every machine.
##
## Host-authoritative: the host runs the whole match (AI included); clients
## send orders (OrderRouter dictionaries) and draw what the host's snapshots
## show them (Replicator). The lobby lives on the host and is mirrored.
## Roles: NONE (single player), HOST, CLIENT.
## Lobby slot: {"peer": int (0 = AI), "name": String, "ready": bool, "ai": bool,
##              "difficulty": String, "connected": bool}. Slot index + 1 = player id.
## Data: net_settings.json.
## Example:
##   Net.host("Ana")                       # then Net.host_start() from the lobby
##   Net.join("Luis", "26.12.34.56")       # Radmin / LAN address of the host

signal lobby_changed
signal chat_received(from: String, text: String)
signal match_started(cfg: Dictionary)
signal connection_failed(reason: String)
signal session_ended(reason: String)
signal games_found(list: Array)

enum Role { NONE, HOST, CLIENT }

const SETTINGS := "res://assets/data/net_settings.json"

var role := Role.NONE
var settings: Dictionary = {}
var slots: Array = []
## Map/victory settings chosen by the host, mirrored to the lobby.
var match_settings: Dictionary = {"map_type": "continental", "size": "small", "victory": "conquest", "fog": true, "seed": 0}
var my_name := "Player"
var in_match := false
## The running match's replicator (set by Replicator when it starts).
var replicator: Node = null
## Player id of this machine in the current match.
var local_player := 1

var _peer: ENetMultiplayerPeer
var _udp_send: PacketPeerUDP
var _udp_listen: PacketPeerUDP
var _beacon_timer := 0.0
var _found: Dictionary = {}
var _connect_timer := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	settings = raw if raw is Dictionary else {}
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("Could not connect to the host"))
	multiplayer.server_disconnected.connect(func() -> void: _end("The host closed the game"))


func is_networked() -> bool:
	return role != Role.NONE


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func port() -> int:
	return int(settings.get("port", 24680))


## IPv4 addresses of this machine that others can type (LAN and VPN adapters).
func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.count(".") == 3 and not s.begins_with("127.") and not s.begins_with("169.254."):
			out.append(s)
	out.sort()
	return out


# --- Session --------------------------------------------------------------------------

## Opens a game on this machine. Returns "" or an error message.
func host(player_name: String, at_port: int = -1) -> String:
	leave()
	my_name = player_name if player_name != "" else "Host"
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(at_port if at_port > 0 else port(), int(settings.get("max_players", 4)) - 1)
	if err != OK:
		_peer = null
		return Loc.msg("Cannot open port %s (already in use?)", [at_port if at_port > 0 else port()])
	multiplayer.multiplayer_peer = _peer
	role = Role.HOST
	slots = [{"peer": 1, "name": my_name, "ready": true, "ai": false, "difficulty": "normal", "connected": true}]
	_udp_send = PacketPeerUDP.new()
	_udp_send.set_broadcast_enabled(true)
	lobby_changed.emit()
	return ""


## Connects to a host by IP (LAN or VPN address). Result arrives as
## lobby_changed (accepted) or connection_failed.
func join(player_name: String, ip: String, at_port: int = -1) -> String:
	leave()
	my_name = player_name if player_name != "" else "Player"
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip.strip_edges(), at_port if at_port > 0 else port())
	if err != OK:
		_peer = null
		return "Invalid address"
	multiplayer.multiplayer_peer = _peer
	role = Role.CLIENT
	_connect_timer = float(settings.get("connect_timeout", 8.0))
	return ""


func leave() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	slots = []
	in_match = false
	replicator = null
	_udp_send = null
	_connect_timer = -1.0


func _fail(reason: String) -> void:
	leave()
	connection_failed.emit(reason)


func _end(reason: String) -> void:
	var was := role != Role.NONE
	leave()
	if was:
		session_ended.emit(reason)


# --- LAN discovery -----------------------------------------------------------------------

## Starts listening for host beacons on the local network (and VPNs that pass broadcasts).
func browse(on: bool) -> void:
	if on and _udp_listen == null:
		_udp_listen = PacketPeerUDP.new()
		if _udp_listen.bind(int(settings.get("discovery_port", 24681))) != OK:
			_udp_listen = null
	elif not on and _udp_listen != null:
		_udp_listen.close()
		_udp_listen = null
	_found.clear()


func _process(delta: float) -> void:
	if _connect_timer > 0.0:
		_connect_timer -= delta
		if _connect_timer <= 0.0 and role == Role.CLIENT and slots.is_empty():
			_fail("No answer from the host (check the IP, the VPN and the firewall)")
	if role == Role.HOST and not in_match and _udp_send != null:
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			_beacon_timer = float(settings.get("discovery_interval", 1.0))
			var beacon := JSON.stringify({"tag": settings.get("game_tag", "PixelEmpire1"), "name": my_name,
				"port": port(), "players": slots.size(), "max": int(settings.get("max_players", 4))})
			_udp_send.set_dest_address("255.255.255.255", int(settings.get("discovery_port", 24681)))
			_udp_send.put_packet(beacon.to_utf8_buffer())
	if _udp_listen != null:
		var changed := false
		while _udp_listen.get_available_packet_count() > 0:
			var pkt := _udp_listen.get_packet().get_string_from_utf8()
			var ip := _udp_listen.get_packet_ip()
			var info: Variant = JSON.parse_string(pkt)
			if info is Dictionary and info.get("tag", "") == settings.get("game_tag", "PixelEmpire1"):
				info["ip"] = ip
				info["seen"] = Time.get_ticks_msec()
				_found["%s:%d" % [ip, int(info.get("port", port()))]] = info
				changed = true
		var now := Time.get_ticks_msec()
		for k in _found.keys():
			if now - int(_found[k]["seen"]) > 4000:
				_found.erase(k)
				changed = true
		if changed:
			games_found.emit(_found.values())


# --- Lobby (host side) -------------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass  # the client introduces itself with _c_hello


func _on_connected() -> void:
	_connect_timer = float(settings.get("connect_timeout", 8.0))
	_c_hello.rpc_id(1, my_name)


func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST:
		return
	for i in slots.size():
		if int(slots[i]["peer"]) == id:
			if in_match:
				# The civilisation keeps playing under AI control until they return.
				slots[i]["connected"] = false
				slots[i]["peer"] = -1
				if replicator != null:
					replicator.player_dropped(i + 1)
				_broadcast_chat("", "%s disconnected - the AI takes over" % slots[i]["name"])
			else:
				slots.remove_at(i)
			break
	_push_lobby()


func host_add_ai(difficulty: String = "normal") -> void:
	if role != Role.HOST or in_match or slots.size() >= int(settings.get("max_players", 4)):
		return
	slots.append({"peer": 0, "name": tr("AI (%s)") % tr(String(difficulty).capitalize()), "ready": true, "ai": true, "difficulty": difficulty, "connected": true})
	_push_lobby()


func host_remove_slot(index: int) -> void:
	if role != Role.HOST or in_match or index <= 0 or index >= slots.size():
		return
	var s: Dictionary = slots[index]
	if not s["ai"] and int(s["peer"]) > 1:
		_kick.rpc_id(int(s["peer"]), "Removed by the host")
	slots.remove_at(index)
	_push_lobby()


func host_set_settings(values: Dictionary) -> void:
	if role != Role.HOST:
		return
	match_settings.merge(values, true)
	_push_lobby()


func all_ready() -> bool:
	return slots.size() >= 2 and slots.all(func(s): return s["ready"])


func _push_lobby() -> void:
	lobby_changed.emit()
	if role == Role.HOST:
		_h_lobby.rpc(slots, match_settings)


func set_ready(r: bool) -> void:
	if role == Role.CLIENT:
		_c_ready.rpc_id(1, r)


func send_chat(text: String) -> void:
	text = text.strip_edges().left(200)
	if text == "":
		return
	if role == Role.HOST:
		_broadcast_chat(my_name, text)
	elif role == Role.CLIENT:
		_c_chat.rpc_id(1, text)


func _broadcast_chat(from: String, text: String) -> void:
	chat_received.emit(from, text)
	_h_chat.rpc(from, text)


## Host: builds the match configuration and starts it everywhere.
func host_start() -> String:
	if role != Role.HOST:
		return "Only the host can start"
	if not all_ready():
		return "Waiting for every player to be ready"
	var seed_v := int(match_settings.get("seed", 0))
	if seed_v == 0:
		seed_v = randi() % 1000000 + 1
	var players := []
	for s in slots:
		players.append({"name": s["name"], "ai": s["ai"]})
	var difficulty := "normal"
	for s2 in slots:
		if s2["ai"]:
			difficulty = s2["difficulty"]
	var cfg := {"mode": "skirmish", "size": match_settings.get("size", "small"), "map_type": match_settings.get("map_type", "continental"),
		"seed": seed_v, "victory": match_settings.get("victory", "conquest"), "fog": match_settings.get("fog", true),
		"difficulty": difficulty, "players": players, "net": true}
	in_match = true
	for i in slots.size():
		var peer := int(slots[i]["peer"])
		if peer > 1:
			var c := cfg.duplicate(true)
			c["local_player"] = i + 1
			c["replica"] = true
			_h_start.rpc_id(peer, c)
	var mine := cfg.duplicate(true)
	mine["local_player"] = 1
	local_player = 1
	match_started.emit(mine)
	return ""


## Player id of a connected peer in the running match (0 = unknown).
func player_of_peer(peer: int) -> int:
	for i in slots.size():
		if int(slots[i]["peer"]) == peer:
			return i + 1
	return 0


func peer_of_player(pid: int) -> int:
	if pid < 1 or pid > slots.size():
		return 0
	return int(slots[pid - 1]["peer"])


# --- RPCs: client -> host -------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _c_hello(player_name: String) -> void:
	if role != Role.HOST:
		return
	var peer := multiplayer.get_remote_sender_id()
	if in_match:
		# Rejoin: a dropped human with the same name gets their civilisation back.
		for i in slots.size():
			if not slots[i]["ai"] and not slots[i]["connected"] and slots[i]["name"] == player_name:
				slots[i]["peer"] = peer
				slots[i]["connected"] = true
				if replicator != null:
					replicator.player_returned(i + 1)
					var cfg: Dictionary = replicator.match_config().duplicate(true)
					cfg["local_player"] = i + 1
					cfg["replica"] = true
					_h_lobby.rpc_id(peer, slots, match_settings)
					_h_start.rpc_id(peer, cfg)
				_broadcast_chat("", "%s is back" % player_name)
				return
		_kick.rpc_id(peer, "The match has already started")
		return
	if slots.size() >= int(settings.get("max_players", 4)):
		_kick.rpc_id(peer, "The game is full")
		return
	slots.append({"peer": peer, "name": player_name, "ready": false, "ai": false, "difficulty": "normal", "connected": true})
	_push_lobby()
	_broadcast_chat("", "%s joined" % player_name)


@rpc("any_peer", "reliable")
func _c_ready(r: bool) -> void:
	var pid := player_of_peer(multiplayer.get_remote_sender_id())
	if role == Role.HOST and pid > 0:
		slots[pid - 1]["ready"] = r
		_push_lobby()


@rpc("any_peer", "reliable")
func _c_chat(text: String) -> void:
	var pid := player_of_peer(multiplayer.get_remote_sender_id())
	if role == Role.HOST and pid > 0:
		_broadcast_chat(slots[pid - 1]["name"], text.left(200))


## A client's order, applied by the host on behalf of the sender's player.
@rpc("any_peer", "reliable")
func _c_order(order: Dictionary) -> void:
	var pid := player_of_peer(multiplayer.get_remote_sender_id())
	if role == Role.HOST and pid > 0 and replicator != null:
		replicator.apply_remote_order(pid, order)


@rpc("any_peer", "reliable")
func _c_pause(paused: bool) -> void:
	if role == Role.HOST and player_of_peer(multiplayer.get_remote_sender_id()) > 0:
		set_paused(paused)


# --- RPCs: host -> clients -----------------------------------------------------------------

@rpc("authority", "reliable")
func _h_lobby(new_slots: Array, values: Dictionary) -> void:
	slots = new_slots
	match_settings = values
	_connect_timer = -1.0
	lobby_changed.emit()


@rpc("authority", "reliable")
func _h_chat(from: String, text: String) -> void:
	chat_received.emit(from, text)


@rpc("authority", "reliable")
func _h_start(cfg: Dictionary) -> void:
	in_match = true
	local_player = int(cfg.get("local_player", 1))
	match_started.emit(cfg)


@rpc("authority", "unreliable_ordered")
func _h_snapshot(data: PackedByteArray) -> void:
	if replicator != null:
		replicator.receive_snapshot(data)


@rpc("authority", "reliable")
func _h_events(events: Array) -> void:
	if replicator != null:
		replicator.receive_events(events)


@rpc("authority", "reliable")
func _h_pause(paused: bool) -> void:
	get_tree().paused = paused
	EventBus.net_paused.emit(paused)


@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	_end(reason)


# --- Shared --------------------------------------------------------------------------------------

## Pauses or resumes the whole networked match (any player may ask).
func set_paused(paused: bool) -> void:
	if role == Role.CLIENT:
		_c_pause.rpc_id(1, paused)
		return
	get_tree().paused = paused
	EventBus.net_paused.emit(paused)
	if role == Role.HOST:
		_h_pause.rpc(paused)


func send_order(order: Dictionary) -> void:
	if role == Role.CLIENT:
		_c_order.rpc_id(1, order)


func send_snapshot(peer: int, data: PackedByteArray) -> void:
	_h_snapshot.rpc_id(peer, data)


func send_events(peer: int, events: Array) -> void:
	_h_events.rpc_id(peer, events)

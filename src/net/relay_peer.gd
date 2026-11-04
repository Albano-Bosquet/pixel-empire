class_name RelayPeer
extends MultiplayerPeerExtension
## MultiplayerPeer that reaches the other players through the Pixel Empire relay
## server (tools/relay) over one outgoing WebSocket, so nobody opens ports or
## touches a firewall, and phones on mobile data can host or join.
## The game's RPCs stay as they are: the host is peer 1, clients get ids from
## the relay, and every packet is forwarded by it unchanged.
## Wire format (binary frames): [int32 LE peer][u8 channel][u8 mode] + payload,
## peer = target when sending, sender when receiving. Control = JSON text frames.
## Example:
##   var p := RelayPeer.new()
##   p.host_room("wss://relay.example", {"tag": "PixelEmpire1", "version": "1.5.1", "name": "Ana"})
##   p.hosted.connect(func(code): print("share ", code))   # then multiplayer.multiplayer_peer = p

## The relay opened our room (host side). Share `code` with the other players.
signal hosted(code: String)
## The relay refused or dropped us; `reason` is a translatable message.
signal relay_failed(reason: String)

const HEADER := 6
const MAX_PACKET := 1 << 20

## Room code of the game we host or joined.
var code := ""
## Unreliable packets (snapshots) are dropped while more than this many bytes
## wait to go out: over TCP a stale snapshot only delays the fresh ones.
var max_backlog := 16384
## Unreliable packets dropped so far, sending and receiving (diagnostics / tests).
var dropped := 0

var _ws := WebSocketPeer.new()
var _hello: Dictionary = {}
var _hello_sent := false
var _id := 0
var _host := false
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _incoming: Array = []   # [peer, channel, mode, PackedByteArray]
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refusing := false


func _init() -> void:
	_ws.inbound_buffer_size = 1 << 22
	_ws.outbound_buffer_size = 1 << 22
	_ws.max_queued_packets = 8192
	_ws.heartbeat_interval = 10.0


## Opens a new room on the relay at `url`. `hello` carries tag, version, name, max.
func host_room(url: String, hello: Dictionary) -> Error:
	_host = true
	var h := hello.duplicate()
	h["op"] = "host"
	return _open(url, h)


## Joins the room `room_code` on the relay at `url`. `hello` carries tag and version.
func join_room(url: String, room_code: String, hello: Dictionary) -> Error:
	_host = false
	var h := hello.duplicate()
	h["op"] = "join"
	h["code"] = room_code.strip_edges().to_upper()
	return _open(url, h)


## Host: tells the relay how many players there are and whether the game is
## still open for the public list (false once the match started).
func send_info(players: int, open: bool) -> void:
	_send_control({"op": "info", "players": players, "open": open})


## Polls the socket (also usable before the peer is given to the multiplayer API).
func pump() -> void:
	_poll()


func _open(url: String, hello: Dictionary) -> Error:
	_hello = hello
	_hello_sent = false
	var err := _ws.connect_to_url(url)
	if err == OK:
		_status = MultiplayerPeer.CONNECTION_CONNECTING
	return err


func _send_control(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func _poll() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _hello_sent:
			_hello_sent = true
			_send_control(_hello)
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			if _ws.was_string_packet():
				_on_control(pkt.get_string_from_utf8())
			elif pkt.size() >= HEADER and _status == MultiplayerPeer.CONNECTION_CONNECTED:
				_receive([pkt.decode_s32(0), pkt[4], pkt[5], pkt.slice(HEADER)])
	elif state == WebSocketPeer.STATE_CLOSED and _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
		var was := _status
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		if was == MultiplayerPeer.CONNECTION_CONNECTING:
			relay_failed.emit("Could not reach the online server")
		elif not _host:
			peer_disconnected.emit(1)


# A burst of snapshots after a hiccup: only the newest one from that peer and
# channel is worth applying, the older unreliable ones are skipped.
func _receive(entry: Array) -> void:
	if int(entry[2]) != MultiplayerPeer.TRANSFER_MODE_RELIABLE:
		for i in range(_incoming.size() - 1, -1, -1):
			var e: Array = _incoming[i]
			if e[0] == entry[0] and e[1] == entry[1] and int(e[2]) != MultiplayerPeer.TRANSFER_MODE_RELIABLE:
				_incoming.remove_at(i)
				dropped += 1
	_incoming.append(entry)


func _on_control(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	match String(msg.get("op", "")):
		"hosted":
			_id = 1
			code = String(msg.get("code", ""))
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			hosted.emit(code)
		"joined":
			_id = int(msg.get("id", 0))
			code = String(msg.get("code", ""))
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			peer_connected.emit(1)
		"peer_in":
			if _refusing:
				_send_control({"op": "kick", "id": int(msg.get("id", 0))})
			else:
				peer_connected.emit(int(msg.get("id", 0)))
		"peer_out":
			peer_disconnected.emit(int(msg.get("id", 0)))
		"error":
			var was_connecting := _status == MultiplayerPeer.CONNECTION_CONNECTING
			_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			_ws.close()
			if was_connecting:
				relay_failed.emit(String(msg.get("reason", "Could not reach the online server")))


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front()[3]


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if _mode != MultiplayerPeer.TRANSFER_MODE_RELIABLE and _ws.get_current_outbound_buffered_amount() > max_backlog:
		dropped += 1
		return OK
	var out := PackedByteArray()
	out.resize(HEADER)
	out.encode_s32(0, _target)
	out[4] = _channel
	out[5] = _mode
	out.append_array(buffer)
	return _ws.send(out)


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return MAX_PACKET - HEADER


# The packet getters describe the next packet to be read (the queue front),
# as SceneMultiplayer asks for them before taking the packet.
func _get_packet_peer() -> int:
	return int(_incoming[0][0]) if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_incoming[0][1]) if not _incoming.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return int(_incoming[0][2]) as MultiplayerPeer.TransferMode if not _incoming.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _is_server() -> bool:
	return _id == 1


func _close() -> void:
	_ws.close()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_incoming.clear()


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _host:
		_send_control({"op": "kick", "id": peer})


func _get_unique_id() -> int:
	return _id


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _is_server_relay_supported() -> bool:
	return false


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status

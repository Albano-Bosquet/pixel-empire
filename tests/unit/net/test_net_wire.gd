extends "res://tests/test_case.gd"
## Online wire: compressed snapshots round-trip, and the relay peer keeps only
## the newest unreliable packet of a burst (stale snapshots are lag over TCP).


func _sample_snapshot() -> Dictionary:
	var units := []
	for i in 200:
		units.append([i, 3, 1 + i % 2, 10.5 + i, 20.25, 40, 40, "walk", i % 8, "wood", 7.5, 0, 0, 1, "gather:wood"])
	return {"t": 12.5, "pl": [[1, {"food": 200}, 1, ["loom"], false]], "u": units, "b": [], "r": [], "pr": [], "mp": {}}


func test_snapshot_round_trip_is_identical_and_smaller() -> void:
	var rep := Replicator.new()
	var snap := _sample_snapshot()
	var wire := rep.encode_snapshot(snap)
	assert_eq(Replicator.decode_snapshot(wire), snap, "decoded snapshot equals the original")
	assert_true(wire.size() < var_to_bytes(snap).size() / 3, "compressed to under a third (%d -> %d bytes)" % [rep.last_snapshot_size[0], wire.size()])
	rep.free()


func test_malformed_snapshot_decodes_to_empty() -> void:
	assert_true(Replicator.decode_snapshot(PackedByteArray()).is_empty(), "empty packet")
	assert_true(Replicator.decode_snapshot(PackedByteArray([255, 255, 255, 255, 1, 2, 3])).is_empty(), "absurd size")
	assert_true(Replicator.decode_snapshot(PackedByteArray([10, 0, 0, 0, 1, 2, 3])).is_empty(), "garbage body")


func test_burst_keeps_only_newest_unreliable_per_peer_and_channel() -> void:
	var p := RelayPeer.new()
	var U := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var R := MultiplayerPeer.TRANSFER_MODE_RELIABLE
	p._receive([1, 0, U, PackedByteArray([1])])
	p._receive([1, 0, R, PackedByteArray([2])])
	p._receive([1, 0, U, PackedByteArray([3])])
	p._receive([1, 1, U, PackedByteArray([4])])
	assert_eq(p._get_available_packet_count(), 3, "older snapshot on the same channel dropped")
	assert_eq(p.dropped, 1, "one packet counted as dropped")
	assert_eq(p._get_packet_script(), PackedByteArray([2]), "reliable packet kept in order")
	assert_eq(p._get_packet_script(), PackedByteArray([3]), "newest snapshot kept")
	assert_eq(p._get_packet_script(), PackedByteArray([4]), "other channel untouched")

extends Node

signal status_changed(message: String)
signal match_ready(player_id: int)
signal snapshot_received(state: GameState, viewer_id: int)
signal action_result_received(accepted: bool, message: String)
signal match_ended(message: String)

const DEFAULT_PORT: int = 7777
const MIN_ROOM_CODE_LENGTH: int = 6
const MAX_ROOM_CODE_LENGTH: int = 16
const MAX_ROOMS: int = 32
const DEFAULT_RECONNECT_GRACE_SECONDS: float = 120.0
const MAX_RECONNECT_ATTEMPTS: int = 6
const RECONNECT_DELAY_SECONDS: float = 2.0

var mode: String = "offline"
var local_player_id: int = -1
var current_state: GameState
var current_visual_action: Dictionary = {}
var action_pending: bool = false
var reconnect_grace_seconds: float = DEFAULT_RECONNECT_GRACE_SECONDS
var _pending_join: Dictionary = {}
var _rooms: Dictionary = {}
var _peer_rooms: Dictionary = {}
var _peer_seats: Dictionary = {}
var _announced_match_ready: bool = false
var _server_address: String = ""
var _server_port: int = 0
var _session_token: String = ""
var _reconnect_attempts: int = 0
var _reconnect_timer: Timer
var _reconnect_pending: bool = false

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_attempt_reconnect)
	add_child(_reconnect_timer)
	_start_server_from_args()

func _process(_delta: float) -> void:
	if mode == "server":
		_expire_vacated_seats()

func start_server(port: int = DEFAULT_PORT) -> Error:
	if port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, 64)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	mode = "server"
	print("Online match server listening on UDP port %d." % port)
	return OK

func connect_to_server(
	address: String,
	port: int,
	room_code: String,
	create_room: bool,
	display_name: String,
	army_id: String,
	deck_card_ids: Array[String],
	setup_tiles: int,
	player_count: int = 2
) -> Error:
	if address.strip_edges().is_empty() or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	var code: String = room_code.strip_edges().to_upper()
	if not _valid_room_code(code):
		return ERR_INVALID_PARAMETER
	if not ArmyCatalog.is_army(army_id) or not DeckData.validate(deck_card_ids).is_empty():
		return ERR_INVALID_PARAMETER
	if DeckData.army_of(deck_card_ids) not in ["", army_id] or setup_tiles not in [0, 3] or player_count not in [2, 4]:
		return ERR_INVALID_PARAMETER
	_disconnect_peer()
	_pending_join = {
		"room_code": code,
		"create_room": create_room,
		"display_name": display_name.strip_edges().left(24),
		"army_id": army_id,
		"deck_card_ids": deck_card_ids.duplicate(),
		"setup_tiles": setup_tiles,
		"player_count": player_count,
	}
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address.strip_edges(), port)
	if error != OK:
		_pending_join.clear()
		return error
	multiplayer.multiplayer_peer = peer
	mode = "connecting"
	local_player_id = -1
	current_state = null
	current_visual_action.clear()
	action_pending = false
	_announced_match_ready = false
	_server_address = address.strip_edges()
	_server_port = port
	_session_token = ""
	_reconnect_attempts = 0
	_reconnect_pending = false
	status_changed.emit("Connecting to %s:%d..." % [_server_address, port])
	return OK

func submit_action(action: Dictionary) -> bool:
	if mode != "client" or action_pending or local_player_id < 0:
		return false
	action_pending = true
	rpc_id(1, "_server_submit_action", action)
	return true

func disconnect_from_server() -> void:
	_disconnect_peer()
	_reset_session()

# Drops the connection as if the network failed, so the reconnect path runs. Used by smoke tests.
func simulate_connection_loss() -> void:
	if mode != "client":
		return
	_on_server_disconnected()

func _reset_session() -> void:
	_reconnect_timer.stop()
	mode = "offline"
	local_player_id = -1
	current_state = null
	current_visual_action.clear()
	action_pending = false
	_pending_join.clear()
	_session_token = ""
	_reconnect_attempts = 0
	_reconnect_pending = false

func generate_room_code() -> String:
	var alphabet: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code: String = ""
	for _index in range(8):
		var character_index: int = randi_range(0, alphabet.length() - 1)
		code += alphabet.substr(character_index, 1)
	return code

func _start_server_from_args() -> void:
	var port: int = -1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--reconnect-grace="):
			reconnect_grace_seconds = maxf(0.0, argument.trim_prefix("--reconnect-grace=").to_float())
		elif argument.begins_with("--server-port="):
			port = argument.trim_prefix("--server-port=").to_int()
	if port < 0:
		return
	var error: Error = start_server(port)
	if error != OK:
		push_error("Could not start online server on port %d (error %d)." % [port, error])

@rpc("any_peer", "call_remote", "reliable")
func _server_join_request(request: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if _peer_rooms.has(peer_id):
		rpc_id(peer_id, "_client_join_status", false, "You are already in a room.", -1, false, "")
		return
	var validation_error: String = _validate_join_request(request)
	if validation_error != "":
		rpc_id(peer_id, "_client_join_status", false, validation_error, -1, false, "")
		return
	var room_code: String = str(request["room_code"]).to_upper()
	var create_room: bool = bool(request["create_room"])
	var player_count: int = int(request.get("player_count", 2))
	if not _rooms.has(room_code):
		if not create_room:
			rpc_id(peer_id, "_client_join_status", false, "That room does not exist.", -1, false, "")
			return
		if _rooms.size() >= MAX_ROOMS:
			rpc_id(peer_id, "_client_join_status", false, "The server has too many rooms open. Try again later.", -1, false, "")
			return
		_rooms[room_code] = {
			"peers": [],
			"player_data": [],
			"tokens": [],
			"vacated_at": [],
			"engine": null,
			"setup_tiles": int(request["setup_tiles"]),
			"player_count": player_count,
		}
		for _index in range(player_count):
			(_rooms[room_code]["peers"] as Array).append(-1)
			(_rooms[room_code]["player_data"] as Array).append({})
			(_rooms[room_code]["tokens"] as Array).append("")
			(_rooms[room_code]["vacated_at"] as Array).append(0)
	elif create_room:
		rpc_id(peer_id, "_client_join_status", false, "That room code is already in use.", -1, false, "")
		return
	var room: Dictionary = _rooms[room_code]
	if int(room["player_count"]) != player_count:
		rpc_id(peer_id, "_client_join_status", false, "Choose the same player count as the room creator.", -1, false, "")
		return
	var peers: Array = room["peers"]
	var seat: int = -1
	for index in range(player_count):
		if int(peers[index]) < 0:
			seat = index
			break
	if seat < 0:
		rpc_id(peer_id, "_client_join_status", false, "That room is full.", -1, false, "")
		return
	if room["engine"] != null:
		_take_over_seat(room_code, seat, peer_id)
		return
	peers[seat] = peer_id
	room["peers"] = peers
	var player_data: Array = room["player_data"]
	player_data[seat] = request.duplicate(true)
	room["player_data"] = player_data
	var tokens: Array = room["tokens"]
	tokens[seat] = _new_session_token()
	room["tokens"] = tokens
	_rooms[room_code] = room
	_peer_rooms[peer_id] = room_code
	_peer_seats[peer_id] = seat
	if peers.has(-1):
		var waiting: String = "Room created. Waiting for the other player." if player_count == 2 else "Joined room. Waiting for %d more player(s)." % peers.count(-1)
		rpc_id(peer_id, "_client_join_status", true, waiting, seat, false, tokens[seat])
		return

	var decks: Array = []
	var armies: Array = []
	for data: Dictionary in player_data:
		decks.append(data["deck_card_ids"])
		armies.append(data["army_id"])
	var game := GameEngine.new(
		randi(),
		decks,
		false,
		armies,
		int(room["setup_tiles"]),
		player_count
	)
	for index in range(player_count):
		game.state.players[index].display_name = str(player_data[index]["display_name"])
	room["engine"] = game
	_rooms[room_code] = room
	for index in range(player_count):
		var joined_peer: int = int(peers[index])
		rpc_id(joined_peer, "_client_join_status", true, "Match ready.", index, true, tokens[index])
		_send_snapshot(joined_peer, index, game.state)

# A vacant seat in a running match: the newcomer keeps the seat's existing army, deck and name.
func _take_over_seat(room_code: String, seat: int, peer_id: int) -> void:
	var room: Dictionary = _rooms[room_code]
	var peers: Array = room["peers"]
	var tokens: Array = room["tokens"]
	var vacated: Array = room["vacated_at"]
	peers[seat] = peer_id
	tokens[seat] = _new_session_token()
	vacated[seat] = 0
	_peer_rooms[peer_id] = room_code
	_peer_seats[peer_id] = seat
	rpc_id(peer_id, "_client_join_status", true, "You took over seat %d." % (seat + 1), seat, true, tokens[seat])
	_send_snapshot(peer_id, seat, (room["engine"] as GameEngine).state)
	_notify_room(room, "%s took over seat %d." % [_seat_name(room, seat), seat + 1], peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _server_reconnect(request: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var room_code: String = str(request.get("room_code", "")).to_upper()
	var token: String = str(request.get("token", ""))
	var room: Dictionary = _rooms.get(room_code, {})
	if _peer_rooms.has(peer_id) or room.is_empty() or room["engine"] == null or token.is_empty():
		rpc_id(peer_id, "_client_join_status", false, "Could not restore your seat.", -1, false, "")
		return
	var seat: int = (room["tokens"] as Array).find(token)
	if seat < 0 or int((room["peers"] as Array)[seat]) >= 0:
		rpc_id(peer_id, "_client_join_status", false, "Your seat is no longer available.", -1, false, "")
		return
	(room["peers"] as Array)[seat] = peer_id
	(room["vacated_at"] as Array)[seat] = 0
	_peer_rooms[peer_id] = room_code
	_peer_seats[peer_id] = seat
	rpc_id(peer_id, "_client_join_status", true, "Reconnected.", seat, true, token)
	_send_snapshot(peer_id, seat, (room["engine"] as GameEngine).state)
	_notify_room(room, "%s reconnected." % _seat_name(room, seat), peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _server_submit_action(action: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not _peer_rooms.has(peer_id):
		rpc_id(peer_id, "_client_action_result", false, "You are not in a match.")
		return
	var room_code: String = str(_peer_rooms[peer_id])
	var room: Dictionary = _rooms.get(room_code, {})
	var game: GameEngine = room.get("engine") as GameEngine
	if game == null:
		rpc_id(peer_id, "_client_action_result", false, "The match is not ready.")
		return
	var seat: int = int(_peer_seats[peer_id])
	if game.state.active_player_id != seat:
		rpc_id(peer_id, "_client_action_result", false, "It is not your turn.")
		return
	if not _is_legal_action(game.state, action):
		rpc_id(peer_id, "_client_action_result", false, "That action is not legal.")
		return
	var result: Dictionary = game.submit_action(action)
	if not bool(result["ok"]):
		rpc_id(peer_id, "_client_action_result", false, str(result["error"]))
		return
	rpc_id(peer_id, "_client_action_result", true, "")
	var peers: Array = room["peers"]
	for index in range(peers.size()):
		_send_snapshot(int(peers[index]), index, game.state, {"action": action, "result": result})

@rpc("authority", "call_remote", "reliable")
func _client_join_status(accepted: bool, message: String, player_id: int, ready: bool, session_token: String) -> void:
	if not accepted:
		if mode == "reconnecting":
			_give_up_reconnecting(message)
			return
		mode = "connected"
		status_changed.emit(message)
		return
	_reconnect_attempts = 0
	_session_token = session_token
	local_player_id = player_id
	mode = "client" if ready else "waiting"
	status_changed.emit(message)

@rpc("authority", "call_remote", "reliable")
func _client_seat_status(message: String) -> void:
	status_changed.emit(message)

@rpc("authority", "call_remote", "reliable")
func _client_receive_snapshot(snapshot: Dictionary) -> void:
	var result: Dictionary = GameStateCodec.decode(snapshot)
	if not bool(result["ok"]):
		push_error("Rejected server game state: %s" % str(result["error"]))
		disconnect_from_server()
		return
	var decoded_state: GameState = result["state"]
	if decoded_state.players.size() != int(_pending_join.get("player_count", 2)):
		disconnect_from_server()
		status_changed.emit("The server does not support the selected player count.")
		return
	var visual: Variant = snapshot.get("visual_action", {})
	if not visual is Dictionary or (not visual.is_empty() and (
			not visual.get("action") is Dictionary or not visual.get("result") is Dictionary)):
		push_error("Rejected server game state: invalid visual action.")
		disconnect_from_server()
		return
	current_visual_action = visual
	current_state = decoded_state
	local_player_id = int(snapshot["viewer_id"])
	action_pending = false
	snapshot_received.emit(current_state, local_player_id)
	if mode == "client" and not _announced_match_ready:
		_announced_match_ready = true
		match_ready.emit(local_player_id)

@rpc("authority", "call_remote", "reliable")
func _client_action_result(accepted: bool, message: String) -> void:
	if not accepted:
		action_pending = false
	action_result_received.emit(accepted, message)

func _validate_join_request(request: Dictionary) -> String:
	var room_code: String = str(request.get("room_code", "")).to_upper()
	if not _valid_room_code(room_code):
		return "Room codes must be 6-16 letters or numbers."
	if not request.get("create_room", false) is bool:
		return "Invalid room request."
	var display_name: String = str(request.get("display_name", "")).strip_edges()
	if display_name.is_empty() or display_name.length() > 24:
		return "Player name must be 1-24 characters."
	var army_id: String = str(request.get("army_id", ""))
	if not ArmyCatalog.is_army(army_id):
		return "Invalid army."
	if not request.get("deck_card_ids") is Array:
		return "Invalid deck."
	var deck_card_ids: Array[String] = []
	for card_id: Variant in request["deck_card_ids"]:
		deck_card_ids.append(str(card_id))
	if not DeckData.validate(deck_card_ids).is_empty():
		return "The selected deck is not legal."
	if DeckData.army_of(deck_card_ids) not in ["", army_id]:
		return "The selected deck does not match that army."
	var setup_tiles: int = int(request.get("setup_tiles", -1))
	if setup_tiles not in [0, 3]:
		return "Invalid terrain setup option."
	if not request.get("player_count", 2) is int or int(request.get("player_count", 2)) not in [2, 4]:
		return "Invalid player count."
	return ""

func _is_legal_action(state: GameState, action: Dictionary) -> bool:
	for legal_action: Dictionary in ActionGenerator.legal_actions(state):
		if action == legal_action:
			return true
	return false

func _send_snapshot(peer_id: int, viewer_id: int, state: GameState, visual_action: Dictionary = {}) -> void:
	if peer_id > 0:
		var snapshot: Dictionary = GameStateCodec.encode(state, viewer_id)
		if not visual_action.is_empty():
			snapshot["visual_action"] = visual_action
		rpc_id(peer_id, "_client_receive_snapshot", snapshot)

func _on_connected_to_server() -> void:
	if _reconnect_pending:
		_reconnect_pending = false
		rpc_id(1, "_server_reconnect", {"room_code": _pending_join.get("room_code", ""), "token": _session_token})
		status_changed.emit("Reconnecting to the match...")
		return
	if _pending_join.is_empty():
		return
	rpc_id(1, "_server_join_request", _pending_join)
	status_changed.emit("Connected. Joining room...")

func _on_connection_failed() -> void:
	if mode == "reconnecting":
		_schedule_reconnect()
		return
	_disconnect_peer()
	mode = "offline"
	_pending_join.clear()
	status_changed.emit("Could not connect to the server.")

func _on_server_disconnected() -> void:
	if (mode == "client" or mode == "reconnecting") and not _session_token.is_empty():
		_schedule_reconnect()
		return
	var message: String = "Disconnected from the match server."
	mode = "disconnected"
	local_player_id = -1
	current_state = null
	current_visual_action.clear()
	action_pending = false
	status_changed.emit(message)
	match_ended.emit(message)

func _schedule_reconnect() -> void:
	_reconnect_attempts += 1
	if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
		_give_up_reconnecting("Lost the connection to the match server.")
		return
	mode = "reconnecting"
	action_pending = false
	status_changed.emit("Connection lost. Reconnecting (%d/%d)..." % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
	_reconnect_timer.start(RECONNECT_DELAY_SECONDS)

func _attempt_reconnect() -> void:
	_disconnect_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(_server_address, _server_port) != OK:
		_schedule_reconnect()
		return
	multiplayer.multiplayer_peer = peer
	_reconnect_pending = true

func _give_up_reconnecting(message: String) -> void:
	_disconnect_peer()
	_reset_session()
	mode = "disconnected"
	status_changed.emit(message)
	match_ended.emit(message)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server() or not _peer_rooms.has(peer_id):
		return
	var room_code: String = str(_peer_rooms[peer_id])
	var room: Dictionary = _rooms.get(room_code, {})
	var seat: int = int(_peer_seats[peer_id])
	_peer_rooms.erase(peer_id)
	_peer_seats.erase(peer_id)
	if room.is_empty():
		return
	var peers: Array = room["peers"]
	peers[seat] = -1
	if room["engine"] == null:
		# Waiting rooms have no match to resume, so the seat is simply released.
		(room["player_data"] as Array)[seat] = {}
		(room["tokens"] as Array)[seat] = ""
		_notify_room(room, "%s left the room." % _seat_name(room, seat), -1)
	else:
		(room["vacated_at"] as Array)[seat] = Time.get_ticks_msec()
		_notify_room(room, "%s disconnected. Waiting up to %d seconds for them to reconnect." % [
			_seat_name(room, seat), int(reconnect_grace_seconds)], -1)
	if _room_is_abandoned(room):
		_rooms.erase(room_code)

# Frees seats whose player did not reconnect in time, so another player can take them with the room code.
func _expire_vacated_seats() -> void:
	var now: int = Time.get_ticks_msec()
	for room_code: String in _rooms.keys():
		var room: Dictionary = _rooms[room_code]
		if room["engine"] == null:
			continue
		var vacated: Array = room["vacated_at"]
		for seat in range(vacated.size()):
			if int(vacated[seat]) > 0 and now - int(vacated[seat]) >= reconnect_grace_seconds * 1000.0:
				vacated[seat] = 0
				(room["tokens"] as Array)[seat] = ""
				_notify_room(room, "%s did not return. Seat %d is open: join with room code %s." % [
					_seat_name(room, seat), seat + 1, room_code], -1)
		if _room_is_abandoned(room):
			_rooms.erase(room_code)

func _room_has_connected_peers(room: Dictionary) -> bool:
	for peer_id: Variant in room["peers"]:
		if int(peer_id) > 0:
			return true
	return false

# A room is abandoned once no seat is connected and no seat is still waiting for its player to return.
func _room_is_abandoned(room: Dictionary) -> bool:
	if _room_has_connected_peers(room):
		return false
	for vacated_at: Variant in room["vacated_at"]:
		if int(vacated_at) > 0:
			return false
	return true

func _notify_room(room: Dictionary, message: String, except_peer: int) -> void:
	var connected_peers: PackedInt32Array = multiplayer.get_peers()
	for peer_id: Variant in room["peers"]:
		var target: int = int(peer_id)
		if target > 0 and target != except_peer and connected_peers.has(target):
			rpc_id(target, "_client_seat_status", message)

func _seat_name(room: Dictionary, seat: int) -> String:
	var data: Dictionary = (room["player_data"] as Array)[seat]
	return str(data.get("display_name", "Seat %d" % (seat + 1)))

func _new_session_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _disconnect_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _valid_room_code(code: String) -> bool:
	if code.length() < MIN_ROOM_CODE_LENGTH or code.length() > MAX_ROOM_CODE_LENGTH:
		return false
	for character: String in code:
		if not character.to_upper() in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
			return false
	return true

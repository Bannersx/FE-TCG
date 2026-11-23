extends SceneTree

var online: Node
var _submit_first_action: bool = false
var _submitted: bool = false
var _action_accepted: bool = false
var _finished: bool = false
var _wait_for_disconnect: bool = false
var _test_invalid_action: bool = false
var _invalid_action_rejected: bool = false
var _player_count: int = 2
var _cycle_turns: bool = false
var _animation_scenario: bool = false
var _animation_scene: Control
var _confirmation_scenario: bool = false
var _confirmation_scene: Control
var _drop_once: bool = false
var _dropped: bool = false
var _stay: bool = false
var _late_join: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	online = root.get_node("OnlineMatch")
	online.snapshot_received.connect(_on_snapshot_received)
	online.action_result_received.connect(_on_action_result)
	online.match_ended.connect(_on_match_ended)
	online.status_changed.connect(_on_status)
	var options: Dictionary = _parse_options(OS.get_cmdline_user_args())
	var army_id: String = str(options.get("army", ArmyCatalog.IRONCREST_ID))
	_player_count = int(options.get("players", 2))
	_cycle_turns = _is_enabled(options.get("cycle", false))
	_animation_scenario = _is_enabled(options.get("animation", false))
	_confirmation_scenario = _is_enabled(options.get("confirmation", false))
	_submit_first_action = _is_enabled(options.get("submit", false))
	_wait_for_disconnect = _is_enabled(options.get("wait_disconnect", false))
	_test_invalid_action = _is_enabled(options.get("test_invalid", false))
	_drop_once = _is_enabled(options.get("drop_once", false))
	_stay = _is_enabled(options.get("stay", false))
	_late_join = _is_enabled(options.get("late_join", false))
	print("SMOKE_OPTIONS: submit=%s wait_disconnect=%s test_invalid=%s" % [
		_submit_first_action, _wait_for_disconnect, _test_invalid_action,
	])
	var error: Error = online.connect_to_server(
		str(options.get("address", "127.0.0.1")),
		int(options.get("port", 18777)),
		str(options.get("code", "SMOKETST")),
		_is_enabled(options.get("create", false)),
		str(options.get("name", "SmokeTest")),
		army_id,
		DeckData.starter_ids(0, army_id),
		0,
		_player_count
	)
	if error != OK:
		push_error("Smoke client could not connect (error %d)." % error)
		quit(1)
		return
	await create_timer(90.0).timeout
	if not _finished:
		push_error("Smoke client timed out.")
		quit(1)

func _on_snapshot_received(state: GameState, viewer_id: int) -> void:
	var hidden_cards_ok: bool = true
	for player: PlayerState in state.players:
		if player.player_id == viewer_id:
			continue
		for card: CardData in player.hand + player.deck:
			if card.card_id != GameStateCodec.HIDDEN_CARD_ID:
				hidden_cards_ok = false
	if state.players.size() != _player_count:
		hidden_cards_ok = false
	print("SNAPSHOT: seat=%d phase=%d turn=%d hidden_cards_ok=%s" % [
		viewer_id, state.phase, state.turn_number, hidden_cards_ok,
	])
	if not hidden_cards_ok:
		push_error("Opponent hand identities were not hidden.")
		_finished = true
		quit(1)
		return
	if _drop_once:
		if not _dropped:
			_dropped = true
			print("DROPPING_CONNECTION: seat=%d" % viewer_id)
			online.simulate_connection_loss()
		else:
			print("RECONNECT_OK: seat=%d" % viewer_id)
			_finished = true
			quit(0)
		return
	if _confirmation_scenario and viewer_id == 0 and state.phase == GameState.Phase.DEPLOYMENT and _confirmation_scene == null:
		GameSettings.confirm_actions = true
		_confirmation_scene = load("res://scenes/main/game_scene.tscn").instantiate()
		root.add_child(_confirmation_scene)
		_confirmation_scene.call("_on_advance_pressed")
		var dialog: ConfirmationDialog = _confirmation_scene.get("action_dialog")
		if not dialog.visible or bool(online.get("action_pending")):
			push_error("Online action was submitted before confirmation.")
			_finished = true
			quit(1)
			return
		dialog.get_ok_button().pressed.emit()
		if not bool(online.get("action_pending")):
			push_error("Confirmed online action was not submitted.")
			_finished = true
			quit(1)
			return
		_submitted = true
		print("ONLINE_CONFIRMATION_SUBMITTED")
		return
	if _animation_scenario:
		_animation_step(state, viewer_id)
		return
	if state.phase == GameState.Phase.COMMAND and not _cycle_turns and not _late_join:
		var visual: Dictionary = online.get("current_visual_action")
		if visual.is_empty() or str(visual["action"].get("type", "")) != "advance_phase" \
				or not visual["result"].has("visual_effects"):
			push_error("The authoritative action was not delivered with the snapshot.")
			_finished = true
			quit(1)
			return
		print("VISUAL_ACTION_OK: seat=%d" % viewer_id)
	if _cycle_turns:
		if state.turn_number > _player_count and viewer_id == 0:
			print("NETWORK_CYCLE_OK: all %d players completed a turn" % _player_count)
			_finished = true
			quit(0)
		elif state.turn_number <= _player_count and state.active_player_id == viewer_id:
			print("CYCLE_ADVANCE: seat=%d phase=%d" % [viewer_id, state.phase])
			if not online.submit_action({"type": "advance_phase"}):
				push_error("Could not submit cycle action.")
				_finished = true
				quit(1)
		return
	if _submit_first_action and viewer_id == 0 and not _submitted:
		var action: Dictionary = {"type": "advance_phase"}
		if _test_invalid_action and not _invalid_action_rejected:
			action = {"type": "move", "destination": Vector2i(1, 1)}
		_submitted = online.submit_action(action)
		if not _submitted:
			push_error("Smoke action was not submitted.")
			_finished = true
			quit(1)
			return
	var action_complete: bool = _action_accepted if _submit_first_action else not _wait_for_disconnect
	if state.phase == GameState.Phase.COMMAND and action_complete:
		if _stay:
			print("HOLDING_SEAT: seat=%d" % viewer_id)
			return
		print("NETWORK_SMOKE_OK: seat=%d active=%d phase=%d" % [viewer_id, state.active_player_id, state.phase])
		_finished = true
		quit(0)

func _on_action_result(accepted: bool, message: String) -> void:
	print("ACTION_RESULT: accepted=%s message=%s" % [accepted, message])
	if not accepted and _test_invalid_action and not _invalid_action_rejected:
		if message != "That action is not legal.":
			push_error("Unexpected invalid-action response: %s" % message)
			_finished = true
			quit(1)
			return
		_invalid_action_rejected = true
		print("INVALID_ACTION_REJECTED")
		_submitted = online.submit_action({"type": "advance_phase"})
		if not _submitted:
			push_error("Legal action could not be submitted after invalid action rejection.")
			_finished = true
			quit(1)
		return
	_action_accepted = accepted
	if not accepted:
		_finished = true
		quit(1)

func _animation_step(state: GameState, viewer_id: int) -> void:
	if _animation_scene == null:
		_animation_scene = load("res://scenes/main/game_scene.tscn").instantiate()
		root.add_child(_animation_scene)
	if viewer_id == 0:
		var action: Dictionary = {}
		if state.phase == GameState.Phase.DEPLOYMENT:
			action = {"type": "advance_phase"}
		elif state.current_activation_unit_id.is_empty():
			action = {"type": "start_activation", "unit_id": state.players[0].commander.instance_id}
		elif not state.current_activation_moved:
			action = {"type": "move", "destination": Vector2i(1, 3)}
		if not action.is_empty() and not online.submit_action(action):
			push_error("Could not submit animation scenario action.")
			_finished = true
			quit(1)
	elif str((online.get("current_visual_action") as Dictionary).get("action", {}).get("type", "")) == "move":
		call_deferred("_verify_remote_animation")

func _verify_remote_animation() -> void:
	var visual: Dictionary = online.get("current_visual_action")
	var layer: Control = _animation_scene.get("effect_layer")
	if str(visual["action"].get("type", "")) != "move" or layer.get_child_count() == 0:
		push_error("The remote move did not produce an animation.")
		_finished = true
		quit(1)
		return
	print("REMOTE_MOVE_ANIMATION_OK")
	_finished = true
	quit(0)

func _on_match_ended(message: String) -> void:
	print("MATCH_ENDED: %s" % message)
	if _drop_once and not _dropped:
		push_error("Match ended before the simulated drop: %s" % message)
		_finished = true
		quit(1)

func _on_status(message: String) -> void:
	print("STATUS: %s" % message)
	if _wait_for_disconnect and message.contains("Waiting up to"):
		print("DISCONNECT_SMOKE_OK")
		_finished = true
		quit(0)

func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for argument: String in arguments:
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", false, 1)
		if parts.size() == 2:
			result[parts[0].replace("-", "_")] = parts[1]
	return result

func _is_enabled(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	return str(value).to_lower() in ["true", "1", "yes"]

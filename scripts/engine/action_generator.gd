class_name ActionGenerator
extends RefCounted

# Every action the active player could submit right now. Uses the engine's own validators.
static func legal_actions(state: GameState) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if state.phase == GameState.Phase.GAME_OVER:
		return actions
	var pid: int = state.active_player_id
	var player: PlayerState = state.players[pid]
	match state.phase:
		GameState.Phase.SETUP:
			actions.append_array(GameEngine.terrain_options(state, pid))
			actions.append({"type": "pass_setup"})
		GameState.Phase.DEPLOYMENT:
			_deployment_actions(state, player, actions)
			_tactic_actions(state, player, actions)
		GameState.Phase.COMMAND:
			_command_actions(state, player, actions)
			_tactic_actions(state, player, actions)
	if state.phase == GameState.Phase.DEPLOYMENT or state.phase == GameState.Phase.COMMAND:
		actions.append({"type": "advance_phase"})
	return actions

static func _unique_hand(player: PlayerState) -> Array[CardData]:
	var seen: Dictionary = {}
	var cards: Array[CardData] = []
	for card in player.hand:
		if not seen.has(card.card_id):
			seen[card.card_id] = true
			cards.append(card)
	return cards

static func _deployment_actions(state: GameState, player: PlayerState, actions: Array[Dictionary]) -> void:
	var pid: int = player.player_id
	for card in _unique_hand(player):
		match card.card_type:
			CardData.CardType.UNIT:
				for y in range(state.board.height):
					for x in range(state.board.width):
						var tile := Vector2i(x, y)
						if GameEngine.deploy_error(state, pid, card, tile) == "":
							actions.append({"type": "deploy", "card_id": card.card_id, "tile": tile})
			CardData.CardType.EQUIPMENT:
				for unit in player.units:
					if GameEngine.equip_error(state, pid, card, unit) == "":
						actions.append({"type": "equip", "card_id": card.card_id, "unit_id": unit.instance_id})
			CardData.CardType.PROMOTION:
				for unit in player.units:
					if GameEngine.promote_error(state, pid, card, unit) == "":
						actions.append({"type": "promote", "card_id": card.card_id, "unit_id": unit.instance_id})

static func _tactic_actions(state: GameState, player: PlayerState, actions: Array[Dictionary]) -> void:
	var pid: int = player.player_id
	for card in _unique_hand(player):
		if card.card_type != CardData.CardType.TACTIC:
			continue
		for other in state.players:
			for unit in other.units:
				if unit.current_hp <= 0:
					continue
				if card.target_kind == "friendly_unit_tile":
					for y in range(state.board.height):
						for x in range(state.board.width):
							var tile := Vector2i(x, y)
							if GameEngine.tactic_error(state, pid, card, unit.instance_id, tile) == "":
								actions.append({"type": "play_tactic", "card_id": card.card_id, "target_id": unit.instance_id, "destination": tile})
				elif GameEngine.tactic_error(state, pid, card, unit.instance_id, Vector2i(-1, -1)) == "":
					actions.append({"type": "play_tactic", "card_id": card.card_id, "target_id": unit.instance_id})

static func _command_actions(state: GameState, player: PlayerState, actions: Array[Dictionary]) -> void:
	var pid: int = player.player_id
	if state.current_activation_unit_id == "":
		for unit in player.units:
			if GameEngine.activation_error(state, pid, unit) == "":
				actions.append({"type": "start_activation", "unit_id": unit.instance_id})
		return
	var active: UnitState = state.find_unit(state.current_activation_unit_id)
	if not state.current_activation_moved:
		var reachable: Dictionary = MovementResolver.reachable_tiles(state.board, active)
		for tile: Vector2i in reachable:
			if tile != active.position:
				actions.append({"type": "move", "destination": tile})
	for other in state.players:
		if other.player_id == pid:
			continue
		for enemy in other.units:
			if GameEngine.attack_error(state, active, enemy) == "":
				actions.append({"type": "attack", "target_id": enemy.instance_id, "support": false})
				if SupportResolver.find_attack_partner(state, active, enemy) != null:
					actions.append({"type": "attack", "target_id": enemy.instance_id, "support": true})
	actions.append({"type": "wait"})

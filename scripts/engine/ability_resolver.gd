class_name AbilityResolver
extends RefCounted

# Returns an error message, or "" when the tactic is legal against this target.
static func validate(state: GameState, player_id: int, card: CardData, target_id: String, destination: Vector2i) -> String:
	var target: UnitState = state.find_unit(target_id)
	if target == null or target.current_hp <= 0:
		return "Invalid target."
	var board: BoardState = state.board
	match card.target_kind:
		"enemy_unit":
			if target.owner_id == player_id:
				return "Must target an enemy unit."
			return ""
		"friendly_unit", "friendly_unit_tile":
			if target.owner_id != player_id:
				return "Must target a friendly unit."
		_:
			return "Unknown target kind."
	if card.tactic_effect == "heal" and target.current_hp >= target.max_hp():
		return "Target is not damaged."
	if card.tactic_effect == "sow" and state.seeds.has(target.position):
		return "That tile already holds a seed."
	if card.target_kind == "friendly_unit":
		return ""
	if not board.is_valid_position(destination) or board.occupants.has(destination):
		return "Destination must be an empty tile."
	if board.movement_cost(destination, target.card.movement_type) < 0:
		return "Destination is impassable."
	if card.tactic_effect == "reposition" and BoardState.distance(target.position, destination) > card.magnitude:
		return "Destination is too far."
	if card.tactic_effect == "retreat" and destination.x != board.deployment_column(player_id):
		return "Destination must be in your deployment column."
	return ""

# Applies a validated tactic and returns the instance ids of defeated units.
static func apply(state: GameState, card: CardData, target_id: String, destination: Vector2i) -> Array[String]:
	var defeated: Array[String] = []
	var target: UnitState = state.find_unit(target_id)
	match card.tactic_effect:
		"buff":
			target.mods.append({"stat": card.buff_stat, "amount": card.magnitude, "expires": card.duration})
		"heal":
			target.current_hp = mini(target.max_hp(), target.current_hp + card.magnitude)
		"damage":
			target.current_hp = maxi(0, target.current_hp - card.magnitude)
			if target.current_hp <= 0:
				defeated.append(target.instance_id)
		"burn":
			target.current_hp = maxi(0, target.current_hp - card.magnitude)
			if target.current_hp <= 0:
				defeated.append(target.instance_id)
			else:
				target.apply_status("burn", card.status_turns)
		"chill":
			target.apply_status("chill", card.status_turns)
		"sow":
			state.seeds[target.position] = target.owner_id
		"reposition", "retreat":
			state.board.move_unit(target, destination)
	return defeated

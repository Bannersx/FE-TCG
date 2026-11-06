class_name VictoryResolver
extends RefCounted

static func check_victory(state: GameState) -> int:
	for player in state.players:
		if player.commander == null or player.commander.current_hp <= 0:
			return 1 - player.player_id
	for player in state.players:
		if player.victory_points >= 6:
			return player.player_id
	return -1

static func finish_if_won(state: GameState, winner_id: int, reason: String) -> void:
	if winner_id < 0 or state.phase == GameState.Phase.GAME_OVER:
		return
	state.winner_id = winner_id
	state.game_over_reason = reason
	state.phase = GameState.Phase.GAME_OVER
	state.current_activation_unit_id = ""
	state.events.append("Player %d wins: %s" % [winner_id + 1, reason])

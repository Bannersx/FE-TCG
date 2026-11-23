class_name GameState
extends RefCounted

enum Phase { DEPLOYMENT, COMMAND, END, GAME_OVER, SETUP }

var board: BoardState = BoardState.new()
var players: Array[PlayerState] = []
var active_player_id: int = 0
var phase: Phase = Phase.DEPLOYMENT
var turn_number: int = 1
var winner_id: int = -1
var game_over_reason: String = ""
var next_instance_number: int = 1
var current_activation_unit_id: String = ""
var current_activation_moved: bool = false
var activated_unit_ids: Array[String] = []
var events: Array[String] = []
var bonds: Dictionary = {}
var activation_moved_tiles: int = 0
var chain_count: int = 0
# Verdant seeds: tile -> owner player id. A seed blooms at the start of its owner's turn if their unit stands on it.
var seeds: Dictionary = {}
var used_shrines: Dictionary = {}
# Pre-game terrain setup: placements each player still has, and what they have used (terrain name -> count).
var setup_left: Array[int] = [0, 0]
var setup_used: Array[Dictionary] = [{}, {}]
var history: Array[Dictionary] = []

func active_player() -> PlayerState:
	return players[active_player_id]

func opponent_player() -> PlayerState:
	return players[1 - active_player_id]

func find_unit(instance_id: String) -> UnitState:
	for player in players:
		for unit in player.units:
			if unit.instance_id == instance_id:
				return unit
	return null

func find_card_in_hand(player_id: int, card_id: String) -> int:
	for index in range(players[player_id].hand.size()):
		if players[player_id].hand[index].card_id == card_id:
			return index
	return -1

func create_instance_id() -> String:
	var result: String = "unit_%04d" % next_instance_number
	next_instance_number += 1
	return result

class_name PlayerState
extends RefCounted

var player_id: int = 0
var display_name: String = ""
var deck: Array[CardData] = []
var hand: Array[CardData] = []
var discard: Array[CardData] = []
var max_supply: int = 0
var current_supply: int = 0
var victory_points: int = 0
var normal_deployments_this_turn: int = 0
var fallen: Array[CardData] = []
var units: Array[UnitState] = []
var commander: UnitState
var army_id: String = ""
var tactics_this_turn: int = 0
var eliminated: bool = false
var turns_started: int = 0
# Ashen commander passive: this unit may act on the turn it was deployed.
var haste_unit_id: String = ""

func normal_unit_count() -> int:
	var count: int = 0
	for unit in units:
		if not unit.is_commander and unit.current_hp > 0:
			count += 1
	return count

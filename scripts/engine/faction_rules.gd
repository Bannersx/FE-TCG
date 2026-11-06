class_name FactionRules
extends RefCounted

# Army passives, kept in one place so the combat, movement and turn code only call these hooks.
#
# Ashen Vanguard (aggro):   Momentum - an activated unit that moved 2+ tiles hits for +1 ATK.
# Ironcrest Order (control): Shield Wall - +1 DEF next to an ally; commander Maren: +1 DEF on objectives.
# Verdant Circle (combo):   Chain - +1 ATK per tactic/bloom this turn (max 3); Forestwalkers.

const MOMENTUM_TILES: int = 2
const CHAIN_CAP: int = 3
const BLOOM_HEAL: int = 2
const FOREST_HEAL: int = 1

static func attack_bonus(state: GameState, attacker: UnitState) -> int:
	if state == null:
		return 0
	match attacker.card.faction:
		CardCatalog.IRONCREST:
			return 1 if _has_adjacent_ally(state, attacker) else 0
		CardCatalog.ASHEN:
			if attacker.instance_id == state.current_activation_unit_id and state.activation_moved_tiles >= MOMENTUM_TILES:
				return 1
		CardCatalog.VERDANT:
			if attacker.owner_id == state.active_player_id:
				return mini(state.chain_count, CHAIN_CAP)
	return 0

static func _has_adjacent_ally(state: GameState, unit: UnitState) -> bool:
	for ally in state.players[unit.owner_id].units:
		if ally != unit and ally.current_hp > 0 and BoardState.distance(ally.position, unit.position) == 1:
			return true
	return false

static func defense_bonus(state: GameState, defender: UnitState) -> int:
	if state == null or defender.card.faction != CardCatalog.IRONCREST:
		return 0
	var bonus: int = 1 if _has_adjacent_ally(state, defender) else 0
	if state.board.terrain_at(defender.position) == BoardState.OBJECTIVE:
		bonus += 1
	return bonus

static func move_cost(board: BoardState, unit: UnitState, tile: Vector2i) -> int:
	if unit.card.faction == CardCatalog.VERDANT and unit.card.movement_type == CardData.MovementType.GROUND \
			and board.terrain_at(tile) == BoardState.FOREST:
		return 1
	return board.movement_cost(tile, unit.card.movement_type)

# Ashen's commander lets one freshly deployed unit act immediately.
static func has_haste(state: GameState, unit: UnitState) -> bool:
	return state.players[unit.owner_id].haste_unit_id == unit.instance_id

# Verdant's commander discounts the first tactic each turn by 1 supply.
static func tactic_cost(state: GameState, player_id: int, card: CardData) -> int:
	var player: PlayerState = state.players[player_id]
	if player.army_id == ArmyCatalog.VERDANT_ID and player.tactics_this_turn == 0:
		return maxi(0, card.supply_cost - 1)
	return card.supply_cost

static func grants_haste(player: PlayerState) -> bool:
	return player.army_id == ArmyCatalog.ASHEN_ID

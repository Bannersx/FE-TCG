class_name SupportResolver
extends RefCounted

const RANK_C_PROGRESS: int = 1
const RANK_A_PROGRESS: int = 3

static func bond_key(id_a: String, id_b: String) -> String:
	return "%s|%s" % ([id_a, id_b] if id_a < id_b else [id_b, id_a])

static func get_bond(state: GameState, unit_a: UnitState, unit_b: UnitState) -> Dictionary:
	return state.bonds.get(bond_key(unit_a.instance_id, unit_b.instance_id), {})

static func rank(bond: Dictionary) -> String:
	if bond.is_empty():
		return "-"
	var progress: int = int(bond["progress"])
	if progress >= RANK_A_PROGRESS:
		return "A"
	if progress >= RANK_C_PROGRESS:
		return "C"
	return "-"

static func are_adjacent(unit_a: UnitState, unit_b: UnitState) -> bool:
	return BoardState.distance(unit_a.position, unit_b.position) == 1

static func partners_of(state: GameState, unit: UnitState) -> Array[UnitState]:
	var result: Array[UnitState] = []
	if unit.is_commander:
		return result
	for other in state.players[unit.owner_id].units:
		if other != unit and other.current_hp > 0 and not other.is_commander \
				and SupportData.are_partners(unit.card.card_id, other.card.card_id):
			result.append(other)
	return result

# Adds one point of bond progress per turn to each adjacent partner pair of the active player.
static func process_start_of_turn(state: GameState) -> void:
	var units: Array[UnitState] = state.active_player().units
	for index in range(units.size()):
		for other_index in range(index + 1, units.size()):
			var unit_a: UnitState = units[index]
			var unit_b: UnitState = units[other_index]
			if unit_a.current_hp <= 0 or unit_b.current_hp <= 0 or unit_a.is_commander or unit_b.is_commander:
				continue
			if not SupportData.are_partners(unit_a.card.card_id, unit_b.card.card_id):
				continue
			if not are_adjacent(unit_a, unit_b):
				continue
			var key: String = bond_key(unit_a.instance_id, unit_b.instance_id)
			var bond: Dictionary = state.bonds.get(key, {
				"a": unit_a.instance_id, "b": unit_b.instance_id, "progress": 0, "last_turn": -1, "used": false,
			})
			if int(bond["last_turn"]) == state.turn_number:
				continue
			bond["progress"] = int(bond["progress"]) + 1
			bond["last_turn"] = state.turn_number
			state.bonds[key] = bond
			state.events.append("Bond between %s and %s reaches rank %s." % [
				unit_a.card.card_name, unit_b.card.card_name, rank(bond)
			])

static func defense_bonus(state: GameState, unit: UnitState) -> int:
	for partner in partners_of(state, unit):
		if are_adjacent(unit, partner) and int(get_bond(state, unit, partner).get("progress", 0)) >= RANK_C_PROGRESS:
			return 1
	return 0

# A partner with an A-rank, unused bond that can reach the defender joins the attack.
static func find_attack_partner(state: GameState, attacker: UnitState, defender: UnitState) -> UnitState:
	for partner in partners_of(state, attacker):
		var bond: Dictionary = get_bond(state, attacker, partner)
		if bond.is_empty() or bool(bond["used"]) or int(bond["progress"]) < RANK_A_PROGRESS:
			continue
		if CombatResolver.in_range(partner, defender):
			return partner
	return null

static func mark_used(state: GameState, unit_a: UnitState, unit_b: UnitState) -> void:
	var key: String = bond_key(unit_a.instance_id, unit_b.instance_id)
	if state.bonds.has(key):
		var bond: Dictionary = state.bonds[key]
		bond["used"] = true

static func describe(state: GameState, unit: UnitState) -> String:
	var parts: PackedStringArray = []
	for partner in partners_of(state, unit):
		var bond: Dictionary = get_bond(state, unit, partner)
		parts.append("%s: rank %s%s" % [
			partner.card.card_name, rank(bond), " (used)" if not bond.is_empty() and bool(bond["used"]) else ""
		])
	return ", ".join(parts)

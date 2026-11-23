class_name CombatResolver
extends RefCounted

static func triangle_modifier(attacker_weapon: CardData.WeaponType, defender_weapon: CardData.WeaponType) -> int:
	var W := CardData.WeaponType
	if attacker_weapon == W.SWORD and defender_weapon == W.AXE:
		return 1
	if attacker_weapon == W.AXE and defender_weapon == W.LANCE:
		return 1
	if attacker_weapon == W.LANCE and defender_weapon == W.SWORD:
		return 1
	if defender_weapon == W.SWORD and attacker_weapon == W.AXE:
		return -1
	if defender_weapon == W.AXE and attacker_weapon == W.LANCE:
		return -1
	if defender_weapon == W.LANCE and attacker_weapon == W.SWORD:
		return -1
	return 0

static func attack_value(attacker: UnitState, defender: UnitState, state: GameState = null) -> int:
	var value: int = attacker.attack() + triangle_modifier(attacker.weapon_type(), defender.weapon_type())
	value += FactionRules.attack_bonus(state, attacker)
	if attacker.weapon_type() == CardData.WeaponType.BOW and defender.card.movement_type == CardData.MovementType.FLYING:
		value += 2
	return value

static func defense_value(board: BoardState, attacker: UnitState, defender: UnitState, state: GameState = null) -> int:
	var value: int = defender.defense()
	if attacker.weapon_type() == CardData.WeaponType.MAGIC:
		value -= defender.card.defense
	value += board.defense_bonus(defender.position)
	if board.terrain_at(defender.position) == BoardState.RUINS and BoardState.distance(attacker.position, defender.position) > 1:
		value += 1
	if state != null:
		value += SupportResolver.defense_bonus(state, defender)
		value += FactionRules.defense_bonus(state, defender)
	return value

static func calculate_damage(board: BoardState, attacker: UnitState, defender: UnitState, state: GameState = null) -> int:
	var attack: int = attack_value(attacker, defender, state)
	if board.terrain_at(attacker.position) == BoardState.HIGH_GROUND and BoardState.distance(attacker.position, defender.position) > 1:
		attack += 1
	return maxi(0, attack - defense_value(board, attacker, defender, state))

static func in_range(attacker: UnitState, defender: UnitState) -> bool:
	var dist: int = BoardState.distance(attacker.position, defender.position)
	return dist >= 1 and dist <= attacker.attack_range()

static func can_follow_up(attacker: UnitState, defender: UnitState) -> bool:
	return attacker.speed() >= defender.speed() + 3

# Applies damage to the units and returns a report of every step taken.
static func resolve(
	board: BoardState, attacker: UnitState, defender: UnitState,
	state: GameState = null, partner: UnitState = null
) -> Dictionary:
	var report: Dictionary = {
		"steps": [], "defeated": [], "supported": false, "support_damage": 0,
		"counter": false, "follow_up": false,
	}
	if not _hit(board, attacker, defender, state, "attack", report):
		return report
	if partner != null:
		report["supported"] = true
		var before: int = defender.current_hp
		var alive: bool = _hit(board, partner, defender, state, "support", report)
		report["support_damage"] = before - maxi(0, defender.current_hp)
		if not alive:
			return report
	if in_range(defender, attacker):
		report["counter"] = true
		if not _hit(board, defender, attacker, state, "counter", report):
			return report
	if can_follow_up(attacker, defender):
		report["follow_up"] = true
		_hit(board, attacker, defender, state, "follow_up", report)
	return report

# Returns true if the target survived the hit.
static func _hit(
	board: BoardState, source: UnitState, target: UnitState,
	state: GameState, kind: String, report: Dictionary
) -> bool:
	var damage: int = calculate_damage(board, source, target, state)
	target.current_hp -= damage
	var steps: Array = report["steps"]
	steps.append({"kind": kind, "source": source.instance_id, "target": target.instance_id, "damage": damage})
	if target.current_hp <= 0:
		target.current_hp = 0
		var defeated: Array = report["defeated"]
		defeated.append(target.instance_id)
		return false
	if source.card.on_hit_status != "" and source.card.status_turns > 0:
		target.apply_status(source.card.on_hit_status, source.card.status_turns)
	return true

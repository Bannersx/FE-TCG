class_name AIController
extends RefCounted

enum Difficulty { EASY, NORMAL, HARD }

const MIN_PLAN_SCORE: float = 0.01
const SEARCH_MAX_CANDIDATES: int = 24
const SEARCH_MAX_ROLLOUT_STEPS: int = 80
const SEARCH_BASELINE_BONUS: float = 1.0

var difficulty: Difficulty = Difficulty.NORMAL
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var plan: Dictionary = {}

var weights: Dictionary = {
	"damage": 3.0, "kill": 12.0, "commander_hit": 2.0, "counter": 2.0, "counter_cmd": 3.0, "die": 14.0,
}

func _init(new_difficulty: Difficulty = Difficulty.NORMAL, ai_seed: int = 1) -> void:
	difficulty = new_difficulty
	rng.seed = ai_seed

# Returns exactly one action for the active player. It only reads state the player could see:
# their own hand and the public board. Hard additionally searches ahead on clones with the opponent's hidden cards re-dealt.
func choose_action(engine: GameEngine) -> Dictionary:
	if difficulty == Difficulty.HARD:
		return _search_action(engine)
	return _heuristic_action(engine)

func _heuristic_action(engine: GameEngine) -> Dictionary:
	var state: GameState = engine.state
	match state.phase:
		GameState.Phase.SETUP:
			return _setup_action(state)
		GameState.Phase.DEPLOYMENT:
			return _deployment_action(state)
		GameState.Phase.COMMAND:
			return _command_action(state)
	return {"type": "advance_phase"}

# ---- Pre-game terrain setup ----

# Picks the placement that best suits this army and hurts the opponent; passes when nothing is worth it.
func _setup_action(state: GameState) -> Dictionary:
	var pid: int = state.active_player_id
	var best: Dictionary = {}
	var best_score: float = 1.0
	for option in GameEngine.terrain_options(state, pid):
		var score: float = _terrain_score(state, pid, option) + rng.randf() * 0.4
		if score > best_score:
			best_score = score
			best = option
	return best if not best.is_empty() else {"type": "pass_setup"}

func _terrain_score(state: GameState, pid: int, option: Dictionary) -> float:
	var tile: Vector2i = option["tile"]
	var army: String = state.players[pid].army_id
	var own_column: int = state.board.deployment_column(pid)
	var enemy_column: int = state.board.deployment_column(1 - pid)
	var mine: bool = absi(tile.x - own_column) < absi(tile.x - enemy_column)
	var theirs: bool = absi(tile.x - own_column) > absi(tile.x - enemy_column)
	var near: bool = _goal_distance(state, tile, pid) <= 2
	var current: String = state.board.terrain_at(tile)
	match str(option["terrain"]):
		BoardState.FOREST:
			if army == ArmyCatalog.VERDANT_ID:
				return (2.5 if near else 1.0) if not theirs else 0.2
			if army == ArmyCatalog.IRONCREST_ID:
				return 1.5 if (mine and near) else (1.2 if theirs else 0.3)
			return 0.4 if theirs else (0.0 if near else -0.5)
		BoardState.FORT:
			if army == ArmyCatalog.ASHEN_ID:
				return -0.5
			if theirs:
				return -1.0
			return 2.3 if near else 0.8
		BoardState.MOUNTAIN:
			if army == ArmyCatalog.IRONCREST_ID:
				return 2.0 if theirs else 0.3
			if army == ArmyCatalog.ASHEN_ID:
				return -1.0
			return 1.5 if (theirs and state.players[1 - pid].army_id == ArmyCatalog.ASHEN_ID) else (0.5 if theirs else -0.5)
		BoardState.PLAIN:
			match current:
				BoardState.FOREST:
					if army == ArmyCatalog.VERDANT_ID:
						return -3.0
					if state.players[1 - pid].army_id == ArmyCatalog.VERDANT_ID:
						return 2.2
					return 1.5 if (army == ArmyCatalog.ASHEN_ID and mine) else -0.3
				BoardState.MOUNTAIN:
					if army == ArmyCatalog.IRONCREST_ID:
						return -2.0 if mine else 0.0
					return 1.5 if mine else 0.5
				BoardState.FORT:
					return 1.8 if theirs else -2.0
	return 0.0

# ---- Deployment phase ----

func _deployment_action(state: GameState) -> Dictionary:
	var actions: Array[Dictionary] = ActionGenerator.legal_actions(state)
	var deploys: Array[Dictionary] = _of_type(actions, "deploy")
	var equips: Array[Dictionary] = _of_type(actions, "equip")
	var promotes: Array[Dictionary] = _of_type(actions, "promote")
	if difficulty == Difficulty.EASY:
		return _easy_deployment(deploys, equips, promotes)
	var strike: Dictionary = _lethal_strike(state, actions)
	if not strike.is_empty():
		return strike
	if not promotes.is_empty():
		return promotes[0]
	if not deploys.is_empty():
		return _best_deploy(state, deploys)
	var equip: Dictionary = _best_equip(state, equips)
	if not equip.is_empty():
		return equip
	var tactic: Dictionary = _useful_tactic(state, _of_type(actions, "play_tactic"))
	if not tactic.is_empty():
		return tactic
	return {"type": "advance_phase"}

func _easy_deployment(deploys: Array[Dictionary], equips: Array[Dictionary], promotes: Array[Dictionary]) -> Dictionary:
	if not deploys.is_empty() and rng.randf() < 0.85:
		return deploys[rng.randi_range(0, deploys.size() - 1)]
	var options: Array[Dictionary] = []
	options.append_array(promotes)
	options.append_array(equips)
	if not options.is_empty() and rng.randf() < 0.6:
		return options[rng.randi_range(0, options.size() - 1)]
	return {"type": "advance_phase"}

func _of_type(actions: Array[Dictionary], action_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action in actions:
		if str(action["type"]) == action_type:
			result.append(action)
	return result

func _card_of(state: GameState, card_id: String) -> CardData:
	var index: int = state.find_card_in_hand(state.active_player_id, card_id)
	return state.active_player().hand[index] if index >= 0 else null

func _lethal_strike(state: GameState, actions: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_is_commander: bool = false
	for action in _of_type(actions, "play_tactic"):
		var card: CardData = _card_of(state, str(action["card_id"]))
		if card.tactic_effect != "damage" and card.tactic_effect != "burn":
			continue
		var target: UnitState = state.find_unit(str(action["target_id"]))
		if target.current_hp > card.magnitude:
			continue
		if best.is_empty() or (target.is_commander and not best_is_commander):
			best = action
			best_is_commander = target.is_commander
	return best

func _goal_distance(state: GameState, tile: Vector2i, player_id: int) -> int:
	var best: int = 99
	for objective in BoardState.OBJECTIVE_POSITIONS:
		if BoardState.objective_scores_for(objective, player_id):
			best = mini(best, BoardState.distance(tile, objective))
	return best

func _best_deploy(state: GameState, deploys: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_key: float = -1000.0
	for action in deploys:
		var card: CardData = _card_of(state, str(action["card_id"]))
		var tile: Vector2i = action["tile"]
		var key: float = card.supply_cost * 10.0 - _goal_distance(state, tile, state.active_player_id)
		if key > best_key:
			best_key = key
			best = action
	return best

func _best_equip(state: GameState, equips: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_key: float = -1.0
	for action in equips:
		var card: CardData = _card_of(state, str(action["card_id"]))
		var unit: UnitState = state.find_unit(str(action["unit_id"]))
		if unit.item_in_slot(card.equip_slot) != null:
			continue
		var key: float = card.bonus_atk * 2.0 + card.bonus_def + card.bonus_rng - (3.0 if unit.is_commander else 0.0)
		if key > best_key:
			best_key = key
			best = action
	return best

func _nearest_enemy_distance(state: GameState, unit: UnitState) -> int:
	var best: int = 99
	for enemy in state.players[1 - unit.owner_id].units:
		if enemy.current_hp > 0:
			best = mini(best, BoardState.distance(unit.position, enemy.position))
	return best

func _useful_tactic(state: GameState, tactics: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_value: float = 0.0
	for action in tactics:
		var card: CardData = _card_of(state, str(action["card_id"]))
		var target: UnitState = state.find_unit(str(action["target_id"]))
		var value: float = 0.0
		var hostile: bool = target.owner_id != state.active_player_id
		match card.tactic_effect:
			"heal":
				var missing: int = target.max_hp() - target.current_hp
				if missing >= 3:
					value = missing * (2.0 if target.is_commander else 1.0)
			"buff":
				var close: int = _nearest_enemy_distance(state, target)
				if hostile:
					# Slowing a unit that is near its goal
					if _goal_distance(state, target.position, target.owner_id) <= target.movement() + 2 and not target.is_commander:
						value = 1.5
				elif card.buff_stat == "attack":
					var can_act: bool = target.deployed_turn < state.turn_number and not target.exhausted
					if can_act and close <= target.movement() + target.attack_range():
						value = 3.0
				elif card.buff_stat == "movement":
					var ready: bool = target.deployed_turn < state.turn_number and not target.exhausted
					var gap: int = _goal_distance(state, target.position, target.owner_id)
					if ready and gap > target.movement() and gap <= target.movement() + card.magnitude:
						value = 2.5
				elif close <= 4 and not _has_mod(target, "defense"):
					value = 2.0 + (2.0 if target.is_commander else 0.0)
			"damage":
				if target.is_commander:
					value = 4.0
				elif target.current_hp <= card.magnitude:
					value = 6.0
			"burn":
				if target.current_hp <= card.magnitude:
					value = 6.0
				elif not target.has_status("burn"):
					value = 3.5 if target.is_commander else 3.0
			"chill":
				if not target.has_status("chill"):
					value = 1.5
					if BoardState.objective_scores_for(target.position, target.owner_id):
						value = 3.5
					elif _goal_distance(state, target.position, target.owner_id) <= target.movement() + 1:
						value = 2.5
			"sow":
				if not target.is_commander and not target.exhausted or target.deployed_turn == state.turn_number:
					value = 1.5
					if BoardState.OBJECTIVE_POSITIONS.has(target.position) or target.current_hp < target.max_hp():
						value = 2.5
		if value > best_value:
			best_value = value
			best = action
	return best

func _has_mod(unit: UnitState, stat: String) -> bool:
	for mod in unit.mods:
		if str(mod["stat"]) == stat:
			return true
	return false

# ---- Command phase ----

func _command_action(state: GameState) -> Dictionary:
	if state.current_activation_unit_id != "":
		return _continue_activation(state)
	var pid: int = state.active_player_id
	var candidates: Array[UnitState] = []
	for unit in state.players[pid].units:
		if GameEngine.activation_error(state, pid, unit) == "":
			candidates.append(unit)
	if candidates.is_empty():
		return {"type": "advance_phase"}
	if difficulty == Difficulty.EASY:
		return _easy_start(state, candidates)
	var best_plan: Dictionary = {}
	var best_score: float = MIN_PLAN_SCORE
	for unit in candidates:
		var unit_plan: Dictionary = _best_plan_for(state, unit)
		if float(unit_plan["score"]) > best_score:
			best_score = float(unit_plan["score"])
			best_plan = unit_plan
	if best_plan.is_empty():
		return {"type": "advance_phase"}
	plan = best_plan
	return {"type": "start_activation", "unit_id": str(best_plan["unit_id"])}

func _easy_start(state: GameState, candidates: Array[UnitState]) -> Dictionary:
	if rng.randf() < 0.15:
		return {"type": "advance_phase"}
	var unit: UnitState = candidates[rng.randi_range(0, candidates.size() - 1)]
	var reachable: Dictionary = MovementResolver.reachable_tiles(state.board, unit)
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in reachable:
		tiles.append(tile)
	var destination: Vector2i = tiles[rng.randi_range(0, tiles.size() - 1)]
	if rng.randf() < 0.6:
		var best_distance: int = 999
		for tile in tiles:
			var distance: int = _nearest_enemy_distance_from(state, unit, tile)
			if distance < best_distance:
				best_distance = distance
				destination = tile
	plan = {"unit_id": unit.instance_id, "destination": destination, "target_id": "", "support": false, "random_target": true}
	return {"type": "start_activation", "unit_id": unit.instance_id}

func _nearest_enemy_distance_from(state: GameState, unit: UnitState, tile: Vector2i) -> int:
	var best: int = 99
	for enemy in state.players[1 - unit.owner_id].units:
		if enemy.current_hp > 0:
			best = mini(best, BoardState.distance(tile, enemy.position))
	return best

func _continue_activation(state: GameState) -> Dictionary:
	var unit: UnitState = state.find_unit(state.current_activation_unit_id)
	if plan.is_empty() or str(plan.get("unit_id", "")) != unit.instance_id:
		plan = {"unit_id": unit.instance_id, "destination": unit.position, "target_id": "", "support": false, "random_target": difficulty == Difficulty.EASY}
	var destination: Vector2i = plan["destination"]
	if not state.current_activation_moved and destination != unit.position:
		if MovementResolver.can_reach(state.board, unit, destination):
			return {"type": "move", "destination": destination}
		plan["destination"] = unit.position
	if bool(plan.get("random_target", false)):
		var targets: Array[UnitState] = []
		for enemy in state.players[1 - unit.owner_id].units:
			if GameEngine.attack_error(state, unit, enemy) == "":
				targets.append(enemy)
		plan["random_target"] = false
		if not targets.is_empty():
			plan["target_id"] = targets[rng.randi_range(0, targets.size() - 1)].instance_id
	var target: UnitState = state.find_unit(str(plan["target_id"])) if str(plan["target_id"]) != "" else null
	if target != null and GameEngine.attack_error(state, unit, target) == "":
		var use_support: bool = bool(plan["support"]) and SupportResolver.find_attack_partner(state, unit, target) != null
		plan["target_id"] = ""
		return {"type": "attack", "target_id": target.instance_id, "support": use_support}
	plan = {}
	return {"type": "wait"}

# ---- Plan scoring ----

func _best_plan_for(state: GameState, unit: UnitState) -> Dictionary:
	var board: BoardState = state.board
	var origin: Vector2i = unit.position
	var base_position: float = _position_score(state, unit, origin)
	var result: Dictionary = {"unit_id": unit.instance_id, "destination": origin, "target_id": "", "support": false, "score": -1000.0}
	var reachable: Dictionary = MovementResolver.reachable_tiles(board, unit)
	var saved_activation: String = state.current_activation_unit_id
	var saved_moved: int = state.activation_moved_tiles
	state.current_activation_unit_id = unit.instance_id
	for tile: Vector2i in reachable:
		state.activation_moved_tiles = BoardState.distance(origin, tile)
		var position_delta: float = _position_score(state, unit, tile) - base_position
		var option: Dictionary = {"unit_id": unit.instance_id, "destination": tile, "target_id": "", "support": false, "score": position_delta}
		if position_delta > float(result["score"]):
			result = option
		unit.position = tile
		for enemy in state.players[1 - unit.owner_id].units:
			if enemy.current_hp <= 0 or not CombatResolver.in_range(unit, enemy):
				continue
			var attack: Dictionary = _score_attack(state, unit, enemy)
			var total: float = position_delta + float(attack["score"])
			if total > float(result["score"]):
				result = {
					"unit_id": unit.instance_id, "destination": tile, "target_id": enemy.instance_id,
					"support": bool(attack["support"]), "score": total,
				}
		unit.position = origin
	state.current_activation_unit_id = saved_activation
	state.activation_moved_tiles = saved_moved
	return result

func _score_attack(state: GameState, unit: UnitState, enemy: UnitState) -> Dictionary:
	var board: BoardState = state.board
	var damage: int = CombatResolver.calculate_damage(board, unit, enemy, state)
	var partner: UnitState = SupportResolver.find_attack_partner(state, unit, enemy)
	var support_damage: int = 0
	if partner != null:
		support_damage = CombatResolver.calculate_damage(board, partner, enemy, state)
	var dealt: int = damage + support_damage
	var score: float = dealt * float(weights["damage"])
	var killed: bool = dealt >= enemy.current_hp
	if not killed and unit.card.on_hit_status != "" and not enemy.has_status(unit.card.on_hit_status):
		score += 2.0 * unit.card.status_turns if unit.card.on_hit_status == "burn" else 2.5
	if killed:
		score += float(weights["kill"])
		if enemy.is_commander:
			score += 1000.0
	elif enemy.is_commander:
		score += dealt * float(weights["commander_hit"])
	if not killed and CombatResolver.in_range(enemy, unit):
		var counter: int = CombatResolver.calculate_damage(board, enemy, unit, state)
		score -= counter * (float(weights["counter_cmd"]) if unit.is_commander else float(weights["counter"]))
		if counter >= unit.current_hp:
			score -= 500.0 if unit.is_commander else float(weights["die"])
		elif CombatResolver.can_follow_up(unit, enemy):
			score += 2.0
			if dealt * 2 >= enemy.current_hp:
				score += 6.0
	return {"score": score, "support": partner != null}

func _position_score(state: GameState, unit: UnitState, tile: Vector2i) -> float:
	var board: BoardState = state.board
	var score: float = board.defense_bonus(tile) * 0.7
	var exposure: int = 0
	for enemy in state.players[1 - unit.owner_id].units:
		if enemy.current_hp > 0 and BoardState.distance(tile, enemy.position) <= enemy.movement() + enemy.attack_range():
			exposure += 1
	if unit.is_commander:
		score -= BoardState.distance(tile, Vector2i(board.deployment_column(unit.owner_id), BoardState.COMMANDER_ROW)) * 1.0
		score -= exposure * 1.5
		return score
	score -= _goal_distance(state, tile, unit.owner_id) * 0.5
	score -= exposure * 0.3
	if BoardState.objective_scores_for(tile, unit.owner_id):
		score += 5.0
	return score

# ---- Hard difficulty: rollout search ----

# Plays each candidate action on a clone, finishes the turn and the opponent's reply with the Normal policy,
# and keeps the candidate whose resulting position scores best. Ties favor the heuristic's own choice.
func _search_action(engine: GameEngine) -> Dictionary:
	var state: GameState = engine.state
	if state.phase == GameState.Phase.SETUP:
		return _heuristic_action(engine)
	if state.phase == GameState.Phase.COMMAND and state.current_activation_unit_id != "":
		plan = _plan_for_active(state)
	var baseline: Dictionary = _heuristic_action(engine)
	var actions: Array[Dictionary] = ActionGenerator.legal_actions(state)
	if actions.size() <= 1:
		return baseline
	var baseline_key: String = str(baseline)
	var candidates: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	for action in actions:
		if str(action) == baseline_key:
			continue
		others.append(action)
	for index in range(others.size() - 1, 0, -1):
		var swap: int = rng.randi_range(0, index)
		var temp: Dictionary = others[index]
		others[index] = others[swap]
		others[swap] = temp
	candidates.append(baseline)
	candidates.append_array(others.slice(0, SEARCH_MAX_CANDIDATES - 1))
	var me: int = state.active_player_id
	var world: GameEngine = engine.clone(me)
	var best: Dictionary = baseline
	var best_value: float = -INF
	for candidate in candidates:
		var copy: GameEngine = world.clone()
		if not bool(copy.submit_action(candidate)["ok"]):
			continue
		var value: float = _rollout_value(copy, me, state.turn_number)
		if str(candidate) == baseline_key:
			value += SEARCH_BASELINE_BONUS
		if value > best_value:
			best_value = value
			best = candidate
	return best

func _rollout_value(copy: GameEngine, me: int, start_turn: int) -> float:
	var policies: Array[AIController] = [
		AIController.new(Difficulty.NORMAL, rng.randi()), AIController.new(Difficulty.NORMAL, rng.randi())
	]
	var state: GameState = copy.state
	if state.phase == GameState.Phase.COMMAND and state.current_activation_unit_id != "":
		policies[state.active_player_id].plan = policies[state.active_player_id]._plan_for_active(state)
	var steps: int = 0
	while state.phase != GameState.Phase.GAME_OVER and steps < SEARCH_MAX_ROLLOUT_STEPS:
		if state.active_player_id == me and state.turn_number > start_turn:
			break
		if not bool(copy.submit_action(policies[state.active_player_id].choose_action(copy))["ok"]):
			break
		steps += 1
	return _evaluate(state, me)

# Plan for a unit that is already mid-activation (it may have moved already).
func _plan_for_active(state: GameState) -> Dictionary:
	var unit: UnitState = state.find_unit(state.current_activation_unit_id)
	if not state.current_activation_moved:
		return _best_plan_for(state, unit)
	var result: Dictionary = {"unit_id": unit.instance_id, "destination": unit.position, "target_id": "", "support": false}
	var best_score: float = MIN_PLAN_SCORE
	for enemy in state.players[1 - unit.owner_id].units:
		if enemy.current_hp > 0 and GameEngine.attack_error(state, unit, enemy) == "":
			var attack: Dictionary = _score_attack(state, unit, enemy)
			if float(attack["score"]) > best_score:
				best_score = float(attack["score"])
				result["target_id"] = enemy.instance_id
				result["support"] = bool(attack["support"])
	return result

# Position value from `me`'s point of view: victory points, objectives, unit strength and cards in hand.
func _evaluate(state: GameState, me: int) -> float:
	if state.phase == GameState.Phase.GAME_OVER:
		if state.winner_id < 0:
			return 0.0
		return 100000.0 if state.winner_id == me else -100000.0
	var score: float = (state.players[me].victory_points - state.players[1 - me].victory_points) * 12.0
	for player in state.players:
		var sign: float = 1.0 if player.player_id == me else -1.0
		score += sign * player.hand.size() * 0.7
		for unit in player.units:
			if unit.current_hp <= 0:
				continue
			if unit.is_commander:
				score += sign * unit.current_hp * 2.5
			else:
				score += sign * (unit.current_hp + 5.0 + unit.card.supply_cost * 1.5)
		for objective in BoardState.OBJECTIVE_POSITIONS:
			var occupant: UnitState = state.board.unit_at(objective)
			if occupant != null and occupant.owner_id == player.player_id and BoardState.objective_scores_for(objective, player.player_id):
				score += sign * 4.0
	return score

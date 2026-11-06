class_name GameEngine
extends RefCounted

const MAX_NORMAL_UNITS: int = 5
const ACTIVATIONS_PER_TURN: int = 2
const MAX_SUPPLY: int = 6
const STARTING_HAND: int = 5
const WIN_POINTS: int = 6

var state: GameState = GameState.new()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# decks: optional per-seat arrays of card ids; missing seats use their starter deck.
func _init(match_seed: int = 0, decks: Array = [], blank: bool = false, armies: Array = [], setup_tiles: int = 0) -> void:
	rng.seed = match_seed if match_seed != 0 else int(Time.get_ticks_usec())
	if not blank:
		_initialize_match(decks, armies, setup_tiles)

# Independent deep copy for lookahead. With `viewer_id` >= 0 the opponent's hidden cards (hand and deck) are
# pooled and redealt randomly, so a search run for `viewer_id` never relies on information that player cannot see.
func clone(viewer_id: int = -1) -> GameEngine:
	var copy := GameEngine.new(0, [], true)
	copy.rng.seed = rng.randi()
	var source: GameState = state
	var target: GameState = copy.state
	target.board.terrain = source.board.terrain.duplicate()
	target.setup_left = source.setup_left.duplicate()
	target.setup_used = [source.setup_used[0].duplicate(), source.setup_used[1].duplicate()]
	target.active_player_id = source.active_player_id
	target.phase = source.phase
	target.turn_number = source.turn_number
	target.winner_id = source.winner_id
	target.game_over_reason = source.game_over_reason
	target.next_instance_number = source.next_instance_number
	target.current_activation_unit_id = source.current_activation_unit_id
	target.current_activation_moved = source.current_activation_moved
	target.activated_unit_ids = source.activated_unit_ids.duplicate()
	target.bonds = source.bonds.duplicate(true)
	target.activation_moved_tiles = source.activation_moved_tiles
	target.chain_count = source.chain_count
	target.seeds = source.seeds.duplicate()
	for old_player in source.players:
		var player := PlayerState.new()
		player.player_id = old_player.player_id
		player.army_id = old_player.army_id
		player.tactics_this_turn = old_player.tactics_this_turn
		player.haste_unit_id = old_player.haste_unit_id
		player.display_name = old_player.display_name
		player.deck = old_player.deck.duplicate()
		player.hand = old_player.hand.duplicate()
		player.discard = old_player.discard.duplicate()
		player.fallen = old_player.fallen.duplicate()
		player.max_supply = old_player.max_supply
		player.current_supply = old_player.current_supply
		player.victory_points = old_player.victory_points
		player.normal_deployments_this_turn = old_player.normal_deployments_this_turn
		for old_unit in old_player.units:
			var unit := UnitState.new()
			unit.instance_id = old_unit.instance_id
			unit.card = old_unit.card
			unit.owner_id = old_unit.owner_id
			unit.position = old_unit.position
			unit.current_hp = old_unit.current_hp
			unit.exhausted = old_unit.exhausted
			unit.deployed_turn = old_unit.deployed_turn
			unit.promotion = old_unit.promotion
			unit.weapon_item = old_unit.weapon_item
			unit.accessory_item = old_unit.accessory_item
			unit.mods = old_unit.mods.duplicate(true)
			unit.statuses = old_unit.statuses.duplicate()
			player.units.append(unit)
			if old_unit == old_player.commander:
				player.commander = unit
			if unit.current_hp > 0:
				target.board.occupants[unit.position] = unit
		if viewer_id >= 0 and player.player_id != viewer_id:
			var hand_size: int = player.hand.size()
			var pool: Array[CardData] = player.hand + player.deck
			copy._shuffle(pool)
			player.hand.assign(pool.slice(0, hand_size))
			player.deck.assign(pool.slice(hand_size))
		target.players.append(player)
	return copy

# ---- Validators (static so the UI and AI can query legality without mutating state) ----

static func deploy_error(game: GameState, player_id: int, card: CardData, tile: Vector2i) -> String:
	if game.phase != GameState.Phase.DEPLOYMENT or game.active_player_id != player_id:
		return "Units can only be deployed during your deployment phase."
	var player: PlayerState = game.players[player_id]
	if card == null or card.card_type != CardData.CardType.UNIT:
		return "Only unit cards can be deployed."
	if player.normal_deployments_this_turn >= 1:
		return "Only one unit may be deployed per turn."
	if player.normal_unit_count() >= MAX_NORMAL_UNITS:
		return "You already control the maximum number of units."
	if player.current_supply < card.supply_cost:
		return "Not enough supply."
	if tile.x != game.board.deployment_column(player_id) or not game.board.is_valid_position(tile):
		return "Deploy into your home column."
	if game.board.occupants.has(tile):
		return "That tile is occupied."
	if game.board.movement_cost(tile, card.movement_type) < 0:
		return "That tile is impassable."
	return ""

static func equip_error(game: GameState, player_id: int, card: CardData, unit: UnitState) -> String:
	if game.phase != GameState.Phase.DEPLOYMENT or game.active_player_id != player_id:
		return "Equipment can only be attached during your deployment phase."
	if card == null or card.card_type != CardData.CardType.EQUIPMENT:
		return "Not an equipment card."
	if unit == null or unit.owner_id != player_id or unit.current_hp <= 0:
		return "Choose one of your units."
	if game.players[player_id].current_supply < card.supply_cost:
		return "Not enough supply."
	if not card.allowed_weapons.is_empty() and not card.allowed_weapons.has(int(unit.weapon_type())):
		return "This unit cannot use that equipment."
	return ""

static func promote_error(game: GameState, player_id: int, card: CardData, unit: UnitState) -> String:
	if game.phase != GameState.Phase.DEPLOYMENT or game.active_player_id != player_id:
		return "Promotions can only be played during your deployment phase."
	if card == null or card.card_type != CardData.CardType.PROMOTION:
		return "Not a promotion card."
	if unit == null or unit.owner_id != player_id or unit.current_hp <= 0:
		return "Choose one of your units."
	if unit.is_commander:
		return "Commanders cannot be promoted."
	if unit.promotion != null:
		return "This unit is already promoted."
	if unit.card.unit_class != card.promotes_from:
		return "This promotion requires a %s." % card.promotes_from
	if unit.deployed_turn > game.turn_number - 2:
		return "The unit must have been deployed on an earlier turn."
	if game.players[player_id].current_supply < card.supply_cost:
		return "Not enough supply."
	return ""

static func tactic_error(game: GameState, player_id: int, card: CardData, target_id: String, destination: Vector2i) -> String:
	if game.active_player_id != player_id:
		return "It is not your turn."
	if game.phase != GameState.Phase.DEPLOYMENT and game.phase != GameState.Phase.COMMAND:
		return "Tactics cannot be played now."
	if game.current_activation_unit_id != "":
		return "Finish the current activation first."
	if card == null or card.card_type != CardData.CardType.TACTIC:
		return "Not a tactic card."
	if game.players[player_id].current_supply < FactionRules.tactic_cost(game, player_id, card):
		return "Not enough supply."
	return AbilityResolver.validate(game, player_id, card, target_id, destination)

static func activation_error(game: GameState, player_id: int, unit: UnitState) -> String:
	if game.phase != GameState.Phase.COMMAND or game.active_player_id != player_id:
		return "Units can only be activated during your command phase."
	if game.current_activation_unit_id != "":
		return "Another unit is already active."
	if game.activated_unit_ids.size() >= ACTIVATIONS_PER_TURN:
		return "No activations remaining."
	if unit == null or unit.owner_id != player_id or unit.current_hp <= 0:
		return "Choose one of your units."
	if unit.exhausted or game.activated_unit_ids.has(unit.instance_id):
		return "That unit has already acted."
	if unit.deployed_turn == game.turn_number and not FactionRules.has_haste(game, unit):
		return "Units cannot act on the turn they are deployed."
	return ""

static func attack_error(game: GameState, attacker: UnitState, target: UnitState) -> String:
	if game.phase != GameState.Phase.COMMAND or attacker == null or game.current_activation_unit_id != attacker.instance_id:
		return "No active unit."
	if target == null or target.current_hp <= 0 or target.owner_id == attacker.owner_id:
		return "Choose an enemy target."
	if not CombatResolver.in_range(attacker, target):
		return "Target is out of range."
	return ""

static func terrain_error(game: GameState, player_id: int, tile: Vector2i, terrain_name: String) -> String:
	if game.phase != GameState.Phase.SETUP or game.active_player_id != player_id:
		return "Terrain can only be placed during your setup turn."
	if game.setup_left[player_id] <= 0:
		return "You have no placements left."
	if not BoardState.PLACEABLE.has(terrain_name):
		return "That terrain cannot be placed."
	if not game.board.is_valid_position(tile):
		return "Invalid tile."
	if game.board.is_locked_tile(tile):
		return "Objectives and deployment columns cannot be changed."
	if game.board.terrain_at(tile) == terrain_name:
		return "That tile is already %s." % terrain_name
	var cap: int = int(BoardState.PLACEMENT_CAPS.get(terrain_name, 99))
	if int(game.setup_used[player_id].get(terrain_name, 0)) >= cap:
		return "You may place at most %d %s." % [cap, terrain_name]
	var layout: Dictionary = game.board.terrain.duplicate()
	layout[tile] = terrain_name
	if not BoardState.objectives_reachable(layout):
		return "That would cut off an objective."
	return ""

# Every legal placement for the active player (used by the UI highlights and the AI).
static func terrain_options(game: GameState, player_id: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for y in range(BoardState.HEIGHT):
		for x in range(BoardState.WIDTH):
			for terrain_name in BoardState.PLACEABLE:
				if terrain_error(game, player_id, Vector2i(x, y), terrain_name) == "":
					options.append({"type": "place_terrain", "tile": Vector2i(x, y), "terrain": terrain_name})
	return options

# ---- Action entry point ----

func submit_action(action: Dictionary) -> Dictionary:
	if state.phase == GameState.Phase.GAME_OVER:
		return _fail("The match is over.")
	var pid: int = state.active_player_id
	var kind: String = str(action.get("type", ""))
	var result: Dictionary
	match kind:
		"deploy":
			result = _deploy(pid, action)
		"equip":
			result = _equip(pid, action)
		"promote":
			result = _promote(pid, action)
		"play_tactic":
			result = _play_tactic(pid, action)
		"start_activation":
			result = _start_activation(pid, action)
		"move":
			result = _move(pid, action)
		"attack":
			result = _attack(pid, action)
		"wait":
			result = _wait(pid)
		"advance_phase":
			result = _advance_phase(pid)
		"place_terrain":
			result = _place_terrain(pid, action)
		"pass_setup":
			result = _pass_setup(pid)
		_:
			return _fail("Unknown action.")
	if bool(result["ok"]):
		state.history.append({"turn": state.turn_number, "player": pid, "action": action.duplicate()})
	return result

func _place_terrain(pid: int, action: Dictionary) -> Dictionary:
	var tile: Vector2i = action.get("tile", Vector2i(-1, -1))
	var terrain_name: String = str(action.get("terrain", ""))
	var error: String = terrain_error(state, pid, tile, terrain_name)
	if error != "":
		return _fail(error)
	state.board.terrain[tile] = terrain_name
	state.setup_left[pid] -= 1
	state.setup_used[pid][terrain_name] = int(state.setup_used[pid].get(terrain_name, 0)) + 1
	state.events.append("%s sets %s at column %d, row %d." % [state.players[pid].display_name, terrain_name, tile.x + 1, tile.y + 1])
	_advance_setup(pid)
	return _ok()

func _pass_setup(pid: int) -> Dictionary:
	if state.phase != GameState.Phase.SETUP or state.active_player_id != pid:
		return _fail("It is not your setup turn.")
	state.setup_left[pid] = 0
	state.events.append("%s finishes their terrain setup." % state.players[pid].display_name)
	_advance_setup(pid)
	return _ok()

# Players alternate; a player with nothing left is skipped. When both are done the match begins.
func _advance_setup(pid: int) -> void:
	if state.setup_left[1 - pid] > 0:
		state.active_player_id = 1 - pid
	elif state.setup_left[pid] <= 0:
		state.active_player_id = 0
		state.turn_number = 1
		_start_turn()

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _ok(extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "error": ""}
	result.merge(extra)
	return result

func _take_from_hand(pid: int, card_id: String) -> CardData:
	var index: int = state.find_card_in_hand(pid, card_id)
	if index < 0:
		return null
	return state.players[pid].hand[index]

func _spend_card(pid: int, card: CardData, cost: int = -1) -> void:
	var player: PlayerState = state.players[pid]
	player.hand.erase(card)
	player.current_supply -= card.supply_cost if cost < 0 else cost

# ---- Deployment-phase actions ----

func _deploy(pid: int, action: Dictionary) -> Dictionary:
	var card: CardData = _take_from_hand(pid, str(action.get("card_id", "")))
	var tile: Vector2i = action.get("tile", Vector2i(-1, -1))
	if card == null:
		return _fail("That card is not in your hand.")
	var error: String = deploy_error(state, pid, card, tile)
	if error != "":
		return _fail(error)
	_spend_card(pid, card)
	var unit := UnitState.new()
	unit.initialize(state.create_instance_id(), card, pid, tile, state.turn_number)
	state.board.place_unit(unit, tile)
	var player: PlayerState = state.players[pid]
	player.units.append(unit)
	player.normal_deployments_this_turn += 1
	if FactionRules.grants_haste(player) and player.haste_unit_id == "":
		player.haste_unit_id = unit.instance_id
	state.events.append("%s deploys %s." % [player.display_name, card.card_name])
	return _ok({"unit_id": unit.instance_id})

func _equip(pid: int, action: Dictionary) -> Dictionary:
	var card: CardData = _take_from_hand(pid, str(action.get("card_id", "")))
	var unit: UnitState = state.find_unit(str(action.get("unit_id", "")))
	var error: String = equip_error(state, pid, card, unit) if card != null else "That card is not in your hand."
	if error != "":
		return _fail(error)
	_spend_card(pid, card)
	var old_item: CardData = unit.item_in_slot(card.equip_slot)
	if old_item != null:
		state.players[pid].discard.append(old_item)
	unit.set_item(card.equip_slot, card)
	unit.current_hp = mini(unit.current_hp, unit.max_hp())
	state.events.append("%s equips %s." % [unit.card.card_name, card.card_name])
	return _ok()

func _promote(pid: int, action: Dictionary) -> Dictionary:
	var card: CardData = _take_from_hand(pid, str(action.get("card_id", "")))
	var unit: UnitState = state.find_unit(str(action.get("unit_id", "")))
	var error: String = promote_error(state, pid, card, unit) if card != null else "That card is not in your hand."
	if error != "":
		return _fail(error)
	_spend_card(pid, card)
	var old_max: int = unit.max_hp()
	unit.promotion = card
	unit.current_hp += unit.max_hp() - old_max
	state.events.append("%s is promoted to %s." % [unit.card.card_name, card.promotes_to])
	return _ok()

func _play_tactic(pid: int, action: Dictionary) -> Dictionary:
	var card: CardData = _take_from_hand(pid, str(action.get("card_id", "")))
	if card == null:
		return _fail("That card is not in your hand.")
	var target_id: String = str(action.get("target_id", ""))
	var destination: Vector2i = action.get("destination", Vector2i(-1, -1))
	var error: String = tactic_error(state, pid, card, target_id, destination)
	if error != "":
		return _fail(error)
	_spend_card(pid, card, FactionRules.tactic_cost(state, pid, card))
	state.players[pid].tactics_this_turn += 1
	state.chain_count += 1
	state.players[pid].discard.append(card)
	var target: UnitState = state.find_unit(target_id)
	state.events.append("%s plays %s on %s." % [state.players[pid].display_name, card.card_name, target.card.card_name])
	var defeated: Array[String] = AbilityResolver.apply(state, card, target_id, destination)
	_handle_defeats(defeated)
	_check_victory()
	return _ok({"defeated": defeated})

# ---- Command-phase actions ----

func _start_activation(pid: int, action: Dictionary) -> Dictionary:
	var unit: UnitState = state.find_unit(str(action.get("unit_id", "")))
	var error: String = activation_error(state, pid, unit)
	if error != "":
		return _fail(error)
	state.current_activation_unit_id = unit.instance_id
	state.current_activation_moved = false
	state.activation_moved_tiles = 0
	state.activated_unit_ids.append(unit.instance_id)
	return _ok()

func _active_unit(pid: int) -> UnitState:
	if state.phase != GameState.Phase.COMMAND or state.current_activation_unit_id == "":
		return null
	var unit: UnitState = state.find_unit(state.current_activation_unit_id)
	if unit == null or unit.owner_id != pid:
		return null
	return unit

func _move(pid: int, action: Dictionary) -> Dictionary:
	var unit: UnitState = _active_unit(pid)
	if unit == null:
		return _fail("No active unit.")
	if state.current_activation_moved:
		return _fail("This unit has already moved.")
	var destination: Vector2i = action.get("destination", Vector2i(-1, -1))
	if not MovementResolver.can_reach(state.board, unit, destination):
		return _fail("That tile is not reachable.")
	var origin: Vector2i = unit.position
	state.board.move_unit(unit, destination)
	state.activation_moved_tiles = BoardState.distance(unit.position, origin)
	state.current_activation_moved = true
	return _ok()

func _attack(pid: int, action: Dictionary) -> Dictionary:
	var attacker: UnitState = _active_unit(pid)
	var target: UnitState = state.find_unit(str(action.get("target_id", "")))
	var error: String = attack_error(state, attacker, target) if attacker != null else "No active unit."
	if error != "":
		return _fail(error)
	var partner: UnitState = null
	if bool(action.get("support", false)):
		partner = SupportResolver.find_attack_partner(state, attacker, target)
		if partner == null:
			return _fail("No support partner is available for this attack.")
		SupportResolver.mark_used(state, attacker, partner)
	var report: Dictionary = CombatResolver.resolve(state.board, attacker, target, state, partner)
	state.events.append("%s attacks %s." % [attacker.card.card_name, target.card.card_name])
	for step: Dictionary in report["steps"]:
		var source: UnitState = state.find_unit(str(step["source"]))
		var victim: UnitState = state.find_unit(str(step["target"]))
		state.events.append("  %s: %s hits %s for %d." % [
			str(step["kind"]), source.card.card_name, victim.card.card_name, int(step["damage"])
		])
	_handle_defeats(report["defeated"])
	_finish_activation(attacker)
	_check_victory()
	return _ok(report)

func _wait(pid: int) -> Dictionary:
	var unit: UnitState = _active_unit(pid)
	if unit == null:
		return _fail("No active unit.")
	_finish_activation(unit)
	return _ok()

func _finish_activation(unit: UnitState) -> void:
	unit.exhausted = true
	state.current_activation_unit_id = ""
	state.current_activation_moved = false
	state.activation_moved_tiles = 0

func _advance_phase(pid: int) -> Dictionary:
	match state.phase:
		GameState.Phase.DEPLOYMENT:
			state.phase = GameState.Phase.COMMAND
			return _ok()
		GameState.Phase.COMMAND:
			var active: UnitState = _active_unit(pid)
			if active != null:
				_finish_activation(active)
			_end_turn()
			return _ok()
	return _fail("Cannot advance now.")

# ---- Defeat, victory, turn flow ----

func _handle_defeats(defeated: Array) -> void:
	for unit_id: String in defeated:
		var unit: UnitState = state.find_unit(unit_id)
		if unit != null:
			_defeat_unit(unit)

func _defeat_unit(unit: UnitState) -> void:
	var owner: PlayerState = state.players[unit.owner_id]
	state.board.remove_unit(unit)
	unit.current_hp = 0
	state.events.append("%s is defeated." % unit.card.card_name)
	if state.current_activation_unit_id == unit.instance_id:
		state.current_activation_unit_id = ""
	if unit.is_commander:
		return
	owner.units.erase(unit)
	owner.fallen.append(unit.card)
	for item in unit.equipment_items():
		owner.discard.append(item)
	if unit.promotion != null:
		owner.discard.append(unit.promotion)
	unit.mods.clear()
	unit.statuses.clear()
	state.seeds.erase(unit.position)
	unit.weapon_item = null
	unit.accessory_item = null
	unit.promotion = null

func _check_victory() -> void:
	var winner: int = VictoryResolver.check_victory(state)
	if winner < 0:
		return
	var loser: PlayerState = state.players[1 - winner]
	var reason: String = "enemy commander defeated" if loser.commander.current_hp <= 0 else "objectives captured"
	VictoryResolver.finish_if_won(state, winner, reason)

func _end_turn() -> void:
	var finished: PlayerState = state.active_player()
	for unit in finished.units:
		unit.expire_mods("end_of_turn")
		unit.exhausted = false
		if unit.has_status("chill"):
			unit.statuses["chill"] = int(unit.statuses["chill"]) - 1
			if int(unit.statuses["chill"]) <= 0:
				unit.statuses.erase("chill")
	state.current_activation_unit_id = ""
	state.activation_moved_tiles = 0
	state.activated_unit_ids.clear()
	state.active_player_id = 1 - state.active_player_id
	state.turn_number += 1
	_start_turn()

func _tick_burn(player: PlayerState) -> void:
	var defeated: Array[String] = []
	for unit in player.units.duplicate():
		if not unit.has_status("burn"):
			continue
		unit.current_hp = maxi(0, unit.current_hp - 1)
		state.events.append("%s burns for 1." % unit.card.card_name)
		unit.statuses["burn"] = int(unit.statuses["burn"]) - 1
		if int(unit.statuses["burn"]) <= 0:
			unit.statuses.erase("burn")
		if unit.current_hp <= 0:
			defeated.append(unit.instance_id)
	_handle_defeats(defeated)
	_check_victory()

func _bloom_seeds(player: PlayerState) -> void:
	for tile: Vector2i in state.seeds.keys():
		if int(state.seeds[tile]) != player.player_id:
			continue
		var occupant: UnitState = state.board.unit_at(tile)
		if occupant == null or occupant.owner_id != player.player_id:
			continue
		state.seeds.erase(tile)
		occupant.current_hp = mini(occupant.max_hp(), occupant.current_hp + FactionRules.BLOOM_HEAL)
		state.chain_count += 1
		state.events.append("A seed blooms under %s." % occupant.card.card_name)

func _start_turn() -> void:
	var player: PlayerState = state.active_player()
	state.phase = GameState.Phase.DEPLOYMENT
	player.normal_deployments_this_turn = 0
	player.tactics_this_turn = 0
	player.haste_unit_id = ""
	state.chain_count = 0
	for unit in player.units:
		unit.expire_mods("until_next_turn")
	player.max_supply = mini(MAX_SUPPLY, player.max_supply + 1)
	player.current_supply = player.max_supply
	var skip_draw: bool = state.turn_number == 1
	if not skip_draw:
		if player.deck.is_empty():
			VictoryResolver.finish_if_won(state, 1 - player.player_id, "opponent deck exhausted")
			return
		player.hand.append(player.deck.pop_back())
	for unit in player.units:
		var tile_terrain: String = state.board.terrain_at(unit.position)
		if tile_terrain == BoardState.FORT and unit.current_hp < unit.max_hp():
			unit.current_hp += 1
		elif tile_terrain == BoardState.FOREST and unit.card.faction == CardCatalog.VERDANT \
				and unit.current_hp < unit.max_hp():
			unit.current_hp = mini(unit.max_hp(), unit.current_hp + FactionRules.FOREST_HEAL)
	_tick_burn(player)
	if state.winner_id >= 0:
		return
	_bloom_seeds(player)
	var held: int = 0
	for objective in BoardState.OBJECTIVE_POSITIONS:
		var occupant: UnitState = state.board.unit_at(objective)
		if occupant != null and occupant.owner_id == player.player_id and not occupant.has_status("chill") \
				and BoardState.objective_scores_for(objective, player.player_id):
			held += 1
	player.victory_points += held
	SupportResolver.process_start_of_turn(state)
	state.events.append("Turn %d: %s begins (supply %d, +%d VP)." % [
		state.turn_number, player.display_name, player.current_supply, held
	])
	_check_victory()

# ---- Setup ----

func _initialize_match(decks: Array, armies: Array = [], setup_tiles: int = 0) -> void:
	for player_id in range(2):
		var player := PlayerState.new()
		player.player_id = player_id
		player.display_name = "Player %d" % (player_id + 1)
		player.army_id = str(armies[player_id]) if armies.size() > player_id and ArmyCatalog.is_army(str(armies[player_id])) \
				else ArmyCatalog.default_army(player_id)
		if decks.size() > player_id and not (decks[player_id] as Array).is_empty():
			player.deck = CardCatalog.deck_from_ids(decks[player_id])
		else:
			player.deck = CardCatalog.make_starter_deck(player_id, player.army_id)
		_shuffle(player.deck)
		for _draw in range(STARTING_HAND):
			if not player.deck.is_empty():
				player.hand.append(player.deck.pop_back())
		_ensure_affordable_start_card(player)
		var commander := UnitState.new()
		commander.initialize(
			state.create_instance_id(), CardCatalog.get_commander(player_id, player.army_id), player_id,
			Vector2i(state.board.deployment_column(player_id), BoardState.COMMANDER_ROW), 0
		)
		state.board.place_unit(commander, commander.position)
		player.commander = commander
		player.units.append(commander)
		state.players.append(player)
	state.active_player_id = 0
	state.turn_number = 1
	if setup_tiles > 0:
		state.phase = GameState.Phase.SETUP
		state.setup_left = [setup_tiles, setup_tiles]
		state.events.append("Terrain setup: each player places up to %d tiles." % setup_tiles)
		return
	_start_turn()

func _shuffle(cards: Array[CardData]) -> void:
	for index in range(cards.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temp: CardData = cards[index]
		cards[index] = cards[swap_index]
		cards[swap_index] = temp

func _ensure_affordable_start_card(player: PlayerState) -> void:
	for card in player.hand:
		if card.card_type == CardData.CardType.UNIT and card.supply_cost <= 1:
			return
	for deck_index in range(player.deck.size()):
		var candidate: CardData = player.deck[deck_index]
		if candidate.card_type == CardData.CardType.UNIT and candidate.supply_cost <= 1:
			var replaced: CardData = player.hand[0]
			player.hand[0] = candidate
			player.deck[deck_index] = replaced
			return

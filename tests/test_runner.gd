extends SceneTree

var failures: int = 0
var checks: int = 0

func _init() -> void:
	_test_collection_and_decks()
	_test_setup_and_turns()
	_test_movement_and_terrain()
	_test_new_terrain()
	_test_visual_effect_events()
	_test_combat()
	_test_equipment()
	_test_tactics()
	_test_promotion()
	_test_support()
	_test_fallen_zone_and_victory()
	_test_invalid_actions()
	_run_extra_tests()
	print("%d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("All tactical TCG tests passed.")
	quit(1 if failures > 0 else 0)

func _run_extra_tests() -> void:
	_test_engine_clone()
	_test_game_state_codec()
	_test_four_player_mode()
	_test_armies()
	_test_setup()
	_test_contested_objectives()
	_test_deck_rules()
	_test_deck_storage()
	_test_deck_filters()
	_test_custom_decks_in_engine()
	_test_action_generator()
	_test_ai_matches()

func _legal_deck() -> Array[String]:
	return DeckData.starter_ids(0)

func _test_deck_rules() -> void:
	var deck: Array[String] = _legal_deck()
	_expect(DeckData.validate(deck).is_empty(), "starter deck is legal")
	_expect(DeckData.validate(DeckData.starter_ids(1)).is_empty(), "second starter deck is legal")
	_expect(DeckData.warnings(deck).is_empty(), "starter deck follows the recommended 22/10/8 mix")
	var short: Array[String] = deck.duplicate()
	short.pop_back()
	_expect(not DeckData.validate(short).is_empty(), "39-card deck is illegal")
	var heavy: Array[String] = deck.duplicate()
	heavy.erase("heal")
	heavy.erase("heal")
	heavy.erase("heal")
	for _i in range(3):
		heavy.append("fortify")
	_expect(not DeckData.validate(heavy).is_empty(), "more than 3 copies is illegal")
	var unknown: Array[String] = deck.duplicate()
	unknown[0] = "no_such_card"
	_expect(not DeckData.validate(unknown).is_empty(), "unknown card ids are illegal")
	var skewed: Array[String] = deck.duplicate()
	for index in range(skewed.size()):
		if CardCatalog.get_card(skewed[index]).card_type == CardData.CardType.EQUIPMENT:
			skewed[index] = "rally"
	_expect(DeckData.warnings(deck).is_empty() and not DeckData.warnings(skewed).is_empty(), "unusual composition gives advice only")

func _test_deck_storage() -> void:
	var dir: String = "user://test_decks"
	var deck: Array[String] = _legal_deck()
	_expect(DeckData.save_deck("Test Deck", deck, dir) == OK, "deck saves to JSON")
	_expect(DeckData.list_decks(dir).has("Test Deck"), "saved deck is listed")
	var loaded: Dictionary = DeckData.load_deck("Test Deck", dir)
	var ids: Array[String] = []
	ids.assign(loaded["cards"])
	_expect(DeckData.count_ids(ids) == DeckData.count_ids(deck), "deck reloads with the same cards")
	var text: String = FileAccess.get_file_as_string(dir + "/Test Deck.json")
	_expect(text.contains("iron_guard") and not text.contains("max_hp"), "deck file stores card ids only")
	_expect(DeckData.resolve("Test Deck", 1, dir) == ids, "a saved deck can be chosen for a seat")
	_expect(DeckData.resolve("Missing", 1, dir) == DeckData.starter_ids(1), "missing deck falls back to the starter deck")
	_expect(DeckData.from_json("not json").is_empty() and DeckData.from_json("{\"cards\": 5}").is_empty(), "malformed deck files are rejected")
	_expect(DeckData.save_deck("   ", deck, dir) != OK, "empty deck names are rejected")
	DeckData.save_deck("Short", ["iron_guard"], dir)
	_expect(DeckData.resolve("Short", 0, dir) == DeckData.starter_ids(0), "illegal saved deck falls back to the starter deck")
	_expect(DeckData.delete_deck("Test Deck", dir) == OK and DeckData.delete_deck("Short", dir) == OK, "decks can be deleted")
	_expect(not DeckData.list_decks(dir).has("Test Deck"), "deleted deck is no longer listed")

func _test_deck_filters() -> void:
	var all_cards: Array[CardData] = CardCatalog.get_all_cards()
	_expect(DeckData.filter_cards(all_cards, "All", "All", "All", "").size() == all_cards.size(), "no filters shows every card")
	_expect(DeckData.filter_cards(all_cards, "Tactic", "All", "All", "").size() == 13, "category filter shows 13 tactics")
	_expect(DeckData.filter_cards(all_cards, "Unit", "All", "Bow", "").size() == 4, "weapon filter finds the four bow units")
	var mages: Array[CardData] = DeckData.filter_cards(all_cards, "All", "Mage", "All", "")
	_expect(mages.size() == 5, "class filter finds mages and their promotion")
	_expect(DeckData.filter_cards(all_cards, "All", "All", "All", "RING").size() == 1, "search is case-insensitive")
	_expect(DeckData.filter_cards(all_cards, "Equipment", "All", "Axe", "").size() == 1, "weapon filter covers equipment")

func _test_custom_decks_in_engine() -> void:
	var custom: Array[String] = []
	for card_id: String in ["iron_guard", "iron_guard", "iron_guard"]:
		custom.append(card_id)
	for _i in range(37):
		custom.append("heal" if _i % 2 == 0 else "rally")
	var engine := GameEngine.new(5, [custom, []])
	_expect(engine.state.players[0].hand.size() == 5, "custom deck draws an opening hand")
	_expect(engine.state.players[0].deck.size() == 35, "custom deck supplies the remaining cards")
	_expect(engine.state.players[1].deck.size() + engine.state.players[1].hand.size() == 40, "empty seat uses its starter deck")

func _test_action_generator() -> void:
	var engine := _new_engine()
	var actions: Array[Dictionary] = ActionGenerator.legal_actions(engine.state)
	var types: Dictionary = {}
	var all_home: bool = true
	for action in actions:
		types[str(action["type"])] = true
		if str(action["type"]) == "deploy" and Vector2i(action["tile"]).x != 0:
			all_home = false
	_expect(types.has("deploy") and types.has("advance_phase"), "generator offers deployment and ending the phase")
	_expect(all_home and not types.has("move") and not types.has("attack"), "generator offers only phase-legal actions")
	var unit := _spawn(engine, "oakblade", 0, Vector2i(1, 3))
	_command_phase(engine)
	var command_actions: Array[Dictionary] = ActionGenerator.legal_actions(engine.state)
	var activations: int = 0
	for action in command_actions:
		if str(action["type"]) == "start_activation":
			activations += 1
	_expect(activations == 2, "generator offers every ready unit for activation")
	_act(engine, {"type": "start_activation", "unit_id": unit.instance_id})
	var accepted: bool = true
	for action in ActionGenerator.legal_actions(engine.state):
		if str(action["type"]) == "move" and not MovementResolver.can_reach(engine.state.board, unit, action["destination"]):
			accepted = false
	_expect(accepted, "generated moves are reachable")

func _play_ai_match(match_seed: int, first: AIController.Difficulty, second: AIController.Difficulty) -> Dictionary:
	var engine := _new_engine(match_seed)
	var controllers: Array[AIController] = [AIController.new(first, match_seed + 1), AIController.new(second, match_seed + 2)]
	var failed: int = 0
	var steps: int = 0
	while engine.state.phase != GameState.Phase.GAME_OVER and engine.state.turn_number < 150 and steps < 20000:
		var action: Dictionary = controllers[engine.state.active_player_id].choose_action(engine)
		if not bool(engine.submit_action(action)["ok"]):
			failed += 1
			print("  rejected AI action: %s" % str(action))
			break
		steps += 1
	return {"failed": failed, "winner": engine.state.winner_id, "turns": engine.state.turn_number, "history": engine.state.history.size(), "over": engine.state.phase == GameState.Phase.GAME_OVER}

func _test_ai_matches() -> void:
	var normal: AIController.Difficulty = AIController.Difficulty.NORMAL
	var easy: AIController.Difficulty = AIController.Difficulty.EASY
	var decisive: int = 0
	for match_seed in [11, 12, 13]:
		var result: Dictionary = _play_ai_match(match_seed, normal, normal)
		_expect(int(result["failed"]) == 0, "normal AI vs normal AI seed %d submits only valid actions" % match_seed)
		print("  seed %d: winner %d after %d turns" % [match_seed, int(result["winner"]), int(result["turns"])])
		if bool(result["over"]):
			decisive += 1
	_expect(decisive >= 2, "normal AI matches reach a conclusion")
	var easy_result: Dictionary = _play_ai_match(21, easy, easy)
	_expect(int(easy_result["failed"]) == 0 and bool(easy_result["over"]), "easy AI plays a full valid match")
	var first: Dictionary = _play_ai_match(31, normal, easy)
	var second: Dictionary = _play_ai_match(31, normal, easy)
	_expect(first["history"] == second["history"] and first["winner"] == second["winner"], "AI matches are deterministic for a seed")
	var mixed_wins: int = 0
	for match_seed in [41, 42, 43, 44]:
		var mixed: Dictionary = _play_ai_match(match_seed, normal, easy)
		_expect(int(mixed["failed"]) == 0, "normal vs easy seed %d is valid" % match_seed)
		if int(mixed["winner"]) == 0:
			mixed_wins += 1
	print("  normal AI won %d of 4 against easy" % mixed_wins)
	var hard_result: Dictionary = _play_ai_match(51, AIController.Difficulty.HARD, normal)
	_expect(int(hard_result["failed"]) == 0 and bool(hard_result["over"]), "hard AI plays a full valid match")
	var hard_a: Dictionary = _play_ai_match(52, normal, AIController.Difficulty.HARD)
	var hard_b: Dictionary = _play_ai_match(52, normal, AIController.Difficulty.HARD)
	_expect(hard_a["history"] == hard_b["history"], "hard AI matches are deterministic for a seed")

func _test_engine_clone() -> void:
	var engine := GameEngine.new(77)
	var controllers: Array[AIController] = [AIController.new(AIController.Difficulty.NORMAL, 1), AIController.new(AIController.Difficulty.NORMAL, 2)]
	for _step in range(60):
		engine.submit_action(controllers[engine.state.active_player_id].choose_action(engine))
	var copy: GameEngine = engine.clone()
	_expect(_fingerprint(copy) == _fingerprint(engine), "clone matches the original state")
	var before: String = _fingerprint(engine)
	for _step in range(40):
		copy.submit_action(controllers[copy.state.active_player_id].choose_action(copy))
	_expect(_fingerprint(engine) == before, "playing on a clone never changes the original")
	_expect(_fingerprint(copy) != before, "the clone advances independently")
	var hidden: GameEngine = engine.clone(0)
	var opponent: PlayerState = hidden.state.players[1]
	var real: PlayerState = engine.state.players[1]
	_expect(opponent.hand.size() == real.hand.size() and opponent.deck.size() == real.deck.size(), "hidden-information clone keeps hand and deck sizes")
	_expect(hidden.state.players[0].hand == engine.state.players[0].hand, "hidden-information clone keeps the viewer's own hand")

func _test_game_state_codec() -> void:
	var engine := GameEngine.new(89)
	var snapshot: Dictionary = GameStateCodec.encode(engine.state, 0)
	var opponent_data: Dictionary = snapshot["players"][1]
	_expect(not opponent_data.has("hand_card_ids") and not opponent_data.has("deck_card_ids"), "state snapshots omit the other player's hidden card identities")
	_expect(int(opponent_data["hand_count"]) == engine.state.players[1].hand.size(), "state snapshots preserve the other player's hand size")
	var decoded_result: Dictionary = GameStateCodec.decode(snapshot)
	_expect(bool(decoded_result["ok"]), "a filtered game-state snapshot decodes")
	if bool(decoded_result["ok"]):
		var decoded: GameState = decoded_result["state"]
		var own_hand_matches: bool = decoded.players[0].hand.size() == engine.state.players[0].hand.size()
		for index in range(mini(decoded.players[0].hand.size(), engine.state.players[0].hand.size())):
			if decoded.players[0].hand[index].card_id != engine.state.players[0].hand[index].card_id:
				own_hand_matches = false
		_expect(own_hand_matches, "decoded state preserves the viewing player's hand")
		_expect(decoded.players[1].hand.size() == engine.state.players[1].hand.size(), "decoded state preserves the opponent's hidden hand size")
		var opponent_hand_hidden: bool = true
		for card: CardData in decoded.players[1].hand:
			if card.card_id != GameStateCodec.HIDDEN_CARD_ID:
				opponent_hand_hidden = false
		_expect(opponent_hand_hidden, "decoded opponent hand contains no card identities")
		_expect(decoded.board.terrain == engine.state.board.terrain, "decoded state preserves board terrain")
		_expect(decoded.players[0].commander.current_hp == engine.state.players[0].commander.current_hp, "decoded state reconnects commander references")
	var invalid_snapshot: Dictionary = snapshot.duplicate(true)
	invalid_snapshot["version"] = GameStateCodec.VERSION + 1
	_expect(not bool(GameStateCodec.decode(invalid_snapshot)["ok"]), "unsupported game-state snapshots are rejected")
	var leaking_snapshot: Dictionary = snapshot.duplicate(true)
	leaking_snapshot["players"][1]["hand_card_ids"] = ["heal"]
	_expect(not bool(GameStateCodec.decode(leaking_snapshot)["ok"]), "state decoder rejects leaked opponent card identities")

func _test_four_player_mode() -> void:
	var duel := GameEngine.new(31)
	var game := GameEngine.new(32, [], false, [], 0, 4)
	var state: GameState = game.state
	_expect(state.players.size() == 4 and state.board.width == 9 and state.board.height == 9, "four-player game has four seats and a 9x9 board")
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(8, 0), Vector2i(8, 8), Vector2i(0, 8)]
	for player_id in range(4):
		var player: PlayerState = state.players[player_id]
		_expect(player.commander.position == corners[player_id], "four-player commander %d starts in its corner" % player_id)
		_expect(state.board.is_deployment_tile(player_id, corners[player_id]) and not state.board.is_deployment_tile((player_id + 1) % 4, corners[player_id]), "four-player deployment zones do not overlap")
	_end_turn(game)
	_expect(state.active_player_id == 1 and state.players[1].hand.size() == 5, "second player starts without an extra draw")
	_end_turn(game)
	_end_turn(game)
	_end_turn(game)
	_expect(state.active_player_id == 0 and state.players[0].hand.size() == 6, "turn order wraps and first player draws on their second turn")
	_expect(duel.state.board.width == 7 and duel.state.board.commander_position(1) == Vector2i(6, 3), "four-player board does not change a concurrent duel")
	for viewer in range(4):
		var snapshot: Dictionary = GameStateCodec.encode(state, viewer)
		var privacy_ok: bool = true
		for other in range(4):
			if other != viewer and (snapshot["players"][other].has("hand_card_ids") or snapshot["players"][other].has("deck_card_ids")):
				privacy_ok = false
		var decoded: Dictionary = GameStateCodec.decode(snapshot)
		_expect(privacy_ok and bool(decoded["ok"]), "four-player snapshot hides every opponent and decodes for seat %d" % viewer)
		if bool(decoded["ok"]):
			_expect((decoded["state"] as GameState).board.width == 9 and duel.state.board.width == 7, "four-player snapshot preserves independent board dimensions")

	var battle := GameEngine.new(33, [], false, [], 0, 4)
	var attacker := _spawn(battle, "swiftblade", 0, Vector2i(7, 8))
	attacker.mods.append({"stat": "attack", "amount": 20, "expires": "end_of_turn"})
	var eliminated_unit := _spawn(battle, "iron_guard", 2, Vector2i(6, 7))
	battle.state.seeds[Vector2i(5, 7)] = 2
	battle.state.players[2].commander.current_hp = 1
	_command_phase(battle, 0)
	_act(battle, {"type": "start_activation", "unit_id": attacker.instance_id})
	var attack: Dictionary = {"type": "attack", "target_id": battle.state.players[2].commander.instance_id, "support": false}
	_expect(ActionGenerator.legal_actions(battle.state).has(attack), "online action generation includes attacks against the third player")
	_expect(bool(_act(battle, attack)["ok"]), "can attack any opposing commander")
	_expect(battle.state.players[2].eliminated and battle.state.phase != GameState.Phase.GAME_OVER, "commander defeat eliminates one player without ending a four-player match")
	_expect(battle.state.board.unit_at(eliminated_unit.position) == null and not battle.state.seeds.has(Vector2i(5, 7)), "elimination removes units and seeds")
	battle.state.active_player_id = 1
	battle.state.phase = GameState.Phase.COMMAND
	_end_turn(battle)
	_expect(battle.state.active_player_id == 3, "turn order skips eliminated players")
	var copy: GameEngine = battle.clone()
	_expect(copy.state.players[2].eliminated and copy.state.board.width == 9, "clone preserves four-player elimination and board")
	_expect(bool(GameStateCodec.decode(GameStateCodec.encode(battle.state, 3))["ok"]), "eliminated-player state round-trips through snapshots")

	var exhausted := GameEngine.new(34, [], false, [], 0, 4)
	exhausted.state.players[1].turns_started = 1
	exhausted.state.players[1].deck.clear()
	exhausted.state.phase = GameState.Phase.COMMAND
	_end_turn(exhausted)
	_expect(exhausted.state.players[1].eliminated and exhausted.state.active_player_id == 2, "deck exhaustion eliminates a player and starts the next turn")
	exhausted._eliminate_player(exhausted.state.players[2])
	exhausted._eliminate_player(exhausted.state.players[3])
	exhausted._check_victory()
	_expect(exhausted.state.winner_id == 0 and exhausted.state.game_over_reason == "last player standing", "last remaining player wins")

	var burning := GameEngine.new(37, [], false, [], 0, 4)
	burning.state.players[1].commander.current_hp = 1
	burning.state.players[1].commander.apply_status("burn", 1)
	burning.state.phase = GameState.Phase.COMMAND
	_end_turn(burning)
	_expect(burning.state.players[1].eliminated and burning.state.active_player_id == 2, "commander burn eliminates the active player and advances the turn")

	var scoring := GameEngine.new(35, [], false, [], 0, 4)
	_spawn(scoring, "iron_guard", 1, scoring.state.board.objective_positions[0])
	scoring.state.players[1].victory_points = 5
	_end_turn(scoring)
	_expect(scoring.state.winner_id == 1 and scoring.state.game_over_reason == "objectives captured", "six objective points win the four-player game")

	var setup := GameEngine.new(36, [], false, [], 1, 4)
	for player_id in range(4):
		_expect(setup.state.active_player_id == player_id and bool(_act(setup, {"type": "pass_setup"})["ok"]), "terrain setup advances through four players")
	_expect(setup.state.phase == GameState.Phase.DEPLOYMENT and setup.state.active_player_id == 0, "four-player game starts after terrain setup")

func _fingerprint(engine: GameEngine) -> String:
	var parts: PackedStringArray = []
	parts.append("%d %d %d %d" % [engine.state.turn_number, engine.state.active_player_id, engine.state.phase, engine.state.current_activation_unit_id.length()])
	for player in engine.state.players:
		parts.append("%d %d %d %d %d %d" % [player.current_supply, player.victory_points, player.deck.size(), player.hand.size(), player.discard.size(), player.fallen.size()])
		for unit in player.units:
			parts.append("%s %s %d %s %d" % [unit.instance_id, unit.position, unit.current_hp, unit.exhausted, unit.mods.size()])
	return "|".join(parts)

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		print("FAIL: %s" % label)

# ---- Helpers ----

func _new_engine(match_seed: int = 7) -> GameEngine:
	return GameEngine.new(match_seed)

func _spawn(engine: GameEngine, card_id: String, player_id: int, tile: Vector2i) -> UnitState:
	var unit := UnitState.new()
	unit.initialize(engine.state.create_instance_id(), CardCatalog.get_card(card_id), player_id, tile, 1)
	engine.state.board.place_unit(unit, tile)
	engine.state.players[player_id].units.append(unit)
	return unit

func _command_phase(engine: GameEngine, player_id: int = 0) -> void:
	engine.state.active_player_id = player_id
	engine.state.phase = GameState.Phase.COMMAND
	engine.state.turn_number = 5
	engine.state.activated_unit_ids.clear()

func _give(engine: GameEngine, player_id: int, card_ids: Array, supply: int = 6) -> void:
	var cards: Array[CardData] = []
	for card_id: String in card_ids:
		cards.append(CardCatalog.get_card(card_id))
	engine.state.players[player_id].hand = cards
	engine.state.players[player_id].current_supply = supply

func _act(engine: GameEngine, action: Dictionary) -> Dictionary:
	return engine.submit_action(action)

func _end_turn(engine: GameEngine) -> void:
	if engine.state.phase == GameState.Phase.DEPLOYMENT:
		engine.submit_action({"type": "advance_phase"})
	engine.submit_action({"type": "advance_phase"})

func _duel(engine: GameEngine, attacker: UnitState, defender: UnitState) -> Dictionary:
	_command_phase(engine, attacker.owner_id)
	_act(engine, {"type": "start_activation", "unit_id": attacker.instance_id})
	return _act(engine, {"type": "attack", "target_id": defender.instance_id})

# ---- Tests ----

func _plain(engine: GameEngine, tiles: Array[Vector2i]) -> void:
	for tile in tiles:
		engine.state.board.terrain[tile] = BoardState.PLAIN

func _test_setup() -> void:
	var engine := GameEngine.new(5, [], false, ["ironcrest", "ashen"], 2)
	var s: GameState = engine.state
	_expect(s.phase == GameState.Phase.SETUP and s.active_player_id == 0 and s.setup_left == [2, 2], "setup phase starts with placements")
	_expect(not bool(_act(engine, {"type": "advance_phase"})["ok"]), "setup rejects other actions")
	var locked := Vector2i(0, 2)
	_expect(not bool(_act(engine, {"type": "place_terrain", "tile": locked, "terrain": "forest"})["ok"]), "deployment column is locked")
	_expect(not bool(_act(engine, {"type": "place_terrain", "tile": BoardState.OBJECTIVE_POSITIONS[0], "terrain": "forest"})["ok"]), "objectives are locked")
	var wall: Dictionary = {}
	for y in range(BoardState.HEIGHT):
		wall[Vector2i(3, y)] = BoardState.MOUNTAIN
	_expect(not BoardState.objectives_reachable(wall), "a mountain wall fails the reachability check")
	var options: Array[Dictionary] = GameEngine.terrain_options(s, 0)
	_expect(not options.is_empty(), "terrain options exist")
	var generated_setup_actions: Array[Dictionary] = ActionGenerator.legal_actions(s)
	var has_setup_actions: bool = false
	var has_invalid_advance: bool = false
	for action: Dictionary in generated_setup_actions:
		if action["type"] == "place_terrain" or action["type"] == "pass_setup":
			has_setup_actions = true
		if action["type"] == "advance_phase":
			has_invalid_advance = true
	_expect(has_setup_actions and not has_invalid_advance, "action generator exposes terrain setup actions only")
	var first: Dictionary = options[0]
	_expect(bool(_act(engine, first)["ok"]), "legal placement accepted")
	_expect(s.active_player_id == 1 and s.setup_left[0] == 1, "placement alternates players")
	_act(engine, {"type": "pass_setup"})
	_expect(s.active_player_id == 0 and s.setup_left[1] == 0, "a finished player is skipped")
	_act(engine, {"type": "pass_setup"})
	_expect(s.phase == GameState.Phase.DEPLOYMENT and s.turn_number == 1 and s.active_player_id == 0, "match starts after setup")
	var copy: GameEngine = engine.clone()
	_expect(copy.state.board.terrain == s.board.terrain, "clone copies terrain")
	copy.state.board.terrain[Vector2i(3, 0)] = BoardState.MOUNTAIN
	_expect(s.board.terrain.get(Vector2i(3, 0)) != BoardState.MOUNTAIN, "clone terrain is independent")
	for seed_value in range(1, 6):
		var game := GameEngine.new(seed_value, [], false, ["verdant", "ironcrest"], 3)
		var ai := AIController.new(AIController.Difficulty.NORMAL, seed_value)
		var guard: int = 0
		while game.state.phase == GameState.Phase.SETUP and guard < 20:
			_expect(bool(game.submit_action(ai.choose_action(game))["ok"]), "AI setup action is legal")
			guard += 1
		_expect(game.state.phase == GameState.Phase.DEPLOYMENT and BoardState.objectives_reachable(game.state.board.terrain), "AI setup ends with a reachable map")

func _test_contested_objectives() -> void:
	BoardState.configure(7, 7, "contested")
	var engine := GameEngine.new(9)
	var home_one: Vector2i = BoardState.OBJECTIVE_POSITIONS[0]
	var home_two: Vector2i = BoardState.OBJECTIVE_POSITIONS[2]
	_expect(not BoardState.objective_scores_for(home_one, 0) and BoardState.objective_scores_for(home_one, 1), "home objective is denied to its own side only")
	_expect(BoardState.objective_scores_for(BoardState.OBJECTIVE_POSITIONS[1], 0) and BoardState.objective_scores_for(BoardState.OBJECTIVE_POSITIONS[1], 1), "centre objective scores for both")
	_spawn(engine, "ash_reaver", 0, home_one)
	_spawn(engine, "ash_reaver", 1, home_two)
	engine.state.players[0].victory_points = 0
	engine.state.players[1].victory_points = 0
	_end_turn(engine)
	_end_turn(engine)
	_expect(engine.state.players[0].victory_points == 0 and engine.state.players[1].victory_points == 0, "holding your own side's objective earns nothing")
	var other := GameEngine.new(9)
	_spawn(other, "ash_reaver", 1, home_one)
	_end_turn(other)
	_end_turn(other)
	_expect(other.state.players[1].victory_points >= 1, "holding the enemy-side objective scores")
	BoardState.configure(7, 7, "column")

func _test_armies() -> void:
	# Starter decks and the deck faction rule
	for army_id in ArmyCatalog.ARMY_IDS:
		var ids: Array[String] = DeckData.starter_ids(0, army_id)
		_expect(ids.size() == 40 and DeckData.validate(ids).is_empty(), "%s starter deck is legal" % army_id)
		_expect(DeckData.army_of(ids) == army_id and DeckData.warnings(ids).is_empty(), "%s deck belongs to its army" % army_id)
	var mixed: Array[String] = DeckData.starter_ids(0, ArmyCatalog.IRONCREST_ID)
	mixed[0] = "ash_reaver"
	_expect(not DeckData.validate(mixed).is_empty(), "a deck cannot mix two armies' units")

	var engine := GameEngine.new(3, [], false, ["verdant", "ashen"])
	_expect(engine.state.players[0].army_id == "verdant" and engine.state.players[0].commander.card.faction == CardCatalog.VERDANT, "army choice sets commander and passive")

	# Momentum
	var reaver := _spawn(engine, "ash_reaver", 1, Vector2i(5, 1))
	var target := _spawn(engine, "bramble_warden", 0, Vector2i(2, 1))
	_plain(engine, [Vector2i(5, 1), Vector2i(4, 1), Vector2i(3, 1), Vector2i(2, 1)])
	_command_phase(engine, 1)
	_act(engine, {"type": "start_activation", "unit_id": reaver.instance_id})
	var base_attack: int = CombatResolver.attack_value(reaver, target, engine.state)
	_act(engine, {"type": "move", "destination": Vector2i(3, 1)})
	_expect(engine.state.activation_moved_tiles == 2 and CombatResolver.attack_value(reaver, target, engine.state) == base_attack + 1, "Momentum gives +1 ATK after moving 2 tiles")

	# Shield Wall and Maren's objective bonus
	engine = _new_engine()
	var guard := _spawn(engine, "iron_guard", 0, Vector2i(5, 5))
	_plain(engine, [Vector2i(5, 5), Vector2i(5, 4), Vector2i(1, 5)])
	_expect(FactionRules.defense_bonus(engine.state, guard) == 0, "a lone Ironcrest unit has no Shield Wall")
	_spawn(engine, "oakblade", 0, Vector2i(5, 4))
	_expect(FactionRules.defense_bonus(engine.state, guard) == 1, "Shield Wall gives +1 DEF beside an ally")
	var objective: Vector2i = BoardState.OBJECTIVE_POSITIONS[0]
	engine.state.board.move_unit(guard, objective)
	_expect(FactionRules.defense_bonus(engine.state, guard) == 1, "Ironcrest units on an objective gain +1 DEF")

	# Burn: ticks at the start of its owner's turn and counts down
	engine = _new_engine()
	var scout := _spawn(engine, "cinder_scout", 1, Vector2i(4, 1))
	var victim := _spawn(engine, "iron_guard", 0, Vector2i(2, 1))
	_plain(engine, [Vector2i(4, 1), Vector2i(2, 1)])
	var hp_before: int = victim.current_hp
	var hit: Dictionary = _duel(engine, scout, victim)
	var dealt: int = hp_before - victim.current_hp
	_expect(hit["ok"] and victim.has_status("burn"), "a Cinder Scout hit applies Burn")
	_end_turn(engine)
	_expect(victim.current_hp == hp_before - dealt - 1, "Burn deals 1 damage at its owner's turn start")
	_end_turn(engine)
	_end_turn(engine)
	_expect(not victim.has_status("burn") and victim.current_hp == hp_before - dealt - 2, "Burn wears off after two ticks")
	victim.current_hp = 1
	victim.apply_status("burn", 2)
	_end_turn(engine)
	_end_turn(engine)
	_expect(victim.current_hp <= 0 and engine.state.players[0].fallen.size() == 1, "Burn can defeat a unit")

	# Chill: -1 MOV through the victim's turn, no objective control
	engine = _new_engine()
	var swift := _spawn(engine, "swiftblade", 1, Vector2i(5, 2))
	_command_phase(engine, 0)
	_give(engine, 0, ["frostbind"])
	_expect(_act(engine, {"type": "play_tactic", "card_id": "frostbind", "target_id": swift.instance_id})["ok"], "Frostbind targets an enemy")
	_expect(swift.movement() == swift.card.movement - 1, "Chill reduces MOV by 1")
	_end_turn(engine)
	_expect(swift.has_status("chill"), "Chill lasts through the victim's turn")
	_end_turn(engine)
	_expect(not swift.has_status("chill"), "Chill expires at the end of the victim's turn")

	# Ashen commander: first deployed unit acts immediately
	engine = _new_engine()
	engine.state.active_player_id = 1
	engine.state.phase = GameState.Phase.DEPLOYMENT
	engine.state.turn_number = 5
	engine.state.players[1].normal_deployments_this_turn = 0
	_give(engine, 1, ["ash_reaver"])
	var column: int = engine.state.board.deployment_column(1)
	_expect(_act(engine, {"type": "deploy", "card_id": "ash_reaver", "tile": Vector2i(column, 1)})["ok"], "Ashen deploys a unit")
	_act(engine, {"type": "advance_phase"})
	var fresh: UnitState = engine.state.board.unit_at(Vector2i(column, 1))
	_expect(GameEngine.activation_error(engine.state, 1, fresh) == "", "Tarek lets the first deployed unit act immediately")

	# Verdant: discounted first tactic, Chain, Seeds, Forest
	engine = GameEngine.new(4, [], false, ["verdant", "verdant"])
	var warden := _spawn(engine, "bramble_warden", 0, Vector2i(2, 2))
	_plain(engine, [Vector2i(2, 2), Vector2i(4, 2)])
	engine.state.board.terrain[Vector2i(3, 2)] = BoardState.FOREST
	_expect(MovementResolver.can_reach(engine.state.board, warden, Vector2i(4, 2)), "Verdant units cross Forest at normal cost")
	var ash := _spawn(engine, "ash_reaver", 1, Vector2i(2, 4))
	engine.state.board.terrain[Vector2i(3, 4)] = BoardState.FOREST
	_plain(engine, [Vector2i(4, 4)])
	_expect(not MovementResolver.can_reach(engine.state.board, ash, Vector2i(4, 4)), "other armies still pay double for Forest")
	_command_phase(engine, 0)
	_give(engine, 0, ["sow", "sow"], 3)
	_expect(_act(engine, {"type": "play_tactic", "card_id": "sow", "target_id": warden.instance_id})["ok"], "Sow plants a seed")
	_expect(engine.state.players[0].current_supply == 3 and engine.state.chain_count == 1, "first tactic is discounted and builds Chain")
	_expect(not _act(engine, {"type": "play_tactic", "card_id": "sow", "target_id": warden.instance_id})["ok"], "cannot sow twice on one tile")
	_expect(FactionRules.attack_bonus(engine.state, warden) == 1, "Chain grants +1 ATK")
	warden.current_hp = 3
	var clone: GameEngine = engine.clone()
	_expect(clone.state.seeds.has(Vector2i(2, 2)) and clone.state.chain_count == 1, "clone copies seeds and chain")
	_end_turn(engine)
	_end_turn(engine)
	_expect(warden.current_hp == 5 and engine.state.seeds.is_empty() and engine.state.chain_count == 1, "a seed blooms: heal 2, +1 Chain, seed consumed")

func _test_collection_and_decks() -> void:
	var all_cards: Array[CardData] = CardCatalog.get_all_cards()
	_expect(all_cards.size() + 3 == 46, "collection has 46 cards including commanders")
	for player_id in range(2):
		var deck: Array[CardData] = CardCatalog.make_starter_deck(player_id)
		var counts: Dictionary = {}
		var types: Dictionary = {}
		for card in deck:
			counts[card.card_id] = int(counts.get(card.card_id, 0)) + 1
			types[card.card_type] = int(types.get(card.card_type, 0)) + 1
		var max_copies: int = 0
		for count: int in counts.values():
			max_copies = maxi(max_copies, count)
		_expect(deck.size() == 40, "player %d deck has 40 cards" % (player_id + 1))
		_expect(max_copies <= 3, "player %d deck has at most 3 copies" % (player_id + 1))
		_expect(int(types[CardData.CardType.TACTIC]) == 10, "player %d deck has 10 tactics" % (player_id + 1))
		_expect(int(types[CardData.CardType.EQUIPMENT]) == 8, "player %d deck has 8 equipment" % (player_id + 1))

func _test_setup_and_turns() -> void:
	var engine := _new_engine()
	var state := engine.state
	_expect(BoardState.WIDTH == 7 and BoardState.HEIGHT == 7, "board is 7x7")
	_expect(state.players[0].hand.size() == 5 and state.players[1].hand.size() == 5, "both players start with 5 cards")
	_expect(state.players[0].current_supply == 1, "player 1 starts with 1 supply")
	_expect(state.players[0].commander.position == Vector2i(0, 3), "player 1 commander home")
	_expect(state.players[1].commander.position == Vector2i(6, 3), "player 2 commander home")
	var unit_card: CardData = null
	for card in state.players[0].hand:
		if card.card_type == CardData.CardType.UNIT and card.supply_cost <= 1:
			unit_card = card
	_expect(unit_card != null, "opening hand has an affordable unit")
	_expect(not _act(engine, {"type": "deploy", "card_id": unit_card.card_id, "tile": Vector2i(2, 3)})["ok"], "deploy outside home column fails")
	_expect(not _act(engine, {"type": "deploy", "card_id": unit_card.card_id, "tile": Vector2i(0, 3)})["ok"], "deploy onto occupied tile fails")
	var result: Dictionary = _act(engine, {"type": "deploy", "card_id": unit_card.card_id, "tile": Vector2i(0, 4)})
	_expect(result["ok"], "deploy into home column succeeds")
	_expect(state.players[0].current_supply == 1 - unit_card.supply_cost, "deploy spends supply")
	_expect(state.players[0].hand.size() == 4, "deploy removes the card from hand")
	_act(engine, {"type": "advance_phase"})
	var deployed: UnitState = state.board.unit_at(Vector2i(0, 4))
	_expect(not _act(engine, {"type": "start_activation", "unit_id": deployed.instance_id})["ok"], "new unit cannot act on deployment turn")
	_act(engine, {"type": "advance_phase"})
	_expect(state.active_player_id == 1 and state.turn_number == 2, "turn passes to player 2")
	_expect(state.players[1].current_supply == 1 and state.players[1].hand.size() == 6, "player 2 gets supply and draws")
	_end_turn(engine)
	_expect(state.active_player_id == 0 and state.players[0].current_supply == 2, "supply grows each own turn")
	_expect(state.players[0].hand.size() == 5, "player 1 draws after the first turn")

func _test_movement_and_terrain() -> void:
	var engine := _new_engine()
	var scout := _spawn(engine, "oakblade", 0, Vector2i(1, 3))
	_command_phase(engine)
	_act(engine, {"type": "start_activation", "unit_id": scout.instance_id})
	_expect(not _act(engine, {"type": "move", "destination": Vector2i(5, 3)})["ok"], "cannot move beyond movement")
	_expect(_act(engine, {"type": "move", "destination": Vector2i(2, 3)})["ok"], "move onto plain succeeds")
	_expect(not _act(engine, {"type": "move", "destination": Vector2i(3, 3)})["ok"], "cannot move twice in one activation")
	var forest_engine := _new_engine()
	var mover := _spawn(forest_engine, "ash_reaver", 0, Vector2i(3, 1))
	var reach: Dictionary = MovementResolver.reachable_tiles(forest_engine.state.board, mover)
	_expect(reach.has(Vector2i(2, 1)) and int(reach[Vector2i(2, 1)]) == 2, "forest costs 2 movement for ground units")
	_expect(not reach.has(Vector2i(1, 1)), "forest cost limits further movement")
	var mountain_engine := _new_engine()
	var climber := _spawn(mountain_engine, "ash_reaver", 0, Vector2i(1, 0))
	_expect(not MovementResolver.can_reach(mountain_engine.state.board, climber, Vector2i(0, 0)), "ground units cannot enter mountains")
	var flyer := _spawn(mountain_engine, "gale_rider", 0, Vector2i(1, 1))
	_expect(MovementResolver.can_reach(mountain_engine.state.board, flyer, Vector2i(0, 0)), "flying units can enter mountains")
	var block_engine := _new_engine()
	var walker := _spawn(block_engine, "oakblade", 0, Vector2i(1, 3))
	_spawn(block_engine, "ash_reaver", 1, Vector2i(2, 3))
	_expect(not MovementResolver.can_reach(block_engine.state.board, walker, Vector2i(2, 3)), "cannot move onto occupied tile")

func _test_new_terrain() -> void:
	var setup := GameEngine.new(7, [], false, [], 3)
	var new_terrain: Array[String] = [
		BoardState.ROAD, BoardState.RIVER, BoardState.BRIDGE, BoardState.HIGH_GROUND,
		BoardState.RUINS, BoardState.LAVA, BoardState.SHRINE,
	]
	for terrain: String in new_terrain:
		_expect(GameEngine.terrain_error(setup.state, 0, Vector2i(3, 0), terrain) == "", "%s is available in setup" % terrain)
	var roundtrip_game := _new_engine()
	for index in range(new_terrain.size()):
		roundtrip_game.state.board.terrain[Vector2i(index, 1)] = new_terrain[index]
	var terrain_snapshot: Dictionary = GameStateCodec.encode(roundtrip_game.state, 0)
	var terrain_decoded: Dictionary = GameStateCodec.decode(terrain_snapshot)
	_expect(bool(terrain_decoded["ok"]) and (terrain_decoded["state"] as GameState).board.terrain == roundtrip_game.state.board.terrain, "all new terrain survives an online snapshot")
	terrain_snapshot["used_shrines"] = [{"x": 0, "y": 1}]
	_expect(not bool(GameStateCodec.decode(terrain_snapshot)["ok"]), "snapshots reject used shrines on non-shrine tiles")

	var engine := _new_engine()
	var board: BoardState = engine.state.board
	var unit := _spawn(engine, "ash_reaver", 0, Vector2i(1, 3))
	var target := Vector2i(4, 3)
	_expect(not MovementResolver.can_reach(board, unit, target), "normal movement cannot reach three tiles away")
	board.terrain[unit.position] = BoardState.ROAD
	_expect(MovementResolver.can_reach(board, unit, target), "starting on a road grants one movement")
	board.terrain[unit.position] = BoardState.PLAIN
	board.terrain[Vector2i(2, 3)] = BoardState.ROAD
	_expect(not MovementResolver.can_reach(board, unit, target), "entering a road does not grant movement during that move")
	board.terrain[Vector2i(2, 3)] = BoardState.RIVER
	_expect(board.movement_cost(Vector2i(2, 3), CardData.MovementType.GROUND) == 2, "river slows ground units")
	_expect(board.movement_cost(Vector2i(2, 3), CardData.MovementType.FLYING) == 1, "fliers ignore river movement cost")
	board.terrain[Vector2i(2, 3)] = BoardState.BRIDGE
	_expect(board.movement_cost(Vector2i(2, 3), CardData.MovementType.GROUND) == 1, "bridge has normal ground movement")

	var archer := _spawn(engine, "hawkeye", 0, Vector2i(2, 2))
	var defender := _spawn(engine, "iron_guard", 1, Vector2i(4, 2))
	board.terrain[archer.position] = BoardState.PLAIN
	board.terrain[defender.position] = BoardState.PLAIN
	var damage: int = CombatResolver.calculate_damage(board, archer, defender)
	board.terrain[archer.position] = BoardState.HIGH_GROUND
	_expect(CombatResolver.calculate_damage(board, archer, defender) == damage + 1, "high ground improves ranged attacks")
	board.terrain[defender.position] = BoardState.RUINS
	_expect(CombatResolver.calculate_damage(board, archer, defender) == damage, "ruins protect against ranged attacks")
	defender.position = Vector2i(3, 2)
	board.terrain[defender.position] = BoardState.RUINS
	var melee_damage: int = CombatResolver.calculate_damage(board, archer, defender)
	board.terrain[archer.position] = BoardState.PLAIN
	board.terrain[defender.position] = BoardState.PLAIN
	_expect(CombatResolver.calculate_damage(board, archer, defender) == melee_damage, "high ground and ruins do not change adjacent attacks")

	var shrine_game := _new_engine()
	var shrine_unit := _spawn(shrine_game, "ash_reaver", 0, Vector2i(1, 3))
	var shrine := Vector2i(2, 3)
	shrine_game.state.board.terrain[shrine] = BoardState.SHRINE
	shrine_game.state.players[0].current_supply = 1
	_command_phase(shrine_game)
	_act(shrine_game, {"type": "start_activation", "unit_id": shrine_unit.instance_id})
	_expect(bool(_act(shrine_game, {"type": "move", "destination": shrine})["ok"]) and shrine_game.state.players[0].current_supply == 2, "landing on a shrine grants supply above the current maximum")
	var copy: GameEngine = shrine_game.clone()
	_expect(copy.state.used_shrines.has(shrine), "clones preserve used shrines")
	var snapshot: Dictionary = GameStateCodec.encode(shrine_game.state, 0)
	var decoded: Dictionary = GameStateCodec.decode(snapshot)
	_expect(bool(decoded["ok"]) and (decoded["state"] as GameState).used_shrines.has(shrine), "online snapshots preserve used shrines")
	_act(shrine_game, {"type": "wait"})
	_give(shrine_game, 0, ["reposition", "reposition"], 4)
	_act(shrine_game, {"type": "play_tactic", "card_id": "reposition", "target_id": shrine_unit.instance_id, "destination": Vector2i(1, 3)})
	_act(shrine_game, {"type": "play_tactic", "card_id": "reposition", "target_id": shrine_unit.instance_id, "destination": shrine})
	_expect(shrine_game.state.players[0].current_supply == 2, "a shrine cannot grant supply twice in one turn, including tactic movement")
	_end_turn(shrine_game)
	_expect(shrine_game.state.used_shrines.is_empty(), "shrines refresh for the next player's turn")
	shrine_game.state.active_player_id = 0
	shrine_game.state.phase = GameState.Phase.DEPLOYMENT
	shrine_game.state.board.move_unit(shrine_unit, Vector2i(1, 3))
	_give(shrine_game, 0, ["reposition"], GameEngine.MAX_SUPPLY)
	_act(shrine_game, {"type": "play_tactic", "card_id": "reposition", "target_id": shrine_unit.instance_id, "destination": shrine})
	_expect(shrine_game.state.players[0].current_supply == GameEngine.MAX_SUPPLY and shrine_game.state.used_shrines.has(shrine), "tactic movement activates a refreshed shrine without exceeding the supply cap")
	var full_supply := _new_engine()
	var full_unit := _spawn(full_supply, "ash_reaver", 0, Vector2i(1, 3))
	full_supply.state.board.terrain[shrine] = BoardState.SHRINE
	full_supply.state.players[0].current_supply = GameEngine.MAX_SUPPLY
	_command_phase(full_supply)
	_act(full_supply, {"type": "start_activation", "unit_id": full_unit.instance_id})
	_act(full_supply, {"type": "move", "destination": shrine})
	_expect(full_supply.state.players[0].current_supply == GameEngine.MAX_SUPPLY and full_supply.state.used_shrines.has(shrine), "a shrine at full supply is consumed without exceeding the cap")
	var second_shrine := Vector2i(1, 2)
	full_supply.state.board.terrain[second_shrine] = BoardState.SHRINE
	_act(full_supply, {"type": "wait"})
	_give(full_supply, 0, ["reposition"], 3)
	_act(full_supply, {"type": "play_tactic", "card_id": "reposition", "target_id": full_unit.instance_id, "destination": second_shrine})
	_expect(full_supply.state.players[0].current_supply == 3 and full_supply.state.used_shrines.has(second_shrine), "a different shrine can grant supply in the same turn")

	var lava_game := _new_engine()
	var ground := _spawn(lava_game, "ash_reaver", 0, Vector2i(1, 3))
	var flyer := _spawn(lava_game, "gale_rider", 0, Vector2i(1, 2))
	lava_game.state.board.terrain[ground.position] = BoardState.LAVA
	lava_game.state.board.terrain[flyer.position] = BoardState.LAVA
	ground.current_hp = 1
	var flyer_hp: int = flyer.current_hp
	_end_turn(lava_game)
	_expect(not lava_game.state.players[0].units.has(ground) and lava_game.state.players[0].fallen.has(ground.card), "lava defeats ground units through normal defeat handling")
	_expect(flyer.current_hp == flyer_hp, "flying units are immune to lava")
	var lethal := _new_engine()
	lethal.state.board.terrain[lethal.state.players[0].commander.position] = BoardState.LAVA
	lethal.state.players[0].commander.current_hp = 1
	_end_turn(lethal)
	_expect(lethal.state.phase == GameState.Phase.GAME_OVER and lethal.state.winner_id == 1, "lava commander defeat ends the match before the next turn")
	var four := GameEngine.new(8, [], false, [], 0, 4)
	four.state.board.terrain[four.state.players[0].commander.position] = BoardState.LAVA
	four.state.players[0].commander.current_hp = 1
	_end_turn(four)
	_expect(four.state.players[0].eliminated and four.state.active_player_id == 1 and four.state.phase != GameState.Phase.GAME_OVER, "lava eliminates a four-player commander and advances to the next survivor")

func _test_visual_effect_events() -> void:
	var engine := _new_engine()
	var ground := _spawn(engine, "ash_reaver", 0, Vector2i(1, 3))
	ground.current_hp = 1
	engine.state.board.terrain[ground.position] = BoardState.LAVA
	var healed := _spawn(engine, "iron_guard", 1, Vector2i(5, 1))
	healed.current_hp -= 2
	engine.state.board.terrain[healed.position] = BoardState.FORT
	engine.state.seeds[healed.position] = 1
	var burned := _spawn(engine, "iron_guard", 1, Vector2i(5, 2))
	burned.apply_status("burn", 2)
	_spawn(engine, "iron_guard", 1, Vector2i(3, 3))
	_command_phase(engine)
	var result: Dictionary = _act(engine, {"type": "advance_phase"})
	var kinds: Array[String] = []
	for effect: Dictionary in result["visual_effects"]:
		kinds.append(str(effect["kind"]))
		if effect["kind"] == "draw":
			_expect(not effect.has("card_id"), "draw animation event does not reveal the drawn card")
	for kind: String in ["lava", "defeat", "draw", "heal", "burn", "bloom", "objective"]:
		_expect(kinds.has(kind), "%s produces a cosmetic event" % kind)
	_expect(engine.state.active_player_id == 1 and not engine.state.players[0].units.has(ground), "cosmetic events do not change turn or defeat outcomes")

func _test_combat() -> void:
	var board := BoardState.new()
	var sword := UnitState.new()
	sword.initialize("a", CardCatalog.get_card("oakblade"), 0, Vector2i(3, 3), 1)
	var axe := UnitState.new()
	axe.initialize("b", CardCatalog.get_card("ash_reaver"), 1, Vector2i(4, 3), 1)
	var lance := UnitState.new()
	lance.initialize("c", CardCatalog.get_card("iron_guard"), 1, Vector2i(4, 2), 1)
	_expect(CombatResolver.calculate_damage(board, sword, axe) == 3, "sword beats axe for +1 damage")
	_expect(CombatResolver.calculate_damage(board, axe, sword) == 2, "axe loses to sword for -1 damage")
	axe.position = Vector2i(4, 3)
	lance.position = Vector2i(5, 3)
	_expect(CombatResolver.calculate_damage(board, axe, lance) == 3, "axe beats lance on plain")
	lance.position = Vector2i(4, 2)
	_expect(CombatResolver.calculate_damage(board, axe, lance) == 2, "forest adds 1 defense")
	var fort_target := UnitState.new()
	fort_target.initialize("d", CardCatalog.get_card("iron_guard"), 1, Vector2i(6, 0), 1)
	_expect(CombatResolver.calculate_damage(board, axe, fort_target) == 1, "fort adds 2 defense")
	var archer := UnitState.new()
	archer.initialize("e", CardCatalog.get_card("hawkeye"), 0, Vector2i(2, 3), 1)
	var flyer := UnitState.new()
	flyer.initialize("f", CardCatalog.get_card("gale_rider"), 1, Vector2i(4, 3), 1)
	_expect(CombatResolver.calculate_damage(board, archer, flyer) == 4, "bows deal +2 damage to flying units")
	var mage := UnitState.new()
	mage.initialize("g", CardCatalog.get_card("ember_mage"), 0, Vector2i(2, 3), 1)
	var knight := UnitState.new()
	knight.initialize("h", CardCatalog.get_card("stonewall"), 1, Vector2i(4, 3), 1)
	_expect(CombatResolver.calculate_damage(board, mage, knight) == 4, "magic ignores base defense")

	var engine := _new_engine()
	var swift := _spawn(engine, "swiftblade", 0, Vector2i(3, 3))
	var reaver := _spawn(engine, "ash_reaver", 1, Vector2i(4, 3))
	var report: Dictionary = _duel(engine, swift, reaver)
	_expect(report["ok"], "attack action succeeds")
	_expect(bool(report["counter"]), "defender counterattacks when in range")
	_expect(bool(report["follow_up"]), "much faster attacker follows up")
	_expect(reaver.current_hp == 2 and swift.current_hp == 3, "damage from attack, counter and follow-up")
	_end_turn(engine)
	_expect(reaver.current_hp == 2, "damage persists between turns")
	_expect(swift.exhausted == false, "units ready again at end of own turn")

	var ranged := _new_engine()
	var bow := _spawn(ranged, "hawkeye", 0, Vector2i(2, 3))
	var target := _spawn(ranged, "oakblade", 1, Vector2i(4, 3))
	var ranged_report: Dictionary = _duel(ranged, bow, target)
	_expect(ranged_report["ok"] and not bool(ranged_report["counter"]), "no counter outside defender range")
	var far := _new_engine()
	var short := _spawn(far, "oakblade", 0, Vector2i(1, 3))
	var distant := _spawn(far, "ash_reaver", 1, Vector2i(4, 3))
	_expect(not _duel(far, short, distant)["ok"], "out-of-range attack is rejected")

func _test_equipment() -> void:
	var engine := _new_engine()
	var blade := _spawn(engine, "oakblade", 0, Vector2i(1, 3))
	_give(engine, 0, ["iron_sword", "steel_axe", "iron_sword", "defensive_shield"], 6)
	engine.state.phase = GameState.Phase.DEPLOYMENT
	var supply: int = engine.state.players[0].current_supply
	_expect(_act(engine, {"type": "equip", "card_id": "iron_sword", "unit_id": blade.instance_id})["ok"], "compatible weapon equips")
	_expect(blade.attack() == 4 and engine.state.players[0].current_supply == supply - 1, "equipment raises ATK and costs supply")
	_expect(not _act(engine, {"type": "equip", "card_id": "steel_axe", "unit_id": blade.instance_id})["ok"], "incompatible weapon is rejected")
	_expect(engine.state.players[0].hand.size() == 3, "rejected equip keeps the card")
	_expect(_act(engine, {"type": "equip", "card_id": "iron_sword", "unit_id": blade.instance_id})["ok"], "replacing a weapon succeeds")
	_expect(engine.state.players[0].discard.size() == 1, "replaced equipment is discarded")
	_expect(_act(engine, {"type": "equip", "card_id": "defensive_shield", "unit_id": blade.instance_id})["ok"], "accessory fits its own slot")
	_expect(blade.defense() == 2, "accessory raises DEF")
	var foe := _spawn(engine, "ash_reaver", 1, Vector2i(2, 3))
	blade.current_hp = 1
	foe.mods.append({"stat": "attack", "amount": 3, "expires": "end_of_turn"})
	var discard_before: int = engine.state.players[0].discard.size()
	_command_phase(engine, 1)
	_act(engine, {"type": "start_activation", "unit_id": foe.instance_id})
	_act(engine, {"type": "attack", "target_id": blade.instance_id})
	_expect(engine.state.players[0].fallen.size() == 1, "unit with equipment is defeated")
	_expect(engine.state.players[0].discard.size() == discard_before + 2, "equipment returns to discard when its unit falls")

func _test_tactics() -> void:
	var engine := _new_engine()
	var guard := _spawn(engine, "iron_guard", 0, Vector2i(2, 3))
	var enemy := _spawn(engine, "ash_reaver", 1, Vector2i(5, 3))
	engine.state.phase = GameState.Phase.DEPLOYMENT
	_give(engine, 0, ["rally", "heal", "heal", "reposition", "fortify", "precision_strike", "tactical_retreat"], 12)
	var base_attack: int = guard.attack()
	_expect(_act(engine, {"type": "play_tactic", "card_id": "rally", "target_id": guard.instance_id})["ok"], "rally succeeds")
	_expect(guard.attack() == base_attack + 2, "rally grants +2 ATK")
	_expect(_act(engine, {"type": "play_tactic", "card_id": "fortify", "target_id": guard.instance_id})["ok"], "fortify succeeds")
	_expect(guard.defense() == 4, "fortify grants +2 DEF")
	var supply: int = engine.state.players[0].current_supply
	var hand_size: int = engine.state.players[0].hand.size()
	_expect(not _act(engine, {"type": "play_tactic", "card_id": "heal", "target_id": guard.instance_id})["ok"], "heal on an undamaged unit fails")
	_expect(engine.state.players[0].current_supply == supply and engine.state.players[0].hand.size() == hand_size, "failed tactic changes nothing")
	guard.current_hp = 2
	_expect(_act(engine, {"type": "play_tactic", "card_id": "heal", "target_id": guard.instance_id})["ok"], "heal succeeds")
	_expect(guard.current_hp == 6, "heal restores 4 HP")
	_expect(not _act(engine, {"type": "play_tactic", "card_id": "reposition", "target_id": guard.instance_id, "destination": Vector2i(5, 5)})["ok"], "reposition beyond 2 tiles fails")
	_expect(_act(engine, {"type": "play_tactic", "card_id": "reposition", "target_id": guard.instance_id, "destination": Vector2i(3, 3)})["ok"], "reposition succeeds")
	_expect(guard.position == Vector2i(3, 3) and engine.state.board.unit_at(Vector2i(3, 3)) == guard, "reposition moves the unit")
	_expect(not _act(engine, {"type": "play_tactic", "card_id": "tactical_retreat", "target_id": guard.instance_id, "destination": Vector2i(1, 1)})["ok"], "retreat must use the home column")
	_expect(_act(engine, {"type": "play_tactic", "card_id": "tactical_retreat", "target_id": guard.instance_id, "destination": Vector2i(0, 1)})["ok"], "tactical retreat succeeds")
	_expect(guard.position == Vector2i(0, 1), "retreat moves the unit home")
	_expect(not _act(engine, {"type": "play_tactic", "card_id": "precision_strike", "target_id": guard.instance_id})["ok"], "precision strike cannot hit allies")
	_expect(_act(engine, {"type": "play_tactic", "card_id": "precision_strike", "target_id": enemy.instance_id})["ok"], "precision strike succeeds")
	_expect(enemy.current_hp == enemy.max_hp() - 3, "precision strike deals 3 damage")
	_expect(engine.state.players[0].discard.size() >= 6, "played tactics go to the discard pile")
	_end_turn(engine)
	_expect(guard.attack() == base_attack, "rally expires at end of turn")
	_expect(guard.defense() == 4, "fortify lasts through the opponent's turn")
	_end_turn(engine)
	_expect(guard.defense() == 2, "fortify expires at the start of the owner's next turn")

func _test_promotion() -> void:
	var engine := _new_engine()
	var blade := _spawn(engine, "oakblade", 0, Vector2i(1, 3))
	var mage := _spawn(engine, "ember_mage", 0, Vector2i(1, 2))
	engine.state.phase = GameState.Phase.DEPLOYMENT
	engine.state.turn_number = 1
	_give(engine, 0, ["promo_hero", "promo_sage", "promo_hero"], 6)
	_expect(not _act(engine, {"type": "promote", "card_id": "promo_hero", "unit_id": blade.instance_id})["ok"], "promotion on the deployment turn is rejected")
	engine.state.turn_number = 3
	_expect(not _act(engine, {"type": "promote", "card_id": "promo_sage", "unit_id": blade.instance_id})["ok"], "promotion needs the matching class")
	blade.current_hp = 3
	_expect(_act(engine, {"type": "promote", "card_id": "promo_hero", "unit_id": blade.instance_id})["ok"], "matching promotion succeeds")
	_expect(blade.max_hp() == 8 and blade.current_hp == 6, "promotion keeps damage taken")
	_expect(blade.attack() == 5 and blade.unit_class() == "Hero", "promotion improves stats and class")
	_expect(not _act(engine, {"type": "promote", "card_id": "promo_hero", "unit_id": blade.instance_id})["ok"], "units promote only once")
	engine.state.players[0].current_supply = 1
	_expect(not _act(engine, {"type": "promote", "card_id": "promo_sage", "unit_id": mage.instance_id})["ok"], "promotion needs enough supply")
	_expect(not _act(engine, {"type": "promote", "card_id": "promo_sage", "unit_id": engine.state.players[0].commander.instance_id})["ok"], "commanders cannot be promoted")

func _test_support() -> void:
	var engine := _new_engine()
	var guard := _spawn(engine, "iron_guard", 0, Vector2i(1, 3))
	var wall := _spawn(engine, "stonewall", 0, Vector2i(1, 4))
	var base_def: int = guard.defense()
	engine.state.turn_number = 1
	_end_turn(engine)
	_end_turn(engine)
	var bond: Dictionary = SupportResolver.get_bond(engine.state, guard, wall)
	_expect(not bond.is_empty() and int(bond["progress"]) == 1, "adjacent partners gain bond progress at turn start")
	_expect(guard.defense() + SupportResolver.defense_bonus(engine.state, guard) == base_def + 1, "rank C grants +1 DEF while adjacent")
	SupportResolver.process_start_of_turn(engine.state)
	_expect(int(SupportResolver.get_bond(engine.state, guard, wall)["progress"]) == 1, "progress is granted once per turn")

	var duo := _new_engine()
	var lead := _spawn(duo, "iron_guard", 0, Vector2i(1, 3))
	var ally := _spawn(duo, "stonewall", 0, Vector2i(2, 2))
	var foe := _spawn(duo, "gale_rider", 1, Vector2i(2, 3))
	_expect(SupportResolver.find_attack_partner(duo.state, lead, foe) == null, "no coordinated attack without an A-rank bond")
	duo.state.bonds[SupportResolver.bond_key(lead.instance_id, ally.instance_id)] = {
		"a": lead.instance_id, "b": ally.instance_id, "progress": 3, "last_turn": 0, "used": false,
	}
	_command_phase(duo)
	_act(duo, {"type": "start_activation", "unit_id": lead.instance_id})
	var report: Dictionary = _act(duo, {"type": "attack", "target_id": foe.instance_id, "support": true})
	_expect(report["ok"] and bool(report["supported"]) and int(report["support_damage"]) == 1, "A-rank partner joins the attack")
	_expect(SupportResolver.find_attack_partner(duo.state, lead, foe) == null, "coordinated attack is once per match")

func _test_fallen_zone_and_victory() -> void:
	var engine := _new_engine()
	var swift := _spawn(engine, "swiftblade", 0, Vector2i(3, 3))
	var reaver := _spawn(engine, "ash_reaver", 1, Vector2i(4, 3))
	reaver.current_hp = 1
	var report: Dictionary = _duel(engine, swift, reaver)
	_expect(report["ok"] and engine.state.board.unit_at(Vector2i(4, 3)) == null, "defeated unit leaves the board")
	_expect(engine.state.players[1].fallen.size() == 1 and engine.state.players[1].fallen[0].card_id == "ash_reaver", "defeated units go to the Fallen Zone")
	_expect(not engine.state.players[1].discard.has(reaver.card), "defeated units do not enter the discard pile")
	_expect(engine.state.find_unit(reaver.instance_id) == null, "defeated unit cannot be revived or targeted")

	var duel := _new_engine()
	var hunter := _spawn(duel, "swiftblade", 0, Vector2i(5, 3))
	duel.state.players[1].commander.current_hp = 1
	_duel(duel, hunter, duel.state.players[1].commander)
	_expect(duel.state.phase == GameState.Phase.GAME_OVER and duel.state.winner_id == 0, "defeating the enemy commander wins")
	_expect(not _act(duel, {"type": "advance_phase"})["ok"], "no actions after game over")

	var objectives := _new_engine()
	for index in range(BoardState.OBJECTIVE_POSITIONS.size()):
		_spawn(objectives, "iron_guard", 0, BoardState.OBJECTIVE_POSITIONS[index])
	objectives.state.players[0].victory_points = 3
	objectives.state.active_player_id = 1
	objectives.state.phase = GameState.Phase.COMMAND
	objectives.state.turn_number = 4
	_act(objectives, {"type": "advance_phase"})
	_expect(objectives.state.players[0].victory_points == 6, "held objectives score 1 VP each at turn start")
	_expect(objectives.state.winner_id == 0 and objectives.state.phase == GameState.Phase.GAME_OVER, "reaching 6 VP wins")

	var exhausted := _new_engine()
	exhausted.state.players[0].deck.clear()
	exhausted.state.active_player_id = 1
	exhausted.state.phase = GameState.Phase.COMMAND
	exhausted.state.turn_number = 4
	_act(exhausted, {"type": "advance_phase"})
	_expect(exhausted.state.winner_id == 1, "drawing from an empty deck loses")

func _test_invalid_actions() -> void:
	var engine := _new_engine()
	var history_size: int = engine.state.history.size()
	_expect(not _act(engine, {"type": "dance"})["ok"], "unknown action is rejected")
	_expect(not _act(engine, {"type": "attack", "target_id": "unit_0002"})["ok"], "attack without activation is rejected")
	_expect(not _act(engine, {"type": "deploy", "card_id": "missing", "tile": Vector2i(0, 4)})["ok"], "deploying a card not in hand is rejected")
	_expect(not _act(engine, {"type": "move", "destination": Vector2i(1, 3)})["ok"], "moving in the deployment phase is rejected")
	_expect(engine.state.history.size() == history_size, "rejected actions are not recorded")
	_act(engine, {"type": "advance_phase"})
	_expect(engine.state.history.size() == history_size + 1, "accepted actions are recorded")

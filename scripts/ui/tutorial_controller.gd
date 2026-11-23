class_name TutorialController
extends RefCounted

var engine: GameEngine
var steps: Array[Dictionary] = []
var step_index: int = 0
var finished: bool = false

func _init() -> void:
	engine = GameEngine.new(271828, [], false, [], 0, 2)
	var state: GameState = engine.state
	state.board = BoardState.new(7, 7, "column")
	for player: PlayerState in state.players:
		state.board.place_unit(player.commander, state.board.commander_position(player.player_id))
	state.turn_number = 3
	state.players[0].turns_started = 2
	state.players[1].turns_started = 1
	state.players[0].max_supply = 6
	state.players[0].current_supply = 6
	state.players[0].hand.assign([
		CardCatalog.get_card("iron_guard"),
		CardCatalog.get_card("iron_sword"),
		CardCatalog.get_card("promo_hero"),
		CardCatalog.get_card("rally"),
	])
	state.events.clear()
	state.events.append("Training scenario: an earlier turn with extra supply and prepared units.")
	var ally := _add_unit("oakblade", 0, Vector2i(1, 3))
	var enemy := _add_unit("ash_reaver", 1, Vector2i(4, 3))
	steps = [
		{"text": "This prepared scenario starts on an earlier turn with 6 supply. Play Iron Guard in your home column: column 1, row 3.",
			"action": {"type": "deploy", "card_id": "iron_guard", "tile": Vector2i(0, 2)}},
		{"text": "Cards spend supply. Select Iron Sword and equip it to Oakblade; OK marks a compatible unit.",
			"action": {"type": "equip", "card_id": "iron_sword", "unit_id": ally.instance_id}},
		{"text": "Select Hero and promote Oakblade. Promotions require the matching class and a unit deployed on an earlier turn.",
			"action": {"type": "promote", "card_id": "promo_hero", "unit_id": ally.instance_id}},
		{"text": "Select Rally and play it on Oakblade to gain attack for this turn.",
			"action": {"type": "play_tactic", "card_id": "rally", "target_id": ally.instance_id}},
		{"text": "Deployment is complete. Press Go to Command Phase.",
			"action": {"type": "advance_phase"}},
		{"text": "Activate Oakblade by selecting it. You can activate up to two units per turn.",
			"action": {"type": "start_activation", "unit_id": ally.instance_id}},
		{"text": "Move Oakblade to the central objective at column 4, row 4. Blue tiles are reachable.",
			"action": {"type": "move", "destination": Vector2i(3, 3)}},
		{"text": "Attack the adjacent Ash Reaver. Combat may include a counterattack or follow-up.",
			"action": {"type": "attack", "target_id": enemy.instance_id, "support": false}},
		{"text": "End your turn. The scripted opponent will pass; holding the objective scores at the start of your next turn.",
			"action": {"type": "advance_phase"}},
	]

func _add_unit(card_id: String, player_id: int, tile: Vector2i) -> UnitState:
	var unit := UnitState.new()
	unit.initialize(engine.state.create_instance_id(), CardCatalog.get_card(card_id), player_id, tile, 1)
	var placed: bool = engine.state.board.place_unit(unit, tile)
	assert(placed, "Tutorial unit must have an empty starting tile.")
	engine.state.players[player_id].units.append(unit)
	return unit

func expected_action() -> Dictionary:
	return steps[step_index]["action"] if step_index < steps.size() else {}

func instruction() -> String:
	if finished:
		return "You gained 1 victory point! Supply refills and grows to 6 each turn. In two-player play, draw each turn except the first. Win with 6 points, by defeating the enemy commander, or when your opponent cannot draw."
	if step_index >= steps.size():
		return "The scripted opponent is taking its turn..."
	return str(steps[step_index]["text"])

func accepts(action: Dictionary) -> bool:
	var expected: Dictionary = expected_action()
	if expected.is_empty() or str(action.get("type", "")) != str(expected["type"]):
		return false
	for key in expected:
		if not action.has(key) or action[key] != expected[key]:
			return false
	return true

func expected_tile() -> Vector2i:
	var action: Dictionary = expected_action()
	if action.has("tile"):
		return action["tile"]
	if action.has("destination"):
		return action["destination"]
	var unit_id: String = str(action.get("unit_id", action.get("target_id", "")))
	var unit: UnitState = engine.state.find_unit(unit_id)
	return unit.position if unit != null else Vector2i(-1, -1)

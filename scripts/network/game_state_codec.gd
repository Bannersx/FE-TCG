class_name GameStateCodec
extends RefCounted

const VERSION: int = 2
const HIDDEN_CARD_ID: String = "__hidden__"

static func encode(state: GameState, viewer_id: int) -> Dictionary:
	if viewer_id < 0 or viewer_id >= state.players.size():
		return {}
	var players: Array[Dictionary] = []
	for player: PlayerState in state.players:
		var player_data: Dictionary = {
			"player_id": player.player_id,
			"display_name": player.display_name,
			"army_id": player.army_id,
			"deck_count": player.deck.size(),
			"hand_count": player.hand.size(),
			"discard_card_ids": _card_ids(player.discard),
			"fallen_card_ids": _card_ids(player.fallen),
			"commander_id": player.commander.instance_id,
			"max_supply": player.max_supply,
			"current_supply": player.current_supply,
			"victory_points": player.victory_points,
			"normal_deployments_this_turn": player.normal_deployments_this_turn,
			"tactics_this_turn": player.tactics_this_turn,
			"eliminated": player.eliminated,
			"turns_started": player.turns_started,
			"haste_unit_id": player.haste_unit_id,
			"units": _encode_units(player.units),
		}
		if player.player_id == viewer_id:
			player_data["deck_card_ids"] = _card_ids(player.deck)
			player_data["hand_card_ids"] = _card_ids(player.hand)
		players.append(player_data)

	var terrain: Array[Dictionary] = []
	for tile: Vector2i in state.board.terrain:
		terrain.append({
			"x": tile.x,
			"y": tile.y,
			"name": str(state.board.terrain[tile]),
		})
	var seeds: Array[Dictionary] = []
	for tile: Vector2i in state.seeds:
		seeds.append({"x": tile.x, "y": tile.y, "owner_id": int(state.seeds[tile])})
	var used_shrines: Array[Dictionary] = []
	for tile: Vector2i in state.used_shrines:
		used_shrines.append({"x": tile.x, "y": tile.y})

	return {
		"version": VERSION,
		"viewer_id": viewer_id,
		"board_width": state.board.width,
		"board_height": state.board.height,
		"objective_layout": state.board.objective_layout,
		"terrain": terrain,
		"players": players,
		"active_player_id": state.active_player_id,
		"phase": state.phase,
		"turn_number": state.turn_number,
		"winner_id": state.winner_id,
		"game_over_reason": state.game_over_reason,
		"next_instance_number": state.next_instance_number,
		"current_activation_unit_id": state.current_activation_unit_id,
		"current_activation_moved": state.current_activation_moved,
		"activated_unit_ids": state.activated_unit_ids.duplicate(),
		"events": state.events.duplicate(),
		"bonds": state.bonds.duplicate(true),
		"activation_moved_tiles": state.activation_moved_tiles,
		"chain_count": state.chain_count,
		"seeds": seeds,
		"used_shrines": used_shrines,
		"setup_left": state.setup_left.duplicate(),
		"setup_used": state.setup_used.duplicate(true),
		"history": state.history.duplicate(true),
	}

static func decode(data: Dictionary) -> Dictionary:
	if int(data.get("version", -1)) != VERSION:
		return _failure("Unsupported game-state version.")
	if not _is_array(data.get("players")) or (data["players"] as Array).size() not in [2, 4]:
		return _failure("Game state must contain two or four players.")
	var player_count: int = (data["players"] as Array).size()
	var viewer_id: int = int(data.get("viewer_id", -1))
	if viewer_id < 0 or viewer_id >= player_count:
		return _failure("Game state has an invalid viewer.")
	if not _is_array(data.get("terrain")) or not _is_array(data.get("seeds")) or not _is_array(data.get("used_shrines")):
		return _failure("Game state has invalid board data.")

	var width: int = int(data.get("board_width", 0))
	var height: int = int(data.get("board_height", 0))
	if width < 5 or height < 3 or width > 32 or height > 32:
		return _failure("Game state has invalid board dimensions.")
	var layout: String = str(data.get("objective_layout", ""))
	if not BoardState.OBJECTIVE_LAYOUTS.has(layout):
		return _failure("Game state has an invalid objective layout.")
	if (player_count == 4 and (layout != "four_corners" or width != 9 or height != 9)) \
			or (player_count == 2 and layout == "four_corners"):
		return _failure("Game state has a board that does not match the player count.")

	var state := GameState.new()
	state.board = BoardState.new(width, height, layout)
	state.board.terrain.clear()
	for y in range(height):
		for x in range(width):
			state.board.terrain[Vector2i(x, y)] = BoardState.PLAIN
	for terrain_entry: Variant in data["terrain"]:
		if not terrain_entry is Dictionary:
			return _failure("Game state has an invalid terrain entry.")
		var tile := Vector2i(int(terrain_entry.get("x", -1)), int(terrain_entry.get("y", -1)))
		var terrain_name: String = str(terrain_entry.get("name", ""))
		if not state.board.is_valid_position(tile) or (terrain_name != BoardState.OBJECTIVE and not BoardState.PLACEABLE.has(terrain_name)):
			return _failure("Game state contains invalid terrain.")
		state.board.terrain[tile] = terrain_name

	var players_data: Array = data["players"]
	for player_id in range(player_count):
		var player_data: Variant = players_data[player_id]
		if not player_data is Dictionary or int(player_data.get("player_id", -1)) != player_id:
			return _failure("Game state has invalid player data.")
		var player := PlayerState.new()
		player.player_id = player_id
		player.display_name = str(player_data.get("display_name", "Player %d" % (player_id + 1)))
		player.army_id = str(player_data.get("army_id", ""))
		if not ArmyCatalog.is_army(player.army_id):
			return _failure("Game state has an invalid army.")
		player.max_supply = int(player_data.get("max_supply", 0))
		player.current_supply = int(player_data.get("current_supply", 0))
		player.victory_points = int(player_data.get("victory_points", 0))
		player.normal_deployments_this_turn = int(player_data.get("normal_deployments_this_turn", 0))
		player.tactics_this_turn = int(player_data.get("tactics_this_turn", 0))
		player.eliminated = bool(player_data.get("eliminated", false))
		player.turns_started = int(player_data.get("turns_started", 0))
		player.haste_unit_id = str(player_data.get("haste_unit_id", ""))

		var hidden: bool = player_id != viewer_id
		var deck_result: Dictionary = _decode_card_pile(player_data, "deck", hidden, player.army_id, player_id)
		if not bool(deck_result["ok"]):
			return deck_result
		player.deck = deck_result["cards"]
		var hand_result: Dictionary = _decode_card_pile(player_data, "hand", hidden, player.army_id, player_id)
		if not bool(hand_result["ok"]):
			return hand_result
		player.hand = hand_result["cards"]

		var discard_result: Dictionary = _decode_card_list(player_data.get("discard_card_ids", []), player.army_id, player_id)
		if not bool(discard_result["ok"]):
			return discard_result
		player.discard = discard_result["cards"]
		var fallen_result: Dictionary = _decode_card_list(player_data.get("fallen_card_ids", []), player.army_id, player_id)
		if not bool(fallen_result["ok"]):
			return fallen_result
		player.fallen = fallen_result["cards"]

		if not _is_array(player_data.get("units")):
			return _failure("Game state has invalid unit data.")
		for unit_data: Variant in player_data["units"]:
			if not unit_data is Dictionary:
				return _failure("Game state has an invalid unit.")
			var unit_result: Dictionary = _decode_unit(unit_data, player_id, player.army_id, width, height)
			if not bool(unit_result["ok"]):
				return unit_result
			var unit: UnitState = unit_result["unit"]
			player.units.append(unit)
			if unit.instance_id == str(player_data.get("commander_id", "")):
				if not unit.is_commander:
					return _failure("Game state commander data is inconsistent.")
				player.commander = unit
			if unit.current_hp > 0 and not state.board.place_unit(unit, unit.position):
				return _failure("Game state contains overlapping units.")
		if player.commander == null:
			return _failure("Game state is missing a commander.")
		state.players.append(player)

	state.active_player_id = int(data.get("active_player_id", -1))
	state.phase = int(data.get("phase", -1))
	state.turn_number = int(data.get("turn_number", 0))
	state.winner_id = int(data.get("winner_id", -1))
	state.game_over_reason = str(data.get("game_over_reason", ""))
	state.next_instance_number = int(data.get("next_instance_number", 0))
	state.current_activation_unit_id = str(data.get("current_activation_unit_id", ""))
	state.current_activation_moved = bool(data.get("current_activation_moved", false))
	state.activation_moved_tiles = int(data.get("activation_moved_tiles", 0))
	state.chain_count = int(data.get("chain_count", 0))
	if state.active_player_id < 0 or state.active_player_id >= player_count \
			or state.phase < GameState.Phase.DEPLOYMENT or state.phase > GameState.Phase.SETUP \
			or state.turn_number < 1 or state.next_instance_number < 1:
		return _failure("Game state contains invalid turn data.")
	if not _is_array(data.get("activated_unit_ids")) or not _is_array(data.get("events")) \
			or not _is_array(data.get("setup_left")) or (data["setup_left"] as Array).size() != player_count \
			or not _is_array(data.get("setup_used")) or (data["setup_used"] as Array).size() != player_count \
			or not _is_array(data.get("history")):
		return _failure("Game state has invalid match metadata.")
	state.activated_unit_ids.assign(data["activated_unit_ids"])
	state.events.assign(data["events"])
	state.setup_left.assign(data["setup_left"])
	state.setup_used.assign(data["setup_used"])
	state.history.assign(data["history"])
	if not data.get("bonds", {}) is Dictionary:
		return _failure("Game state has invalid support data.")
	state.bonds = data.get("bonds", {}).duplicate(true)
	for seed_entry: Variant in data["seeds"]:
		if not seed_entry is Dictionary:
			return _failure("Game state has an invalid seed.")
		var tile := Vector2i(int(seed_entry.get("x", -1)), int(seed_entry.get("y", -1)))
		var owner_id: int = int(seed_entry.get("owner_id", -1))
		if not state.board.is_valid_position(tile) or owner_id < 0 or owner_id >= player_count:
			return _failure("Game state contains an invalid seed.")
		state.seeds[tile] = owner_id
	for shrine_entry: Variant in data["used_shrines"]:
		if not shrine_entry is Dictionary:
			return _failure("Game state has an invalid shrine.")
		var tile := Vector2i(int(shrine_entry.get("x", -1)), int(shrine_entry.get("y", -1)))
		if not state.board.is_valid_position(tile) or state.board.terrain_at(tile) != BoardState.SHRINE:
			return _failure("Game state contains an invalid shrine.")
		state.used_shrines[tile] = true
	return {"ok": true, "state": state}

static func _encode_units(units: Array[UnitState]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: UnitState in units:
		result.append({
			"instance_id": unit.instance_id,
			"card_id": unit.card.card_id,
			"owner_id": unit.owner_id,
			"x": unit.position.x,
			"y": unit.position.y,
			"current_hp": unit.current_hp,
			"exhausted": unit.exhausted,
			"deployed_turn": unit.deployed_turn,
			"promotion_card_id": _card_id(unit.promotion),
			"weapon_item_card_id": _card_id(unit.weapon_item),
			"accessory_item_card_id": _card_id(unit.accessory_item),
			"mods": unit.mods.duplicate(true),
			"statuses": unit.statuses.duplicate(true),
		})
	return result

static func _decode_unit(data: Dictionary, expected_owner: int, army_id: String, width: int, height: int) -> Dictionary:
	var unit := UnitState.new()
	unit.instance_id = str(data.get("instance_id", ""))
	unit.owner_id = int(data.get("owner_id", -1))
	unit.position = Vector2i(int(data.get("x", -1)), int(data.get("y", -1)))
	if unit.instance_id.is_empty() or unit.owner_id != expected_owner \
			or unit.position.x < 0 or unit.position.x >= width or unit.position.y < 0 or unit.position.y >= height:
		return _failure("Game state contains an invalid unit.")
	var card: CardData = _card_from_id(str(data.get("card_id", "")), army_id, expected_owner)
	if card == null or not card.is_unit_like():
		return _failure("Game state contains an unknown unit card.")
	unit.card = card
	unit.current_hp = int(data.get("current_hp", 0))
	unit.exhausted = bool(data.get("exhausted", false))
	unit.deployed_turn = int(data.get("deployed_turn", -1))
	var promotion_id: String = str(data.get("promotion_card_id", ""))
	var weapon_item_id: String = str(data.get("weapon_item_card_id", ""))
	var accessory_item_id: String = str(data.get("accessory_item_card_id", ""))
	if (not promotion_id.is_empty() and _card_from_id(promotion_id, army_id, expected_owner) == null) \
			or (not weapon_item_id.is_empty() and _card_from_id(weapon_item_id, army_id, expected_owner) == null) \
			or (not accessory_item_id.is_empty() and _card_from_id(accessory_item_id, army_id, expected_owner) == null):
		return _failure("Game state contains an unknown unit card.")
	unit.promotion = _card_from_optional_id(promotion_id, army_id, expected_owner)
	unit.weapon_item = _card_from_optional_id(weapon_item_id, army_id, expected_owner)
	unit.accessory_item = _card_from_optional_id(accessory_item_id, army_id, expected_owner)
	if unit.current_hp < 0 or unit.current_hp > unit.max_hp() or unit.deployed_turn < 0 \
			or (unit.promotion != null and unit.promotion.card_type != CardData.CardType.PROMOTION) \
			or (unit.weapon_item != null and unit.weapon_item.card_type != CardData.CardType.EQUIPMENT) \
			or (unit.accessory_item != null and unit.accessory_item.card_type != CardData.CardType.EQUIPMENT):
		return _failure("Game state contains invalid unit attributes.")
	if not data.get("mods", []) is Array or not data.get("statuses", {}) is Dictionary:
		return _failure("Game state contains invalid unit effects.")
	unit.mods.assign(data.get("mods", []))
	unit.statuses = data.get("statuses", {}).duplicate(true)
	return {"ok": true, "unit": unit}

static func _decode_card_pile(data: Dictionary, pile_name: String, hidden: bool, army_id: String, player_id: int) -> Dictionary:
	var count: int = int(data.get(pile_name + "_count", -1))
	if count < 0 or count > DeckData.DECK_SIZE:
		return _failure("Game state has an invalid card count.")
	var key: String = pile_name + "_card_ids"
	if hidden and data.has(key):
		return _failure("Game state exposes hidden card identities.")
	if data.has(key):
		var visible_result: Dictionary = _decode_card_list(data[key], army_id, player_id)
		if not bool(visible_result["ok"]):
			return visible_result
		if (visible_result["cards"] as Array).size() != count:
			return _failure("Game state card count does not match its card list.")
		return visible_result
	if not hidden:
		return _failure("Game state omitted a player's visible cards.")
	var cards: Array[CardData] = []
	for _index in range(count):
		var placeholder := CardData.new()
		placeholder.card_id = HIDDEN_CARD_ID
		placeholder.card_name = "Hidden card"
		cards.append(placeholder)
	return {"ok": true, "cards": cards}

static func _decode_card_list(card_ids: Variant, army_id: String, player_id: int) -> Dictionary:
	if not _is_array(card_ids):
		return _failure("Game state has an invalid card list.")
	var cards: Array[CardData] = []
	for card_id: Variant in card_ids:
		var card: CardData = _card_from_id(str(card_id), army_id, player_id)
		if card == null:
			return _failure("Game state contains an unknown card.")
		cards.append(card)
	return {"ok": true, "cards": cards}

static func _card_from_optional_id(card_id: String, army_id: String, player_id: int) -> CardData:
	return null if card_id.is_empty() else _card_from_id(card_id, army_id, player_id)

static func _card_from_id(card_id: String, army_id: String, player_id: int) -> CardData:
	if card_id.begins_with("commander_"):
		return CardCatalog.get_commander(player_id, army_id) if card_id == "commander_" + army_id else null
	return CardCatalog.get_card(card_id)

static func _card_id(card: CardData) -> String:
	return "" if card == null else card.card_id

static func _card_ids(cards: Array[CardData]) -> Array[String]:
	var result: Array[String] = []
	for card: CardData in cards:
		result.append(card.card_id)
	return result

static func _is_array(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

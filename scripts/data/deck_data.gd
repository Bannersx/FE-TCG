class_name DeckData
extends RefCounted

const DECK_SIZE: int = 40
const MAX_COPIES: int = 3
const MAX_LEGENDARY_COPIES: int = 1
const SAVE_DIR: String = "user://decks"
const RECOMMENDED_UNITS: int = 22
const RECOMMENDED_TACTICS: int = 10
const RECOMMENDED_EQUIPMENT: int = 8

static func starter_ids(player_id: int, army_id: String = "") -> Array[String]:
	var ids: Array[String] = []
	for card in CardCatalog.make_starter_deck(player_id, army_id):
		ids.append(card.card_id)
	return ids

# The army whose faction the deck's cards belong to; "" when it holds only neutral cards.
static func army_of(card_ids: Array) -> String:
	for card_id in card_ids:
		var card: CardData = CardCatalog.get_card(str(card_id))
		if card != null:
			var army_id: String = ArmyCatalog.army_of_faction(card.faction)
			if army_id != "":
				return army_id
	return ""

static func count_ids(card_ids: Array) -> Dictionary:
	var counts: Dictionary = {}
	for card_id in card_ids:
		counts[str(card_id)] = int(counts.get(str(card_id), 0)) + 1
	return counts

# Hard rules: exactly 40 known cards, within the copy limits.
static func validate(card_ids: Array) -> Array[String]:
	var errors: Array[String] = []
	if card_ids.size() != DECK_SIZE:
		errors.append("The deck has %d cards; it needs exactly %d." % [card_ids.size(), DECK_SIZE])
	var counts: Dictionary = count_ids(card_ids)
	var factions: Array[String] = []
	for card_id: String in counts:
		var card: CardData = CardCatalog.get_card(card_id)
		if card == null:
			errors.append("Unknown card: %s." % card_id)
			continue
		var army_id: String = ArmyCatalog.army_of_faction(card.faction)
		if army_id != "" and not factions.has(army_id):
			factions.append(army_id)
		var limit: int = MAX_LEGENDARY_COPIES if card.rarity == "Legendary" else MAX_COPIES
		if int(counts[card_id]) > limit:
			errors.append("%s has %d copies (max %d)." % [card.card_name, int(counts[card_id]), limit])
	if factions.size() > 1:
		errors.append("A deck can only use one army's units (found %s)." % ", ".join(factions))
	return errors

static func composition(card_ids: Array) -> Dictionary:
	var result: Dictionary = {"units": 0, "tactics": 0, "equipment": 0}
	for card_id in card_ids:
		var card: CardData = CardCatalog.get_card(str(card_id))
		if card == null:
			continue
		match card.card_type:
			CardData.CardType.UNIT, CardData.CardType.PROMOTION:
				result["units"] = int(result["units"]) + 1
			CardData.CardType.TACTIC:
				result["tactics"] = int(result["tactics"]) + 1
			CardData.CardType.EQUIPMENT:
				result["equipment"] = int(result["equipment"]) + 1
	return result

# The recommended 22/10/8 split is advice, not a rule.
static func warnings(card_ids: Array) -> Array[String]:
	var result: Array[String] = []
	var parts: Dictionary = composition(card_ids)
	if int(parts["units"]) < 16 or int(parts["units"]) > 24 or int(parts["tactics"]) < 6 \
			or int(parts["tactics"]) > 16 or int(parts["equipment"]) < 4 or int(parts["equipment"]) > 10:
		result.append("Recommended mix is about %d units/promotions, %d tactics, %d equipment (you have %d / %d / %d)." % [
			RECOMMENDED_UNITS, RECOMMENDED_TACTICS, RECOMMENDED_EQUIPMENT,
			int(parts["units"]), int(parts["tactics"]), int(parts["equipment"]),
		])
	var has_unit: bool = false
	for card_id in card_ids:
		var card: CardData = CardCatalog.get_card(str(card_id))
		if card != null and card.card_type == CardData.CardType.UNIT:
			has_unit = true
			break
	if not has_unit:
		result.append("The deck has no unit cards to deploy.")
	return result

# ---- JSON storage: decks hold card ids and counts only ----

static func to_json(deck_name: String, card_ids: Array) -> String:
	return JSON.stringify({"version": 1, "name": deck_name, "cards": count_ids(card_ids)}, "\t")

# Returns {"name": String, "cards": Array[String]}, or an empty dictionary if the text is malformed.
static func from_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	if not data.get("cards") is Dictionary:
		return {}
	var counts: Dictionary = data["cards"]
	var keys: Array = counts.keys()
	keys.sort()
	var ids: Array[String] = []
	for key in keys:
		var count: Variant = counts[key]
		if not (count is float or count is int) or int(count) < 0 or int(count) > DECK_SIZE:
			return {}
		for _copy in range(int(count)):
			ids.append(str(key))
	return {"name": str(data.get("name", "")), "cards": ids}

static func sanitize_name(raw: String) -> String:
	var cleaned: String = ""
	for character in raw.strip_edges():
		if character.is_valid_identifier() or character == " " or character == "-" or character.is_valid_int():
			cleaned += character
	return cleaned.strip_edges()

static func _path(deck_name: String, dir: String) -> String:
	return "%s/%s.json" % [dir, sanitize_name(deck_name)]

static func save_deck(deck_name: String, card_ids: Array, dir: String = SAVE_DIR) -> Error:
	if sanitize_name(deck_name) == "":
		return ERR_INVALID_PARAMETER
	var made: Error = DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return made
	var file: FileAccess = FileAccess.open(_path(deck_name, dir), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json(sanitize_name(deck_name), card_ids))
	return OK

static func load_deck(deck_name: String, dir: String = SAVE_DIR) -> Dictionary:
	if sanitize_name(deck_name) == "" or not FileAccess.file_exists(_path(deck_name, dir)):
		return {}
	return from_json(FileAccess.get_file_as_string(_path(deck_name, dir)))

static func list_decks(dir: String = SAVE_DIR) -> Array[String]:
	var names: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return names
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(".json"):
			names.append(file_name.trim_suffix(".json"))
	names.sort()
	return names

static func delete_deck(deck_name: String, dir: String = SAVE_DIR) -> Error:
	if not FileAccess.file_exists(_path(deck_name, dir)):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(_path(deck_name, dir))

# The deck a seat will play: a saved legal deck by name, otherwise that seat's starter deck.
static func resolve(deck_name: String, player_id: int, dir: String = SAVE_DIR, army_id: String = "") -> Array[String]:
	if deck_name != "":
		var data: Dictionary = load_deck(deck_name, dir)
		if not data.is_empty():
			var ids: Array[String] = []
			ids.assign(data["cards"])
			if validate(ids).is_empty() and (army_id == "" or army_of(ids) in ["", army_id]):
				return ids
	return starter_ids(player_id, army_id)

# ---- Browsing ----

static func filter_cards(cards: Array[CardData], category: String, unit_class: String, weapon: String, search: String) -> Array[CardData]:
	var result: Array[CardData] = []
	var needle: String = search.strip_edges().to_lower()
	for card in cards:
		if category != "All" and card.type_label() != category:
			continue
		if unit_class != "All":
			var class_match: bool = card.unit_class == unit_class
			if card.card_type == CardData.CardType.PROMOTION and card.promotes_from == unit_class:
				class_match = true
			if card.card_type == CardData.CardType.TACTIC or card.card_type == CardData.CardType.EQUIPMENT:
				class_match = false
			if not class_match:
				continue
		if weapon != "All":
			var weapon_match: bool = false
			if card.is_unit_like():
				weapon_match = CardData.weapon_name(card.weapon_type) == weapon
			elif card.card_type == CardData.CardType.EQUIPMENT:
				for allowed in card.allowed_weapons:
					if CardData.weapon_name(allowed as CardData.WeaponType) == weapon:
						weapon_match = true
			if not weapon_match:
				continue
		if needle != "" and not card.card_name.to_lower().contains(needle):
			continue
		result.append(card)
	return result

static func class_options() -> Array[String]:
	var options: Array[String] = []
	for card in CardCatalog.get_all_cards():
		if card.card_type == CardData.CardType.UNIT or card.card_type == CardData.CardType.PROMOTION:
			if not options.has(card.unit_class):
				options.append(card.unit_class)
	options.sort()
	return options

class_name SupportData
extends RefCounted

# Predefined support pairs, by unit card id.
const PAIRS: Array = [
	["iron_guard", "stonewall"],
	["oakblade", "ridge_scout"],
	["lancer", "field_medic"],
	["ash_reaver", "ember_mage"],
	["swiftblade", "gale_rider"],
	["hawkeye", "dune_cavalier"],
]

static func are_partners(card_a: String, card_b: String) -> bool:
	for pair: Array in PAIRS:
		if (pair[0] == card_a and pair[1] == card_b) or (pair[0] == card_b and pair[1] == card_a):
			return true
	return false

static func partner_ids(card_id: String) -> Array[String]:
	var result: Array[String] = []
	for pair: Array in PAIRS:
		if pair[0] == card_id:
			result.append(str(pair[1]))
		elif pair[1] == card_id:
			result.append(str(pair[0]))
	return result

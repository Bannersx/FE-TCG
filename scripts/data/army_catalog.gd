class_name ArmyCatalog
extends RefCounted

const IRONCREST_ID: String = "ironcrest"
const ASHEN_ID: String = "ashen"
const VERDANT_ID: String = "verdant"
const ARMY_IDS: Array[String] = [IRONCREST_ID, ASHEN_ID, VERDANT_ID]
const SEAT_DEFAULTS: Array[String] = [IRONCREST_ID, ASHEN_ID]

const ARMIES: Dictionary = {
	IRONCREST_ID: {
		"name": "Ironcrest Bulwark", "faction": "Ironcrest Order", "archetype": "Control",
		"summary": "Stone and frost. Shield Wall (+1 DEF beside an ally), Chill slows and unseats enemies.",
		"commander": "Captain Maren", "weapon": CardData.WeaponType.SWORD,
		"passive": "Units standing on objectives gain +1 DEF.",
	},
	ASHEN_ID: {
		"name": "Ashen Legion", "faction": "Ashen Vanguard", "archetype": "Aggro",
		"summary": "Fire and speed. Momentum (+1 ATK after moving 2+ tiles), Burn damages over time.",
		"commander": "Warden Tarek", "weapon": CardData.WeaponType.AXE,
		"passive": "The first unit you deploy each turn can act immediately.",
	},
	VERDANT_ID: {
		"name": "Verdant Circle", "faction": "Verdant Circle", "archetype": "Combo",
		"summary": "Nature. Sow Seeds that bloom, build Chain with tactics for +ATK, Forestwalkers.",
		"commander": "Elder Sylra", "weapon": CardData.WeaponType.MAGIC,
		"passive": "Your first tactic each turn costs 1 less supply.",
	},
}

const DECKS: Dictionary = {
	IRONCREST_ID: {
		"iron_guard": 3, "stonewall": 3, "field_medic": 2, "frost_sentinel": 3, "oakblade": 2, "ridge_scout": 2, "lancer": 2,
		"promo_hero": 2, "promo_general": 2, "promo_sage": 1,
		"frostbind": 3, "stoneskin": 2, "fortify": 2, "heal": 2, "tactical_retreat": 1,
		"defensive_shield": 3, "iron_sword": 2, "magic_ring": 1, "longbow": 1, "steel_axe": 1,
	},
	ASHEN_ID: {
		"ash_reaver": 3, "gale_rider": 2, "ember_mage": 3, "swiftblade": 3, "hawkeye": 2, "dune_cavalier": 2, "cinder_scout": 3,
		"promo_swordmaster": 2, "promo_paladin": 1, "promo_sage": 1,
		"scorch": 3, "surge": 3, "rally": 2, "precision_strike": 2,
		"steel_axe": 3, "iron_sword": 2, "magic_ring": 2, "longbow": 1,
	},
	VERDANT_ID: {
		"bramble_warden": 3, "sapling_scout": 2, "grove_druid": 3, "vine_lancer": 2, "thornblade": 3, "moss_giant": 2,
		"promo_hero": 1, "promo_sage": 2, "promo_paladin": 1,
		"sow": 3, "entangle": 2, "thornlash": 2, "rally": 2, "heal": 2, "fortify": 1, "reposition": 2, "tactical_retreat": 1,
		"defensive_shield": 2, "magic_ring": 2, "iron_sword": 1, "longbow": 1,
	},
}

static func is_army(army_id: String) -> bool:
	return ARMIES.has(army_id)

static func army_name(army_id: String) -> String:
	return str(ARMIES[army_id]["name"]) if ARMIES.has(army_id) else army_id

static func default_army(seat: int) -> String:
	return SEAT_DEFAULTS[seat % SEAT_DEFAULTS.size()]

static func army_of_faction(faction: String) -> String:
	for army_id: String in ARMY_IDS:
		if ARMIES[army_id]["faction"] == faction:
			return army_id
	return ""

static func starter_card_ids(army_id: String) -> Array[String]:
	var ids: Array[String] = []
	var list: Dictionary = DECKS.get(army_id, DECKS[IRONCREST_ID])
	for card_id: String in list:
		for _copy in range(int(list[card_id])):
			ids.append(card_id)
	return ids

static func get_commander(army_id: String, seat: int) -> CardData:
	var info: Dictionary = ARMIES.get(army_id, ARMIES[default_army(seat)])
	var commander := CardData.new()
	commander.card_id = "commander_%s" % army_id
	commander.card_name = str(info["commander"])
	commander.card_type = CardData.CardType.COMMANDER
	commander.unit_class = "Commander"
	commander.weapon_type = info["weapon"]
	commander.max_hp = 12
	commander.attack = 3
	commander.defense = 2
	commander.speed = 3
	commander.movement = 2
	commander.attack_range = 2 if army_id == VERDANT_ID else 1
	commander.supply_cost = 0
	commander.faction = str(info["faction"])
	commander.rarity = "Commander"
	commander.ability_text = "Defeat eliminates its player. Passive: %s" % info["passive"]
	return commander

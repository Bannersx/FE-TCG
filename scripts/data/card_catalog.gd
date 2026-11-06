class_name CardCatalog
extends RefCounted

const IRONCREST: String = "Ironcrest Order"
const ASHEN: String = "Ashen Vanguard"
const VERDANT: String = "Verdant Circle"

static func get_unit_cards() -> Array[CardData]:
	var sword := CardData.WeaponType.SWORD
	var lance := CardData.WeaponType.LANCE
	var axe := CardData.WeaponType.AXE
	var bow := CardData.WeaponType.BOW
	var magic := CardData.WeaponType.MAGIC
	var result: Array[CardData] = []
	result.append(_unit("iron_guard", "Iron Guard", lance, "Vanguard", 7, 2, 2, 1, 2, 1, 1, IRONCREST))
	result.append(_unit("ridge_scout", "Ridge Scout", bow, "Ranger", 5, 2, 1, 4, 3, 2, 2, IRONCREST))
	result.append(_unit("oakblade", "Oakblade", sword, "Mercenary", 5, 3, 1, 4, 3, 1, 2, IRONCREST))
	result.append(_unit("stonewall", "Stonewall", axe, "Armored Knight", 8, 3, 3, 1, 2, 1, 3, IRONCREST))
	result.append(_unit("field_medic", "Field Medic", magic, "Mage", 5, 2, 1, 3, 2, 2, 2, IRONCREST))
	result.append(_unit("lancer", "Northwind Lancer", lance, "Cavalier", 6, 3, 1, 3, 3, 1, 3, IRONCREST))
	result.append(_unit("ash_reaver", "Ash Reaver", axe, "Reaver", 6, 4, 1, 2, 2, 1, 1, ASHEN))
	result.append(_unit("gale_rider", "Gale Rider", sword, "Sky Knight", 5, 2, 1, 4, 3, 1, 3, ASHEN, CardData.MovementType.FLYING))
	result.append(_unit("ember_mage", "Ember Mage", magic, "Mage", 4, 4, 0, 3, 2, 2, 2, ASHEN))
	result.append(_unit("swiftblade", "Swiftblade", sword, "Myrmidon", 5, 2, 1, 6, 3, 1, 2, ASHEN))
	result.append(_unit("hawkeye", "Hawkeye", bow, "Archer", 5, 3, 1, 3, 2, 2, 2, ASHEN))
	result.append(_unit("dune_cavalier", "Dune Cavalier", lance, "Cavalier", 6, 3, 1, 3, 3, 1, 3, ASHEN))
	result.append(_status_unit(_unit("cinder_scout", "Cinder Scout", bow, "Ranger", 4, 2, 0, 4, 3, 2, 2, ASHEN), "burn", 2, "Burn"))
	result.append(_status_unit(_unit("frost_sentinel", "Frost Sentinel", magic, "Mage", 5, 2, 1, 2, 2, 2, 2, IRONCREST), "chill", 1, "Chill"))
	result.append(_unit("bramble_warden", "Bramble Warden", axe, "Warden", 6, 2, 2, 2, 2, 1, 1, VERDANT))
	result.append(_unit("sapling_scout", "Sapling Scout", bow, "Ranger", 4, 2, 0, 4, 3, 2, 2, VERDANT))
	result.append(_unit("grove_druid", "Grove Druid", magic, "Mage", 5, 3, 0, 3, 2, 2, 2, VERDANT))
	result.append(_unit("vine_lancer", "Vine Lancer", lance, "Cavalier", 6, 2, 1, 3, 3, 1, 3, VERDANT))
	result.append(_unit("thornblade", "Thornblade", sword, "Mercenary", 5, 2, 1, 4, 3, 1, 2, VERDANT))
	result.append(_unit("moss_giant", "Moss Giant", axe, "Armored Knight", 8, 2, 2, 1, 1, 1, 3, VERDANT))
	return result

static func _status_unit(card: CardData, status: String, turns: int, label: String) -> CardData:
	card.on_hit_status = status
	card.status_turns = turns
	card.ability_text = "%s: a hit leaves the target with %s for %d turn(s)." % [label, label, turns]
	return card

static func get_promotion_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	result.append(_promotion("promo_hero", "Hero", "Mercenary", 3, 2, 1, 1, 0))
	result.append(_promotion("promo_swordmaster", "Swordmaster", "Myrmidon", 2, 1, 0, 2, 1))
	result.append(_promotion("promo_paladin", "Paladin", "Cavalier", 3, 1, 1, 0, 1))
	result.append(_promotion("promo_sage", "Sage", "Mage", 2, 2, 0, 1, 0))
	result.append(_promotion("promo_general", "General", "Armored Knight", 4, 1, 2, 0, 0))
	return result

static func get_equipment_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	result.append(_equipment("iron_sword", "Iron Sword", "weapon", 1, [CardData.WeaponType.SWORD], 1, 0, 0, 0, "Sword wielders only. +1 ATK."))
	result.append(_equipment("steel_axe", "Steel Axe", "weapon", 2, [CardData.WeaponType.AXE], 2, 0, 0, 0, "Axe wielders only. +2 ATK."))
	result.append(_equipment("defensive_shield", "Defensive Shield", "accessory", 1, [], 0, 1, 0, 0, "Any unit. +1 DEF."))
	result.append(_equipment("longbow", "Longbow", "weapon", 2, [CardData.WeaponType.BOW], 1, 0, 0, 1, "Bow wielders only. +1 ATK, +1 RNG."))
	result.append(_equipment("magic_ring", "Magic Ring", "accessory", 2, [CardData.WeaponType.MAGIC], 2, 0, 0, 0, "Magic users only. +2 ATK."))
	return result

static func get_tactic_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	result.append(_tactic("rally", "Rally", 1, "buff", 2, "friendly_unit", "Target ally gains +2 ATK this turn.", "attack", "end_of_turn"))
	result.append(_tactic("heal", "Heal", 2, "heal", 4, "friendly_unit", "Restore 4 HP to a damaged ally."))
	result.append(_tactic("reposition", "Reposition", 1, "reposition", 2, "friendly_unit_tile", "Move an ally up to 2 tiles to an empty tile."))
	result.append(_tactic("fortify", "Fortify", 1, "buff", 2, "friendly_unit", "Target ally gains +2 DEF until your next turn.", "defense", "until_next_turn"))
	result.append(_tactic("precision_strike", "Precision Strike", 3, "damage", 3, "enemy_unit", "Deal 3 damage to an enemy unit, ignoring DEF."))
	result.append(_tactic("tactical_retreat", "Tactical Retreat", 1, "retreat", 0, "friendly_unit_tile", "Move an ally to an empty tile in your deployment column."))
	result.append(_status_tactic(_tactic("scorch", "Scorch", 2, "burn", 2, "enemy_unit", "Deal 2 damage ignoring DEF and set the target ablaze (1 damage at the start of its owner's turn, 2 turns)."), 2))
	result.append(_tactic("surge", "Surge", 1, "buff", 2, "friendly_unit", "Target ally gains +2 MOV this turn.", "movement", "end_of_turn"))
	result.append(_status_tactic(_tactic("frostbind", "Frostbind", 1, "chill", 0, "enemy_unit", "Chill an enemy: -1 MOV and it cannot hold objectives until the end of its next turn."), 1))
	result.append(_tactic("stoneskin", "Stoneskin", 2, "buff", 3, "friendly_unit", "Target ally gains +3 DEF until your next turn.", "defense", "until_next_turn"))
	result.append(_tactic("sow", "Sow Seed", 1, "sow", 0, "friendly_unit", "Plant a seed under an ally. It blooms at the start of your turn if an ally stands there: heal 2 and +1 Chain."))
	result.append(_tactic("entangle", "Entangle", 1, "buff", -2, "enemy_unit", "Target enemy suffers -2 MOV this turn.", "movement", "end_of_turn"))
	result.append(_tactic("thornlash", "Thorn Lash", 2, "damage", 2, "enemy_unit", "Deal 2 damage to an enemy unit, ignoring DEF."))
	return result

static func _status_tactic(card: CardData, turns: int) -> CardData:
	card.status_turns = turns
	return card

static func get_all_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	result.append_array(get_unit_cards())
	result.append_array(get_promotion_cards())
	result.append_array(get_equipment_cards())
	result.append_array(get_tactic_cards())
	return result

static func get_card(card_id: String) -> CardData:
	for card in get_all_cards():
		if card.card_id == card_id:
			return card
	return null

static func get_commander(player_id: int, army_id: String = "") -> CardData:
	if army_id == "":
		army_id = ArmyCatalog.default_army(player_id)
	return ArmyCatalog.get_commander(army_id, player_id)

static func make_starter_deck(player_id: int, army_id: String = "") -> Array[CardData]:
	if army_id == "":
		army_id = ArmyCatalog.default_army(player_id)
	return deck_from_ids(ArmyCatalog.starter_card_ids(army_id))

# Builds fresh deck contents from card ids; unknown ids are skipped.
static func deck_from_ids(card_ids: Array) -> Array[CardData]:
	var lookup: Dictionary = {}
	for card in get_all_cards():
		lookup[card.card_id] = card
	var deck: Array[CardData] = []
	for card_id in card_ids:
		if lookup.has(str(card_id)):
			deck.append(lookup[str(card_id)])
	return deck

static func _unit(
	card_id: String, card_name: String, weapon: CardData.WeaponType, unit_class: String,
	hp: int, attack: int, defense: int, speed: int, movement: int, attack_range: int,
	cost: int, faction: String, movement_type: CardData.MovementType = CardData.MovementType.GROUND
) -> CardData:
	var card := CardData.new()
	card.card_id = card_id
	card.card_name = card_name
	card.card_type = CardData.CardType.UNIT
	card.unit_class = unit_class
	card.weapon_type = weapon
	card.movement_type = movement_type
	card.max_hp = hp
	card.attack = attack
	card.defense = defense
	card.speed = speed
	card.movement = movement
	card.attack_range = attack_range
	card.supply_cost = cost
	card.faction = faction
	card.rarity = "Common"
	return card

static func _promotion(
	card_id: String, card_name: String, from_class: String,
	hp: int, atk: int, def: int, spd: int, mov: int
) -> CardData:
	var card := CardData.new()
	card.card_id = card_id
	card.card_name = card_name
	card.card_type = CardData.CardType.PROMOTION
	card.supply_cost = 2
	card.promotes_from = from_class
	card.promotes_to = card_name
	card.bonus_hp = hp
	card.bonus_atk = atk
	card.bonus_def = def
	card.bonus_spd = spd
	card.bonus_mov = mov
	card.rarity = "Rare"
	card.unit_class = card_name
	card.ability_text = "Promote a %s: +%d HP, +%d ATK, +%d DEF, +%d SPD, +%d MOV." % [from_class, hp, atk, def, spd, mov]
	return card

static func _equipment(
	card_id: String, card_name: String, slot: String, cost: int, weapons: Array,
	atk: int, def: int, spd: int, rng: int, text: String
) -> CardData:
	var card := CardData.new()
	card.card_id = card_id
	card.card_name = card_name
	card.card_type = CardData.CardType.EQUIPMENT
	card.equip_slot = slot
	card.supply_cost = cost
	card.allowed_weapons.assign(weapons)
	card.bonus_atk = atk
	card.bonus_def = def
	card.bonus_spd = spd
	card.bonus_rng = rng
	card.ability_text = text
	return card

static func _tactic(
	card_id: String, card_name: String, cost: int, effect: String, magnitude: int,
	target_kind: String, text: String, stat: String = "", duration: String = ""
) -> CardData:
	var card := CardData.new()
	card.card_id = card_id
	card.card_name = card_name
	card.card_type = CardData.CardType.TACTIC
	card.supply_cost = cost
	card.tactic_effect = effect
	card.magnitude = magnitude
	card.target_kind = target_kind
	card.buff_stat = stat
	card.duration = duration
	card.ability_text = text
	return card

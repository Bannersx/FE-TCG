class_name CardData
extends Resource

enum CardType { UNIT, COMMANDER, EQUIPMENT, TACTIC, PROMOTION }
enum WeaponType { SWORD, LANCE, AXE, BOW, MAGIC }
enum MovementType { GROUND, FLYING }

@export var card_id: String = ""
@export var card_name: String = ""
@export var card_type: CardType = CardType.UNIT
@export var unit_class: String = "Infantry"
@export var weapon_type: WeaponType = WeaponType.SWORD
@export var movement_type: MovementType = MovementType.GROUND
@export var max_hp: int = 5
@export var attack: int = 2
@export var defense: int = 1
@export var speed: int = 2
@export var movement: int = 2
@export var attack_range: int = 1
@export var supply_cost: int = 1
@export var faction: String = "Free Companies"
@export var rarity: String = "Common"
@export_multiline var ability_text: String = ""

# Stat modifiers granted by equipment and promotion cards.
@export var equip_slot: String = ""
@export var allowed_weapons: Array[int] = []
@export var bonus_hp: int = 0
@export var bonus_atk: int = 0
@export var bonus_def: int = 0
@export var bonus_spd: int = 0
@export var bonus_mov: int = 0
@export var bonus_rng: int = 0
@export var promotes_from: String = ""
@export var promotes_to: String = ""

# Data-driven tactic definition resolved by AbilityResolver.
@export var tactic_effect: String = ""
@export var magnitude: int = 0
@export var target_kind: String = ""
@export var buff_stat: String = ""
@export var duration: String = ""

# Status applied by a unit's hits ("burn", "chill") or by a status tactic, and how many turns it lasts.
@export var on_hit_status: String = ""
@export var status_turns: int = 0

static func weapon_name(weapon: WeaponType) -> String:
	match weapon:
		WeaponType.SWORD:
			return "Sword"
		WeaponType.LANCE:
			return "Lance"
		WeaponType.AXE:
			return "Axe"
		WeaponType.BOW:
			return "Bow"
		WeaponType.MAGIC:
			return "Magic"
	return "Unknown"

func type_label() -> String:
	match card_type:
		CardType.UNIT:
			return "Unit"
		CardType.COMMANDER:
			return "Commander"
		CardType.EQUIPMENT:
			return "Equipment"
		CardType.TACTIC:
			return "Tactic"
		CardType.PROMOTION:
			return "Promotion"
	return "Card"

func is_unit_like() -> bool:
	return card_type == CardType.UNIT or card_type == CardType.COMMANDER

func summary() -> String:
	if is_unit_like():
		return "%s · %s\nATK %d  DEF %d  SPD %d\nMOV %d  RNG %d  HP %d\nSupply %d" % [
			unit_class, weapon_name(weapon_type), attack, defense, speed, movement, attack_range, max_hp, supply_cost
		]
	return "%s\nSupply %d" % [ability_text, supply_cost]

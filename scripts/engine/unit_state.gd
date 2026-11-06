class_name UnitState
extends RefCounted

var instance_id: String = ""
var card: CardData
var owner_id: int = -1
var position: Vector2i = Vector2i(-1, -1)
var current_hp: int = 1
var exhausted: bool = false
var deployed_turn: int = -1
var promotion: CardData
var weapon_item: CardData
var accessory_item: CardData
var mods: Array[Dictionary] = []
# Status name ("burn", "chill") -> turns remaining.
var statuses: Dictionary = {}

var is_commander: bool:
	get:
		return card != null and card.card_type == CardData.CardType.COMMANDER

func initialize(new_id: String, definition: CardData, owner: int, tile: Vector2i, turn_number: int) -> void:
	instance_id = new_id
	card = definition
	owner_id = owner
	position = tile
	current_hp = definition.max_hp
	deployed_turn = turn_number

func max_hp() -> int:
	return card.max_hp + _bonus("hp")

func attack() -> int:
	return card.attack + _bonus("atk") + _mod("attack")

func defense() -> int:
	return card.defense + _bonus("def") + _mod("defense")

func speed() -> int:
	return card.speed + _bonus("spd") + _mod("speed")

func movement() -> int:
	var slowed: int = 1 if has_status("chill") else 0
	return maxi(0, card.movement + _bonus("mov") + _mod("movement") - slowed)

func has_status(status: String) -> bool:
	return int(statuses.get(status, 0)) > 0

func apply_status(status: String, turns: int) -> void:
	statuses[status] = maxi(int(statuses.get(status, 0)), turns)

func describe_statuses() -> String:
	var parts: PackedStringArray = []
	for status: String in statuses:
		parts.append("%s (%d)" % [status.capitalize(), int(statuses[status])])
	return ", ".join(parts)

func attack_range() -> int:
	return card.attack_range + _bonus("rng")

func weapon_type() -> CardData.WeaponType:
	return card.weapon_type

func unit_class() -> String:
	return promotion.promotes_to if promotion != null else card.unit_class

func display_name() -> String:
	if promotion != null:
		return "%s (%s)" % [card.card_name, promotion.promotes_to]
	return card.card_name

func item_in_slot(slot: String) -> CardData:
	return weapon_item if slot == "weapon" else accessory_item

func set_item(slot: String, item: CardData) -> void:
	if slot == "weapon":
		weapon_item = item
	else:
		accessory_item = item

func equipment_items() -> Array[CardData]:
	var items: Array[CardData] = []
	if weapon_item != null:
		items.append(weapon_item)
	if accessory_item != null:
		items.append(accessory_item)
	return items

func expire_mods(duration: String) -> void:
	var kept: Array[Dictionary] = []
	for mod in mods:
		if str(mod["expires"]) != duration:
			kept.append(mod)
	mods = kept

func describe_mods() -> String:
	var parts: PackedStringArray = []
	for mod in mods:
		parts.append("%+d %s" % [int(mod["amount"]), str(mod["stat"])])
	return ", ".join(parts)

func _bonus(stat: String) -> int:
	var total: int = 0
	for source: CardData in [promotion, weapon_item, accessory_item]:
		if source != null:
			total += int(source.get("bonus_" + stat))
	return total

func _mod(stat: String) -> int:
	var total: int = 0
	for mod in mods:
		if str(mod["stat"]) == stat:
			total += int(mod["amount"])
	return total

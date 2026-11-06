class_name CardInspector
extends PanelContainer

const TYPE_COLORS: Dictionary = {
	CardData.CardType.UNIT: Color(0.30, 0.45, 0.70),
	CardData.CardType.COMMANDER: Color(0.75, 0.60, 0.20),
	CardData.CardType.EQUIPMENT: Color(0.45, 0.55, 0.35),
	CardData.CardType.TACTIC: Color(0.65, 0.35, 0.55),
	CardData.CardType.PROMOTION: Color(0.80, 0.50, 0.20),
}

var artwork: ColorRect
var art_label: Label
var title_label: Label
var subtitle_label: Label
var body_label: Label

func _init() -> void:
	custom_minimum_size = Vector2(0, 250)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	artwork = ColorRect.new()
	artwork.custom_minimum_size = Vector2(120, 0)
	box.add_child(artwork)
	art_label = Label.new()
	art_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	art_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art_label.add_theme_font_size_override("font_size", 64)
	artwork.add_child(art_label)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text_box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.add_theme_font_size_override("font_size", 13)
	subtitle_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	text_box.add_child(subtitle_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 14)
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.add_child(body_label)
	clear()

func clear() -> void:
	artwork.color = Color(0.2, 0.2, 0.25)
	art_label.text = "?"
	title_label.text = "Card inspector"
	subtitle_label.text = ""
	body_label.text = "Hover over a card or unit to inspect it."

# Shows a card. If a unit and match state are given, live stats, equipment and bonds are shown too.
func show_card(card: CardData, unit: UnitState = null, state: GameState = null) -> void:
	if card == null:
		clear()
		return
	artwork.color = TYPE_COLORS.get(card.card_type, Color.GRAY)
	art_label.text = card.card_name.substr(0, 1)
	title_label.text = card.card_name if unit == null else unit.display_name()
	var supply: String = "" if card.card_type == CardData.CardType.COMMANDER else " | Supply %d" % card.supply_cost
	subtitle_label.text = "%s | %s | %s%s" % [card.type_label(), card.faction, card.rarity, supply]
	var lines: PackedStringArray = []
	if card.is_unit_like():
		lines.append_array(_unit_lines(card, unit, state))
	elif card.card_type == CardData.CardType.EQUIPMENT:
		lines.append("Slot: %s" % card.equip_slot.capitalize())
		lines.append("Usable by: %s" % _allowed_text(card))
		lines.append(card.ability_text)
	elif card.card_type == CardData.CardType.PROMOTION:
		lines.append("Promotes: %s -> %s" % [card.promotes_from, card.promotes_to])
		lines.append(card.ability_text)
		lines.append("Unit must have been deployed on an earlier turn.")
	else:
		lines.append(card.ability_text)
		lines.append("Target: %s" % card.target_kind.replace("_", " "))
	body_label.text = "\n".join(lines)

func _allowed_text(card: CardData) -> String:
	if card.allowed_weapons.is_empty():
		return "any unit"
	var names: PackedStringArray = []
	for weapon in card.allowed_weapons:
		names.append(CardData.weapon_name(weapon as CardData.WeaponType))
	return ", ".join(names)

func _unit_lines(card: CardData, unit: UnitState, state: GameState) -> PackedStringArray:
	var lines: PackedStringArray = []
	if unit != null:
		lines.append("%s | %s" % [unit.unit_class(), CardData.weapon_name(unit.weapon_type())])
		lines.append("HP %d/%d  ATK %d  DEF %d  SPD %d" % [unit.current_hp, unit.max_hp(), unit.attack(), unit.defense(), unit.speed()])
		lines.append("MOV %d  RNG %d  %s" % [unit.movement(), unit.attack_range(), "Flying" if card.movement_type == CardData.MovementType.FLYING else "Ground"])
		if state != null:
			lines.append("Terrain: %s (+%d DEF)" % [state.board.terrain_at(unit.position), state.board.defense_bonus(unit.position)])
		var weapon_name: String = unit.weapon_item.card_name if unit.weapon_item != null else "none"
		var accessory_name: String = unit.accessory_item.card_name if unit.accessory_item != null else "none"
		lines.append("Weapon: %s | Accessory: %s" % [weapon_name, accessory_name])
		if not unit.mods.is_empty():
			lines.append("Effects: %s" % unit.describe_mods())
		if not unit.statuses.is_empty():
			lines.append("Status: %s" % unit.describe_statuses())
		if state != null:
			var bonus_atk: int = FactionRules.attack_bonus(state, unit)
			var bonus_def: int = FactionRules.defense_bonus(state, unit)
			if bonus_atk != 0 or bonus_def != 0:
				lines.append("Army bonus: +%d ATK, +%d DEF" % [bonus_atk, bonus_def])
			if state.seeds.has(unit.position):
				lines.append("A seed is planted here.")
		if state != null:
			var bonds: String = SupportResolver.describe(state, unit)
			if bonds != "":
				lines.append("Bonds: %s" % bonds)
		if unit.exhausted:
			lines.append("Has acted this turn.")
	else:
		lines.append("%s | %s" % [card.unit_class, CardData.weapon_name(card.weapon_type)])
		lines.append("HP %d  ATK %d  DEF %d  SPD %d" % [card.max_hp, card.attack, card.defense, card.speed])
		lines.append("MOV %d  RNG %d  %s" % [card.movement, card.attack_range, "Flying" if card.movement_type == CardData.MovementType.FLYING else "Ground"])
	if card.ability_text != "":
		lines.append(card.ability_text)
	var partners: PackedStringArray = []
	for partner_id in SupportData.partner_ids(card.card_id):
		var partner: CardData = CardCatalog.get_card(partner_id)
		if partner != null:
			partners.append(partner.card_name)
	if not partners.is_empty():
		lines.append("Support partner: %s" % ", ".join(partners))
	return lines

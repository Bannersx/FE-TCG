extends Control

const MAIN_MENU: String = "res://scenes/main/main_menu.tscn"

var deck: Array[String] = []
var collection: Array[CardData] = []
var category_filter: OptionButton
var class_filter: OptionButton
var weapon_filter: OptionButton
var search_box: LineEdit
var collection_box: VBoxContainer
var deck_box: VBoxContainer
var count_label: Label
var status_label: Label
var name_box: LineEdit
var saved_picker: OptionButton
var inspector: CardInspector

func _ready() -> void:
	collection = CardCatalog.get_all_cards()
	_build_ui()
	_load_starter(ArmyCatalog.IRONCREST_ID)
	_refresh_saved_list()

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.10, 0.14)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	root.add_child(left)
	left.add_child(_title("Card collection (click to add)"))
	var filters := HFlowContainer.new()
	left.add_child(filters)
	category_filter = _option(filters, "Category", ["All", "Unit", "Promotion", "Equipment", "Tactic"])
	var classes: Array[String] = ["All"]
	classes.append_array(DeckData.class_options())
	class_filter = _option(filters, "Class", classes)
	var weapons: Array[String] = ["All"]
	for weapon in CardData.WeaponType.values():
		weapons.append(CardData.weapon_name(weapon as CardData.WeaponType))
	weapon_filter = _option(filters, "Weapon", weapons)
	search_box = LineEdit.new()
	search_box.placeholder_text = "Search by name"
	search_box.custom_minimum_size = Vector2(180, 0)
	search_box.text_changed.connect(func(_text: String) -> void: _refresh_collection())
	filters.add_child(search_box)
	var collection_scroll := ScrollContainer.new()
	collection_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(collection_scroll)
	collection_box = VBoxContainer.new()
	collection_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_scroll.add_child(collection_box)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(middle)
	count_label = _title("")
	middle.add_child(count_label)
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(deck_scroll)
	deck_box = VBoxContainer.new()
	deck_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_scroll.add_child(deck_box)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(520, 0)
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	inspector = CardInspector.new()
	right.add_child(inspector)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(status_label)
	name_box = LineEdit.new()
	name_box.placeholder_text = "Deck name"
	name_box.text = "My Deck"
	right.add_child(name_box)
	var save_row := HBoxContainer.new()
	right.add_child(save_row)
	_button(save_row, "Save", _on_save)
	_button(save_row, "Clear", func() -> void: _set_deck([]))
	_button(save_row, "Ironcrest", _load_starter.bind(ArmyCatalog.IRONCREST_ID))
	_button(save_row, "Ashen", _load_starter.bind(ArmyCatalog.ASHEN_ID))
	_button(save_row, "Verdant", _load_starter.bind(ArmyCatalog.VERDANT_ID))
	saved_picker = OptionButton.new()
	right.add_child(saved_picker)
	var load_row := HBoxContainer.new()
	right.add_child(load_row)
	_button(load_row, "Load saved", _on_load)
	_button(load_row, "Delete saved", _on_delete)
	_button(load_row, "Back to menu", func() -> void: get_tree().change_scene_to_file(MAIN_MENU))

func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	return label

func _option(parent: Control, caption: String, items: Array[String]) -> OptionButton:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.item_selected.connect(func(_index: int) -> void: _refresh_collection())
	parent.add_child(option)
	return option

func _button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)

# ---- Deck editing (also usable without the UI) ----

func add_card(card_id: String) -> bool:
	var card: CardData = CardCatalog.get_card(card_id)
	if card == null:
		return false
	if deck.size() >= DeckData.DECK_SIZE:
		status_label.text = "The deck is full (%d cards)." % DeckData.DECK_SIZE
		return false
	var limit: int = DeckData.MAX_LEGENDARY_COPIES if card.rarity == "Legendary" else DeckData.MAX_COPIES
	if int(DeckData.count_ids(deck).get(card_id, 0)) >= limit:
		status_label.text = "%s is limited to %d copies." % [card.card_name, limit]
		return false
	var card_army: String = ArmyCatalog.army_of_faction(card.faction)
	var deck_army: String = DeckData.army_of(deck)
	if card_army != "" and deck_army != "" and card_army != deck_army:
		status_label.text = "%s belongs to %s; this deck is %s." % [card.card_name, ArmyCatalog.army_name(card_army), ArmyCatalog.army_name(deck_army)]
		return false
	deck.append(card_id)
	_refresh_all()
	return true

func remove_card(card_id: String) -> bool:
	var index: int = deck.find(card_id)
	if index < 0:
		return false
	deck.remove_at(index)
	_refresh_all()
	return true

func _set_deck(ids: Array[String]) -> void:
	deck = ids
	_refresh_all()

func _load_starter(army_id: String) -> void:
	name_box.text = ArmyCatalog.army_name(army_id)
	_set_deck(DeckData.starter_ids(0, army_id))

# ---- Rendering ----

func _refresh_all() -> void:
	_refresh_collection()
	_refresh_deck()
	_refresh_status()

func _refresh_collection() -> void:
	for child in collection_box.get_children():
		child.queue_free()
	var counts: Dictionary = DeckData.count_ids(deck)
	var shown: Array[CardData] = DeckData.filter_cards(
		collection,
		category_filter.get_item_text(category_filter.selected),
		class_filter.get_item_text(class_filter.selected),
		weapon_filter.get_item_text(weapon_filter.selected),
		search_box.text
	)
	for card in shown:
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = "%s  [%d]  %s  -  in deck: %d" % [card.card_name, card.supply_cost, card.type_label(), int(counts.get(card.card_id, 0))]
		row.pressed.connect(add_card.bind(card.card_id))
		row.mouse_entered.connect(inspector.show_card.bind(card))
		collection_box.add_child(row)

func _refresh_deck() -> void:
	for child in deck_box.get_children():
		child.queue_free()
	var counts: Dictionary = DeckData.count_ids(deck)
	var rows: Array[CardData] = []
	for card_id: String in counts:
		var card: CardData = CardCatalog.get_card(card_id)
		if card != null:
			rows.append(card)
	rows.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.card_type != b.card_type:
			return a.card_type < b.card_type
		return a.card_name < b.card_name)
	for card in rows:
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = "%dx  %s  [%d]  (click to remove one)" % [int(counts[card.card_id]), card.card_name, card.supply_cost]
		row.pressed.connect(remove_card.bind(card.card_id))
		row.mouse_entered.connect(inspector.show_card.bind(card))
		deck_box.add_child(row)

func _refresh_status() -> void:
	var parts: Dictionary = DeckData.composition(deck)
	count_label.text = "Deck: %d / %d cards  (units %d, tactics %d, equipment %d)" % [
		deck.size(), DeckData.DECK_SIZE, int(parts["units"]), int(parts["tactics"]), int(parts["equipment"])
	]
	var errors: Array[String] = DeckData.validate(deck)
	var lines: PackedStringArray = []
	if errors.is_empty():
		lines.append("Deck is legal.")
	else:
		lines.append("Deck is NOT legal:")
		for error in errors:
			lines.append("- " + error)
	for warning in DeckData.warnings(deck):
		lines.append("Note: " + warning)
	status_label.text = "\n".join(lines)

# ---- Saving ----

func _refresh_saved_list() -> void:
	saved_picker.clear()
	for deck_name in DeckData.list_decks():
		saved_picker.add_item(deck_name)

func _on_save() -> void:
	var errors: Array[String] = DeckData.validate(deck)
	if not errors.is_empty():
		status_label.text = "Only legal decks can be saved.\n" + "\n".join(errors)
		return
	var result: Error = DeckData.save_deck(name_box.text, deck)
	if result != OK:
		status_label.text = "Could not save the deck (error %d). Give it a name using letters or numbers." % result
		return
	_refresh_saved_list()
	_refresh_status()
	status_label.text = "Saved '%s'.\n%s" % [DeckData.sanitize_name(name_box.text), status_label.text]

func _on_load() -> void:
	if saved_picker.item_count == 0:
		status_label.text = "There are no saved decks yet."
		return
	var deck_name: String = saved_picker.get_item_text(saved_picker.selected)
	var data: Dictionary = DeckData.load_deck(deck_name)
	if data.is_empty():
		status_label.text = "Could not read '%s'." % deck_name
		return
	var ids: Array[String] = []
	ids.assign(data["cards"])
	name_box.text = deck_name
	_set_deck(ids)

func _on_delete() -> void:
	if saved_picker.item_count == 0:
		return
	DeckData.delete_deck(saved_picker.get_item_text(saved_picker.selected))
	_refresh_saved_list()

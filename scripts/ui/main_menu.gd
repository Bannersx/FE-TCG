extends Control

const GAME_SCENE: String = "res://scenes/main/game_scene.tscn"
const DECK_BUILDER: String = "res://scenes/main/deck_builder.tscn"

var deck_pickers: Array[OptionButton] = []
var army_pickers: Array[OptionButton] = []
var setup_check: CheckBox

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.10, 0.14)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "Tactical Fantasy TCG"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Choose an army for each player"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	_add_button(box, "Two Players (same computer)", false, AIController.Difficulty.NORMAL)
	_add_button(box, "Play vs Computer (Easy)", true, AIController.Difficulty.EASY)
	_add_button(box, "Play vs Computer (Normal)", true, AIController.Difficulty.NORMAL)
	_add_button(box, "Play vs Computer (Hard)", true, AIController.Difficulty.HARD)
	for seat in range(2):
		_add_seat_pickers(box, seat)
	setup_check = CheckBox.new()
	setup_check.text = "Pre-game terrain setup (3 tiles each)"
	setup_check.button_pressed = GameSettings.setup_tiles > 0
	box.add_child(setup_check)
	var builder := Button.new()
	builder.text = "Deck Builder"
	builder.custom_minimum_size = Vector2(0, 44)
	builder.pressed.connect(func() -> void: get_tree().change_scene_to_file(DECK_BUILDER))
	box.add_child(builder)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(0, 44)
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

func _add_seat_pickers(parent: Control, seat: int) -> void:
	var caption: String = "Player %d%s" % [seat + 1, " / computer" if seat == 1 else ""]
	var army_row := HBoxContainer.new()
	parent.add_child(army_row)
	var army_label := Label.new()
	army_label.text = "%s army" % caption
	army_label.custom_minimum_size = Vector2(200, 0)
	army_row.add_child(army_label)
	var army_picker := OptionButton.new()
	army_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for army_id in ArmyCatalog.ARMY_IDS:
		army_picker.add_item("%s (%s)" % [ArmyCatalog.army_name(army_id), ArmyCatalog.ARMIES[army_id]["archetype"]])
	army_picker.selected = ArmyCatalog.ARMY_IDS.find(GameSettings.armies[seat])
	army_row.add_child(army_picker)
	army_pickers.append(army_picker)
	var deck_picker: OptionButton = _add_deck_picker(parent, "%s deck" % caption)
	deck_pickers.append(deck_picker)
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 12)
	summary.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(summary)
	var refresh: Callable = func(_index: int = 0) -> void:
		var army_id: String = ArmyCatalog.ARMY_IDS[army_picker.selected]
		_fill_deck_picker(deck_picker, army_id)
		summary.text = "%s Commander %s: %s" % [ArmyCatalog.ARMIES[army_id]["summary"], ArmyCatalog.ARMIES[army_id]["commander"], ArmyCatalog.ARMIES[army_id]["passive"]]
	army_picker.item_selected.connect(refresh)
	refresh.call()

func _fill_deck_picker(picker: OptionButton, army_id: String) -> void:
	picker.clear()
	picker.add_item("Starter deck")
	for deck_name in DeckData.list_decks():
		var data: Dictionary = DeckData.load_deck(deck_name)
		if data.is_empty() or not DeckData.validate(data["cards"]).is_empty():
			continue
		if DeckData.army_of(data["cards"]) in ["", army_id]:
			picker.add_item(deck_name)

func _add_deck_picker(parent: Control, caption: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(200, 0)
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	return picker

func _add_button(parent: Control, label: String, ai: bool, difficulty: AIController.Difficulty) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 52)
	button.pressed.connect(_start.bind(ai, difficulty))
	parent.add_child(button)

func _start(ai: bool, difficulty: AIController.Difficulty) -> void:
	GameSettings.ai_enabled = ai
	GameSettings.ai_difficulty = difficulty
	GameSettings.ai_player_id = 1
	GameSettings.setup_tiles = 3 if setup_check.button_pressed else 0
	for seat in range(2):
		GameSettings.armies[seat] = ArmyCatalog.ARMY_IDS[army_pickers[seat].selected]
		var picker: OptionButton = deck_pickers[seat]
		GameSettings.deck_names[seat] = "" if picker.selected <= 0 else picker.get_item_text(picker.selected)
	get_tree().change_scene_to_file(GAME_SCENE)

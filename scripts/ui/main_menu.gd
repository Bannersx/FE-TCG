extends Control

const GAME_SCENE: String = "res://scenes/main/game_scene.tscn"
const DECK_BUILDER: String = "res://scenes/main/deck_builder.tscn"
const INK: Color = Color(0.06, 0.10, 0.14)
const PANEL: Color = Color(0.10, 0.15, 0.19)
const GOLD: Color = Color(0.77, 0.62, 0.36)
const TEXT: Color = Color(0.94, 0.90, 0.80)

enum LocalMode { COMPUTER, TWO_PLAYERS, FOUR_PLAYERS }

var ui_scale: float = 1.0
var scroll: ScrollContainer
var menu_panel: PanelContainer
var views: Dictionary = {}
var current_view: String = ""
var local_mode_picker: OptionButton
var difficulty_row: Control
var difficulty_picker: OptionButton
var seat_panels: Array[Control] = []
var seat_labels: Array[Label] = []
var army_pickers: Array[OptionButton] = []
var deck_pickers: Array[OptionButton] = []
var local_setup_check: CheckBox
var online_forms: Dictionary = {}
var scale_entries: Array[Dictionary] = []
var layout_update_pending: bool = false

func _ready() -> void:
	ui_scale = _screen_ui_scale()
	theme = _make_theme()
	var background := ColorRect.new()
	background.color = INK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, _px(18))
	add_child(margin)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	menu_panel = PanelContainer.new()
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(menu_panel)
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, _px(28))
	menu_panel.add_child(padding)
	var host := VBoxContainer.new()
	host.add_theme_constant_override("separation", _px(12))
	padding.add_child(host)
	_build_home(host)
	_build_local(host)
	_build_online_choice(host)
	_build_online_form(host, true)
	_build_online_form(host, false)
	_capture_scale(self)
	resized.connect(_schedule_layout_update)
	get_window().size_changed.connect(_schedule_layout_update)
	_resize_panel()
	_show_view("home")
	if not OnlineMatch.status_changed.is_connected(_on_online_status_changed):
		OnlineMatch.status_changed.connect(_on_online_status_changed)
	if not OnlineMatch.match_ready.is_connected(_on_online_match_ready):
		OnlineMatch.match_ready.connect(_on_online_match_ready)

func _screen_ui_scale() -> float:
	var pixel_scale: float = absf(get_viewport().get_screen_transform().get_scale().x)
	var target_scale: float = 0.75
	if OS.has_feature("mobile"):
		target_scale = maxf(1.0, float(DisplayServer.screen_get_dpi()) / 160.0)
	return clampf(target_scale / maxf(pixel_scale, 0.01), 1.0, 6.0)

func _capture_scale(node: Node) -> void:
	if node is Control:
		var control: Control = node
		var entry: Dictionary = {"control": control, "minimum": control.custom_minimum_size / ui_scale, "constants": {}}
		if control.has_theme_font_size_override("font_size"):
			entry["font_size"] = float(control.get_theme_font_size("font_size")) / ui_scale
		for constant_name in ["separation", "margin_left", "margin_right", "margin_top", "margin_bottom"]:
			if control.has_theme_constant_override(constant_name):
				entry["constants"][constant_name] = float(control.get_theme_constant(constant_name)) / ui_scale
		scale_entries.append(entry)
	for child in node.get_children():
		_capture_scale(child)

func _schedule_layout_update() -> void:
	if not layout_update_pending:
		layout_update_pending = true
		call_deferred("_update_layout")

func _update_layout() -> void:
	layout_update_pending = false
	if not is_inside_tree():
		return
	var next_scale: float = _screen_ui_scale()
	if not is_equal_approx(next_scale, ui_scale):
		var scroll_position: int = roundi(scroll.scroll_vertical * next_scale / ui_scale)
		ui_scale = next_scale
		theme = _make_theme()
		for entry: Dictionary in scale_entries:
			var control: Control = entry["control"]
			control.custom_minimum_size = (entry["minimum"] as Vector2) * ui_scale
			if entry.has("font_size"):
				control.add_theme_font_size_override("font_size", _px(entry["font_size"]))
			for constant_name: String in entry["constants"]:
				control.add_theme_constant_override(constant_name, _px(entry["constants"][constant_name]))
		menu_panel.add_theme_stylebox_override("panel", _panel_style())
		scroll.set_deferred("scroll_vertical", scroll_position)
	_resize_panel()

func _px(value: float) -> int:
	return roundi(value * ui_scale)

func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = _px(21)
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, _button_style(Color(0.12, 0.20, 0.26)))
		result.set_stylebox("hover", type, _button_style(Color(0.18, 0.29, 0.35)))
		result.set_stylebox("pressed", type, _button_style(Color(0.09, 0.16, 0.20)))
		result.set_stylebox("disabled", type, _button_style(Color(0.12, 0.13, 0.14)))
		result.set_color("font_color", type, TEXT)
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_pressed_color", type, TEXT)
		result.set_color("font_disabled_color", type, Color(0.55, 0.55, 0.52))
	result.set_stylebox("normal", "LineEdit", _button_style(Color(0.06, 0.10, 0.13)))
	result.set_stylebox("focus", "LineEdit", _button_style(Color(0.10, 0.17, 0.20)))
	result.set_color("font_color", "LineEdit", TEXT)
	result.set_color("font_color", "Label", TEXT)
	var divider := StyleBoxLine.new()
	divider.color = GOLD
	divider.thickness = _px(1)
	result.set_stylebox("separator", "HSeparator", divider)
	return result

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = GOLD
	style.set_border_width_all(_px(1))
	style.set_corner_radius_all(_px(4))
	style.content_margin_left = _px(14)
	style.content_margin_right = _px(14)
	style.content_margin_top = _px(8)
	style.content_margin_bottom = _px(8)
	return style

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = GOLD
	style.set_border_width_all(_px(2))
	style.set_corner_radius_all(_px(8))
	return style

func _resize_panel() -> void:
	if is_instance_valid(menu_panel):
		menu_panel.custom_minimum_size.x = minf(_px(820), maxf(0.0, size.x - _px(36)))

func _new_view(host: Control, name: String, heading: String, description: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = name.capitalize()
	box.add_theme_constant_override("separation", _px(12))
	host.add_child(box)
	views[name] = box
	var title := Label.new()
	title.text = heading
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", _px(34))
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = description
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", _px(17))
	box.add_child(subtitle)
	box.add_child(HSeparator.new())
	return box

func _show_view(name: String) -> void:
	current_view = name
	for view_name: String in views:
		(views[view_name] as Control).visible = view_name == name
	scroll.set_deferred("scroll_vertical", 0)

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.custom_minimum_size.y = _px(54)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _field(parent: Control, caption: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(4))
	parent.add_child(box)
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", _px(18))
	box.add_child(label)
	control.custom_minimum_size.y = _px(48)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	return box

func _option() -> OptionButton:
	var picker := OptionButton.new()
	picker.fit_to_longest_item = false
	picker.clip_text = true
	return picker

func _army_picker(selected_army: String) -> OptionButton:
	var picker := _option()
	for army_id: String in ArmyCatalog.ARMY_IDS:
		picker.add_item("%s (%s)" % [ArmyCatalog.army_name(army_id), ArmyCatalog.ARMIES[army_id]["archetype"]])
	picker.select(maxi(0, ArmyCatalog.ARMY_IDS.find(selected_army)))
	return picker

func _build_home(host: Control) -> void:
	var box := _new_view(host, "home", "Tactical Fantasy TCG", "Gather your forces and choose how to play.")
	_button(box, "Tutorial", _start_tutorial)
	_button(box, "Local Play", func() -> void: _show_view("local"))
	_button(box, "Online Play", func() -> void: _show_view("online"))
	_button(box, "Deck Builder", func() -> void: get_tree().change_scene_to_file(DECK_BUILDER))
	var motion := CheckBox.new()
	motion.text = "Reduce motion"
	motion.button_pressed = GameSettings.reduce_motion
	motion.toggled.connect(func(enabled: bool) -> void: GameSettings.reduce_motion = enabled)
	box.add_child(motion)
	var confirmations := CheckBox.new()
	confirmations.text = "Confirm actions"
	confirmations.button_pressed = GameSettings.confirm_actions
	confirmations.toggled.connect(func(enabled: bool) -> void: GameSettings.confirm_actions = enabled)
	box.add_child(confirmations)
	_button(box, "Quit", func() -> void: get_tree().quit())

func _build_local(host: Control) -> void:
	var box := _new_view(host, "local", "Local Play", "Choose a mode, then prepare each player's army and deck.")
	local_mode_picker = _option()
	local_mode_picker.add_item("Two players (same device)", LocalMode.TWO_PLAYERS)
	local_mode_picker.add_item("Four-player free-for-all", LocalMode.FOUR_PLAYERS)
	local_mode_picker.add_item("Play vs Computer", LocalMode.COMPUTER)
	_field(box, "Game mode", local_mode_picker)
	difficulty_picker = _option()
	difficulty_picker.add_item("Easy", AIController.Difficulty.EASY)
	difficulty_picker.add_item("Normal", AIController.Difficulty.NORMAL)
	difficulty_picker.add_item("Hard", AIController.Difficulty.HARD)
	difficulty_picker.select(1)
	difficulty_row = _field(box, "Computer difficulty", difficulty_picker)
	for seat in range(4):
		_add_seat_pickers(box, seat)
	local_setup_check = CheckBox.new()
	local_setup_check.text = "Pre-game terrain setup (3 tiles each)"
	local_setup_check.custom_minimum_size.y = _px(48)
	local_setup_check.button_pressed = GameSettings.setup_tiles > 0
	box.add_child(local_setup_check)
	_button(box, "Start Match", _start_local)
	_button(box, "Back", func() -> void: _show_view("home"))
	local_mode_picker.item_selected.connect(_refresh_local_mode)
	_refresh_local_mode()

func _add_seat_pickers(parent: Control, seat: int) -> void:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", _px(6))
	parent.add_child(panel)
	seat_panels.append(panel)
	var heading := Label.new()
	heading.add_theme_color_override("font_color", GOLD)
	heading.add_theme_font_size_override("font_size", _px(23))
	panel.add_child(heading)
	seat_labels.append(heading)
	var army := _army_picker(GameSettings.armies[seat])
	_field(panel, "Army", army)
	army_pickers.append(army)
	var deck := _option()
	_field(panel, "Deck", deck)
	deck_pickers.append(deck)
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", _px(16))
	panel.add_child(summary)
	var refresh: Callable = func(_index: int = 0) -> void:
		var army_id: String = ArmyCatalog.ARMY_IDS[army.selected]
		_fill_deck_picker(deck, army_id)
		summary.text = "%s Commander %s: %s" % [ArmyCatalog.ARMIES[army_id]["summary"], ArmyCatalog.ARMIES[army_id]["commander"], ArmyCatalog.ARMIES[army_id]["passive"]]
	army.item_selected.connect(refresh)
	refresh.call()
	_select_deck(deck, GameSettings.deck_names[seat])

func _refresh_local_mode(_index: int = 0) -> void:
	var mode: int = local_mode_picker.get_selected_id()
	var player_count: int = 4 if mode == LocalMode.FOUR_PLAYERS else 2
	difficulty_row.visible = mode == LocalMode.COMPUTER
	for seat in range(seat_panels.size()):
		seat_panels[seat].visible = seat < player_count
		seat_labels[seat].text = "Player %d%s" % [seat + 1, " / Computer" if seat == 1 and mode == LocalMode.COMPUTER else ""]

func _start_local() -> void:
	GameSettings.tutorial_mode = false
	var mode: int = local_mode_picker.get_selected_id()
	GameSettings.ai_enabled = mode == LocalMode.COMPUTER
	GameSettings.player_count = 4 if mode == LocalMode.FOUR_PLAYERS else 2
	GameSettings.ai_difficulty = difficulty_picker.get_selected_id() as AIController.Difficulty
	GameSettings.ai_player_id = 1
	GameSettings.setup_tiles = 3 if local_setup_check.button_pressed else 0
	for seat in range(GameSettings.player_count):
		GameSettings.armies[seat] = ArmyCatalog.ARMY_IDS[army_pickers[seat].selected]
		var picker: OptionButton = deck_pickers[seat]
		GameSettings.deck_names[seat] = "" if picker.selected <= 0 else picker.get_item_text(picker.selected)
	get_tree().change_scene_to_file(GAME_SCENE)

func _start_tutorial() -> void:
	GameSettings.tutorial_mode = true
	get_tree().change_scene_to_file(GAME_SCENE)

func _build_online_choice(host: Control) -> void:
	var box := _new_view(host, "online", "Online Play", "Play a private match using a server address and room code.")
	_button(box, "Create Room", func() -> void: _show_view("create"))
	_button(box, "Join Room", func() -> void: _show_view("join"))
	_button(box, "Back", func() -> void: _show_view("home"))

func _build_online_form(host: Control, create_room: bool) -> void:
	var view_name: String = "create" if create_room else "join"
	var heading: String = "Create Room" if create_room else "Join Room"
	var description: String = "Set up a private match and share its room code." if create_room else "Enter the creator's server address, room size, and room code."
	var box := _new_view(host, view_name, heading, description)
	var form: Dictionary = {}
	online_forms[view_name] = form
	var address := LineEdit.new()
	address.text = "127.0.0.1"
	_field(box, "Server address", address)
	form["address"] = address
	var port := LineEdit.new()
	port.text = str(OnlineMatch.DEFAULT_PORT)
	port.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_field(box, "UDP port", port)
	form["port"] = port
	var display_name := LineEdit.new()
	display_name.text = "Player"
	display_name.max_length = 24
	_field(box, "Your name", display_name)
	form["display_name"] = display_name
	var army := _army_picker(GameSettings.armies[0])
	_field(box, "Your army", army)
	form["army"] = army
	var deck := _option()
	_field(box, "Your deck", deck)
	form["deck"] = deck
	var refresh: Callable = func(_index: int = 0) -> void:
		_fill_deck_picker(deck, ArmyCatalog.ARMY_IDS[army.selected])
	army.item_selected.connect(refresh)
	refresh.call()
	var player_count := _option()
	player_count.add_item("2 players", 2)
	player_count.add_item("4 players free-for-all", 4)
	_field(box, "Room size" if create_room else "Room size (must match the creator)", player_count)
	form["player_count"] = player_count
	var code := LineEdit.new()
	code.max_length = OnlineMatch.MAX_ROOM_CODE_LENGTH
	code.text_submitted.connect(func(value: String) -> void: code.text = value.to_upper())
	_field(box, "Room code", code)
	form["code"] = code
	if create_room:
		form["generate"] = _button(box, "Generate Room Code", func() -> void: code.text = OnlineMatch.generate_room_code())
		var setup := CheckBox.new()
		setup.text = "Pre-game terrain setup (3 tiles each)"
		setup.custom_minimum_size.y = _px(48)
		setup.button_pressed = GameSettings.setup_tiles > 0
		box.add_child(setup)
		form["setup"] = setup
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", GOLD)
	box.add_child(status)
	form["status"] = status
	form["submit"] = _button(box, heading, _connect_online.bind(create_room))
	_button(box, "Back", _back_from_online)

func _fill_deck_picker(picker: OptionButton, army_id: String) -> void:
	picker.clear()
	picker.add_item("Starter deck")
	for deck_name: String in DeckData.list_decks():
		var data: Dictionary = DeckData.load_deck(deck_name)
		if data.is_empty() or not DeckData.validate(data["cards"]).is_empty():
			continue
		if DeckData.army_of(data["cards"]) in ["", army_id]:
			picker.add_item(deck_name)

func _select_deck(picker: OptionButton, deck_name: String) -> void:
	for index in range(1, picker.item_count):
		if picker.get_item_text(index) == deck_name:
			picker.select(index)
			return

func _connect_online(create_room: bool) -> void:
	var form: Dictionary = online_forms["create" if create_room else "join"]
	var status: Label = form["status"]
	var code_edit: LineEdit = form["code"]
	var code: String = code_edit.text.strip_edges().to_upper()
	if create_room and code.is_empty():
		code = OnlineMatch.generate_room_code()
	code_edit.text = code
	var port_edit: LineEdit = form["port"]
	if not port_edit.text.is_valid_int() or port_edit.text.to_int() < 1 or port_edit.text.to_int() > 65535:
		status.text = "Enter a valid UDP port between 1 and 65535."
		return
	var name_edit: LineEdit = form["display_name"]
	if name_edit.text.strip_edges().is_empty():
		status.text = "Enter your player name."
		return
	var army_picker: OptionButton = form["army"]
	var deck_picker: OptionButton = form["deck"]
	var count_picker: OptionButton = form["player_count"]
	var army_id: String = ArmyCatalog.ARMY_IDS[army_picker.selected]
	var deck_ids: Array[String] = DeckData.resolve(
		"" if deck_picker.selected <= 0 else deck_picker.get_item_text(deck_picker.selected),
		0, DeckData.SAVE_DIR, army_id
	)
	var address_edit: LineEdit = form["address"]
	var setup_tiles: int = 3 if create_room and (form["setup"] as CheckBox).button_pressed else 0
	var error: Error = OnlineMatch.connect_to_server(
		address_edit.text, port_edit.text.to_int(), code, create_room, name_edit.text,
		army_id, deck_ids, setup_tiles, count_picker.get_selected_id()
	)
	if error != OK:
		status.text = "Could not start connection (error %d). Check the address, room code, deck, and army." % error
		_set_online_busy(form, false)

func _back_from_online() -> void:
	var cancelled: bool = OnlineMatch.mode != "offline" and OnlineMatch.mode != "server"
	if cancelled:
		OnlineMatch.disconnect_from_server()
	if online_forms.has(current_view):
		var current: Dictionary = online_forms[current_view]
		(current["status"] as Label).text = "Connection cancelled." if cancelled else ""
	for form: Dictionary in online_forms.values():
		_set_online_busy(form, false)
	_show_view("online")

func _set_online_busy(form: Dictionary, busy: bool) -> void:
	for key in ["address", "port", "display_name", "code"]:
		(form[key] as LineEdit).editable = not busy
	for key in ["army", "deck", "player_count", "submit"]:
		(form[key] as BaseButton).disabled = busy
	if form.has("setup"):
		(form["setup"] as CheckBox).disabled = busy
	if form.has("generate"):
		(form["generate"] as Button).disabled = busy

func _on_online_status_changed(message: String) -> void:
	if not online_forms.has(current_view):
		return
	var form: Dictionary = online_forms[current_view]
	(form["status"] as Label).text = message
	_set_online_busy(form, OnlineMatch.mode in ["connecting", "waiting", "client"])

func _on_online_match_ready(_player_id: int) -> void:
	if current_view in ["create", "join"] and OnlineMatch.mode == "client":
		get_tree().change_scene_to_file(GAME_SCENE)

extends Control

const CARD_SCENE: PackedScene = preload("res://scenes/cards/card_visual.tscn")
const PLAYER_SUMMARY = preload("res://scripts/ui/player_summary.gd")
const MAIN_MENU: String = "res://scenes/main/main_menu.tscn"
const CELL_SIZE: Vector2 = Vector2(150, 80)
const AI_STEP_SECONDS: float = 0.55
const STEP_DELAY: float = 0.35

const OWNER_TEXT: Array[Color] = [Color(0.65, 0.85, 1.0), Color(1.0, 0.70, 0.65), Color(0.65, 1.0, 0.65), Color(0.90, 0.75, 1.0)]

var engine: GameEngine
var ai: AIController
var tutorial: TutorialController
var tutorial_busy: bool = false
var tutorial_error: String = ""
var tutorial_title: Label
var tutorial_instruction: Label
var tutorial_finish_button: Button
var tutorial_panel: Control
var tutorial_mobile_button: Button
var tutorial_overlay: Control
var tutorial_overlay_title: Label
var tutorial_overlay_instruction: Label
var tutorial_overlay_continue: Button
var tutorial_overlay_scale: float = 1.0
var tutorial_display_key: String = ""
var cells: Dictionary = {}
var highlights: Dictionary = {}
var range_previews: Dictionary = {}
var target_reasons: Dictionary = {}
var selected_card: CardData
var pending_target_id: String = ""
var hover_tile: Vector2i = Vector2i(-1, -1)
var log_cursor: int = 0
var seen_hand_sizes: Dictionary = {}

var board_grid: GridContainer
var hand_box: HBoxContainer
var hand_title: Label
var phase_label: Label
var message_label: Label
var summary_panels: Array[PlayerSummary] = []
var summary_scroll: ScrollContainer
var status_button: Button
var status_overlay: Control
var status_scroll: ScrollContainer
var status_panels: Array[PlayerSummary] = []
var status_overlay_scale: float = 1.0
var inspector: CardInspector
var log_label: RichTextLabel
var advance_button: Button
var wait_button: Button
var finish_setup_button: Button
var support_check: CheckBox
var handoff_panel: Control
var handoff_label: Label
var gameover_panel: Control
var gameover_label: Label
var ai_timer: Timer
var setup_box: HFlowContainer
var setup_description: Label
var effect_layer: Control
var reduce_motion_check: CheckBox
var confirm_actions_check: CheckBox
var action_dialog: ConfirmationDialog
var pending_action: Dictionary = {}
var setup_buttons: Dictionary = {}
var setup_terrain: String = BoardState.FOREST
func _ready() -> void:
	var online: bool = OnlineMatch.mode == "client"
	if online:
		engine = GameEngine.new(0, [], true)
		if OnlineMatch.current_state != null:
			engine.state = OnlineMatch.current_state
		if not OnlineMatch.snapshot_received.is_connected(_on_online_snapshot):
			OnlineMatch.snapshot_received.connect(_on_online_snapshot)
		if not OnlineMatch.action_result_received.is_connected(_on_online_action_result):
			OnlineMatch.action_result_received.connect(_on_online_action_result)
		if not OnlineMatch.match_ended.is_connected(_on_online_match_ended):
			OnlineMatch.match_ended.connect(_on_online_match_ended)
	elif GameSettings.tutorial_mode:
		tutorial = TutorialController.new()
		engine = tutorial.engine
	else:
		var decks: Array = []
		for seat in range(GameSettings.player_count):
			decks.append(DeckData.resolve(GameSettings.deck_names[seat], seat, DeckData.SAVE_DIR, GameSettings.armies[seat]))
		engine = GameEngine.new(0, decks, false, GameSettings.armies, GameSettings.setup_tiles, GameSettings.player_count)
	_build_ui()
	if not online and tutorial == null and GameSettings.ai_enabled:
		ai = AIController.new(GameSettings.ai_difficulty)
		ai_timer = Timer.new()
		ai_timer.wait_time = AI_STEP_SECONDS
		ai_timer.timeout.connect(_ai_step)
		add_child(ai_timer)
		ai_timer.start()
	elif not online and tutorial == null:
		_show_handoff()
	_refresh()

# ---- UI construction ----

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.10, 0.14)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 20)
	left.add_child(phase_label)
	var legend := Label.new()
	legend.text = "Hover a unit: M = movement, A = attack from current position | OK / X = card target"
	legend.add_theme_font_size_override("font_size", 12)
	left.add_child(legend)
	board_grid = GridContainer.new()
	board_grid.columns = _state().board.width
	board_grid.add_theme_constant_override("h_separation", 3)
	board_grid.add_theme_constant_override("v_separation", 3)
	left.add_child(board_grid)
	for y in range(_state().board.height):
		for x in range(_state().board.width):
			var tile := Vector2i(x, y)
			var cell := BattleCell.new()
			cell.custom_minimum_size = Vector2(130, 65) if _state().players.size() == 4 else CELL_SIZE
			cell.pressed.connect(_on_tile_pressed.bind(tile))
			cell.mouse_entered.connect(_on_tile_hover.bind(tile))
			cell.mouse_exited.connect(_on_tile_unhover.bind(tile))
			board_grid.add_child(cell)
			cells[tile] = cell
	hand_title = Label.new()
	hand_title.add_theme_font_size_override("font_size", 16)
	left.add_child(hand_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 226)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 6)
	scroll.add_child(hand_box)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(560, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	if tutorial != null:
		var lesson_panel := PanelContainer.new()
		var lesson_style := StyleBoxFlat.new()
		lesson_style.bg_color = Color(0.10, 0.19, 0.22)
		lesson_style.border_color = Color(0.4, 0.85, 0.75)
		lesson_style.set_border_width_all(2)
		lesson_style.set_corner_radius_all(4)
		lesson_style.set_content_margin_all(10)
		lesson_panel.add_theme_stylebox_override("panel", lesson_style)
		right.add_child(lesson_panel)
		tutorial_panel = lesson_panel
		var lesson_box := VBoxContainer.new()
		lesson_panel.add_child(lesson_box)
		tutorial_title = Label.new()
		tutorial_title.add_theme_font_size_override("font_size", 19)
		tutorial_title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.9))
		lesson_box.add_child(tutorial_title)
		tutorial_instruction = Label.new()
		tutorial_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tutorial_instruction.add_theme_font_size_override("font_size", 16)
		lesson_box.add_child(tutorial_instruction)
		tutorial_finish_button = Button.new()
		tutorial_finish_button.text = "Finish tutorial"
		tutorial_finish_button.pressed.connect(_return_to_menu)
		lesson_box.add_child(tutorial_finish_button)
	summary_scroll = ScrollContainer.new()
	summary_scroll.custom_minimum_size.y = 460
	summary_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	summary_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right.add_child(summary_scroll)
	var summaries := GridContainer.new()
	summaries.columns = 2 if _state().players.size() == 4 else 1
	summaries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summaries.add_theme_constant_override("h_separation", 8)
	summaries.add_theme_constant_override("v_separation", 8)
	summary_scroll.add_child(summaries)
	for _i in range(_state().players.size()):
		var summary: PlayerSummary = PLAYER_SUMMARY.new()
		summaries.add_child(summary)
		summary_panels.append(summary)
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	message_label.custom_minimum_size = Vector2(0, 44)
	right.add_child(message_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	right.add_child(buttons)
	advance_button = Button.new()
	advance_button.custom_minimum_size = Vector2(0, 52)
	advance_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advance_button.tooltip_text = "Advance to the command phase or end your turn."
	_style_phase_button(advance_button, true)
	advance_button.pressed.connect(_on_advance_pressed)
	buttons.add_child(advance_button)
	wait_button = Button.new()
	wait_button.text = "Wait (end activation)"
	wait_button.custom_minimum_size = Vector2(0, 52)
	wait_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wait_button.tooltip_text = "End the active unit's activation."
	_style_phase_button(wait_button, false)
	wait_button.pressed.connect(_on_wait_pressed)
	buttons.add_child(wait_button)
	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.pressed.connect(_return_to_menu)
	buttons.add_child(menu_button)
	reduce_motion_check = CheckBox.new()
	reduce_motion_check.text = "Reduce motion"
	reduce_motion_check.button_pressed = GameSettings.reduce_motion
	reduce_motion_check.toggled.connect(_set_reduce_motion)
	right.add_child(reduce_motion_check)
	confirm_actions_check = CheckBox.new()
	confirm_actions_check.text = "Confirm actions"
	confirm_actions_check.button_pressed = GameSettings.confirm_actions
	confirm_actions_check.toggled.connect(func(enabled: bool) -> void: GameSettings.confirm_actions = enabled)
	right.add_child(confirm_actions_check)
	setup_box = HFlowContainer.new()
	right.add_child(setup_box)
	for terrain: String in BoardState.PLACEABLE:
		var terrain_button := Button.new()
		terrain_button.text = "Erase (Plain)" if terrain == BoardState.PLAIN else terrain.capitalize()
		terrain_button.toggle_mode = true
		terrain_button.pressed.connect(_on_terrain_picked.bind(terrain))
		setup_box.add_child(terrain_button)
		setup_buttons[terrain] = terrain_button
	finish_setup_button = Button.new()
	finish_setup_button.text = "Finish setup"
	finish_setup_button.custom_minimum_size.y = 46
	finish_setup_button.tooltip_text = "Finish your remaining terrain placements."
	_style_phase_button(finish_setup_button, true)
	finish_setup_button.pressed.connect(func() -> void:
		if not _input_locked():
			_request_action({"type": "pass_setup"}))
	setup_box.add_child(finish_setup_button)
	setup_description = Label.new()
	setup_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(setup_description)
	support_check = CheckBox.new()
	support_check.text = "Use A-rank support attack when attacking"
	right.add_child(support_check)
	inspector = CardInspector.new()
	right.add_child(inspector)
	log_label = RichTextLabel.new()
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.scroll_following = true
	log_label.bbcode_enabled = true
	log_label.add_theme_font_size_override("normal_font_size", 13)
	right.add_child(log_label)

	effect_layer = Control.new()
	effect_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	effect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effect_layer)
	handoff_panel = _build_overlay("handoff", "Ready")
	gameover_panel = _build_overlay("gameover", "Back to menu")
	move_child(effect_layer, handoff_panel.get_index())
	status_button = Button.new()
	status_button.text = "Players"
	status_button.pressed.connect(_show_player_status)
	add_child(status_button)
	status_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	if tutorial != null:
		tutorial_mobile_button = Button.new()
		tutorial_mobile_button.pressed.connect(_show_tutorial_overlay)
		add_child(tutorial_mobile_button)
		tutorial_mobile_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	action_dialog = ConfirmationDialog.new()
	action_dialog.title = "Confirm action"
	action_dialog.ok_button_text = "Confirm"
	action_dialog.cancel_button_text = "Cancel"
	action_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_dialog.confirmed.connect(_confirm_action)
	action_dialog.canceled.connect(_cancel_action)
	action_dialog.close_requested.connect(_cancel_action)
	add_child(action_dialog)
	resized.connect(_update_status_button)
	get_window().size_changed.connect(_update_status_button)
	_update_status_button()

func _style_phase_button(button: Button, primary: bool) -> void:
	var border := Color(0.82, 0.67, 0.38)
	var normal := Color(0.12, 0.28, 0.34) if primary else Color(0.25, 0.20, 0.14)
	var hover := Color(0.19, 0.39, 0.45) if primary else Color(0.35, 0.28, 0.18)
	var pressed := Color(0.08, 0.20, 0.25) if primary else Color(0.18, 0.14, 0.10)
	button.add_theme_stylebox_override("normal", _phase_button_style(normal, border))
	button.add_theme_stylebox_override("hover", _phase_button_style(hover, border.lightened(0.25)))
	button.add_theme_stylebox_override("pressed", _phase_button_style(pressed, border))
	button.add_theme_stylebox_override("disabled", _phase_button_style(Color(0.16, 0.17, 0.18), Color(0.38, 0.38, 0.35)))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(1.0, 0.91, 0.63)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(5)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_font_size_override("font_size", 17)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, Color(0.98, 0.96, 0.88))
	button.add_theme_color_override("font_disabled_color", Color(0.68, 0.68, 0.64))

func _phase_button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _status_ui_scale() -> float:
	var pixel_scale: float = absf(get_viewport().get_screen_transform().get_scale().x)
	var target: float = maxf(1.0, float(DisplayServer.screen_get_dpi()) / 160.0) if OS.has_feature("mobile") else 1.0
	return clampf(target / maxf(pixel_scale, 0.01), 1.0, 6.0)

func _update_status_button() -> void:
	if not is_instance_valid(status_button):
		return
	var scale_factor: float = _status_ui_scale()
	if is_instance_valid(status_overlay) and not is_equal_approx(scale_factor, status_overlay_scale):
		var scroll_position: float = float(status_scroll.scroll_vertical) / status_overlay_scale
		_close_player_status()
		_show_player_status()
		status_scroll.set_deferred("scroll_vertical", roundi(scroll_position * scale_factor))
	status_button.visible = scale_factor > 1.5 and _state().phase != GameState.Phase.GAME_OVER
	status_button.add_theme_font_size_override("font_size", roundi(15 * scale_factor))
	status_button.offset_left = -128 * scale_factor
	status_button.offset_right = -8 * scale_factor
	status_button.offset_top = 8 * scale_factor
	status_button.offset_bottom = 52 * scale_factor
	if tutorial != null:
		var mobile: bool = scale_factor > 1.5
		if mobile and not tutorial_mobile_button.visible:
			tutorial_display_key = ""
		tutorial_panel.visible = not mobile
		tutorial_mobile_button.visible = mobile
		tutorial_mobile_button.add_theme_font_size_override("font_size", roundi(15 * scale_factor))
		tutorial_mobile_button.offset_left = -155 * scale_factor
		tutorial_mobile_button.offset_right = -8 * scale_factor
		tutorial_mobile_button.offset_top = -52 * scale_factor
		tutorial_mobile_button.offset_bottom = -8 * scale_factor
		if is_instance_valid(tutorial_overlay) and (not mobile or not is_equal_approx(scale_factor, tutorial_overlay_scale)):
			_close_tutorial_overlay()
			tutorial_display_key = ""
		if is_instance_valid(tutorial_title):
			_refresh_tutorial()

func _show_tutorial_overlay() -> void:
	if is_instance_valid(tutorial_overlay):
		return
	var scale_factor: float = _status_ui_scale()
	tutorial_overlay_scale = scale_factor
	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.07, 0.09, 0.97)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	tutorial_overlay = overlay
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, roundi(16 * scale_factor))
	overlay.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(12 * scale_factor))
	margin.add_child(box)
	tutorial_overlay_title = Label.new()
	tutorial_overlay_title.add_theme_font_size_override("font_size", roundi(22 * scale_factor))
	tutorial_overlay_title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.9))
	box.add_child(tutorial_overlay_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	tutorial_overlay_instruction = Label.new()
	tutorial_overlay_instruction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_overlay_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_overlay_instruction.add_theme_font_size_override("font_size", roundi(18 * scale_factor))
	scroll.add_child(tutorial_overlay_instruction)
	tutorial_overlay_continue = Button.new()
	tutorial_overlay_continue.custom_minimum_size.y = 52 * scale_factor
	tutorial_overlay_continue.add_theme_font_size_override("font_size", roundi(18 * scale_factor))
	tutorial_overlay_continue.pressed.connect(func() -> void:
		if tutorial.finished or not tutorial_error.is_empty():
			_return_to_menu()
		else:
			_close_tutorial_overlay())
	box.add_child(tutorial_overlay_continue)
	var exit := Button.new()
	exit.text = "Exit tutorial"
	exit.custom_minimum_size.y = 52 * scale_factor
	exit.add_theme_font_size_override("font_size", roundi(18 * scale_factor))
	exit.pressed.connect(_return_to_menu)
	box.add_child(exit)
	_update_tutorial_overlay()

func _close_tutorial_overlay() -> void:
	if is_instance_valid(tutorial_overlay):
		tutorial_overlay.queue_free()
	tutorial_overlay = null

func _update_tutorial_overlay() -> void:
	if not is_instance_valid(tutorial_overlay):
		return
	tutorial_overlay_title.text = tutorial_title.text
	tutorial_overlay_instruction.text = tutorial_instruction.text
	tutorial_overlay_continue.text = "Back to menu" if not tutorial_error.is_empty() else ("Finish tutorial" if tutorial.finished else "Continue")


func _show_player_status() -> void:
	if is_instance_valid(status_overlay):
		return
	var scale_factor: float = _status_ui_scale()
	status_overlay_scale = scale_factor
	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.07, 0.09, 0.97)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	status_overlay = overlay
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, roundi(12 * scale_factor))
	overlay.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", roundi(8 * scale_factor))
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "Player status"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", roundi(20 * scale_factor))
	header.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(90, 44) * scale_factor
	close.add_theme_font_size_override("font_size", roundi(15 * scale_factor))
	close.pressed.connect(_close_player_status)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	status_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var panels := VBoxContainer.new()
	panels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panels.add_theme_constant_override("separation", roundi(8 * scale_factor))
	scroll.add_child(panels)
	status_panels.clear()
	for index in range(_state().players.size()):
		var summary: PlayerSummary = PLAYER_SUMMARY.new(scale_factor)
		panels.add_child(summary)
		status_panels.append(summary)
	_refresh_summaries()

func _close_player_status() -> void:
	if is_instance_valid(status_overlay):
		status_overlay.queue_free()
	status_overlay = null
	status_scroll = null
	status_panels.clear()

func _build_overlay(kind: String, button_text: String) -> Control:
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.06, 0.09, 0.96 if kind == "handoff" else 0.88)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	add_child(panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 36)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(260, 56)
	box.add_child(button)
	if kind == "handoff":
		handoff_label = label
		button.pressed.connect(_on_handoff_ready)
	else:
		gameover_label = label
		button.pressed.connect(_return_to_menu)
	return panel

func _return_to_menu() -> void:
	GameSettings.tutorial_mode = false
	if OnlineMatch.mode != "offline" and OnlineMatch.mode != "server":
		OnlineMatch.disconnect_from_server()
	get_tree().change_scene_to_file(MAIN_MENU)

# ---- State helpers ----

func _state() -> GameState:
	return engine.state

func _is_ai_turn() -> bool:
	return ai != null and _state().active_player_id == GameSettings.ai_player_id

func _viewer_id() -> int:
	if tutorial != null:
		return 0
	return OnlineMatch.local_player_id if OnlineMatch.mode == "client" else (0 if ai != null else _state().active_player_id)

func _input_locked() -> bool:
	if not pending_action.is_empty():
		return true
	if tutorial != null and (tutorial_busy or tutorial.finished or not tutorial_error.is_empty()):
		return true
	if OnlineMatch.mode == "disconnected":
		return true
	if OnlineMatch.mode == "client":
		return _state().phase == GameState.Phase.GAME_OVER \
			or _state().active_player_id != OnlineMatch.local_player_id \
			or OnlineMatch.action_pending
	return _state().phase == GameState.Phase.GAME_OVER or _is_ai_turn() or handoff_panel.visible

func _active_unit() -> UnitState:
	if _state().current_activation_unit_id == "":
		return null
	return _state().find_unit(_state().current_activation_unit_id)

# ---- Input handling ----

func _on_tile_hover(tile: Vector2i) -> void:
	hover_tile = tile
	_compute_range_previews()
	_refresh_cells()
	_refresh_info()

func _on_tile_unhover(tile: Vector2i) -> void:
	if hover_tile != tile:
		return
	hover_tile = Vector2i(-1, -1)
	_compute_range_previews()
	_refresh_cells()
	_refresh_info()

func _on_tile_pressed(tile: Vector2i) -> void:
	if _input_locked():
		return
	if tutorial != null:
		if tile != tutorial.expected_tile():
			_show_tutorial_hint()
			return
		var expected_card: String = str(tutorial.expected_action().get("card_id", ""))
		if not expected_card.is_empty() and (selected_card == null or selected_card.card_id != expected_card):
			_show_tutorial_hint()
			return
	var state := _state()
	var pid: int = state.active_player_id
	var unit: UnitState = state.board.unit_at(tile)
	if state.phase == GameState.Phase.SETUP:
		_request_action({"type": "place_terrain", "tile": tile, "terrain": setup_terrain})
		return
	if selected_card != null:
		_play_selected_card(pid, tile, unit)
		return
	if state.phase != GameState.Phase.COMMAND:
		return
	var active: UnitState = _active_unit()
	if active == null:
		if unit != null and unit.owner_id == pid:
			_request_action({"type": "start_activation", "unit_id": unit.instance_id})
		return
	if unit != null and unit.owner_id != pid:
		_request_action({"type": "attack", "target_id": unit.instance_id, "support": support_check.button_pressed})
	elif unit == null:
		_request_action({"type": "move", "destination": tile})

func _play_selected_card(pid: int, tile: Vector2i, unit: UnitState) -> void:
	var card: CardData = selected_card
	match card.card_type:
		CardData.CardType.UNIT:
			_request_action({"type": "deploy", "card_id": card.card_id, "tile": tile})
		CardData.CardType.EQUIPMENT:
			if unit != null:
				_request_action({"type": "equip", "card_id": card.card_id, "unit_id": unit.instance_id})
		CardData.CardType.PROMOTION:
			if unit != null:
				_request_action({"type": "promote", "card_id": card.card_id, "unit_id": unit.instance_id})
		CardData.CardType.TACTIC:
			if card.target_kind == "friendly_unit_tile":
				if pending_target_id == "":
					if unit != null:
						pending_target_id = unit.instance_id
						message_label.text = "Now choose the destination tile."
						_refresh()
				else:
					_request_action({"type": "play_tactic", "card_id": card.card_id, "target_id": pending_target_id, "destination": tile})
			elif unit != null:
				_request_action({"type": "play_tactic", "card_id": card.card_id, "target_id": unit.instance_id})

func _on_card_pressed(card: CardData) -> void:
	if _input_locked() or _state().phase == GameState.Phase.SETUP:
		return
	if tutorial != null and card.card_id != str(tutorial.expected_action().get("card_id", "")):
		_show_tutorial_hint()
		return
	pending_target_id = ""
	selected_card = null if selected_card == card else card
	message_label.text = _card_hint(selected_card)
	_refresh()

func _card_hint(card: CardData) -> String:
	if card == null:
		return ""
	match card.card_type:
		CardData.CardType.UNIT:
			return "Click a highlighted tile in your deployment zone."
		CardData.CardType.EQUIPMENT, CardData.CardType.PROMOTION:
			return "OK: eligible for %s. X: unavailable; hover for the reason." % card.card_name
		CardData.CardType.TACTIC:
			return "Click a target unit for %s." % card.card_name
	return ""

func _on_terrain_picked(terrain: String) -> void:
	setup_terrain = terrain
	_refresh()

func _on_advance_pressed() -> void:
	if not _input_locked():
		_request_action({"type": "advance_phase"})

func _on_wait_pressed() -> void:
	if not _input_locked():
		_request_action({"type": "wait"})

func _on_handoff_ready() -> void:
	handoff_panel.visible = false
	_refresh()

func _show_handoff() -> void:
	inspector.clear()
	handoff_label.text = "%s's turn\nPass the device, then press Ready." % _state().active_player().display_name
	handoff_panel.visible = true

func _set_reduce_motion(enabled: bool) -> void:
	GameSettings.reduce_motion = enabled
	if enabled:
		for cell: BattleCell in cells.values():
			cell.cancel_effects()
		for effect in effect_layer.get_children():
			effect.queue_free()
		_refresh_cells()
		for card in hand_box.get_children():
			if card is CardVisual:
				if card.hover_tween != null and card.hover_tween.is_valid():
					card.hover_tween.kill()
				if card.draw_tween != null and card.draw_tween.is_valid():
					card.draw_tween.kill()
				card.scale = Vector2.ONE
				card.modulate.a = 1.0

# ---- Action submission ----

func _request_action(action: Dictionary) -> void:
	if _input_locked():
		return
	if tutorial != null and not tutorial.accepts(action):
		_show_tutorial_hint()
		return
	if not GameSettings.confirm_actions:
		_submit(action)
		return
	pending_action = action.duplicate(true)
	action_dialog.dialog_text = _describe_action(action)
	var ui_scale: float = _status_ui_scale()
	action_dialog.get_label().add_theme_font_size_override("font_size", roundi(16 * ui_scale))
	for button: Button in [action_dialog.get_ok_button(), action_dialog.get_cancel_button()]:
		button.custom_minimum_size = Vector2(100, 44) * ui_scale
		button.add_theme_font_size_override("font_size", roundi(16 * ui_scale))
	action_dialog.popup_centered(Vector2i(roundi(minf(520 * ui_scale, get_viewport_rect().size.x * 0.9)), 0))

func _describe_action(action: Dictionary) -> String:
	var card_name: String = selected_card.card_name if selected_card != null else str(action.get("card_id", ""))
	match str(action["type"]):
		"place_terrain":
			return "Place %s at %s?" % [str(action["terrain"]).capitalize(), _tile_description(action["tile"])]
		"pass_setup":
			return "Finish terrain setup?"
		"start_activation":
			return "Activate %s?" % _unit_description(str(action["unit_id"]))
		"move":
			return "Move %s to %s?" % [_unit_description(_state().current_activation_unit_id), _tile_description(action["destination"])]
		"attack":
			var support: String = " with support selected" if bool(action.get("support", false)) else ""
			return "Attack %s with %s%s?" % [_unit_description(str(action["target_id"])), _unit_description(_state().current_activation_unit_id), support]
		"deploy":
			return "Deploy %s at %s?" % [card_name, _tile_description(action["tile"])]
		"equip":
			return "Equip %s to %s?" % [card_name, _unit_description(str(action["unit_id"]))]
		"promote":
			return "Promote %s with %s?" % [_unit_description(str(action["unit_id"])), card_name]
		"play_tactic":
			var destination: String = " to %s" % _tile_description(action["destination"]) if action.has("destination") else ""
			return "Play %s on %s%s?" % [card_name, _unit_description(str(action["target_id"])), destination]
		"advance_phase":
			return "Go to the command phase?" if _state().phase == GameState.Phase.DEPLOYMENT else "End your turn?"
		"wait":
			return "End %s's activation?" % _unit_description(_state().current_activation_unit_id)
	return "Confirm this action?"

func _tile_description(tile: Vector2i) -> String:
	return "column %d, row %d" % [tile.x + 1, tile.y + 1]

func _unit_description(unit_id: String) -> String:
	var unit: UnitState = _state().find_unit(unit_id)
	return "%s (%s)" % [unit.display_name(), _tile_description(unit.position)] if unit != null else unit_id

func _confirm_action() -> void:
	if pending_action.is_empty():
		return
	var action: Dictionary = pending_action
	pending_action = {}
	if _input_locked():
		message_label.text = "The action is no longer available."
		_refresh()
		return
	_submit(action)

func _cancel_action() -> void:
	pending_action.clear()

func _submit(action: Dictionary) -> bool:
	if tutorial != null and not tutorial_busy and not tutorial.accepts(action):
		_show_tutorial_hint()
		return false
	if OnlineMatch.mode == "client":
		if not OnlineMatch.submit_action(action):
			message_label.text = "Could not submit that action."
			return false
		selected_card = null
		pending_target_id = ""
		message_label.text = "Submitting action..."
		_refresh()
		return true
	var previous_turn: int = _state().turn_number
	var previous_player: int = _state().active_player_id
	var was_setup: bool = _state().phase == GameState.Phase.SETUP
	var positions: Dictionary = _snapshot_positions()
	var visual_units: Dictionary = _snapshot_visual_units()
	var result: Dictionary = engine.submit_action(action)
	if not bool(result["ok"]):
		message_label.text = str(result["error"])
		_refresh()
		return false
	selected_card = null
	pending_target_id = ""
	message_label.text = ""
	if tutorial != null and not tutorial_busy:
		tutorial.step_index += 1
		if tutorial.step_index == tutorial.steps.size():
			tutorial_busy = true
			call_deferred("_run_tutorial_opponent")
	var switched: bool = _state().turn_number != previous_turn or (was_setup and _state().active_player_id != previous_player)
	if switched and _state().phase != GameState.Phase.GAME_OVER and ai == null and tutorial == null:
		_show_handoff()
	_refresh()
	_animate(action, result, positions, visual_units, previous_turn, previous_player)
	return true

func _show_tutorial_hint() -> void:
	message_label.text = "Follow the current tutorial step: " + tutorial.instruction()

func _run_tutorial_opponent() -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.65).timeout
	if not is_inside_tree():
		return
	if _state().active_player_id != 1 or not _submit({"type": "advance_phase"}) or not _submit({"type": "advance_phase"}):
		_tutorial_failed("The scripted opponent could not complete its turn.")
		return
	if _state().active_player_id != 0 or _state().players[0].victory_points != 1:
		_tutorial_failed("The objective did not score as expected.")
		return
	tutorial.finished = true
	tutorial_busy = false
	_refresh()

func _tutorial_failed(message: String) -> void:
	tutorial_error = message + " Return to the menu and restart the tutorial."
	push_error(tutorial_error)
	_refresh()

func _on_online_snapshot(state: GameState, viewer_id: int) -> void:
	if OnlineMatch.mode != "client" or viewer_id != OnlineMatch.local_player_id:
		return
	if not pending_action.is_empty():
		_cancel_action()
		action_dialog.hide()
	var previous_turn: int = _state().turn_number
	var previous_player: int = _state().active_player_id
	var positions: Dictionary = _snapshot_positions()
	var visual_units: Dictionary = _snapshot_visual_units()
	engine.state = state
	selected_card = null
	pending_target_id = ""
	handoff_panel.visible = false
	message_label.text = ""
	_refresh()
	if not OnlineMatch.current_visual_action.is_empty():
		_animate(OnlineMatch.current_visual_action["action"], OnlineMatch.current_visual_action["result"], positions, visual_units, previous_turn, previous_player)

func _on_online_action_result(accepted: bool, message: String) -> void:
	if not accepted:
		message_label.text = message
	_refresh()

func _on_online_match_ended(message: String) -> void:
	_cancel_action()
	action_dialog.hide()
	message_label.text = message
	_refresh()

# Positions before an action, so effects can still be shown on tiles of units that were just defeated.
func _snapshot_positions() -> Dictionary:
	var positions: Dictionary = {}
	for player in _state().players:
		for unit in player.units:
			positions[unit.instance_id] = unit.position
	return positions

func _snapshot_visual_units() -> Dictionary:
	var units: Dictionary = {}
	for player: PlayerState in _state().players:
		for unit: UnitState in player.units:
			units[unit.instance_id] = {
				"id": unit.instance_id, "name": unit.display_name(), "owner": unit.owner_id, "hp": unit.current_hp,
				"statuses": unit.statuses.duplicate(), "weapon": unit.weapon_type(),
			}
	return units

func _cell_at(tile: Vector2i) -> BattleCell:
	return cells.get(tile) as BattleCell

# Purely cosmetic. State has already changed; nothing here can alter an outcome.
func _animate(action: Dictionary, result: Dictionary, positions: Dictionary, units: Dictionary, previous_turn: int, previous_player: int) -> void:
	var target_tile := Vector2i(-1, -1)
	match str(action["type"]):
		"deploy":
			var cell: BattleCell = _cell_at(action["tile"])
			cell.pulse()
			cell.floating_text("Deployed", Color(0.5, 1.0, 0.6))
			target_tile = action["tile"]
		"move":
			var moving_id: String = ""
			for unit_id: String in positions:
				var moved: UnitState = _state().find_unit(unit_id)
				if moved != null and moved.position == action["destination"] and positions[unit_id] != moved.position:
					moving_id = unit_id
					break
			if not moving_id.is_empty():
				_animate_unit_move(positions[moving_id], action["destination"], units[moving_id])
			_cell_at(action["destination"]).pulse()
		"equip":
			var card: CardData = CardCatalog.get_card(str(action["card_id"]))
			var cell: BattleCell = _cell_at(positions[str(action["unit_id"])])
			cell.flash(Color(1.0, 0.9, 0.5))
			cell.floating_text("+" + card.card_name, Color(1.0, 0.9, 0.5))
			target_tile = positions[str(action["unit_id"])]
		"promote":
			var cell: BattleCell = _cell_at(positions[str(action["unit_id"])])
			cell.flash(Color(1.0, 0.85, 0.3))
			cell.floating_text("Promoted!", Color(1.0, 0.85, 0.3))
			target_tile = positions[str(action["unit_id"])]
		"play_tactic":
			_animate_tactic(action, positions, units)
			target_tile = positions[str(action["target_id"])]
		"attack":
			_animate_attack(result, positions, units)
		"place_terrain":
			var terrain_cell: BattleCell = _cell_at(action["tile"])
			terrain_cell.pulse()
			terrain_cell.floating_text(str(action["terrain"]), Color(0.9, 0.9, 0.6))
	if action.has("card_id") and target_tile != Vector2i(-1, -1):
		var played_card: CardData = CardCatalog.get_card(str(action["card_id"]))
		if played_card != null:
			_animate_card_play(played_card.card_name, previous_player, target_tile)
	var delay: float = float((result.get("steps", []) as Array).size()) * STEP_DELAY if action["type"] == "attack" else 0.0
	_animate_effects(result.get("visual_effects", []), delay)
	_animate_new_statuses(units, positions)
	if _state().turn_number != previous_turn:
		_show_banner("%s's turn" % _state().active_player().display_name, Color(1.0, 0.88, 0.50))
	if _state().phase == GameState.Phase.GAME_OVER:
		if GameSettings.reduce_motion:
			gameover_panel.modulate.a = 1.0
		else:
			gameover_panel.modulate.a = 0.0
			gameover_panel.create_tween().tween_property(gameover_panel, "modulate:a", 1.0, 0.5)

func _animate_tactic(action: Dictionary, positions: Dictionary, units: Dictionary) -> void:
	var card: CardData = CardCatalog.get_card(str(action["card_id"]))
	var target_id: String = str(action["target_id"])
	var target_tile: Vector2i = positions[target_id]
	var cell: BattleCell = _cell_at(target_tile)
	match card.tactic_effect:
		"heal":
			cell.flash(Color(0.6, 1.0, 0.6))
			var healed: UnitState = _state().find_unit(target_id)
			var amount: int = healed.current_hp - int(units[target_id]["hp"])
			cell.floating_text("+%d HP" % amount, Color(0.5, 1.0, 0.5))
		"damage":
			cell.flash(Color(1.0, 0.4, 0.4))
			cell.floating_text("-%d" % mini(card.magnitude, int(units[target_id]["hp"])), Color(1.0, 0.4, 0.4))
		"buff":
			cell.flash(Color(1.0, 0.9, 0.5))
			cell.floating_text(card.card_name, Color(1.0, 0.9, 0.5))
		"burn", "chill", "sow":
			var tint: Color = {"burn": Color(1.0, 0.55, 0.2), "chill": Color(0.5, 0.8, 1.0), "sow": Color(0.5, 1.0, 0.5)}[card.tactic_effect]
			cell.flash(tint)
			cell.floating_text("%s -%d" % [card.card_name, mini(card.magnitude, int(units[target_id]["hp"]))] if card.tactic_effect == "burn" else card.card_name, tint)
		_:
			if action.has("destination"):
				_animate_unit_move(target_tile, action["destination"], units[target_id])
				_cell_at(action["destination"]).pulse()

func _animate_attack(result: Dictionary, positions: Dictionary, units: Dictionary) -> void:
	var steps: Array = result["steps"]
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		var cell: BattleCell = _cell_at(positions[str(step["target"])])
		var delay: float = index * STEP_DELAY
		var source_tile: Vector2i = positions[str(step["source"])]
		var target_tile: Vector2i = positions[str(step["target"])]
		var ranged: bool = BoardState.distance(source_tile, target_tile) > 1
		var magic: bool = int(units[str(step["source"])]["weapon"]) == CardData.WeaponType.MAGIC
		_animate_projectile(source_tile, target_tile, "*" if magic else (">" if ranged else "/"), delay, Color(0.75, 0.6, 1.0) if magic else Color(1.0, 0.85, 0.55))
		cell.flash(Color(1.0, 0.4, 0.4), delay + (0.0 if GameSettings.reduce_motion else 0.18))
		var label: String = "%s -%d" % [str(step["kind"]).replace("_", " ").capitalize(), int(step["damage"])]
		cell.floating_text(label, Color(1.0, 0.45, 0.4), delay + (0.0 if GameSettings.reduce_motion else 0.18))
	if ai_timer != null:
		ai_timer.start(AI_STEP_SECONDS + steps.size() * STEP_DELAY)

func _animate_effects(effects: Array, delay: float) -> void:
	for effect: Dictionary in effects:
		var kind: String = str(effect["kind"])
		if kind == "draw":
			_show_banner("%s draws a card" % _state().players[int(effect["player"])].display_name, Color(0.7, 0.85, 1.0))
			continue
		var cell: BattleCell = _cell_at(effect["tile"])
		if handoff_panel.visible:
			_show_banner("%s at %s" % [kind.capitalize(), str(effect["tile"])], Color(1.0, 0.85, 0.55))
		match kind:
			"defeat":
				cell.floating_text("Defeated", Color(0.85, 0.85, 0.85), delay)
				_animate_defeat(effect, delay)
			"lava", "burn":
				cell.flash(Color(1.0, 0.35, 0.12), delay)
				cell.floating_text("%s -%d" % [kind.capitalize(), int(effect["amount"])], Color(1.0, 0.5, 0.25), delay)
			"heal":
				cell.flash(Color(0.5, 1.0, 0.5), delay)
				cell.floating_text("+%d HP" % int(effect["amount"]), Color(0.5, 1.0, 0.5), delay)
			"bloom":
				cell.flash(Color(0.4, 1.0, 0.5), delay)
				cell.floating_text("Bloom", Color(0.5, 1.0, 0.5), delay)
			"shrine":
				cell.flash(Color(0.8, 0.5, 1.0), delay)
				cell.floating_text("+%d supply" % int(effect["amount"]), Color(0.85, 0.65, 1.0), delay)
			"objective":
				cell.flash(Color(1.0, 0.85, 0.3), delay)
				cell.floating_text("+1 VP", Color(1.0, 0.85, 0.3), delay)

func _animate_new_statuses(units: Dictionary, positions: Dictionary) -> void:
	for unit_id: String in units:
		var unit: UnitState = _state().find_unit(unit_id)
		if unit == null or unit.current_hp <= 0:
			continue
		for status: String in unit.statuses:
			if not (units[unit_id]["statuses"] as Dictionary).has(status):
				var tint: Color = Color(1.0, 0.55, 0.2) if status == "burn" else Color(0.5, 0.8, 1.0)
				_cell_at(positions[unit_id]).floating_text(status.capitalize(), tint)

func _effect_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	effect_layer.add_child(label)
	return label

func _animate_unit_move(origin: Vector2i, destination: Vector2i, unit: Dictionary) -> void:
	if GameSettings.reduce_motion:
		return
	var label: Label = _effect_label(str(unit["name"]), OWNER_TEXT[int(unit["owner"])])
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.10, 0.15, 0.92)
	background.set_corner_radius_all(4)
	background.set_content_margin_all(4)
	label.add_theme_stylebox_override("normal", background)
	label.global_position = _cell_at(origin).global_position + Vector2(10, 15)
	var destination_cell: BattleCell = _cell_at(destination)
	destination_cell.text = ""
	destination_cell.hp_bar.visible = false
	destination_cell.stripe.visible = false
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "global_position", _cell_at(destination).global_position + Vector2(10, 15), 0.25)
	tween.tween_callback(func() -> void:
		var occupant: UnitState = _state().board.unit_at(destination)
		if occupant != null and occupant.instance_id == str(unit["id"]):
			_refresh_cell(destination))
	tween.tween_property(label, "modulate:a", 0.0, 0.15)
	tween.tween_callback(label.queue_free)

func _animate_projectile(origin: Vector2i, destination: Vector2i, symbol: String, delay: float, color: Color) -> void:
	if GameSettings.reduce_motion:
		return
	var label: Label = _effect_label(symbol, color)
	label.add_theme_font_size_override("font_size", 30)
	label.global_position = _cell_at(origin).global_position + _cell_at(origin).size / 2.0
	label.modulate.a = 0.0
	var tween: Tween = label.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(label, "modulate:a", 1.0, 0.0)
	tween.tween_property(label, "global_position", _cell_at(destination).global_position + _cell_at(destination).size / 2.0, 0.18)
	tween.tween_property(label, "modulate:a", 0.0, 0.1)
	tween.tween_callback(label.queue_free)

func _animate_defeat(effect: Dictionary, delay: float) -> void:
	if GameSettings.reduce_motion:
		return
	var label: Label = _effect_label(str(effect["name"]), OWNER_TEXT[int(effect["owner"])])
	label.global_position = _cell_at(effect["tile"]).global_position + Vector2(10, 15)
	label.modulate.a = 0.0
	var tween: Tween = label.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(label, "modulate:a", 1.0, 0.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)

func _animate_card_play(card_name: String, player_id: int, target: Vector2i) -> void:
	if GameSettings.reduce_motion:
		_cell_at(target).floating_text(card_name, Color(1.0, 0.9, 0.6))
		return
	var label: Label = _effect_label(card_name, Color(1.0, 0.9, 0.6))
	label.global_position = summary_panels[player_id].global_position
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "global_position", _cell_at(target).global_position + Vector2(10, 15), 0.25)
	tween.tween_property(label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(label.queue_free)

func _show_banner(text: String, color: Color) -> void:
	var banner_count: int = 0
	for child in effect_layer.get_children():
		if child.has_meta("banner"):
			banner_count += 1
	var label: Label = _effect_label(text, color)
	label.set_meta("banner", true)
	label.global_position = phase_label.global_position + Vector2(0, 30 + 24 * banner_count)
	var tween: Tween = label.create_tween()
	if GameSettings.reduce_motion:
		tween.tween_interval(0.9)
	else:
		label.modulate.a = 0.0
		tween.tween_property(label, "modulate:a", 1.0, 0.1)
		tween.tween_interval(0.45)
		tween.tween_property(label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(label.queue_free)

func _ai_step() -> void:
	if _state().phase == GameState.Phase.GAME_OVER or not _is_ai_turn():
		return
	var action: Dictionary = ai.choose_action(engine)
	if not _submit(action):
		var fallback: String = "wait" if _state().current_activation_unit_id != "" else "advance_phase"
		if _state().phase == GameState.Phase.SETUP:
			fallback = "pass_setup"
		_submit({"type": fallback})

# ---- Rendering ----

func _refresh() -> void:
	_compute_highlights()
	_compute_range_previews()
	_refresh_cells()
	_refresh_hand()
	_refresh_summaries()
	_refresh_controls()
	_refresh_info()
	_refresh_log()
	if tutorial != null:
		_refresh_tutorial()
	if _state().phase == GameState.Phase.GAME_OVER:
		_close_player_status()
		handoff_panel.visible = false
		gameover_label.text = "%s wins!\n(%s)" % [_state().players[_state().winner_id].display_name, _state().game_over_reason]
		gameover_panel.visible = true

func _refresh_tutorial() -> void:
	tutorial_title.text = "Tutorial complete" if tutorial.finished else "Tutorial - step %d of %d" % [mini(tutorial.step_index + 1, tutorial.steps.size()), tutorial.steps.size()]
	tutorial_instruction.text = tutorial_error if not tutorial_error.is_empty() else tutorial.instruction()
	tutorial_finish_button.text = "Back to menu" if not tutorial_error.is_empty() else "Finish tutorial"
	tutorial_finish_button.visible = tutorial.finished or not tutorial_error.is_empty()
	tutorial_mobile_button.text = "Tutorial %d/%d" % [mini(tutorial.step_index + 1, tutorial.steps.size()), tutorial.steps.size()]
	var display_key: String = "%d:%s:%s" % [tutorial.step_index, tutorial.finished, tutorial_error]
	if tutorial_mobile_button.visible and tutorial_display_key != display_key:
		tutorial_display_key = display_key
		_show_tutorial_overlay()
	_update_tutorial_overlay()

func _compute_highlights() -> void:
	highlights.clear()
	target_reasons.clear()
	if _input_locked():
		return
	var state := _state()
	var pid: int = state.active_player_id
	if state.phase == GameState.Phase.SETUP:
		for option in GameEngine.terrain_options(state, pid):
			if option["terrain"] == setup_terrain:
				highlights[option["tile"]] = "deploy"
		return
	if selected_card != null:
		_highlight_for_card(state, pid)
		return
	if state.phase != GameState.Phase.COMMAND:
		return
	var active: UnitState = _active_unit()
	if active == null:
		for unit in state.players[pid].units:
			if GameEngine.activation_error(state, pid, unit) == "":
				highlights[unit.position] = "target"
		return
	highlights[active.position] = "active"
	if not state.current_activation_moved:
		for tile: Vector2i in MovementResolver.reachable_tiles(state.board, active):
			if tile != active.position:
				highlights[tile] = "move"
	for player in state.players:
		if player.player_id == pid:
			continue
		for enemy in player.units:
			if GameEngine.attack_error(state, active, enemy) == "":
				highlights[enemy.position] = "attack"

func _highlight_for_card(state: GameState, pid: int) -> void:
	var card: CardData = selected_card
	match card.card_type:
		CardData.CardType.UNIT:
			for y in range(state.board.height):
				for x in range(state.board.width):
					var tile := Vector2i(x, y)
					if GameEngine.deploy_error(state, pid, card, tile) == "":
						highlights[tile] = "deploy"
		CardData.CardType.EQUIPMENT:
			_highlight_equipment_targets(state, pid, card)
		CardData.CardType.PROMOTION:
			_highlight_equipment_targets(state, pid, card)
		CardData.CardType.TACTIC:
			_highlight_tactic(state, pid, card)

func _highlight_equipment_targets(state: GameState, pid: int, card: CardData) -> void:
	for player: PlayerState in state.players:
		for unit: UnitState in player.units:
			var error: String = GameEngine.equip_error(state, pid, card, unit) if card.card_type == CardData.CardType.EQUIPMENT else GameEngine.promote_error(state, pid, card, unit)
			highlights[unit.position] = "eligible" if error.is_empty() else "ineligible"
			target_reasons[unit.position] = error

func _highlight_tactic(state: GameState, pid: int, card: CardData) -> void:
	if pending_target_id != "":
		for y in range(state.board.height):
			for x in range(state.board.width):
				var tile := Vector2i(x, y)
				if GameEngine.tactic_error(state, pid, card, pending_target_id, tile) == "":
					highlights[tile] = "move"
		return
	for player in state.players:
		for unit in player.units:
			if unit.current_hp <= 0:
				continue
			var probe: Vector2i = Vector2i(-1, -1)
			if card.target_kind == "friendly_unit_tile":
				if unit.owner_id == pid:
					highlights[unit.position] = "target"
			elif GameEngine.tactic_error(state, pid, card, unit.instance_id, probe) == "":
				highlights[unit.position] = "target"

func _compute_range_previews() -> void:
	range_previews.clear()
	var state := _state()
	if selected_card != null or handoff_panel.visible or not state.board.is_valid_position(hover_tile):
		return
	var unit: UnitState = state.board.unit_at(hover_tile)
	if unit == null:
		return
	for tile: Vector2i in MovementResolver.reachable_tiles(state.board, unit):
		if tile != unit.position:
			range_previews[tile] = {"move": true}
	for y in range(state.board.height):
		for x in range(state.board.width):
			var tile := Vector2i(x, y)
			var distance: int = BoardState.distance(unit.position, tile)
			if distance >= 1 and distance <= unit.attack_range():
				if not range_previews.has(tile):
					range_previews[tile] = {}
				range_previews[tile]["attack"] = true

func _refresh_cells() -> void:
	for tile: Vector2i in cells:
		_refresh_cell(tile)

func _refresh_cell(tile: Vector2i) -> void:
	var state := _state()
	var cell: BattleCell = cells[tile]
	var tutorial_target: bool = tutorial != null and not tutorial_busy and not tutorial.finished and tile == tutorial.expected_tile()
	cell.show_state(state.board.terrain_at(tile), state.board.unit_at(tile), str(highlights.get(tile, "")), state.seeds.has(tile), range_previews.get(tile, {}), str(target_reasons.get(tile, "")), tutorial_target)

func _refresh_hand() -> void:
	for child in hand_box.get_children():
		child.queue_free()
	var viewer: int = _viewer_id()
	var player: PlayerState = _state().players[viewer]
	hand_title.text = "%s's hand (%d cards)%s" % [
		player.display_name, player.hand.size(), "  - waiting for the computer" if _is_ai_turn() else ""
	]
	if handoff_panel.visible:
		return
	var seen: int = int(seen_hand_sizes.get(viewer, -1))
	for index in range(player.hand.size()):
		var card: CardData = player.hand[index]
		var visual: CardVisual = CARD_SCENE.instantiate() as CardVisual
		hand_box.add_child(visual)
		var cost: int = FactionRules.tactic_cost(_state(), viewer, card) if card.card_type == CardData.CardType.TACTIC else card.supply_cost
		visual.setup(card, cost <= player.current_supply)
		visual.set_selected(card == selected_card)
		visual.pressed.connect(_on_card_pressed.bind(card))
		visual.inspected.connect(func(hovered: CardData) -> void: inspector.show_card(hovered))
		if seen >= 0 and index >= seen and not GameSettings.reduce_motion:
			visual.modulate.a = 0.0
			visual.draw_tween = visual.create_tween()
			visual.draw_tween.tween_property(visual, "modulate:a", 1.0, 0.5)
	seen_hand_sizes[viewer] = player.hand.size()

func _refresh_summaries() -> void:
	var state := _state()
	for index in range(state.players.size()):
		var player: PlayerState = state.players[index]
		summary_panels[index].show_player(player, index == state.active_player_id, OWNER_TEXT[index])
		if index < status_panels.size():
			status_panels[index].show_player(player, index == state.active_player_id, OWNER_TEXT[index])

func _refresh_controls() -> void:
	var state := _state()
	_update_status_button()
	var locked: bool = _input_locked()
	var in_setup: bool = state.phase == GameState.Phase.SETUP
	setup_box.visible = in_setup
	setup_description.visible = in_setup
	setup_description.text = "%s: %s" % [setup_terrain, BoardState.TERRAIN_DESCRIPTIONS[setup_terrain]]
	for terrain: String in setup_buttons:
		(setup_buttons[terrain] as Button).button_pressed = terrain == setup_terrain
		(setup_buttons[terrain] as Button).disabled = locked
	finish_setup_button.disabled = locked
	match state.phase:
		GameState.Phase.SETUP:
			advance_button.text = "Terrain setup"
		GameState.Phase.DEPLOYMENT:
			advance_button.text = "Go to Command Phase"
		GameState.Phase.COMMAND:
			advance_button.text = "End Turn"
		_:
			advance_button.text = "Game over"
	advance_button.disabled = locked or in_setup
	wait_button.disabled = locked or _active_unit() == null
	support_check.disabled = locked or tutorial != null
	var phase_names: Dictionary = {
		GameState.Phase.SETUP: "Terrain setup: place terrain (%d left), then Finish setup" % state.setup_left[state.active_player_id],
		GameState.Phase.DEPLOYMENT: "Deployment: deploy a unit, equip, promote, play tactics",
		GameState.Phase.COMMAND: "Command: activate up to 2 units (move, then attack), or play tactics",
		GameState.Phase.GAME_OVER: "Game over",
	}
	var activations_left: int = GameEngine.ACTIVATIONS_PER_TURN - state.activated_unit_ids.size()
	var activation_text: String = ""
	if state.phase == GameState.Phase.COMMAND:
		activation_text = " | Activations left: %d" % activations_left
	phase_label.text = "Turn %d - %s - %s%s" % [
		state.turn_number, state.active_player().display_name, str(phase_names.get(state.phase, "")), activation_text
	]

func _refresh_info() -> void:
	var state := _state()
	var unit: UnitState = null
	if state.board.is_valid_position(hover_tile):
		unit = state.board.unit_at(hover_tile)
	if unit == null:
		unit = _active_unit()
	if unit != null:
		inspector.show_card(unit.card, unit, state)

func _refresh_log() -> void:
	var events: Array[String] = _state().events
	while log_cursor < events.size():
		log_label.append_text(_format_log_line(events[log_cursor]) + "\n")
		log_cursor += 1

func _format_log_line(line: String) -> String:
	var color: String = "cccccc"
	if line.begins_with("Turn"):
		return "[color=#f0c040][b]%s[/b][/color]" % line
	if line.contains("defeated") or line.contains("wins"):
		color = "ff7070" if line.contains("defeated") else "70ff90"
	elif line.begins_with("  "):
		color = "9a9aa8"
	elif line.contains("promoted") or line.contains("equips") or line.contains("Bond"):
		color = "70d8ff"
	elif line.contains("plays"):
		color = "d890ff"
	return "[color=#%s]%s[/color]" % [color, line.replace("[", "(")]

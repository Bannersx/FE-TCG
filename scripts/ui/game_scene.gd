extends Control

const CARD_SCENE: PackedScene = preload("res://scenes/cards/card_visual.tscn")
const MAIN_MENU: String = "res://scenes/main/main_menu.tscn"
const CELL_SIZE: Vector2 = Vector2(150, 80)
const AI_STEP_SECONDS: float = 0.55
const STEP_DELAY: float = 0.35

const OWNER_TEXT: Array[Color] = [Color(0.65, 0.85, 1.0), Color(1.0, 0.70, 0.65)]

var engine: GameEngine
var ai: AIController
var cells: Dictionary = {}
var highlights: Dictionary = {}
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
var summary_labels: Array[Label] = []
var inspector: CardInspector
var log_label: RichTextLabel
var advance_button: Button
var wait_button: Button
var support_check: CheckBox
var handoff_panel: Control
var handoff_label: Label
var gameover_panel: Control
var gameover_label: Label
var ai_timer: Timer
var setup_box: HBoxContainer
var setup_buttons: Dictionary = {}
var setup_terrain: String = BoardState.FOREST
func _ready() -> void:
	engine = GameEngine.new(0, [
		DeckData.resolve(GameSettings.deck_names[0], 0, DeckData.SAVE_DIR, GameSettings.armies[0]),
		DeckData.resolve(GameSettings.deck_names[1], 1, DeckData.SAVE_DIR, GameSettings.armies[1]),
	], false, GameSettings.armies, GameSettings.setup_tiles)
	_build_ui()
	if GameSettings.ai_enabled:
		ai_timer = Timer.new()
		ai_timer.wait_time = AI_STEP_SECONDS
		ai_timer.timeout.connect(_ai_step)
		add_child(ai_timer)
		ai_timer.start()
	else:
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
	board_grid = GridContainer.new()
	board_grid.columns = BoardState.WIDTH
	board_grid.add_theme_constant_override("h_separation", 3)
	board_grid.add_theme_constant_override("v_separation", 3)
	left.add_child(board_grid)
	for y in range(BoardState.HEIGHT):
		for x in range(BoardState.WIDTH):
			var tile := Vector2i(x, y)
			var cell := BattleCell.new()
			cell.custom_minimum_size = CELL_SIZE
			cell.pressed.connect(_on_tile_pressed.bind(tile))
			cell.mouse_entered.connect(_on_tile_hover.bind(tile))
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
	for _i in range(2):
		var summary := Label.new()
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_theme_font_size_override("font_size", 14)
		right.add_child(summary)
		summary_labels.append(summary)
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	message_label.custom_minimum_size = Vector2(0, 44)
	right.add_child(message_label)
	var buttons := HBoxContainer.new()
	right.add_child(buttons)
	advance_button = Button.new()
	advance_button.custom_minimum_size = Vector2(0, 46)
	advance_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advance_button.pressed.connect(_on_advance_pressed)
	buttons.add_child(advance_button)
	wait_button = Button.new()
	wait_button.text = "Wait (end activation)"
	wait_button.custom_minimum_size = Vector2(0, 46)
	wait_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wait_button.pressed.connect(_on_wait_pressed)
	buttons.add_child(wait_button)
	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
	buttons.add_child(menu_button)
	setup_box = HBoxContainer.new()
	right.add_child(setup_box)
	for terrain: String in BoardState.PLACEABLE:
		var terrain_button := Button.new()
		terrain_button.text = "Erase (Plain)" if terrain == BoardState.PLAIN else terrain.capitalize()
		terrain_button.toggle_mode = true
		terrain_button.pressed.connect(_on_terrain_picked.bind(terrain))
		setup_box.add_child(terrain_button)
		setup_buttons[terrain] = terrain_button
	var finish_button := Button.new()
	finish_button.text = "Finish setup"
	finish_button.pressed.connect(func() -> void:
		if not _input_locked():
			_submit({"type": "pass_setup"}))
	setup_box.add_child(finish_button)
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

	handoff_panel = _build_overlay("handoff", "Ready")
	gameover_panel = _build_overlay("gameover", "Back to menu")

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
		button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
	return panel

# ---- State helpers ----

func _state() -> GameState:
	return engine.state

func _is_ai_turn() -> bool:
	return ai != null and _state().active_player_id == GameSettings.ai_player_id

func _viewer_id() -> int:
	return 0 if ai != null else _state().active_player_id

func _input_locked() -> bool:
	return _state().phase == GameState.Phase.GAME_OVER or _is_ai_turn() or handoff_panel.visible

func _active_unit() -> UnitState:
	if _state().current_activation_unit_id == "":
		return null
	return _state().find_unit(_state().current_activation_unit_id)

# ---- Input handling ----

func _on_tile_hover(tile: Vector2i) -> void:
	hover_tile = tile
	_refresh_info()

func _on_tile_pressed(tile: Vector2i) -> void:
	if _input_locked():
		return
	var state := _state()
	var pid: int = state.active_player_id
	var unit: UnitState = state.board.unit_at(tile)
	if state.phase == GameState.Phase.SETUP:
		_submit({"type": "place_terrain", "tile": tile, "terrain": setup_terrain})
		return
	if selected_card != null:
		_play_selected_card(pid, tile, unit)
		return
	if state.phase != GameState.Phase.COMMAND:
		return
	var active: UnitState = _active_unit()
	if active == null:
		if unit != null and unit.owner_id == pid:
			_submit({"type": "start_activation", "unit_id": unit.instance_id})
		return
	if unit != null and unit.owner_id != pid:
		_submit({"type": "attack", "target_id": unit.instance_id, "support": support_check.button_pressed})
	elif unit == null:
		_submit({"type": "move", "destination": tile})

func _play_selected_card(pid: int, tile: Vector2i, unit: UnitState) -> void:
	var card: CardData = selected_card
	match card.card_type:
		CardData.CardType.UNIT:
			_submit({"type": "deploy", "card_id": card.card_id, "tile": tile})
		CardData.CardType.EQUIPMENT:
			if unit != null:
				_submit({"type": "equip", "card_id": card.card_id, "unit_id": unit.instance_id})
		CardData.CardType.PROMOTION:
			if unit != null:
				_submit({"type": "promote", "card_id": card.card_id, "unit_id": unit.instance_id})
		CardData.CardType.TACTIC:
			if card.target_kind == "friendly_unit_tile":
				if pending_target_id == "":
					if unit != null:
						pending_target_id = unit.instance_id
						message_label.text = "Now choose the destination tile."
						_refresh()
				else:
					_submit({"type": "play_tactic", "card_id": card.card_id, "target_id": pending_target_id, "destination": tile})
			elif unit != null:
				_submit({"type": "play_tactic", "card_id": card.card_id, "target_id": unit.instance_id})

func _on_card_pressed(card: CardData) -> void:
	if _input_locked() or _state().phase == GameState.Phase.SETUP:
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
			return "Click a highlighted tile in your home column to deploy."
		CardData.CardType.EQUIPMENT, CardData.CardType.PROMOTION:
			return "Click one of your units to use %s." % card.card_name
		CardData.CardType.TACTIC:
			return "Click a target unit for %s." % card.card_name
	return ""

func _on_terrain_picked(terrain: String) -> void:
	setup_terrain = terrain
	_refresh()

func _on_advance_pressed() -> void:
	if not _input_locked():
		_submit({"type": "advance_phase"})

func _on_wait_pressed() -> void:
	if not _input_locked():
		_submit({"type": "wait"})

func _on_handoff_ready() -> void:
	handoff_panel.visible = false
	_refresh()

func _show_handoff() -> void:
	inspector.clear()
	handoff_label.text = "%s's turn\nPass the device, then press Ready." % _state().active_player().display_name
	handoff_panel.visible = true

# ---- Action submission ----

func _submit(action: Dictionary) -> bool:
	var previous_turn: int = _state().turn_number
	var previous_player: int = _state().active_player_id
	var was_setup: bool = _state().phase == GameState.Phase.SETUP
	var positions: Dictionary = _snapshot_positions()
	var result: Dictionary = engine.submit_action(action)
	if not bool(result["ok"]):
		message_label.text = str(result["error"])
		_refresh()
		return false
	selected_card = null
	pending_target_id = ""
	message_label.text = ""
	for tile: Vector2i in cells:
		(cells[tile] as BattleCell).cancel_effects()
	var switched: bool = _state().turn_number != previous_turn or (was_setup and _state().active_player_id != previous_player)
	if switched and _state().phase != GameState.Phase.GAME_OVER and ai == null:
		_show_handoff()
	_refresh()
	_animate(action, result, positions)
	return true

# Positions before an action, so effects can still be shown on tiles of units that were just defeated.
func _snapshot_positions() -> Dictionary:
	var positions: Dictionary = {}
	for player in _state().players:
		for unit in player.units:
			positions[unit.instance_id] = unit.position
	return positions

func _cell_at(tile: Vector2i) -> BattleCell:
	return cells.get(tile) as BattleCell

# Purely cosmetic. State has already changed; nothing here can alter an outcome.
func _animate(action: Dictionary, result: Dictionary, positions: Dictionary) -> void:
	match str(action["type"]):
		"deploy":
			var cell: BattleCell = _cell_at(action["tile"])
			cell.pulse()
			cell.floating_text("Deployed", Color(0.5, 1.0, 0.6))
		"move":
			_cell_at(action["destination"]).pulse()
		"equip":
			var card: CardData = CardCatalog.get_card(str(action["card_id"]))
			var cell: BattleCell = _cell_at(positions[str(action["unit_id"])])
			cell.flash(Color(1.0, 0.9, 0.5))
			cell.floating_text("+" + card.card_name, Color(1.0, 0.9, 0.5))
		"promote":
			var cell: BattleCell = _cell_at(positions[str(action["unit_id"])])
			cell.flash(Color(1.0, 0.85, 0.3))
			cell.floating_text("Promoted!", Color(1.0, 0.85, 0.3))
		"play_tactic":
			_animate_tactic(action, result, positions)
		"attack":
			_animate_attack(result, positions)
		"place_terrain":
			var terrain_cell: BattleCell = _cell_at(action["tile"])
			terrain_cell.pulse()
			terrain_cell.floating_text(str(action["terrain"]), Color(0.9, 0.9, 0.6))
	if _state().phase == GameState.Phase.GAME_OVER:
		gameover_panel.modulate.a = 0.0
		gameover_panel.create_tween().tween_property(gameover_panel, "modulate:a", 1.0, 0.8)

func _animate_tactic(action: Dictionary, result: Dictionary, positions: Dictionary) -> void:
	var card: CardData = CardCatalog.get_card(str(action["card_id"]))
	var target_tile: Vector2i = positions[str(action["target_id"])]
	var cell: BattleCell = _cell_at(target_tile)
	match card.tactic_effect:
		"heal":
			cell.flash(Color(0.6, 1.0, 0.6))
			cell.floating_text("+%d" % card.magnitude, Color(0.5, 1.0, 0.5))
		"damage":
			cell.flash(Color(1.0, 0.4, 0.4))
			cell.floating_text("-%d" % card.magnitude, Color(1.0, 0.4, 0.4))
			if not (result["defeated"] as Array).is_empty():
				cell.floating_text("Defeated", Color(0.8, 0.8, 0.8), 0.5)
		"buff":
			cell.flash(Color(1.0, 0.9, 0.5))
			cell.floating_text(card.card_name, Color(1.0, 0.9, 0.5))
		"burn", "chill", "sow":
			var tint: Color = {"burn": Color(1.0, 0.55, 0.2), "chill": Color(0.5, 0.8, 1.0), "sow": Color(0.5, 1.0, 0.5)}[card.tactic_effect]
			cell.flash(tint)
			cell.floating_text(card.card_name, tint)
		_:
			if action.has("destination"):
				_cell_at(action["destination"]).pulse()

func _animate_attack(result: Dictionary, positions: Dictionary) -> void:
	var steps: Array = result["steps"]
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		var cell: BattleCell = _cell_at(positions[str(step["target"])])
		var delay: float = index * STEP_DELAY
		cell.flash(Color(1.0, 0.4, 0.4), delay)
		cell.floating_text("-%d" % int(step["damage"]), Color(1.0, 0.45, 0.4), delay)
	var defeat_delay: float = steps.size() * STEP_DELAY
	for unit_id: String in result["defeated"]:
		_cell_at(positions[unit_id]).floating_text("Defeated", Color(0.85, 0.85, 0.85), defeat_delay)
	if ai_timer != null:
		ai_timer.start(AI_STEP_SECONDS + steps.size() * STEP_DELAY)

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
	_refresh_cells()
	_refresh_hand()
	_refresh_summaries()
	_refresh_controls()
	_refresh_info()
	_refresh_log()
	if _state().phase == GameState.Phase.GAME_OVER:
		handoff_panel.visible = false
		gameover_label.text = "%s wins!\n(%s)" % [_state().players[_state().winner_id].display_name, _state().game_over_reason]
		gameover_panel.visible = true

func _compute_highlights() -> void:
	highlights.clear()
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
	for enemy in state.players[1 - pid].units:
		if GameEngine.attack_error(state, active, enemy) == "":
			highlights[enemy.position] = "attack"

func _highlight_for_card(state: GameState, pid: int) -> void:
	var card: CardData = selected_card
	match card.card_type:
		CardData.CardType.UNIT:
			for y in range(BoardState.HEIGHT):
				var tile := Vector2i(state.board.deployment_column(pid), y)
				if GameEngine.deploy_error(state, pid, card, tile) == "":
					highlights[tile] = "deploy"
		CardData.CardType.EQUIPMENT:
			for unit in state.players[pid].units:
				if GameEngine.equip_error(state, pid, card, unit) == "":
					highlights[unit.position] = "target"
		CardData.CardType.PROMOTION:
			for unit in state.players[pid].units:
				if GameEngine.promote_error(state, pid, card, unit) == "":
					highlights[unit.position] = "target"
		CardData.CardType.TACTIC:
			_highlight_tactic(state, pid, card)

func _highlight_tactic(state: GameState, pid: int, card: CardData) -> void:
	if pending_target_id != "":
		for y in range(BoardState.HEIGHT):
			for x in range(BoardState.WIDTH):
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

func _refresh_cells() -> void:
	var state := _state()
	for tile: Vector2i in cells:
		var cell: BattleCell = cells[tile]
		cell.show_state(state.board.terrain_at(tile), state.board.unit_at(tile), str(highlights.get(tile, "")), state.seeds.has(tile))

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
		if seen >= 0 and index >= seen:
			visual.modulate.a = 0.0
			visual.create_tween().tween_property(visual, "modulate:a", 1.0, 0.5)
	seen_hand_sizes[viewer] = player.hand.size()

func _refresh_summaries() -> void:
	var state := _state()
	for index in range(2):
		var player: PlayerState = state.players[index]
		var fallen_names: PackedStringArray = []
		for card in player.fallen:
			fallen_names.append(card.card_name)
		var label: String = "%s %s (%s)" % [
			">" if index == state.active_player_id else "  ", player.display_name, player.commander.card.faction
		]
		summary_labels[index].text = "%s\nCommander HP %d/%d | Supply %d/%d | VP %d/6 | Deck %d | Hand %d | Discard %d\nFallen: %s" % [
			label, player.commander.current_hp, player.commander.max_hp(), player.current_supply, player.max_supply,
			player.victory_points, player.deck.size(),
			player.hand.size(), player.discard.size(), ", ".join(fallen_names) if not fallen_names.is_empty() else "none"
		]
		summary_labels[index].add_theme_color_override("font_color", OWNER_TEXT[index])

func _refresh_controls() -> void:
	var state := _state()
	var locked: bool = _input_locked()
	var in_setup: bool = state.phase == GameState.Phase.SETUP
	setup_box.visible = in_setup
	for terrain: String in setup_buttons:
		(setup_buttons[terrain] as Button).button_pressed = terrain == setup_terrain
		(setup_buttons[terrain] as Button).disabled = locked
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
	support_check.disabled = locked
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

extends SceneTree

var failures: int = 0
var first_history: Array = []
var first_hand: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	GameSettings.player_count = 4
	GameSettings.ai_enabled = true
	GameSettings.setup_tiles = 3
	await _play_tutorial(true)
	await _play_tutorial(false)
	await _test_small_view()
	await _test_quit_during_opponent()
	_test_board_defaults()
	quit(1 if failures > 0 else 0)

func _test_small_view() -> void:
	root.size = Vector2i(360, 640)
	GameSettings.confirm_actions = true
	change_scene_to_file("res://scenes/main/main_menu.tscn")
	await process_frame
	await process_frame
	_find_button(current_scene, "Tutorial").pressed.emit()
	await process_frame
	await process_frame
	var scene: Control = current_scene
	var overlay: Control = scene.get("tutorial_overlay")
	var button: Button = scene.get("tutorial_mobile_button")
	_check(is_instance_valid(overlay) and button.visible and (scene.get("tutorial_overlay_instruction") as Label).text.contains("Iron Guard"), "small view opens readable tutorial instructions")
	(scene.get("tutorial_overlay_continue") as Button).pressed.emit()
	await process_frame
	_check(not is_instance_valid(scene.get("tutorial_overlay")), "small-view instructions can be closed to use the board")
	_click_card(scene, "iron_guard")
	_click_tile(scene, Vector2i(0, 2))
	_check((scene.get("action_dialog") as ConfirmationDialog).visible, "small view presents action confirmation")
	(scene.get("action_dialog") as ConfirmationDialog).get_ok_button().pressed.emit()
	await process_frame
	_check(is_instance_valid(scene.get("tutorial_overlay")) and (scene.get("tutorial_overlay_instruction") as Label).text.contains("Iron Sword"), "small view opens the next lesson after an action")
	(scene.get("tutorial_overlay_continue") as Button).pressed.emit()
	await process_frame
	button.pressed.emit()
	_check(is_instance_valid(scene.get("tutorial_overlay")), "small-view instructions can be reopened")
	scene.call("_return_to_menu")
	await process_frame
	await process_frame
	_check(not GameSettings.tutorial_mode, "exiting an unfinished tutorial resets the mode")
	root.size = Vector2i(1440, 810)

func _test_quit_during_opponent() -> void:
	change_scene_to_file("res://scenes/main/main_menu.tscn")
	await process_frame
	await process_frame
	_find_button(current_scene, "Tutorial").pressed.emit()
	await process_frame
	await process_frame
	var scene: Control = current_scene
	var tutorial: TutorialController = scene.get("tutorial")
	for _step in range(tutorial.steps.size()):
		if not bool(scene.call("_submit", tutorial.expected_action().duplicate(true))):
			_check(false, "scripted lesson action succeeds")
			return
	_check(bool(scene.get("tutorial_busy")), "tutorial can be exited during the scripted turn")
	scene.call("_return_to_menu")
	await process_frame
	await process_frame
	_find_button(current_scene, "Tutorial").pressed.emit()
	await process_frame
	await process_frame
	var restarted: Control = current_scene
	await create_timer(0.9).timeout
	var new_tutorial: TutorialController = restarted.get("tutorial")
	_check(new_tutorial.step_index == 0 and not bool(restarted.get("tutorial_busy")) and new_tutorial.engine.state.active_player_id == 0, "quitting the opponent turn cannot affect a restarted tutorial")
	restarted.call("_return_to_menu")
	await process_frame

func _test_board_defaults() -> void:
	var old_width: int = BoardState.WIDTH
	var old_height: int = BoardState.HEIGHT
	var old_layout: String = BoardState.OBJECTIVE_LAYOUT
	BoardState.configure(9, 9, "four_corners")
	var tutorial := TutorialController.new()
	_check(tutorial.engine.state.board.width == 7 and tutorial.engine.state.board.height == 7 and tutorial.engine.state.board.objective_layout == "column" and tutorial.engine.state.players[0].commander.position == Vector2i(0, 3), "tutorial board is independent of configured board defaults")
	_check(BoardState.WIDTH == 9 and BoardState.OBJECTIVE_LAYOUT == "four_corners", "tutorial does not change board defaults")
	BoardState.configure(old_width, old_height, old_layout)

func _play_tutorial(confirmations: bool) -> void:
	GameSettings.confirm_actions = confirmations
	change_scene_to_file("res://scenes/main/main_menu.tscn")
	await process_frame
	await process_frame
	var menu: Control = current_scene
	var button: Button = _find_button(menu, "Tutorial")
	_check(button != null, "tutorial is available from the main menu")
	if button == null:
		return
	button.pressed.emit()
	await process_frame
	await process_frame
	var scene: Control = current_scene
	var tutorial: TutorialController = scene.get("tutorial") if scene != null else null
	_check(tutorial != null, "tutorial opens the guided scenario")
	if tutorial == null:
		return
	var game: GameEngine = scene.get("engine")
	var player: PlayerState = game.state.players[0]
	_check(game.state.players.size() == 2 and game.state.board.width == 7 and game.state.turn_number == 3 and player.current_supply == 6, "tutorial uses its fixed prepared state")
	_check(scene.get("ai") == null and not (scene.get("handoff_panel") as Control).visible and GameSettings.player_count == 4 and GameSettings.ai_enabled and GameSettings.setup_tiles == 3, "tutorial ignores and preserves local match settings")
	var hand_ids: Array = []
	for card: CardData in player.hand:
		hand_ids.append(card.card_id)
	if confirmations:
		first_hand = hand_ids
	else:
		_check(hand_ids == first_hand, "restarting the tutorial reproduces its initial hand")
	var cells: Dictionary = scene.get("cells")
	_check((cells[Vector2i(0, 2)] as BattleCell).tutorial_marker.visible, "next lesson tile has a visible cue")
	(scene.get("advance_button") as Button).pressed.emit()
	_check(tutorial.step_index == 0 and not (scene.get("action_dialog") as ConfirmationDialog).visible and (scene.get("message_label") as Label).text.contains("Follow"), "wrong action is blocked with an explanation")
	_click_card(scene, "iron_sword")
	_check(scene.get("selected_card") == null, "wrong card is blocked")
	_click_card(scene, "iron_guard")
	_click_tile(scene, Vector2i(2, 2))
	_check(tutorial.step_index == 0 and game.state.board.unit_at(Vector2i(0, 2)) == null, "wrong target is blocked without changing state")
	_click_tile(scene, Vector2i(0, 2))
	if confirmations:
		var dialog: ConfirmationDialog = scene.get("action_dialog")
		_check(dialog.visible, "tutorial respects action confirmation")
		dialog.get_cancel_button().pressed.emit()
		await process_frame
		_check(tutorial.step_index == 0 and scene.get("selected_card") != null, "cancelling leaves the lesson and selection unchanged")
		_click_tile(scene, Vector2i(0, 2))
	await _complete_action(scene, confirmations)
	_check(tutorial.step_index == 1 and game.state.board.unit_at(Vector2i(0, 2)).card.card_id == "iron_guard" and player.current_supply == 5, "deployment consumes supply and advances the tutorial")

	_click_card(scene, "iron_sword")
	_click_tile(scene, Vector2i(1, 3))
	await _complete_action(scene, confirmations)
	var ally: UnitState = game.state.board.unit_at(Vector2i(1, 3))
	_check(tutorial.step_index == 2 and ally.weapon_item != null and ally.weapon_item.card_id == "iron_sword", "equipment lesson applies the selected item")
	_click_card(scene, "promo_hero")
	_click_tile(scene, Vector2i(1, 3))
	await _complete_action(scene, confirmations)
	_check(tutorial.step_index == 3 and ally.promotion != null and ally.promotion.card_id == "promo_hero", "promotion lesson applies the promotion")
	_click_card(scene, "rally")
	_click_tile(scene, Vector2i(1, 3))
	await _complete_action(scene, confirmations)
	_check(tutorial.step_index == 4 and player.current_supply == 1 and ally.attack() == 8, "tactic lesson applies the buff and spends supply")
	(scene.get("advance_button") as Button).pressed.emit()
	await _complete_action(scene, confirmations)
	_check(tutorial.step_index == 5 and game.state.phase == GameState.Phase.COMMAND, "phase lesson enters command")
	_click_tile(scene, Vector2i(1, 3))
	await _complete_action(scene, confirmations)
	_check(tutorial.step_index == 6 and game.state.current_activation_unit_id == ally.instance_id, "activation lesson selects the unit")
	_click_tile(scene, Vector2i(3, 3))
	await _complete_action(scene, confirmations)
	_check(tutorial.step_index == 7 and ally.position == Vector2i(3, 3), "movement lesson reaches the objective")
	_click_tile(scene, Vector2i(4, 3))
	await _complete_action(scene, confirmations)
	_check(tutorial.step_index == 8 and game.state.board.unit_at(Vector2i(4, 3)) == null, "combat lesson resolves the attack")
	(scene.get("advance_button") as Button).pressed.emit()
	await _complete_action(scene, confirmations)
	_check(bool(scene.get("tutorial_busy")) and game.state.active_player_id == 1, "opponent turn is scripted and player input is locked")
	scene.call("_on_advance_pressed")
	_check(game.state.history.size() == 9, "player cannot advance during the opponent turn")
	for _attempt in range(40):
		if tutorial.finished or not str(scene.get("tutorial_error")).is_empty():
			break
		await create_timer(0.1).timeout
	_check(tutorial.finished and game.state.active_player_id == 0 and player.victory_points == 1 and (scene.get("tutorial_finish_button") as Button).visible, "objective scores and tutorial completes")
	_check(game.state.history.size() == 11 and int(game.state.history[9]["player"]) == 1 and int(game.state.history[10]["player"]) == 1, "scripted opponent submits two legal phase actions")
	if confirmations:
		first_history = game.state.history.duplicate(true)
	else:
		_check(game.state.history == first_history, "both tutorial runs produce identical action histories")
	(scene.get("tutorial_finish_button") as Button).pressed.emit()
	await process_frame
	await process_frame
	_check(not GameSettings.tutorial_mode and current_scene != null and current_scene.get("current_view") == "home", "finishing returns to the main menu and clears tutorial mode")

func _complete_action(scene: Control, confirmations: bool) -> void:
	var dialog: ConfirmationDialog = scene.get("action_dialog")
	if confirmations:
		if dialog.visible:
			dialog.get_ok_button().pressed.emit()
		else:
			_check(false, "expected action confirmation is visible")
	else:
		_check(not dialog.visible, "action proceeds without confirmation when disabled")
	await process_frame

func _click_card(scene: Control, card_id: String) -> void:
	for child in (scene.get("hand_box") as HBoxContainer).get_children():
		if child is CardVisual and not child.is_queued_for_deletion() and child.card.card_id == card_id:
			child.pressed.emit()
			return
	_check(false, "tutorial card exists: " + card_id)

func _click_tile(scene: Control, tile: Vector2i) -> void:
	var cells: Dictionary = scene.get("cells")
	(cells[tile] as BattleCell).pressed.emit()

func _find_button(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and (child as Button).text == text:
			return child as Button
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		print("FAIL: %s" % label)

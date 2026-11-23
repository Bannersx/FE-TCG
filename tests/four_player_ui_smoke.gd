extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	GameSettings.player_count = 4
	GameSettings.ai_enabled = false
	GameSettings.setup_tiles = 0
	GameSettings.confirm_actions = false
	var scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var engine: GameEngine = scene.get("engine")
	var board: GridContainer = scene.get("board_grid")
	var handoff: Control = scene.get("handoff_panel")
	var advance: Button = scene.get("advance_button")
	var wait: Button = scene.get("wait_button")
	_check(engine.state.players.size() == 4 and board.get_child_count() == 81, "hot-seat renders four players on 81 tiles")
	_check(advance.disabled and wait.disabled and _phase_button_contrast(advance) and _phase_button_contrast(wait), "phase controls remain readable in enabled and disabled states")
	var summaries: Array = scene.get("summary_panels")
	_check(summaries.size() == 4 and (summaries[0].get_parent() as GridContainer).columns == 2, "hot-seat renders four player panels in two columns")
	var first: PlayerSummary = summaries[0]
	var player: PlayerState = engine.state.players[0]
	var original_hp: int = player.commander.current_hp
	player.commander.current_hp = 3
	player.max_supply = 2
	player.current_supply = 4
	player.victory_points = 3
	player.fallen.append(CardCatalog.get_card("ash_reaver"))
	scene.call("_refresh_summaries")
	_check(first.title.text.contains(player.display_name) and first.faction.text.contains("Active turn"), "panel identifies the active player and faction")
	_check(first.health_value.text.contains("3 /") and int(first.health_bar.value) == 3, "panel shows commander HP and health meter")
	_check(first.supply_value.text.contains("4 / 2") and first.supply_value.text.contains("+2 bonus") and first.supply_pips[2].color == PlayerSummary.GOLD, "panel distinguishes bonus supply above the normal maximum")
	_check(first.victory_value.text.contains("3 / 6") and int(first.victory_bar.value) == 3, "panel shows victory points and progress")
	_check(first.deck_value.text == "Deck %d" % player.deck.size() and first.hand_value.text == "Hand %d" % player.hand.size() and first.discard_value.text == "Discard %d" % player.discard.size(), "panel shows public card counts")
	_check(first.fallen_value.text.contains("Ash Reaver"), "panel retains fallen unit names")
	player.commander.current_hp = original_hp
	player.max_supply = 1
	player.current_supply = 1
	player.victory_points = 0
	player.fallen.clear()
	engine.state.players[1].eliminated = true
	scene.call("_refresh_summaries")
	_check((summaries[1] as PlayerSummary).faction.text.contains("Eliminated"), "eliminated player is identified in the panel")
	engine.state.players[1].eliminated = false
	scene.call("_refresh_summaries")
	await process_frame
	var summary_scroll: ScrollContainer = scene.get("summary_scroll")
	var summary_grid: GridContainer = first.get_parent()
	_check(summary_grid.size.x <= summary_scroll.size.x + 1.0, "four player panels fit without horizontal clipping")
	_check(summary_scroll.get_v_scroll_bar().max_value <= summary_scroll.get_v_scroll_bar().page, "all four default player panels fit without scrolling")
	for _index in range(20):
		player.fallen.append(CardCatalog.get_card("ash_reaver"))
	scene.call("_refresh_summaries")
	await process_frame
	await process_frame
	_check(summary_scroll.get_v_scroll_bar().max_value > summary_scroll.get_v_scroll_bar().page, "long fallen lists keep all player panels scrollable")
	player.fallen.clear()
	scene.call("_refresh_summaries")
	var original_size: Vector2i = root.size
	root.size = Vector2i(360, 640)
	await process_frame
	scene.call("_update_status_button")
	var status_button: Button = scene.get("status_button")
	_check(status_button.visible, "small viewports offer an enlarged player status view")
	status_button.pressed.emit()
	var expanded: Array = scene.get("status_panels")
	_check(expanded.size() == 4 and (expanded[0] as PlayerSummary).ui_scale > 1.0, "expanded status view scales all four panels for small screens")
	player.current_supply = 4
	scene.call("_refresh_summaries")
	_check((expanded[0] as PlayerSummary).supply_value.text.contains("4 / 1"), "expanded status stays synchronized with game state")
	player.current_supply = 1
	root.size = original_size
	await process_frame
	scene.call("_update_status_button")
	expanded = scene.get("status_panels")
	var expected_scale: float = clampf(1.0 / absf(root.get_screen_transform().get_scale().x), 1.0, 6.0)
	_check(expanded.size() == 4 and is_equal_approx((expanded[0] as PlayerSummary).ui_scale, expected_scale), "expanded status view rescales when the window changes size")
	scene.call("_close_player_status")
	_check((scene.get("status_panels") as Array).is_empty(), "expanded status view closes cleanly")
	_check(handoff.visible, "first hand is hidden until handoff")
	scene.call("_on_handoff_ready")
	_check(not advance.disabled and wait.disabled and advance.text == "Go to Command Phase", "deployment shows the available phase button and disabled wait")
	var unit_card: CardData
	for card: CardData in engine.state.active_player().hand:
		if card.card_type == CardData.CardType.UNIT and card.supply_cost <= engine.state.active_player().current_supply:
			unit_card = card
			break
	scene.set("selected_card", unit_card)
	scene.call("_compute_highlights")
	_check(unit_card != null and not (scene.get("highlights") as Dictionary).is_empty(), "selected unit highlights its corner deployment zone")
	scene.set("selected_card", null)
	scene.call("_on_advance_pressed")
	_check(advance.text == "End Turn" and not advance.disabled and wait.disabled, "phase button changes to End Turn in command")
	scene.call("_on_tile_pressed", engine.state.players[0].commander.position)
	_check(not wait.disabled, "wait becomes available when a unit is active")
	scene.call("_on_wait_pressed")
	_check(wait.disabled, "wait becomes unavailable after ending the activation")
	scene.call("_on_advance_pressed")
	_check(engine.state.active_player_id == 1 and handoff.visible, "ending a turn presents the next player handoff")
	scene.queue_free()
	await process_frame
	GameSettings.setup_tiles = 3
	var setup_scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
	root.add_child(setup_scene)
	await process_frame
	var setup_engine: GameEngine = setup_scene.get("engine")
	var setup_buttons: Dictionary = setup_scene.get("setup_buttons")
	var finish_setup: Button = setup_scene.get("finish_setup_button")
	_check(setup_buttons.size() == BoardState.PLACEABLE.size() and setup_buttons.has(BoardState.SHRINE), "setup displays buttons for all terrain")
	_check(finish_setup.disabled and _phase_button_contrast(finish_setup), "finish setup is readable and disabled during handoff")
	setup_scene.call("_on_handoff_ready")
	_check(not finish_setup.disabled, "finish setup becomes available after handoff")
	setup_scene.call("_on_terrain_picked", BoardState.ROAD)
	_check((setup_scene.get("setup_description") as Label).text.contains("+1 movement"), "selected terrain explains its effect")
	var tile := Vector2i(3, 0)
	setup_scene.call("_on_tile_pressed", tile)
	_check(setup_engine.state.board.terrain_at(tile) == BoardState.ROAD, "four-player setup can place new terrain")
	_check(finish_setup.disabled, "finish setup is disabled during the next handoff")
	setup_scene.queue_free()
	await process_frame
	GameSettings.setup_tiles = 0
	var animated_scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
	root.add_child(animated_scene)
	await process_frame
	animated_scene.call("_on_handoff_ready")
	var animated_game: GameEngine = animated_scene.get("engine")
	var moving := UnitState.new()
	moving.initialize(animated_game.state.create_instance_id(), CardCatalog.get_card("ash_reaver"), 0, Vector2i(1, 3), 1)
	animated_game.state.board.place_unit(moving, moving.position)
	animated_game.state.players[0].units.append(moving)
	animated_game.state.phase = GameState.Phase.COMMAND
	animated_game.state.turn_number = 5
	animated_scene.call("_refresh")
	animated_scene.call("_submit", {"type": "start_activation", "unit_id": moving.instance_id})
	animated_scene.call("_submit", {"type": "move", "destination": Vector2i(2, 3)})
	var layer: Control = animated_scene.get("effect_layer")
	_check(moving.position == Vector2i(2, 3) and layer.get_child_count() > 0, "movement shows an animated unit without delaying the game state")
	await create_timer(0.6).timeout
	_check(layer.get_child_count() == 0, "movement effects clean themselves up")
	(animated_scene.get("reduce_motion_check") as CheckBox).button_pressed = true
	animated_scene.call("_submit", {"type": "wait"})
	animated_game.state.activated_unit_ids.clear()
	moving.exhausted = false
	animated_scene.call("_submit", {"type": "start_activation", "unit_id": moving.instance_id})
	animated_scene.call("_submit", {"type": "move", "destination": Vector2i(1, 3)})
	_check(GameSettings.reduce_motion and moving.position == Vector2i(1, 3) and layer.get_child_count() == 0, "reduced motion keeps movement functional without moving effects")
	(animated_scene.get("reduce_motion_check") as CheckBox).button_pressed = false
	animated_scene.call("_submit", {"type": "wait"})
	animated_game.state.activated_unit_ids.clear()
	moving.exhausted = false
	animated_game.state.board.move_unit(moving, Vector2i(2, 3))
	var enemy := UnitState.new()
	enemy.initialize(animated_game.state.create_instance_id(), CardCatalog.get_card("iron_guard"), 1, Vector2i(3, 3), 1)
	enemy.current_hp = 1
	animated_game.state.board.place_unit(enemy, enemy.position)
	animated_game.state.players[1].units.append(enemy)
	animated_scene.call("_submit", {"type": "start_activation", "unit_id": moving.instance_id})
	animated_scene.call("_submit", {"type": "attack", "target_id": enemy.instance_id})
	var attack_effect: bool = false
	var defeat_effect: bool = false
	for child in layer.get_children():
		if child is Label:
			attack_effect = attack_effect or child.text == "/"
			defeat_effect = defeat_effect or child.text == enemy.display_name()
	_check(attack_effect and defeat_effect and not animated_game.state.players[1].units.has(enemy), "combat renders an attack and defeated unit from the authoritative result")
	animated_game.state.players[0].hand.assign([CardCatalog.get_card("reposition")])
	animated_game.state.players[0].current_supply = 2
	animated_scene.call("_submit", {"type": "play_tactic", "card_id": "reposition", "target_id": moving.instance_id, "destination": Vector2i(1, 3)})
	_check(moving.position == Vector2i(1, 3) and layer.get_child_count() > 0, "a reposition tactic shows card and movement effects")
	(animated_scene.get("reduce_motion_check") as CheckBox).button_pressed = true
	var restored_cell: BattleCell = (animated_scene.get("cells") as Dictionary)[Vector2i(1, 3)]
	_check(not restored_cell.text.is_empty(), "enabling reduced motion restores a unit during an ongoing move")
	(animated_scene.get("reduce_motion_check") as CheckBox).button_pressed = false
	await process_frame
	animated_game.state.board.terrain[moving.position] = BoardState.LAVA
	animated_scene.call("_submit", {"type": "advance_phase"})
	var turn_handoff: Control = animated_scene.get("handoff_panel")
	var lava_banner: bool = false
	for child in layer.get_children():
		if child is Label and child.text.begins_with("Lava"):
			lava_banner = true
	_check(turn_handoff.visible and layer.get_index() > turn_handoff.get_index() and lava_banner, "turn effects remain visible while hot-seat handoff hides the hand")
	animated_scene.queue_free()
	await process_frame
	var online_game := GameEngine.new(17, [], false, [], 0, 4)
	var snapshot: Dictionary = GameStateCodec.decode(GameStateCodec.encode(online_game.state, 2))
	_check(bool(snapshot["ok"]), "four-player online snapshot is valid")
	if bool(snapshot["ok"]):
		var online: Node = root.get_node("OnlineMatch")
		online.set("mode", "client")
		online.set("local_player_id", 2)
		online.set("current_state", snapshot["state"])
		var online_scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
		root.add_child(online_scene)
		await process_frame
		_check((online_scene.get("board_grid") as GridContainer).get_child_count() == 81, "online game renders the four-player board")
		var online_panels: Array = online_scene.get("summary_panels")
		_check((online_panels[0] as PlayerSummary).hand_value.text == "Hand %d" % (snapshot["state"] as GameState).players[0].hand.size(), "online panels display opponent hand counts without card identities")
		_check(bool(online_scene.call("_input_locked")), "online player cannot act on another player's turn")
		_check(not (online_scene.get("handoff_panel") as Control).visible, "online game does not show hot-seat handoff")
		online_scene.queue_free()
		await process_frame
		online.set("mode", "offline")
	await _test_confirmations()
	await _test_range_and_card_cues()
	quit(1 if failures > 0 else 0)

func _test_range_and_card_cues() -> void:
	GameSettings.player_count = 4
	GameSettings.setup_tiles = 0
	GameSettings.ai_enabled = false
	GameSettings.confirm_actions = false
	var scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.call("_on_handoff_ready")
	var game: GameEngine = scene.get("engine")
	game.state.turn_number = 5
	game.state.players[0].current_supply = 6
	var scout := _spawn_ui_unit(game, "ridge_scout", Vector2i(4, 4), 1)
	var blade := _spawn_ui_unit(game, "oakblade", Vector2i(3, 4), 1)
	var veteran := _spawn_ui_unit(game, "stonewall", Vector2i(1, 3), 1)
	var newcomer := _spawn_ui_unit(game, "stonewall", Vector2i(2, 3), 5)
	game.state.board.terrain[Vector2i(4, 3)] = BoardState.MOUNTAIN
	game.state.board.terrain[Vector2i(5, 4)] = BoardState.RIVER
	scene.call("_refresh")
	scene.call("_on_tile_hover", scout.position)
	var previews: Dictionary = scene.get("range_previews")
	var cells: Dictionary = scene.get("cells")
	_check(not previews.has(scout.position) and bool(previews[Vector2i(5, 4)]["move"]) and bool(previews[Vector2i(5, 4)]["attack"]), "hover previews both movement and attack from the unit's current tile")
	_check(not (previews[Vector2i(4, 3)] as Dictionary).has("move") and bool(previews[Vector2i(4, 3)]["attack"]), "attack coverage includes impassable terrain but movement excludes it")
	_check(not (previews[blade.position] as Dictionary).has("move") and bool(previews[blade.position]["attack"]), "occupied tiles block movement but remain in attack coverage")
	_check(not previews.has(Vector2i(7, 4)), "tiles outside both ranges are not marked")
	var river_cell: BattleCell = cells[Vector2i(5, 4)]
	_check(river_cell.movement_marker.visible and river_cell.attack_marker.visible, "overlapping ranges display both visual markers")
	scout.weapon_item = CardCatalog.get_card("longbow")
	scout.exhausted = true
	scene.call("_on_tile_hover", scout.position)
	previews = scene.get("range_previews")
	_check(bool(previews[Vector2i(7, 4)]["attack"]), "hover uses live equipment range even for an exhausted unit")
	scene.call("_on_tile_unhover", scout.position)
	_check((scene.get("range_previews") as Dictionary).is_empty() and not river_cell.movement_marker.visible and not river_cell.attack_marker.visible, "range cues clear when the pointer leaves")
	scout.exhausted = false

	var sword: CardData = CardCatalog.get_card("iron_sword")
	var promotion: CardData = CardCatalog.get_card("promo_general")
	game.state.players[0].hand.assign([sword, promotion])
	scene.call("_on_tile_hover", scout.position)
	scene.call("_on_card_pressed", sword)
	var highlights: Dictionary = scene.get("highlights")
	_check((scene.get("range_previews") as Dictionary).is_empty(), "card selection replaces range previews with target cues")
	_check(highlights[blade.position] == "eligible" and (cells[blade.position] as BattleCell).target_marker.text == "OK", "compatible equipment target is marked eligible")
	_check(highlights[scout.position] == "ineligible" and (cells[scout.position] as BattleCell).target_marker.text == "X" and (cells[scout.position] as BattleCell).tooltip_text.contains("cannot use"), "incompatible equipment target shows the reason")
	var enemy: UnitState = game.state.players[1].commander
	_check(highlights[enemy.position] == "ineligible", "opponent units are marked unavailable")
	scene.call("_on_card_pressed", promotion)
	_check(highlights[veteran.position] == "eligible" and highlights[newcomer.position] == "ineligible" and (cells[newcomer.position] as BattleCell).tooltip_text.contains("earlier turn"), "promotion cues enforce class and deployment timing")
	game.state.players[0].current_supply = 0
	scene.call("_refresh")
	_check(highlights[veteran.position] == "ineligible" and (cells[veteran.position] as BattleCell).tooltip_text.contains("supply"), "target cues update when supply prevents a card play")
	scene.call("_on_card_pressed", promotion)
	_check(not (cells[veteran.position] as BattleCell).target_marker.visible, "target markers clear when the card is deselected")
	scene.call("_on_tile_hover", scout.position)
	game.state.board.move_unit(scout, Vector2i(5, 4))
	scene.call("_refresh")
	_check((scene.get("range_previews") as Dictionary).is_empty(), "range previews clear when the hovered unit moves away")
	var nearby_enemy := UnitState.new()
	nearby_enemy.initialize(game.state.create_instance_id(), CardCatalog.get_card("ash_reaver"), 1, Vector2i(6, 4), 1)
	game.state.board.place_unit(nearby_enemy, nearby_enemy.position)
	game.state.players[1].units.append(nearby_enemy)
	scene.call("_submit", {"type": "advance_phase"})
	scene.call("_submit", {"type": "start_activation", "unit_id": scout.instance_id})
	scene.call("_on_tile_hover", nearby_enemy.position)
	_check(highlights[nearby_enemy.position] == "attack", "hover previews preserve actionable attack highlights")
	scene.queue_free()
	await process_frame

	var online: Node = root.get_node("OnlineMatch")
	var online_game := GameEngine.new(17)
	online.set("mode", "client")
	online.set("local_player_id", 1)
	online.set("current_state", online_game.state)
	var online_scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
	root.add_child(online_scene)
	await process_frame
	online_scene.call("_on_tile_hover", online_game.state.players[0].commander.position)
	_check(bool(online_scene.call("_input_locked")) and not (online_scene.get("range_previews") as Dictionary).is_empty(), "online players can inspect visible units while waiting for their turn")
	online_scene.queue_free()
	await process_frame
	online.set("mode", "offline")
	GameSettings.confirm_actions = true

func _spawn_ui_unit(game: GameEngine, card_id: String, tile: Vector2i, turn: int) -> UnitState:
	var unit := UnitState.new()
	unit.initialize(game.state.create_instance_id(), CardCatalog.get_card(card_id), 0, tile, turn)
	game.state.board.place_unit(unit, tile)
	game.state.players[0].units.append(unit)
	return unit

func _test_confirmations() -> void:
	GameSettings.player_count = 2
	GameSettings.setup_tiles = 0
	GameSettings.confirm_actions = true
	var scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.call("_on_handoff_ready")
	var game: GameEngine = scene.get("engine")
	var dialog: ConfirmationDialog = scene.get("action_dialog")
	var guard: CardData = CardCatalog.get_card("iron_guard")
	var tactic: CardData = CardCatalog.get_card("reposition")
	game.state.active_player().hand.assign([guard, tactic])
	game.state.active_player().current_supply = 6
	var deploy_tile := Vector2i(-1, -1)
	for y in range(game.state.board.height):
		for x in range(game.state.board.width):
			var tile := Vector2i(x, y)
			if GameEngine.deploy_error(game.state, 0, guard, tile) == "":
				deploy_tile = tile
				break
		if deploy_tile.x >= 0:
			break
	var original_size: Vector2i = root.size
	root.size = Vector2i(360, 640)
	await process_frame
	scene.call("_on_card_pressed", guard)
	scene.call("_on_tile_pressed", deploy_tile)
	await process_frame
	_check(dialog.visible and dialog.dialog_text.contains(guard.card_name) and game.state.board.unit_at(deploy_tile) == null, "deployment waits for confirmation and describes the chosen card")
	_check(dialog.size.x <= scene.get_viewport_rect().size.x and dialog.get_label().get_theme_font_size("font_size") == roundi(16 * float(scene.call("_status_ui_scale"))), "confirmation fits and scales on a narrow viewport")
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	_check(not dialog.visible and game.state.board.unit_at(deploy_tile) == null and scene.get("selected_card") == guard, "cancelling deployment preserves the card selection")
	root.size = original_size
	await process_frame
	scene.call("_on_tile_pressed", deploy_tile)
	dialog.get_ok_button().pressed.emit()
	await process_frame
	var deployed: UnitState = game.state.board.unit_at(deploy_tile)
	_check(deployed != null and scene.get("selected_card") == null, "confirming deployment applies it once")

	var commander: UnitState = game.state.players[0].commander
	var tactic_tile := Vector2i(-1, -1)
	for y in range(game.state.board.height):
		for x in range(game.state.board.width):
			var tile := Vector2i(x, y)
			if GameEngine.tactic_error(game.state, 0, tactic, commander.instance_id, tile) == "":
				tactic_tile = tile
				break
		if tactic_tile.x >= 0:
			break
	scene.call("_on_card_pressed", tactic)
	scene.call("_on_tile_pressed", commander.position)
	scene.call("_on_tile_pressed", tactic_tile)
	_check(dialog.visible and dialog.dialog_text.contains(tactic.card_name) and commander.position != tactic_tile, "two-target tactics wait for confirmation")
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	_check(scene.get("selected_card") == tactic and scene.get("pending_target_id") == commander.instance_id, "cancelling a tactic retains its selected unit")
	scene.call("_on_tile_pressed", tactic_tile)
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check(commander.position == tactic_tile and scene.get("pending_target_id") == "", "confirming a tactic submits its selected target and destination")

	scene.call("_on_advance_pressed")
	_check(dialog.visible and game.state.phase == GameState.Phase.DEPLOYMENT, "phase change waits for confirmation")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	scene.call("_on_tile_pressed", commander.position)
	_check(dialog.visible and game.state.current_activation_unit_id == "", "activation waits for confirmation")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	var move_tile := Vector2i(-1, -1)
	for tile: Vector2i in MovementResolver.reachable_tiles(game.state.board, commander):
		if tile != commander.position:
			move_tile = tile
			break
	var before_move: Vector2i = commander.position
	scene.call("_on_tile_pressed", move_tile)
	_check(dialog.visible and commander.position == before_move, "movement waits for confirmation")
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	_check(commander.position == before_move, "cancelling movement leaves the unit in place")
	scene.call("_on_tile_pressed", move_tile)
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check(commander.position == move_tile, "confirming movement moves the active unit")
	var enemy := UnitState.new()
	var enemy_tile := Vector2i(-1, -1)
	for delta: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var tile: Vector2i = commander.position + delta
		if game.state.board.is_valid_position(tile) and game.state.board.unit_at(tile) == null:
			enemy_tile = tile
			break
	enemy.initialize(game.state.create_instance_id(), CardCatalog.get_card("ash_reaver"), 1, enemy_tile, 1)
	game.state.board.place_unit(enemy, enemy_tile)
	game.state.players[1].units.append(enemy)
	var enemy_hp: int = enemy.current_hp
	scene.call("_on_tile_pressed", enemy_tile)
	_check(dialog.visible and dialog.dialog_text.contains(enemy.display_name()) and enemy.current_hp == enemy_hp, "attack identifies its target and waits for confirmation")
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	_check(enemy.current_hp == enemy_hp, "cancelling attack leaves the target unharmed")
	scene.call("_on_tile_pressed", enemy_tile)
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check(enemy.current_hp < enemy_hp, "confirming attack resolves combat")
	game.state.turn_number = 5
	deployed.deployed_turn = 1
	scene.call("_on_tile_pressed", deployed.position)
	dialog.get_ok_button().pressed.emit()
	await process_frame
	scene.call("_on_wait_pressed")
	_check(dialog.visible and game.state.current_activation_unit_id == deployed.instance_id, "waiting requires confirmation")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check(game.state.current_activation_unit_id == "", "confirming wait ends the activation")
	(scene.get("confirm_actions_check") as CheckBox).button_pressed = false
	scene.call("_on_advance_pressed")
	_check(not GameSettings.confirm_actions and game.state.active_player_id == 1, "disabling confirmations acts immediately")
	scene.queue_free()
	await process_frame

	GameSettings.setup_tiles = 3
	GameSettings.confirm_actions = true
	var setup_scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
	root.add_child(setup_scene)
	await process_frame
	setup_scene.call("_on_handoff_ready")
	setup_scene.call("_on_terrain_picked", BoardState.ROAD)
	var setup_game: GameEngine = setup_scene.get("engine")
	var tile := Vector2i(1, 0)
	var old_terrain: String = setup_game.state.board.terrain_at(tile)
	setup_scene.call("_on_tile_pressed", tile)
	dialog = setup_scene.get("action_dialog")
	_check(dialog.visible and setup_game.state.board.terrain_at(tile) == old_terrain, "terrain placement waits for confirmation")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check(setup_game.state.board.terrain_at(tile) == BoardState.ROAD, "confirmed terrain placement applies")
	setup_scene.call("_on_handoff_ready")
	var finish: Button
	for child in (setup_scene.get("setup_box") as Control).get_children():
		if child is Button and child.text == "Finish setup":
			finish = child
	if finish != null:
		finish.pressed.emit()
	_check(finish != null and dialog.visible and int(setup_game.state.setup_left[1]) > 0, "finishing terrain setup waits for confirmation")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	_check(int(setup_game.state.setup_left[1]) == 0, "confirming finish setup passes remaining placements")
	setup_scene.queue_free()
	await process_frame

	var online: Node = root.get_node("OnlineMatch")
	var online_game := GameEngine.new(17)
	online.set("mode", "client")
	online.set("local_player_id", 0)
	online.set("current_state", online_game.state)
	var online_scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
	root.add_child(online_scene)
	await process_frame
	online_scene.call("_on_advance_pressed")
	dialog = online_scene.get("action_dialog")
	_check(dialog.visible and not bool(online.get("action_pending")), "online action is not sent before confirmation")
	online_scene.call("_on_online_snapshot", online_game.state, 0)
	_check(not dialog.visible and (online_scene.get("pending_action") as Dictionary).is_empty(), "a new online snapshot cancels a stale confirmation")
	dialog.confirmed.emit()
	_check(not bool(online.get("action_pending")), "a stale confirmation cannot submit an action")
	online_scene.queue_free()
	await process_frame
	online.set("mode", "offline")
	GameSettings.setup_tiles = 0
	GameSettings.confirm_actions = true

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		print("FAIL: %s" % label)

func _phase_button_contrast(button: Button) -> bool:
	var styles: Dictionary = {
		"normal": "font_color",
		"hover": "font_hover_color",
		"pressed": "font_pressed_color",
		"disabled": "font_disabled_color",
	}
	for state: String in styles:
		var style: StyleBoxFlat = button.get_theme_stylebox(state)
		if style == null:
			return false
		var foreground: float = _luminance(button.get_theme_color(styles[state]))
		var background: float = _luminance(style.bg_color)
		if (maxf(foreground, background) + 0.05) / (minf(foreground, background) + 0.05) < 4.5:
			return false
	return button.has_theme_stylebox_override("focus")

func _luminance(color: Color) -> float:
	var values: Array[float] = [color.r, color.g, color.b]
	for index in range(values.size()):
		values[index] = values[index] / 12.92 if values[index] <= 0.04045 else pow((values[index] + 0.055) / 1.055, 2.4)
	return 0.2126 * values[0] + 0.7152 * values[1] + 0.0722 * values[2]

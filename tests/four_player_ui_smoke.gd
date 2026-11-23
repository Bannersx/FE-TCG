extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	GameSettings.player_count = 4
	GameSettings.ai_enabled = false
	GameSettings.setup_tiles = 0
	var scene: Control = load("res://scenes/main/game_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var engine: GameEngine = scene.get("engine")
	var board: GridContainer = scene.get("board_grid")
	var handoff: Control = scene.get("handoff_panel")
	_check(engine.state.players.size() == 4 and board.get_child_count() == 81, "hot-seat renders four players on 81 tiles")
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
	_check(setup_buttons.size() == BoardState.PLACEABLE.size() and setup_buttons.has(BoardState.SHRINE), "setup displays buttons for all terrain")
	setup_scene.call("_on_handoff_ready")
	setup_scene.call("_on_terrain_picked", BoardState.ROAD)
	_check((setup_scene.get("setup_description") as Label).text.contains("+1 movement"), "selected terrain explains its effect")
	var tile := Vector2i(3, 0)
	setup_scene.call("_on_tile_pressed", tile)
	_check(setup_engine.state.board.terrain_at(tile) == BoardState.ROAD, "four-player setup can place new terrain")
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
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		print("FAIL: %s" % label)

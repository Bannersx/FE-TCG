extends SceneTree

var failures: int = 0
var online: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	online = root.get_node("OnlineMatch")
	var menu: Control = load("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var views: Dictionary = menu.get("views")
	_check(str(menu.get("current_view")) == "home", "menu opens on home")
	var motion: CheckBox
	for child in views["home"].get_children():
		if child is CheckBox and child.text == "Reduce motion":
			motion = child
	if motion != null:
		motion.button_pressed = true
	_check(motion != null and GameSettings.reduce_motion, "main menu can enable reduced motion")
	if motion != null:
		motion.button_pressed = false
	_press(views["home"], "Local Play")
	var seats: Array = menu.get("seat_panels")
	var mode: OptionButton = menu.get("local_mode_picker")
	_check(str(menu.get("current_view")) == "local" and seats[0].visible and seats[1].visible and not seats[2].visible, "two-player setup shows only two seats")
	mode.select(1)
	mode.item_selected.emit(1)
	_check(seats[2].visible and seats[3].visible, "four-player setup shows all seats")
	var armies: Array = menu.get("army_pickers")
	armies[3].select(2)
	armies[3].item_selected.emit(2)
	root.size = Vector2i(360, 640)
	await create_timer(0.2).timeout
	var panel: Control = menu.get("menu_panel")
	var menu_rect: Rect2 = menu.get_global_rect()
	var panel_rect: Rect2 = panel.get_global_rect()
	_check(panel_rect.position.x >= menu_rect.position.x and panel_rect.end.x <= menu_rect.end.x + 1.0, "menu fits a narrow viewport without horizontal clipping")
	var menu_scroll: ScrollContainer = menu.get("scroll")
	var scrollbar: VScrollBar = menu_scroll.get_v_scroll_bar()
	_check(scrollbar.max_value > scrollbar.page, "four-player settings remain vertically scrollable on a small viewport")
	root.size = Vector2i(1440, 810)
	await create_timer(0.2).timeout
	_check(mode.selected == 1 and armies[3].selected == 2, "resizing preserves local selections")
	_press(views["local"], "Back")
	_press(views["home"], "Local Play")
	_check(mode.selected == 1 and armies[3].selected == 2, "local selections survive navigation")
	mode.select(2)
	mode.item_selected.emit(2)
	_check((menu.get("difficulty_row") as Control).visible and not seats[2].visible, "computer mode shows difficulty and two seats")
	_press(views["local"], "Back")
	_press(views["home"], "Online Play")
	_press(views["online"], "Create Room")
	var forms: Dictionary = menu.get("online_forms")
	var create: Dictionary = forms["create"]
	var join: Dictionary = forms["join"]
	_press(views["create"], "Generate Room Code")
	var code: LineEdit = create["code"]
	_check(code.text.length() == 8, "creator can generate a room code")
	(create["port"] as LineEdit).text = "0"
	(create["submit"] as Button).pressed.emit()
	_check((create["status"] as Label).text.contains("valid UDP port") and online.get("mode") == "offline", "invalid port is reported without connecting")
	_press(views["create"], "Back")
	_press(views["online"], "Join Room")
	_check(str(menu.get("current_view")) == "join" and not join.has("setup"), "join is a separate view without creator terrain settings")
	_press(views["join"], "Back")
	_press(views["online"], "Create Room")
	_check(code.text.length() == 8 and (create["port"] as LineEdit).text == "0", "online form selections survive navigation")

	var options: Dictionary = _options()
	if options.has("port") and options.has("join_code"):
		await _test_online(views, create, join, options)
	_press(views["create"] if str(menu.get("current_view")) == "create" else views["join"], "Back")
	_press(views["online"], "Back")
	_press(views["home"], "Local Play")
	mode.select(1)
	mode.item_selected.emit(1)
	_press(views["local"], "Start Match")
	for _frame in range(3):
		await process_frame
	var game: Control = current_scene
	var game_engine: GameEngine = game.get("engine") if game != null else null
	_check(game_engine != null and game_engine.state.players.size() == 4, "local start launches the selected four-player game")
	if game != null:
		game.queue_free()
	await process_frame
	mode.select(2)
	mode.item_selected.emit(2)
	var difficulty: OptionButton = menu.get("difficulty_picker")
	difficulty.select(0)
	_press(views["local"], "Start Match")
	for _frame in range(3):
		await process_frame
	game = current_scene
	var computer: AIController = game.get("ai") if game != null else null
	_check(computer != null and computer.difficulty == AIController.Difficulty.EASY, "computer match starts with the selected difficulty")
	var summaries: Array = game.get("summary_panels") if game != null else []
	_check(summaries.size() == 2 and (summaries[0].get_parent() as GridContainer).columns == 1, "two-player game uses full-width player panels")
	if computer != null:
		game.call("_on_advance_pressed")
		game.call("_on_advance_pressed")
		game_engine = game.get("engine")
		var computer_acted: bool = false
		for _attempt in range(50):
			for entry: Dictionary in game_engine.state.history:
				if int(entry["player"]) == 1:
					computer_acted = true
			if computer_acted:
				break
			await create_timer(0.1).timeout
		_check(computer_acted, "computer submits an action on its turn")
	if game != null:
		game.queue_free()
	await process_frame
	if options.has("port") and options.has("ready_code") and options.has("ready_role"):
		await _test_match_ready(views, forms, options)
	menu.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)

func _test_online(views: Dictionary, create: Dictionary, join: Dictionary, options: Dictionary) -> void:
	(create["port"] as LineEdit).text = str(options["port"])
	(create["code"] as LineEdit).text = "MENUCREATE"
	(create["player_count"] as OptionButton).select(1)
	(create["submit"] as Button).pressed.emit()
	await _wait_for_room()
	_check(online.get("mode") == "waiting" and (create["status"] as Label).text.contains("3 more"), "create view reaches a four-player room")
	_check((create["submit"] as Button).disabled and not (create["code"] as LineEdit).editable and (create["generate"] as Button).disabled, "waiting room locks connection settings")
	_press(views["create"], "Back")
	_check(online.get("mode") == "offline" and (create["code"] as LineEdit).editable and (create["status"] as Label).text == "Connection cancelled.", "back cancels the active room connection and unlocks settings")
	_press(views["online"], "Join Room")
	(join["port"] as LineEdit).text = str(options["port"])
	(join["code"] as LineEdit).text = str(options["join_code"])
	(join["player_count"] as OptionButton).select(1)
	(join["submit"] as Button).pressed.emit()
	await _wait_for_room()
	_check(online.get("mode") == "waiting" and (join["status"] as Label).text.contains("2 more"), "join view connects to an existing four-player room")
	_press(views["join"], "Back")
	_check(online.get("mode") == "offline", "back disconnects after joining")
	_press(views["online"], "Create Room")

func _wait_for_room() -> void:
	for _attempt in range(80):
		if online.get("mode") in ["waiting", "client"]:
			return
		await create_timer(0.1).timeout

func _test_match_ready(views: Dictionary, forms: Dictionary, options: Dictionary) -> void:
	_press(views["local"], "Back")
	_press(views["home"], "Online Play")
	var create_room: bool = str(options["ready_role"]) == "create"
	_press(views["online"], "Create Room" if create_room else "Join Room")
	var form: Dictionary = forms["create" if create_room else "join"]
	(form["port"] as LineEdit).text = str(options["port"])
	(form["code"] as LineEdit).text = str(options["ready_code"])
	(form["submit"] as Button).pressed.emit()
	await _wait_for_room()
	_check(online.get("mode") in ["waiting", "client"], "online %s flow reaches its room" % str(options["ready_role"]))
	print("READY_FOR_PEER")
	for _attempt in range(120):
		if online.get("mode") == "client" and current_scene != null:
			break
		await create_timer(0.1).timeout
	var scene: Control = current_scene
	var game_engine: GameEngine = scene.get("engine") if scene != null else null
	_check(game_engine != null and game_engine.state.players.size() == 2 and online.get("mode") == "client", "online %s flow opens the game when the room fills" % str(options["ready_role"]))
	online.call("disconnect_from_server")
	if scene != null:
		scene.queue_free()
	await process_frame

func _options() -> Dictionary:
	var result: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.trim_prefix("--").split("=", false, 1)
			result[parts[0]] = parts[1]
	return result

func _press(parent: Node, text: String) -> void:
	var button: Button = _find_button(parent, text)
	if button == null:
		_check(false, "button exists: " + text)
		return
	button.pressed.emit()

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

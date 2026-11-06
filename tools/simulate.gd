extends SceneTree

# Batch AI-vs-AI simulation.
# Usage: godot --headless --path . --script res://tools/simulate.gd -- games=100 first=normal second=easy seed=1

func _initialize() -> void:
	var games: int = 100
	var first: AIController.Difficulty = AIController.Difficulty.NORMAL
	var second: AIController.Difficulty = AIController.Difficulty.NORMAL
	var base_seed: int = 1
	var army_ids: Array[String] = [ArmyCatalog.IRONCREST_ID, ArmyCatalog.ASHEN_ID]
	var width: int = BoardState.DEFAULT_WIDTH
	var height: int = BoardState.DEFAULT_HEIGHT
	var setup_tiles: int = 0
	var layout: String = "column"
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"games": games = int(parts[1])
			"first": first = _difficulty(parts[1])
			"second": second = _difficulty(parts[1])
			"seed": base_seed = int(parts[1])
			"army1": army_ids[0] = parts[1]
			"army2": army_ids[1] = parts[1]
			"setup": setup_tiles = int(parts[1])
			"layout": layout = parts[1]
			"width": width = int(parts[1])
			"height": height = int(parts[1])
	BoardState.configure(width, height, layout)
	var wins: Array[int] = [0, 0]
	var unfinished: int = 0
	var reasons: Dictionary = {}
	var turn_total: int = 0
	var longest: int = 0
	for index in range(games):
		var match_seed: int = base_seed + index
		var engine := GameEngine.new(match_seed, [], false, army_ids, setup_tiles)
		var controllers: Array[AIController] = [AIController.new(first, match_seed + 1), AIController.new(second, match_seed + 2)]
		var steps: int = 0
		while engine.state.phase != GameState.Phase.GAME_OVER and engine.state.turn_number < 150 and steps < 20000:
			var result: Dictionary = engine.submit_action(controllers[engine.state.active_player_id].choose_action(engine))
			if not bool(result["ok"]):
				push_error("Rejected AI action in seed %d" % match_seed)
				break
			steps += 1
		if engine.state.phase != GameState.Phase.GAME_OVER:
			unfinished += 1
			continue
		wins[engine.state.winner_id] += 1
		turn_total += engine.state.turn_number
		longest = maxi(longest, engine.state.turn_number)
		var reason: String = _reason(engine.state.events)
		reasons[reason] = int(reasons.get(reason, 0)) + 1
	var finished: int = games - unfinished
	print("Board %dx%d  Games: %d (seeds %d-%d)  P1: %s (%s)  P2: %s (%s)" % [width, height, games, base_seed, base_seed + games - 1, army_ids[0], _name(first), army_ids[1], _name(second)])
	print("P1 wins: %d  P2 wins: %d  unfinished: %d" % [wins[0], wins[1], unfinished])
	if finished > 0:
		print("Average length: %.1f turns (longest %d)" % [float(turn_total) / finished, longest])
	for reason: String in reasons:
		print("  %s: %d" % [reason, reasons[reason]])
	quit()

func _reason(events: Array[String]) -> String:
	for index in range(events.size() - 1, -1, -1):
		if events[index].contains(" wins: "):
			return events[index].get_slice(" wins: ", 1).strip_edges()
	return "unknown"

func _difficulty(text: String) -> AIController.Difficulty:
	match text.to_lower():
		"easy": return AIController.Difficulty.EASY
		"hard": return AIController.Difficulty.HARD
	return AIController.Difficulty.NORMAL

func _name(difficulty: AIController.Difficulty) -> String:
	return AIController.Difficulty.keys()[difficulty].capitalize()

extends Control

# Purely cosmetic. Game state is already final when these run; nothing here can alter an outcome.

const STEP_DELAY: float = 0.35
const OWNER_TEXT: Array[Color] = [Color(0.65, 0.85, 1.0), Color(1.0, 0.70, 0.65), Color(0.65, 1.0, 0.65), Color(0.90, 0.75, 1.0)]

var _cells: Dictionary = {}
var _state_provider: Callable
var _refresh_cell: Callable
var _banner_anchor: Control
var _summary_panels: Array = []
var _handoff_panel: Control

func configure(
		cells: Dictionary,
		state_provider: Callable,
		refresh_cell: Callable,
		banner_anchor: Control,
		summary_panels: Array,
		handoff_panel: Control) -> void:
	_cells = cells
	_state_provider = state_provider
	_refresh_cell = refresh_cell
	_banner_anchor = banner_anchor
	_summary_panels = summary_panels
	_handoff_panel = handoff_panel

func play(action: Dictionary, result: Dictionary, positions: Dictionary, units: Dictionary, previous_turn: int, previous_player: int) -> void:
	var state: GameState = _state()
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
				var moved: UnitState = state.find_unit(unit_id)
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
	if state.turn_number != previous_turn:
		_show_banner("%s's turn" % state.active_player().display_name, Color(1.0, 0.88, 0.50))

func _state() -> GameState:
	return _state_provider.call() as GameState

func _cell_at(tile: Vector2i) -> BattleCell:
	return _cells.get(tile) as BattleCell

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

func _animate_effects(effects: Array, delay: float) -> void:
	for effect: Dictionary in effects:
		var kind: String = str(effect["kind"])
		if kind == "draw":
			_show_banner("%s draws a card" % _state().players[int(effect["player"])].display_name, Color(0.7, 0.85, 1.0))
			continue
		var cell: BattleCell = _cell_at(effect["tile"])
		if _handoff_panel.visible:
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
	add_child(label)
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
			_refresh_cell.call(destination))
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
	label.global_position = (_summary_panels[player_id] as Control).global_position
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "global_position", _cell_at(target).global_position + Vector2(10, 15), 0.25)
	tween.tween_property(label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(label.queue_free)

func _show_banner(text: String, color: Color) -> void:
	var banner_count: int = 0
	for child in get_children():
		if child.has_meta("banner"):
			banner_count += 1
	var label: Label = _effect_label(text, color)
	label.set_meta("banner", true)
	label.global_position = _banner_anchor.global_position + Vector2(0, 30 + 24 * banner_count)
	var tween: Tween = label.create_tween()
	if GameSettings.reduce_motion:
		tween.tween_interval(0.9)
	else:
		label.modulate.a = 0.0
		tween.tween_property(label, "modulate:a", 1.0, 0.1)
		tween.tween_interval(0.45)
		tween.tween_property(label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(label.queue_free)

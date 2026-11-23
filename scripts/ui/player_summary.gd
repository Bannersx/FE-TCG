class_name PlayerSummary
extends PanelContainer

const GOLD := Color(0.78, 0.63, 0.37)
const TEXT := Color(0.94, 0.90, 0.80)
const MUTED := Color(0.70, 0.72, 0.70)

var title: Label
var faction: Label
var health_value: Label
var health_bar: ProgressBar
var supply_value: Label
var supply_pips: Array[ColorRect] = []
var victory_value: Label
var victory_bar: ProgressBar
var deck_value: Label
var hand_value: Label
var discard_value: Label
var fallen_value: Label
var ui_scale: float

func _init(scale_factor: float = 1.0) -> void:
	ui_scale = scale_factor
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(3 * ui_scale))
	add_child(box)

	title = _label(19, TEXT)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)
	faction = _label(14, MUTED)
	faction.clip_text = true
	faction.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(faction)

	health_value = _label(15, TEXT)
	health_bar = _add_meter(box, health_value, Color(0.74, 0.29, 0.29))
	supply_value = _label(15, TEXT)
	box.add_child(supply_value)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", roundi(3 * ui_scale))
	box.add_child(pips)
	for _index in range(GameEngine.MAX_SUPPLY):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(0, 7 * ui_scale)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
		supply_pips.append(pip)
	victory_value = _label(15, TEXT)
	victory_bar = _add_meter(box, victory_value, GOLD)

	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", roundi(5 * ui_scale))
	box.add_child(counts)
	deck_value = _label(13, MUTED)
	hand_value = _label(13, MUTED)
	discard_value = _label(13, MUTED)
	for value: Label in [deck_value, hand_value, discard_value]:
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		counts.add_child(value)
	fallen_value = _label(13, MUTED)
	fallen_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(fallen_value)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", roundi(font_size * ui_scale))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _add_meter(parent: Control, label: Label, color: Color) -> ProgressBar:
	parent.add_child(label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 6 * ui_scale
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _meter_style(Color(0.13, 0.16, 0.18)))
	bar.add_theme_stylebox_override("fill", _meter_style(color))
	parent.add_child(bar)
	return bar

func _meter_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(roundi(2 * ui_scale))
	return style

func show_player(player: PlayerState, active: bool, owner_color: Color) -> void:
	var border: Color = GOLD if active and not player.eliminated else owner_color.darkened(0.45)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.15, 0.18) if not player.eliminated else Color(0.12, 0.12, 0.13)
	style.border_color = border
	style.set_border_width_all(roundi((2 if active and not player.eliminated else 1) * ui_scale))
	style.set_corner_radius_all(roundi(5 * ui_scale))
	style.set_content_margin_all(8 * ui_scale)
	add_theme_stylebox_override("panel", style)
	title.text = "%s%s" % ["> " if active and not player.eliminated else "", player.display_name]
	title.add_theme_color_override("font_color", owner_color if not player.eliminated else MUTED)
	faction.text = "%s%s" % [player.commander.card.faction, "  - Eliminated" if player.eliminated else ("  - Active turn" if active else "")]
	tooltip_text = "%s - %s%s" % [player.display_name, player.commander.card.faction, " - Eliminated" if player.eliminated else (" - Active turn" if active else "")]

	health_value.text = "Commander HP   %d / %d" % [player.commander.current_hp, player.commander.max_hp()]
	health_bar.max_value = maxi(1, player.commander.max_hp())
	health_bar.value = player.commander.current_hp
	var bonus: int = maxi(0, player.current_supply - player.max_supply)
	supply_value.text = "Supply   %d / %d%s" % [player.current_supply, player.max_supply, "  (+%d bonus)" % bonus if bonus > 0 else ""]
	for index in range(supply_pips.size()):
		var color := Color(0.14, 0.17, 0.20)
		if index < player.current_supply:
			color = GOLD if index >= player.max_supply else Color(0.35, 0.67, 0.87)
		elif index < player.max_supply:
			color = Color(0.26, 0.34, 0.39)
		supply_pips[index].color = color
	victory_value.text = "Victory points   %d / %d" % [player.victory_points, GameEngine.WIN_POINTS]
	victory_bar.max_value = GameEngine.WIN_POINTS
	victory_bar.value = player.victory_points
	deck_value.text = "Deck %d" % player.deck.size()
	hand_value.text = "Hand %d" % player.hand.size()
	discard_value.text = "Discard %d" % player.discard.size()
	var fallen_names: PackedStringArray = []
	for card: CardData in player.fallen:
		fallen_names.append(card.card_name)
	fallen_value.text = "Fallen: %s" % [", ".join(fallen_names) if not fallen_names.is_empty() else "none"]

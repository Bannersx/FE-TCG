class_name CardVisual
extends Button

const TYPE_COLORS: Dictionary = {
	CardData.CardType.UNIT: Color(0.30, 0.45, 0.70),
	CardData.CardType.COMMANDER: Color(0.75, 0.60, 0.20),
	CardData.CardType.EQUIPMENT: Color(0.45, 0.55, 0.35),
	CardData.CardType.TACTIC: Color(0.65, 0.35, 0.55),
	CardData.CardType.PROMOTION: Color(0.80, 0.50, 0.20),
}

@onready var artwork: ColorRect = $Layout/Artwork
@onready var artwork_label: Label = $Layout/Artwork/ArtworkLabel
@onready var name_label: Label = $Layout/NameLabel
@onready var details_label: Label = $Layout/DetailsLabel

var card: CardData
var hover_tween: Tween

signal inspected(card: CardData)

func _ready() -> void:
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))

func _on_hover(entered: bool) -> void:
	pivot_offset = size / 2.0
	if hover_tween != null and hover_tween.is_valid():
		hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.tween_property(self, "scale", Vector2(1.06, 1.06) if entered else Vector2.ONE, 0.1)
	if entered and card != null:
		inspected.emit(card)

func setup(new_card: CardData, affordable: bool = true) -> void:
	card = new_card
	var type_color: Color = TYPE_COLORS.get(card.card_type, Color.GRAY)
	artwork.color = type_color
	artwork_label.text = "%s  %s" % [card.card_name.substr(0, 1), card.type_label().to_upper()]
	artwork_label.add_theme_font_size_override("font_size", 14)
	for style_name in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.13, 0.14, 0.19) if style_name != "hover" else Color(0.18, 0.19, 0.25)
		style.set_corner_radius_all(6)
		style.set_border_width_all(2)
		style.border_color = type_color.lightened(0.2) if style_name != "pressed" else Color.WHITE
		add_theme_stylebox_override(style_name, style)
	name_label.text = "%s  [%d]" % [card.card_name, card.supply_cost]
	name_label.add_theme_font_size_override("font_size", 13)
	details_label.text = card.summary()
	details_label.add_theme_font_size_override("font_size", 11)
	modulate = Color.WHITE if affordable else Color(0.6, 0.6, 0.6)
	tooltip_text = "%s (%s)\n%s" % [card.card_name, card.type_label(), card.summary()]

func set_selected(selected: bool) -> void:
	toggle_mode = true
	button_pressed = selected

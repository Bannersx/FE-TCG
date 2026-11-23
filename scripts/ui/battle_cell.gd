class_name BattleCell
extends Button

const OWNER_COLORS: Array[Color] = [Color(0.35, 0.65, 1.0), Color(1.0, 0.45, 0.40), Color(0.40, 0.85, 0.40), Color(0.85, 0.55, 1.0)]
const TERRAIN_COLORS: Dictionary = {
	BoardState.PLAIN: Color(0.24, 0.30, 0.22),
	BoardState.FOREST: Color(0.12, 0.32, 0.16),
	BoardState.FORT: Color(0.42, 0.36, 0.30),
	BoardState.MOUNTAIN: Color(0.38, 0.38, 0.44),
	BoardState.OBJECTIVE: Color(0.50, 0.42, 0.12),
	BoardState.ROAD: Color(0.48, 0.38, 0.25),
	BoardState.RIVER: Color(0.12, 0.35, 0.58),
	BoardState.BRIDGE: Color(0.52, 0.43, 0.30),
	BoardState.HIGH_GROUND: Color(0.48, 0.42, 0.24),
	BoardState.RUINS: Color(0.37, 0.34, 0.39),
	BoardState.LAVA: Color(0.60, 0.19, 0.10),
	BoardState.SHRINE: Color(0.40, 0.28, 0.55),
}
const HIGHLIGHT_COLORS: Dictionary = {
	"move": Color(0.25, 0.55, 0.95),
	"attack": Color(0.90, 0.25, 0.25),
	"deploy": Color(0.30, 0.80, 0.40),
	"target": Color(0.95, 0.80, 0.25),
	"active": Color(1.0, 1.0, 1.0),
	"eligible": Color(0.95, 0.80, 0.25),
	"ineligible": Color(0.55, 0.48, 0.48),
}

var hp_bar: ProgressBar
var stripe: ColorRect
var terrain_tag: Label
var movement_marker: Label
var attack_marker: Label
var target_marker: Label
var tutorial_marker: Label
var effect_tween: Tween

func _init() -> void:
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 13)
	stripe = ColorRect.new()
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.custom_minimum_size = Vector2(6, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stripe)
	hp_bar = ProgressBar.new()
	hp_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hp_bar.offset_top = -9
	hp_bar.offset_left = 8
	hp_bar.offset_right = -3
	hp_bar.offset_bottom = -3
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hp_bar)
	terrain_tag = Label.new()
	terrain_tag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	terrain_tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	terrain_tag.add_theme_font_size_override("font_size", 10)
	terrain_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	terrain_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(terrain_tag)
	var markers := HBoxContainer.new()
	markers.set_anchors_preset(Control.PRESET_TOP_LEFT)
	markers.position = Vector2(9, 2)
	markers.add_theme_constant_override("separation", 3)
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(markers)
	movement_marker = _marker("M", Color(0.55, 0.78, 1.0))
	attack_marker = _marker("A", Color(1.0, 0.55, 0.50))
	target_marker = _marker("", Color.WHITE)
	tutorial_marker = _marker("GO", Color(0.55, 1.0, 0.9))
	markers.add_child(movement_marker)
	markers.add_child(attack_marker)
	markers.add_child(target_marker)
	markers.add_child(tutorial_marker)

func _marker(value: String, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func show_state(terrain: String, unit: UnitState, highlight: String, seeded: bool = false, range_preview: Dictionary = {}, target_reason: String = "", tutorial_target: bool = false) -> void:
	var color: Color = TERRAIN_COLORS.get(terrain, Color.GRAY)
	tooltip_text = "%s: %s" % [terrain, str(BoardState.TERRAIN_DESCRIPTIONS.get(terrain, ""))]
	movement_marker.visible = bool(range_preview.get("move", false))
	attack_marker.visible = bool(range_preview.get("attack", false))
	target_marker.visible = highlight in ["eligible", "ineligible"]
	tutorial_marker.visible = tutorial_target
	if target_marker.visible:
		target_marker.text = "OK" if highlight == "eligible" else "X"
		target_marker.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4) if highlight == "eligible" else Color(1.0, 0.65, 0.65))
		tooltip_text += "\n" + ("Eligible target" if target_reason.is_empty() else target_reason)
	if highlight == "" and (movement_marker.visible or attack_marker.visible):
		var preview_color: Color = Color(0.65, 0.35, 0.75) if movement_marker.visible and attack_marker.visible else (HIGHLIGHT_COLORS["move"] if movement_marker.visible else HIGHLIGHT_COLORS["attack"])
		color = color.lerp(preview_color, 0.35)
	if highlight != "":
		color = color.lerp(HIGHLIGHT_COLORS[highlight], 0.55)
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(style_name, _style(color, highlight))
	terrain_tag.text = ("" if terrain == BoardState.PLAIN else terrain) + (" (seed)" if seeded else "")
	if unit == null:
		text = ""
		hp_bar.visible = false
		stripe.visible = false
		return
	var owner_color: Color = OWNER_COLORS[unit.owner_id]
	var status_tags: String = ""
	for status: String in unit.statuses:
		status_tags += " [%s]" % status.capitalize()
	text = "%s%s%s\nA%d D%d  %d/%d" % [
		unit.display_name(), "  (acted)" if unit.exhausted else "", status_tags,
		unit.attack(), unit.defense(), unit.current_hp, unit.max_hp(),
	]
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(color_name, owner_color.lightened(0.35))
	stripe.color = owner_color
	stripe.visible = true
	hp_bar.visible = true
	hp_bar.max_value = unit.max_hp()
	hp_bar.value = unit.current_hp
	var ratio: float = float(unit.current_hp) / float(unit.max_hp())
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.8, 0.35) if ratio > 0.5 else (Color(0.9, 0.75, 0.2) if ratio > 0.25 else Color(0.9, 0.3, 0.25))
	hp_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	hp_bar.add_theme_stylebox_override("background", back)

func _style(color: Color, highlight: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.set_border_width_all(3 if highlight != "" else 1)
	style.border_color = HIGHLIGHT_COLORS[highlight] if highlight != "" else Color(0, 0, 0, 0.5)
	return style

# ---- Cosmetic effects. They never touch game state. ----

func cancel_effects() -> void:
	if effect_tween != null and effect_tween.is_valid():
		effect_tween.kill()
	modulate = Color.WHITE
	scale = Vector2.ONE
	for child in get_children():
		if child.has_meta("floater"):
			child.queue_free()

func flash(color: Color, delay: float = 0.0) -> void:
	if GameSettings.reduce_motion:
		return
	var overlay := ColorRect.new()
	overlay.set_meta("floater", true)
	overlay.color = Color(color.r, color.g, color.b, 0.45)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.modulate.a = 0.0
	add_child(overlay)
	var tween: Tween = overlay.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.10)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.25)
	tween.tween_callback(overlay.queue_free)

func pulse(delay: float = 0.0) -> void:
	if GameSettings.reduce_motion:
		return
	pivot_offset = size / 2.0
	if effect_tween != null and effect_tween.is_valid():
		effect_tween.kill()
	scale = Vector2.ONE
	effect_tween = create_tween()
	if delay > 0.0:
		effect_tween.tween_interval(delay)
	effect_tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.12)
	effect_tween.tween_property(self, "scale", Vector2.ONE, 0.18)

func floating_text(message: String, color: Color, delay: float = 0.0) -> void:
	var floater := Label.new()
	floater.set_meta("floater", true)
	floater.text = message
	floater.add_theme_font_size_override("font_size", 22)
	floater.add_theme_color_override("font_color", color)
	floater.add_theme_color_override("font_outline_color", Color.BLACK)
	floater.add_theme_constant_override("outline_size", 6)
	floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floater.position = Vector2(size.x / 2.0 - 20.0, size.y / 2.0 - 14.0)
	floater.modulate.a = 0.0
	add_child(floater)
	var tween: Tween = floater.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	if GameSettings.reduce_motion:
		tween.tween_property(floater, "modulate:a", 1.0, 0.0)
		tween.tween_interval(0.9)
		tween.tween_callback(floater.queue_free)
		return
	tween.tween_property(floater, "modulate:a", 1.0, 0.05)
	tween.set_parallel(true)
	tween.tween_property(floater, "position:y", floater.position.y - 28.0, 0.7)
	tween.tween_property(floater, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(floater.queue_free)

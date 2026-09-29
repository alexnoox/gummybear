extends CanvasLayer

## A big round restart button with no words: a yellow disc with a circular
## arrow drawn on it. It pops in, pulses, takes focus and frees the mouse,
## so A, Enter, Space or a click all press it. Emits `pressed`.

signal pressed

const SIZE := 180.0
const DISC_COLOUR := Color(1.0, 0.85, 0.1)
const DISC_HOVER := Color(1.0, 0.92, 0.4)
const RIM_COLOUR := Color(1.0, 1.0, 1.0)
const ARROW_COLOUR := Color(0.25, 0.15, 0.4)
const PULSE := 1.08
const PULSE_TIME := 0.5

var _button: Button


func _ready() -> void:
	layer = 10
	visible = false
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_button = Button.new()
	_button.custom_minimum_size = Vector2(SIZE, SIZE)
	_button.pivot_offset = Vector2(SIZE, SIZE) * 0.5
	_button.add_theme_stylebox_override("normal", _disc(DISC_COLOUR))
	_button.add_theme_stylebox_override("hover", _disc(DISC_HOVER))
	_button.add_theme_stylebox_override("pressed", _disc(DISC_HOVER))
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.pressed.connect(pressed.emit)
	centre.add_child(_button)

	var icon := Control.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_arrow.bind(icon))
	_button.add_child(icon)


func appear() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_button.grab_focus()
	_button.scale = Vector2.ZERO
	var pop := _button.create_tween()
	pop.tween_property(_button, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_callback(_pulse)


func is_ready() -> bool:
	return visible and _button.has_focus()


## Space and A also jump, so catch them as a press here in case the
## default ui_accept map leaves the pad's A out.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()
		pressed.emit()


func _pulse() -> void:
	var pulse := _button.create_tween().set_loops()
	pulse.tween_property(_button, "scale", Vector2.ONE * PULSE, PULSE_TIME) \
			.set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_button, "scale", Vector2.ONE, PULSE_TIME) \
			.set_trans(Tween.TRANS_SINE)


func _disc(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(int(SIZE * 0.5))
	box.set_border_width_all(8)
	box.border_color = RIM_COLOUR
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	box.shadow_size = 10
	box.anti_aliasing = true
	return box


## A clockwise circular arrow (↻), drawn so no font or asset is needed.
func _draw_arrow(icon: Control) -> void:
	var centre := icon.size * 0.5
	var radius := SIZE * 0.26
	var start := -PI * 0.3
	var end := PI * 1.3
	icon.draw_arc(centre, radius, start, end, 48, ARROW_COLOUR, SIZE * 0.08, true)
	var tip_at := centre + Vector2(cos(end), sin(end)) * radius
	var along := Vector2(-sin(end), cos(end))
	var out := Vector2(cos(end), sin(end))
	var head := SIZE * 0.11
	icon.draw_colored_polygon(PackedVector2Array([
		tip_at + along * head,
		tip_at + out * head - along * head * 0.3,
		tip_at - out * head - along * head * 0.3,
	]), ARROW_COLOUR)

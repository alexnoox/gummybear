extends CanvasLayer

## The pause menu, for the grown-up: Esc or the pad's Menu (Start) button
## opens it, pausing the game and freeing the mouse; Esc, Menu, B or Resume
## close it and put the mouse back as it was. It holds the camera's invert
## toggle (right stick up/down), saved (settings.gd) so it sticks. The D-pad
## or left stick moves between rows and A presses.

const SETTINGS := preload("res://scripts/settings.gd")

## [label, node path under the player, property]; the property is also the
## saved setting's key.
const TOGGLES := [
	["Invert camera up/down (right stick)", "CameraRig", "invert_stick_y"],
]

const FONT_SIZE := 24
const PANEL_COLOUR := Color(0.14, 0.12, 0.2)

var _checks: Array[CheckButton] = []
var _resume: Button
var _mouse_mode_before := Input.MOUSE_MODE_CAPTURED
## Whatever had focus before (the restart button, say), given back on close
## so A still presses it.
var _focus_before: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	# Opaque: the default panel lets the restart button show through.
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = PANEL_COLOUR
	backdrop.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", backdrop)
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)

	for toggle: Array in TOGGLES:
		var check := CheckButton.new()
		check.text = toggle[0]
		check.add_theme_font_size_override("font_size", FONT_SIZE)
		check.toggled.connect(_on_toggled.bind(toggle[1], toggle[2]))
		rows.add_child(check)
		_checks.append(check)
	_resume = Button.new()
	_resume.text = "Resume"
	_resume.add_theme_font_size_override("font_size", FONT_SIZE)
	_resume.pressed.connect(close)
	rows.add_child(_resume)


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_mouse_mode_before = Input.mouse_mode
	_focus_before = get_viewport().gui_get_focus_owner()
	for i in TOGGLES.size():
		var target := _target(TOGGLES[i][1])
		if target != null:
			_checks[i].set_pressed_no_signal(target.get(TOGGLES[i][2]))
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_checks[0].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode_before
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	else:
		get_viewport().gui_release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_toggled(on: bool, path: String, property: String) -> void:
	var target := _target(path)
	if target != null:
		target.set(property, on)
	SETTINGS.save_value(property, on)


## The node a toggle sets, under the player (null if there's no player).
func _target(path: String) -> Node:
	var player := get_tree().get_first_node_in_group("player")
	return player.get_node_or_null(path) if player != null else null

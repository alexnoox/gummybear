extends CanvasLayer

## The pause menu, for the grown-up: Esc or the pad's Menu (Start) button
## opens it, pausing the game and freeing the mouse; Esc, Menu, B or Resume
## close it and put the mouse back as it was. The main page holds the
## camera's invert toggle (right stick up/down), saved (settings.gd) so it
## sticks, and a Sounds button. The Sounds page has one row per game sound
## (sounds.gd): hold Record (A on the pad, or click and hold) to record up
## to 3 s, which then plays back; Play, and Clear (this computer's own
## recording; a sound shipped with the game comes back). B goes back. The D-pad or
## left stick moves between buttons and A presses. F11 or Alt+Enter switches
## between full screen and a window at any time (exported builds start full
## screen: project.godot's window/size/mode.template).

const SETTINGS := preload("res://scripts/settings.gd")

## [label, node path under the player, property]; the property is also the
## saved setting's key.
const TOGGLES := [
	["Invert camera up/down (right stick)", "CameraRig", "invert_stick_y"],
]
## Sounds page rows, in order: [event, label].
const SOUND_ROWS := [
	["throw", "Throw"],
	["hit", "Hit"],
	["pop", "Ball pop"],
	["win", "Win"],
	["walk", "Walk"],
]
const SOUNDS_HINT := "Hold Record to record (up to 3 s)."

const FONT_SIZE := 24
const PANEL_COLOUR := Color(0.14, 0.12, 0.2)

var _checks: Array[CheckButton] = []
var _main_page: VBoxContainer
var _sounds_page: VBoxContainer
var _sounds_button: Button
var _status: Label
## event -> [record, play, clear] buttons
var _sound_buttons := {}
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
	var pages := VBoxContainer.new()
	margin.add_child(pages)
	_main_page = _page()
	pages.add_child(_main_page)
	_sounds_page = _page()
	pages.add_child(_sounds_page)
	_build_main_page()
	_build_sounds_page()
	_sounds_page.visible = false
	Sounds.recorded.connect(_on_recorded)


func _build_main_page() -> void:
	for toggle: Array in TOGGLES:
		var check := CheckButton.new()
		check.text = toggle[0]
		_sized(check)
		check.toggled.connect(_on_toggled.bind(toggle[1], toggle[2]))
		_main_page.add_child(check)
		_checks.append(check)
	_sounds_button = _button("Sounds", _show_sounds)
	_main_page.add_child(_sounds_button)
	_main_page.add_child(_button("Resume", close))


func _build_sounds_page() -> void:
	var hint := Label.new()
	hint.text = SOUNDS_HINT
	_sized(hint)
	_sounds_page.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	_sounds_page.add_child(grid)
	for row: Array in SOUND_ROWS:
		var event: String = row[0]
		var title := Label.new()
		title.text = row[1]
		_sized(title)
		grid.add_child(title)
		var record := _button("Record", Callable())
		# Walkie-talkie: recording lasts while the button is held (A or the
		# mouse); Sounds stops it by itself after 3 s.
		record.button_down.connect(_on_record_down.bind(event, row[1]))
		record.button_up.connect(Sounds.stop_recording)
		var play := _button("Play", Sounds.play.bind(event, false))
		var clear := _button("Clear", _on_clear.bind(event))
		for button in [record, play, clear]:
			grid.add_child(button)
		_sound_buttons[event] = [record, play, clear]
	_status = Label.new()
	_sized(_status)
	_sounds_page.add_child(_status)
	_sounds_page.add_child(_button("Back", _show_main))


func is_open() -> bool:
	return visible


func sounds_page_open() -> bool:
	return visible and _sounds_page.visible


func sound_rows() -> int:
	return _sound_buttons.size()


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
	_show_main()
	_checks[0].grab_focus()


func close() -> void:
	if not visible:
		return
	Sounds.stop_recording()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode_before
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	else:
		get_viewport().gui_release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var window := get_window()
		window.mode = (Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN
				or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
				else Window.MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		if _sounds_page.visible:
			_show_main()
		else:
			close()
		get_viewport().set_input_as_handled()


func _show_main() -> void:
	Sounds.stop_recording()
	var was_sounds := _sounds_page.visible
	_sounds_page.visible = false
	_main_page.visible = true
	if was_sounds:
		_sounds_button.grab_focus()


func _show_sounds() -> void:
	_main_page.visible = false
	_sounds_page.visible = true
	_status.text = ""
	_refresh_sounds()
	(_sound_buttons[SOUND_ROWS[0][0]][0] as Button).grab_focus()


func _refresh_sounds() -> void:
	for event: String in _sound_buttons:
		_sound_buttons[event][1].disabled = not Sounds.has_sound(event)
		_sound_buttons[event][2].disabled = not Sounds.has_own_sound(event)


func _on_record_down(event: String, label: String) -> void:
	Sounds.start_recording(event)
	_status.text = "Recording %s… let go to stop." % label


func _on_recorded(event: String, ok: bool) -> void:
	_refresh_sounds()
	if ok:
		_status.text = ("Got it! Saved in the project: push to send it to the TV."
				if Sounds.records_into_project() else "Got it!")
		Sounds.play(event, false)
	else:
		_status.text = "Nothing came in. Check the microphone (System Settings → Privacy → Microphone)."


func _on_clear(event: String) -> void:
	Sounds.clear(event)
	_status.text = ("Cleared; the game's own %s sound is back." % event
			if Sounds.has_sound(event) else "")
	_refresh_sounds()
	# The Clear button just disabled itself; keep focus on the row.
	(_sound_buttons[event][0] as Button).grab_focus()


func _on_toggled(on: bool, path: String, property: String) -> void:
	var target := _target(path)
	if target != null:
		target.set(property, on)
	SETTINGS.save_value(property, on)


## The node a toggle sets, under the player (null if there's no player).
func _target(path: String) -> Node:
	var player := get_tree().get_first_node_in_group("player")
	return player.get_node_or_null(path) if player != null else null


func _page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	return page


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	_sized(button)
	if on_pressed.is_valid():
		button.pressed.connect(on_pressed)
	return button


func _sized(control: Control) -> void:
	control.add_theme_font_size_override("font_size", FONT_SIZE)

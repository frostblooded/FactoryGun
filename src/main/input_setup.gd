class_name InputSetup
extends RefCounted
## Registers every input action in code (no [input] section in project.godot). Idempotent.

const MOVE_LEFT: StringName = &"move_left"          # physical A, Left
const MOVE_RIGHT: StringName = &"move_right"        # physical D, Right
const MOVE_UP: StringName = &"move_up"              # physical W, Up
const MOVE_DOWN: StringName = &"move_down"          # physical S, Down
const FIRE: StringName = &"fire"                    # left mouse button
const START_WAVE: StringName = &"start_wave"        # Space, Enter, Keypad Enter
const DELETE_HOVERED: StringName = &"delete_hovered"  # Delete, X
const CANCEL: StringName = &"cancel"                # Escape
const RESTART: StringName = &"restart"              # R
const PICK: Array[StringName] = [&"pick_1", &"pick_2", &"pick_3"]   # 1/Keypad 1, 2/Keypad 2, 3/Keypad 3


## Adds each missing action with its events. Physical keycodes make WASD work on AZERTY keyboards.
static func ensure_actions() -> void:
	_add_keys(MOVE_LEFT, [KEY_A, KEY_LEFT])
	_add_keys(MOVE_RIGHT, [KEY_D, KEY_RIGHT])
	_add_keys(MOVE_UP, [KEY_W, KEY_UP])
	_add_keys(MOVE_DOWN, [KEY_S, KEY_DOWN])
	_add_keys(START_WAVE, [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER])
	_add_keys(DELETE_HOVERED, [KEY_DELETE, KEY_X])
	_add_keys(CANCEL, [KEY_ESCAPE])
	_add_keys(RESTART, [KEY_R])
	_add_keys(PICK[0], [KEY_1, KEY_KP_1])
	_add_keys(PICK[1], [KEY_2, KEY_KP_2])
	_add_keys(PICK[2], [KEY_3, KEY_KP_3])
	if not InputMap.has_action(FIRE):
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		_add_action(FIRE, [click])


static func _add_keys(action: StringName, keys: Array[Key]) -> void:
	if InputMap.has_action(action):
		return
	var events: Array[InputEvent] = []
	for k: Key in keys:
		var e: InputEventKey = InputEventKey.new()
		e.physical_keycode = k
		events.append(e)
	_add_action(action, events)


static func _add_action(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.add_action(action)
	for e: InputEvent in events:
		e.device = -1                     # all devices, as the project settings' input map stores them
		InputMap.action_add_event(action, e)

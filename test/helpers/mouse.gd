extends RefCounted
## Real mouse input through Input.parse_input_event (the same path as a player, including drag-and-drop).
## Call `await Mouse.prepare(self)` first. Keep positions at x < 950 (GUT's panel covers x 963..1595).

static func prepare(t: GutTest) -> void:
	t.get_tree().root.size = Vector2i(1600, 900)    # the headless root window is 64x64
	await t.wait_process_frames(2)


static func move(pos: Vector2, last: Vector2, mask: int) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = pos - last                          # Godot starts a drag after 10 px of accumulated relative motion
	e.button_mask = mask
	Input.parse_input_event(e)


static func button(pos: Vector2, pressed: bool, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = index
	e.pressed = pressed
	var mask: int = 0
	if pressed:
		mask = MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	e.button_mask = mask
	Input.parse_input_event(e)


static func drag(t: GutTest, from: Vector2, to: Vector2, steps: int = 10) -> void:
	move(from, from, 0)
	await t.wait_process_frames(1)
	button(from, true)
	await t.wait_process_frames(1)
	var last: Vector2 = from
	for i: int in steps:
		var p: Vector2 = from.lerp(to, float(i + 1) / float(steps))
		move(p, last, MOUSE_BUTTON_MASK_LEFT)
		last = p
		await t.wait_process_frames(1)
	button(to, false)
	await t.wait_process_frames(2)


static func click(t: GutTest, pos: Vector2, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	move(pos, pos, 0)
	await t.wait_process_frames(1)
	button(pos, true, index)
	await t.wait_process_frames(1)
	button(pos, false, index)
	await t.wait_process_frames(1)

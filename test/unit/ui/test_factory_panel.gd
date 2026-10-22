extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")
const Mouse = preload("res://test/helpers/mouse.gd")

const SLOT_0: Vector2 = Vector2(56, 626)        # the Fire slot's centre: PALETTE_POS + (36, 44)
const STATUSES: Array[ShotPlan.MachineStatus] = [ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.CAPPED,
		ShotPlan.MachineStatus.ONE_SIDED, ShotPlan.MachineStatus.DEAD_END, ShotPlan.MachineStatus.IDLE]


func test_render_smoke_all_statuses() -> void:
	# ids 3..9: Fire, Ice, Poison, Speed Up, Size Up, Pierce, then Splitter #9 at (7, 4) -> Output
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE, MachineCatalog.ICE, MachineCatalog.POISON,
			MachineCatalog.SPEED_UP, MachineCatalog.SIZE_UP, MachineCatalog.PIERCE, MachineCatalog.SPLITTER])
	assert_eq(g.add_machine(MachineCatalog.FIRE, Vector2i(9, 7)), 10)
	assert_eq(g.connect_ports(9, 1, 10, 0), GraphError.Code.OK)                  # a dead end
	assert_eq(g.add_machine(MachineCatalog.ICE, Vector2i(3, 9)), 11)
	assert_eq(g.connect_ports(11, 0, FactoryGraph.OUTPUT_ID, 0), GraphError.Code.OK)   # idle
	var plan: ShotPlan = ShotPlan.new()
	var ids: PackedInt32Array = g.machine_ids()
	for i: int in ids.size():
		plan.statuses[ids[i]] = STATUSES[i % STATUSES.size()]
	var kinds: Array[StringName] = MachineCatalog.placeable_kinds()
	var wires: Array[Wire] = g.wires()
	for i: int in wires.size():
		if wires[i].to_id != 10 and wires[i].from_id != 11:
			plan.live_wire_keys[wires[i].key()] = true
			var streams: Array[BulletSpec] = []
			for k: int in i % 4 + 1:
				streams.append(BulletSpec.from_counts({kinds[(i + k) % kinds.size()]: k + 1}, 0))
			plan.wire_streams[wires[i].key()] = streams
	var angles: PackedFloat64Array = [-0.6, -0.4, -0.2, 0.0, 0.1, 0.2, 0.4, 0.6]
	for i: int in angles.size():
		var counts: Dictionary[StringName, int] = {MachineCatalog.SIZE_UP: i % 4}
		counts[kinds[i % kinds.size()]] = 1
		var spec: BulletSpec = BulletSpec.from_counts(counts, i % 2)
		spec.angle_offset = angles[i]
		plan.bullets.append(spec)
	var panel: FactoryPanel = _panel(g, Fixtures.inventory_all(1))
	panel.theme = FactoryTheme.build()
	assert_eq(panel.theme.default_font_size, 14)
	assert_true(panel.theme.get_stylebox("focus", "Button") is StyleBoxEmpty)
	var pressed: StyleBoxFlat = panel.theme.get_stylebox("pressed", "Button")
	assert_eq(pressed.border_color, UiColors.ACCENT)
	assert_eq(pressed.get_border_width(SIDE_LEFT), 2)
	assert_eq(panel.theme.get_color("font_disabled_color", "Button"), UiColors.TEXT_DIM)
	panel.set_plan(plan)
	panel.set_start_state(4, true, "")
	assert_eq(panel.readout.label.text, "\n".join(plan.summary_lines()))
	await wait_process_frames(2)
	var board: FactoryBoard = panel.board
	var hovers: Array[BoardHit.Type] = [BoardHit.Type.MACHINE, BoardHit.Type.PORT, BoardHit.Type.PORT,
			BoardHit.Type.BELT, BoardHit.Type.EMPTY]
	var points: Array[Vector2] = [Vector2(160, 80), Vector2(120, 80), Vector2(200, 80), Vector2(300, 140), Vector2(20, 20)]
	for i: int in points.size():                          # a machine, its input, its output, a belt, nothing
		board.interaction.motion(points[i])
		assert_eq(board.interaction.hover.type, hovers[i])
		await wait_process_frames(2)
	board.interaction.press(Vector2(160, 80), MOUSE_BUTTON_LEFT)
	for p: Vector2 in [Vector2(40, 120), Vector2(80, 240), Vector2(-40, 80)]:   # valid ghost, refused ghost, outside
		board.interaction.motion(p)
		await wait_process_frames(2)
	board.cancel_interaction()
	board.interaction.press(Vector2(60, 220), MOUSE_BUTTON_LEFT)                 # the Source, outside: refused
	board.interaction.motion(Vector2(600, 220))
	await wait_process_frames(2)
	board.cancel_interaction()
	board.interaction.press(Vector2(440, 320), MOUSE_BUTTON_LEFT)                # Fire #10's output
	assert_eq(board.interaction.mode, BoardInteraction.Mode.DRAG_WIRE)
	for p: Vector2 in [Vector2(500, 420), Vector2(125, 395), Vector2(120, 80)]:  # no target, Ice #11 (OK), a loop
		board.interaction.motion(p)
		await wait_process_frames(2)
	assert_eq(board.interaction.wire_code, GraphError.Code.WOULD_CYCLE)
	board.cancel_interaction()
	panel.set_locked(true, "LOCKED · WAVE 4 IN PROGRESS")
	await wait_process_frames(2)
	panel.set_plan(ShotPlan.empty())
	await wait_process_frames(2)
	assert_eq(panel.readout.label.text, "NO PATH: connect the Basic Bullet to the Output")
	for kind: StringName in [MachineCatalog.SOURCE, MachineCatalog.OUTPUT] + kinds:
		add_child_autofree(MachineGhost.make(kind))
	await wait_process_frames(2)


func test_palette_states() -> void:
	var inv: Inventory = Inventory.from_counts({MachineCatalog.FIRE: 2, MachineCatalog.ICE: 1})
	assert_true(inv.take(MachineCatalog.ICE))            # none left, but owned before
	var panel: FactoryPanel = _panel(FactoryGraph.create_default(), inv)
	assert_eq(panel.slots.size(), 7)
	for i: int in panel.slots.size():
		assert_eq(panel.slots[i].kind, MachineCatalog.PALETTE_ORDER[i])
		assert_eq(panel.slots[i].position, Vector2(20 + 78 * i, 582))
		assert_eq(panel.slots[i].size, PaletteSlot.SLOT_SIZE)
	var fire: PaletteSlot = panel.slots[0]
	var ice: PaletteSlot = panel.slots[1]
	var poison: PaletteSlot = panel.slots[2]
	assert_eq([fire.count, fire.ever_owned, fire.can_drag()], [2, true, true])
	assert_eq(fire.tooltip_text, "Fire\nSets targets on fire: 6 damage/s per level for 3 s.")
	assert_eq(fire.mouse_default_cursor_shape, Control.CURSOR_DRAG)
	assert_eq(fire.make_drag_data(), {"type": FactoryBoard.DRAG_TYPE, "kind": MachineCatalog.FIRE})
	assert_eq(fire._get_drag_data(Vector2.ZERO), fire.make_drag_data())   # in the tree but not dragging: no preview
	assert_eq([ice.count, ice.ever_owned, ice.can_drag()], [0, true, false])
	assert_eq(ice.mouse_default_cursor_shape, Control.CURSOR_ARROW)
	assert_null(ice._get_drag_data(Vector2.ZERO))
	assert_eq([poison.count, poison.ever_owned, poison.can_drag()], [0, false, false])
	assert_eq(poison.tooltip_text, "Not found yet. Clear waves to earn new machines.")
	await wait_process_frames(2)
	# the palette follows the inventory
	assert_true(inv.add(MachineCatalog.POISON, 3))
	assert_eq([poison.count, poison.ever_owned, poison.can_drag()], [3, true, true])
	assert_eq(poison.tooltip_text, "Poison\n" + MachineCatalog.get_def(MachineCatalog.POISON).description)
	assert_true(inv.take(MachineCatalog.FIRE))
	assert_eq(fire.count, 1)
	# locking freezes every slot
	panel.set_locked(true, "CHOOSE A REWARD")
	for slot: PaletteSlot in panel.slots:
		assert_true(slot.locked)
		assert_false(slot.can_drag())
	assert_null(fire._get_drag_data(Vector2.ZERO))
	assert_eq(fire.mouse_default_cursor_shape, Control.CURSOR_ARROW)
	await wait_process_frames(2)
	panel.set_locked(false, "")
	assert_true(fire.can_drag())
	# a slot works off-tree too
	var loose: PaletteSlot = PaletteSlot.new()
	loose.setup(MachineCatalog.SPLITTER)
	loose.set_state(1, true, false)
	assert_eq(loose._get_drag_data(Vector2.ZERO), {"type": FactoryBoard.DRAG_TYPE, "kind": MachineCatalog.SPLITTER})
	loose.free()


func test_start_button_state_and_text() -> void:
	var panel: FactoryPanel = _panel(FactoryGraph.create_default(), Inventory.new())
	assert_eq(panel.start_button.focus_mode, Control.FOCUS_NONE)
	assert_eq(panel.start_button.position, Vector2(360, 18))
	assert_eq(panel.board.position, FactoryPanel.BOARD_POS)
	assert_eq(panel.readout.position, FactoryPanel.READOUT_POS)
	watch_signals(panel)
	panel.set_start_state(3, true, "")
	assert_eq(panel.start_button.text, "START WAVE 3  [Space]")
	assert_false(panel.start_button.disabled)
	panel.start_button.pressed.emit()
	assert_signal_emit_count(panel, "start_wave_requested", 1)
	panel.set_locked(true, "LOCKED · WAVE 3 IN PROGRESS")
	assert_true(panel.start_button.disabled)
	panel.set_locked(false, "")
	assert_false(panel.start_button.disabled)
	var reason: String = "Connect the Basic Bullet to the Output first."
	panel.set_start_state(1, false, reason)
	assert_eq(panel.start_button.text, "START WAVE 1  [Space]")
	assert_true(panel.start_button.disabled)
	panel._process(0.0)
	assert_eq(panel.status_label.text, reason)            # in BUILD, the status line says why
	assert_eq(panel.status_label.get_theme_color("font_color"), UiColors.WARN)
	panel.set_locked(true, "GAME OVER")
	panel._process(0.0)
	assert_eq(panel.status_label.text, FactoryPanel.HINT)
	await wait_process_frames(2)


func test_message_expires() -> void:
	var panel: FactoryPanel = _panel(FactoryGraph.create_default(), Inventory.new())
	panel.set_start_state(1, true, "")
	panel._process(0.0)
	assert_eq(panel.status_label.text, FactoryPanel.HINT)
	assert_eq(panel.status_label.get_theme_color("font_color"), UiColors.TEXT_DIM)
	panel.show_message("Something is already there.", true)
	panel._process(0.0)
	assert_eq(panel.status_label.text, "Something is already there.")
	assert_eq(panel.status_label.get_theme_color("font_color"), UiColors.ERROR)
	panel._process(2.4)
	assert_eq(panel.status_label.text, "Something is already there.")
	panel._process(0.2)
	assert_eq(panel.status_label.text, FactoryPanel.HINT)
	panel.show_message("Placed.", false)
	panel._process(0.0)
	assert_eq(panel.status_label.get_theme_color("font_color"), UiColors.TEXT)
	# board refusals land on the status line as errors
	panel.set_locked(true, "LOCKED · WAVE 1 IN PROGRESS")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(80, 240)
	panel.board._gui_input(click)
	panel._process(0.0)
	assert_eq(panel.status_label.text, GraphError.describe(GraphError.Code.LOCKED))
	assert_eq(panel.status_label.get_theme_color("font_color"), UiColors.ERROR)
	await wait_process_frames(2)


func test_hover_refreshes_after_graph_change() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])   # Fire #3 at (3, 1)
	var panel: FactoryPanel = _panel(g, Inventory.new())
	var plan: ShotPlan = ShotPlan.new()
	plan.statuses[3] = ShotPlan.MachineStatus.ACTIVE
	panel.set_plan(plan)
	var ia: BoardInteraction = panel.board.interaction
	ia.motion(Vector2(160, 80))
	assert_true(ia.hover.same_as(BoardHit.make(BoardHit.Type.MACHINE, 3)))
	panel._process(0.0)
	assert_eq(panel.status_label.text, "Fire #3: Sets targets on fire: 6 damage/s per level for 3 s.")
	plan.statuses[3] = ShotPlan.MachineStatus.CAPPED
	panel._process(0.0)
	assert_eq(panel.status_label.text, "Fire #3: Sets targets on fire: 6 damage/s per level for 3 s.  [capped]")
	await wait_process_frames(2)
	assert_eq(g.remove_machine(3), GraphError.Code.OK)    # no motion: the board must re-hover by itself
	assert_eq(ia.hover.type, BoardHit.Type.EMPTY)
	await wait_process_frames(2)
	assert_eq(g.add_machine(MachineCatalog.ICE, Vector2i(3, 1)), 4)
	assert_true(ia.hover.same_as(BoardHit.make(BoardHit.Type.MACHINE, 4)))
	panel._process(0.0)
	assert_eq(panel.status_label.text, "Ice #4: " + MachineCatalog.get_def(MachineCatalog.ICE).description + "  [idle]")
	g.assign_from(FactoryGraph.create_default())          # a restart resets the ids
	assert_eq(ia.hover.type, BoardHit.Type.EMPTY)
	await wait_process_frames(2)
	# the other hover texts; the Source and the Output have no id plate
	ia.motion(Vector2(60, 220))
	panel._process(0.0)
	assert_eq(panel.status_label.text, "Basic Bullet: " + MachineCatalog.get_def(MachineCatalog.SOURCE).description + "  [idle]")
	ia.motion(Vector2(120, 240))
	panel._process(0.0)
	assert_eq(panel.status_label.text, "Output port: drag to an input port to connect.")
	ia.motion(Vector2(300, 240))
	panel._process(0.0)
	assert_eq(panel.status_label.text, "Belt: right-click or X to cut.")
	assert_eq(g.disconnect_wire(g.wire_from(1, 0)), GraphError.Code.OK)
	assert_eq(ia.hover.type, BoardHit.Type.EMPTY)
	await wait_process_frames(2)


func test_palette_drag_places_on_board() -> void:
	await Mouse.prepare(self)
	var g: FactoryGraph = FactoryGraph.create_default()
	var panel: FactoryPanel = _panel(g, Fixtures.inventory_all(1))
	watch_signals(panel.board)
	await Mouse.drag(self, SLOT_0, FactoryPanel.BOARD_POS + Vector2(240, 80))   # the centre of cell (5, 1)
	assert_signal_emit_count(panel.board, "place_requested", 1)
	assert_signal_emitted_with_parameters(panel.board, "place_requested", [MachineCatalog.FIRE, Vector2i(5, 1), null])
	assert_signal_not_emitted(panel.board, "refused")
	assert_eq(g.machine_ids(), PackedInt32Array([1, 2]))   # the board only asks
	# dropped on the Source: refused with the reason, nothing placed
	await Mouse.drag(self, SLOT_0, FactoryPanel.BOARD_POS + Vector2(80, 240))
	assert_signal_emit_count(panel.board, "place_requested", 1)
	assert_signal_emitted_with_parameters(panel.board, "refused", [GraphError.describe(GraphError.Code.CELL_OCCUPIED)])
	assert_eq(panel.status_label.text, GraphError.describe(GraphError.Code.CELL_OCCUPIED))


func test_palette_drag_onto_belt_splices() -> void:
	await Mouse.prepare(self)
	var g: FactoryGraph = FactoryGraph.create_default()
	var panel: FactoryPanel = _panel(g, Fixtures.inventory_all(1))
	watch_signals(panel.board)
	await Mouse.drag(self, SLOT_0, FactoryPanel.BOARD_POS + Vector2(280, 244))   # 4 px from the belt 1:0>2:0
	assert_signal_emit_count(panel.board, "place_requested", 1)
	var params: Array = get_signal_parameters(panel.board, "place_requested")
	assert_eq(params[0], MachineCatalog.FIRE)
	assert_eq(params[1], Vector2i(6, 5))
	assert_same(params[2], g.wire_from(FactoryGraph.SOURCE_ID, 0))


func test_wire_drag_emits_connect() -> void:
	await Mouse.prepare(self)
	var g: FactoryGraph = FactoryGraph.create_default()
	assert_eq(g.add_machine(MachineCatalog.FIRE, Vector2i(5, 1)), 3)   # input at (200, 80)
	var panel: FactoryPanel = _panel(g, Fixtures.inventory_all(1))
	watch_signals(panel.board)
	await Mouse.drag(self, FactoryPanel.BOARD_POS + Vector2(120, 240), FactoryPanel.BOARD_POS + Vector2(205, 85))
	assert_signal_emit_count(panel.board, "connect_requested", 1)
	assert_signal_emitted_with_parameters(panel.board, "connect_requested", [FactoryGraph.SOURCE_ID, 0, 3, 0])
	assert_signal_not_emitted(panel.board, "refused")


func test_machine_drag_off_floor_emits_remove() -> void:
	await Mouse.prepare(self)
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])   # Fire #3 at (3, 1)
	var panel: FactoryPanel = _panel(g, Fixtures.inventory_all(1))
	watch_signals(panel.board)
	await Mouse.drag(self, FactoryPanel.BOARD_POS + Vector2(160, 80), Vector2(300, 560))   # below the floor
	assert_signal_emit_count(panel.board, "remove_requested", 1)
	assert_signal_emitted_with_parameters(panel.board, "remove_requested", [3])
	assert_signal_not_emitted(panel.board, "move_requested")


func test_right_click_belt_emits_disconnect() -> void:
	await Mouse.prepare(self)
	var g: FactoryGraph = FactoryGraph.create_default()
	var panel: FactoryPanel = _panel(g, Fixtures.inventory_all(1))
	watch_signals(panel.board)
	await Mouse.click(self, FactoryPanel.BOARD_POS + Vector2(280, 240), MOUSE_BUTTON_RIGHT)
	assert_signal_emit_count(panel.board, "disconnect_requested", 1)
	assert_same(get_signal_parameters(panel.board, "disconnect_requested")[0], g.wire_from(FactoryGraph.SOURCE_ID, 0))
	assert_signal_not_emitted(panel.board, "remove_requested")


func _panel(g: FactoryGraph, inv: Inventory) -> FactoryPanel:
	var panel: FactoryPanel = FactoryPanel.new()
	add_child_autofree(panel)
	panel.bind(g, inv)
	return panel

extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")

# Fixtures.chain([FIRE]): Fire #3 at (3, 1), body (120, 40)..(200, 120), input (120, 80), output (200, 80).
# Its belts: 1:0>3:0, and 3:0>2:0 whose middle leg runs down x 320 from y 80 to 240.
const FIRE_BODY: Vector2 = Vector2(160, 80)
const FIRE_INPUT: Vector2 = Vector2(120, 80)
const FIRE_OUTPUT: Vector2 = Vector2(200, 80)
const ON_BELT_3_2: Vector2 = Vector2(320, 160)
const SOURCE_BODY: Vector2 = Vector2(60, 220)
const SOURCE_OUTPUT: Vector2 = Vector2(120, 240)

var _locked_text: String = GraphError.describe(GraphError.Code.LOCKED)


func test_drag_machine_moves_it() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])
	var ia: BoardInteraction = _bound(g)
	ia.motion(FIRE_BODY)
	assert_true(ia.hover.same_as(BoardHit.make(BoardHit.Type.MACHINE, 3)))
	var pressed: BoardAction = ia.press(FIRE_BODY, MOUSE_BUTTON_LEFT)
	assert_eq(pressed.type, BoardAction.Type.NONE)
	assert_eq(pressed.refusal, "")
	assert_eq(ia.mode, BoardInteraction.Mode.PRESS_MACHINE)
	assert_eq(ia.drag_id, 3)
	assert_eq(ia.drag_grab, Vector2(40, 40))
	ia.motion(Vector2(200, 100))
	assert_eq(ia.mode, BoardInteraction.Mode.DRAG_MACHINE)
	ia.motion(Vector2(240, 120))
	assert_eq(ia.ghost_cell(), Vector2i(5, 2))
	assert_true(ia.ghost_valid())
	assert_false(ia.is_drag_outside())
	assert_eq(ia.refusal_text(), "")
	ia.refresh_hover()
	assert_eq(ia.hover.type, BoardHit.Type.EMPTY)   # nothing is hovered while a gesture runs
	var moved: BoardAction = ia.release(Vector2(240, 120))
	assert_eq(moved.type, BoardAction.Type.MOVE)
	assert_eq(moved.machine_id, 3)
	assert_eq(moved.cell, Vector2i(5, 2))
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	assert_eq(ia.drag_id, -1)
	assert_eq(g.get_machine(3).cell, Vector2i(3, 1))   # the interaction never mutates the graph
	# the grab offset is kept: grabbed 10 px inside its top-left corner, the machine lands where it is carried
	ia.press(Vector2(130, 50), MOUSE_BUTTON_LEFT)
	assert_eq(ia.drag_grab, Vector2(10, 10))
	ia.motion(Vector2(290, 210))                        # top-left (280, 200): cell (7, 5)
	assert_eq(ia.release(Vector2(290, 210)).cell, Vector2i(7, 5))


func test_small_motion_is_not_a_drag() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])
	var before: Dictionary = g.to_dict()
	var ia: BoardInteraction = _bound(g)
	ia.press(FIRE_BODY, MOUSE_BUTTON_LEFT)
	ia.motion(FIRE_BODY + Vector2(6, 0))   # the threshold must be exceeded
	ia.motion(FIRE_BODY + Vector2(3, 4))
	assert_eq(ia.mode, BoardInteraction.Mode.PRESS_MACHINE)
	var released: BoardAction = ia.release(FIRE_BODY + Vector2(3, 4))
	assert_eq(released.type, BoardAction.Type.NONE)
	assert_eq(released.refusal, "")
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	# an input port also grabs its machine
	ia.press(FIRE_INPUT, MOUSE_BUTTON_LEFT)
	assert_eq(ia.mode, BoardInteraction.Mode.PRESS_MACHINE)
	assert_eq(ia.drag_id, 3)
	ia.motion(FIRE_INPUT + Vector2(0, 7))
	assert_eq(ia.mode, BoardInteraction.Mode.DRAG_MACHINE)
	# a press on empty floor or on a belt starts nothing
	ia.cancel()
	ia.press(Vector2(20, 300), MOUSE_BUTTON_LEFT)
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	ia.press(ON_BELT_3_2, MOUSE_BUTTON_LEFT)
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	assert_eq(ia.release(ON_BELT_3_2).type, BoardAction.Type.NONE)
	assert_eq(g.to_dict(), before)


func test_invalid_move_refused_with_reason() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])
	var ia: BoardInteraction = _bound(g)
	var occupied: String = GraphError.describe(GraphError.Code.CELL_OCCUPIED)
	ia.press(FIRE_BODY, MOUSE_BUTTON_LEFT)
	ia.motion(Vector2(80, 240))                          # onto the Source at (1, 5)
	assert_eq(ia.ghost_cell(), Vector2i(1, 5))
	assert_false(ia.ghost_valid())
	assert_eq(ia.refusal_text(), occupied)
	var refused: BoardAction = ia.release(Vector2(80, 240))
	assert_eq(refused.type, BoardAction.Type.NONE)
	assert_eq(refused.refusal, occupied)
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	assert_eq(ia.refusal_text(), "")
	assert_eq(g.get_machine(3).cell, Vector2i(3, 1))


func test_release_outside_removes() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])
	var ia: BoardInteraction = _bound(g)
	ia.press(FIRE_BODY, MOUSE_BUTTON_LEFT)
	ia.motion(Vector2(-30, 80))
	assert_true(ia.is_drag_outside())
	assert_eq(ia.refusal_text(), "")
	var removed: BoardAction = ia.release(Vector2(-30, 80))
	assert_eq(removed.type, BoardAction.Type.REMOVE)
	assert_eq(removed.machine_id, 3)
	assert_false(ia.is_drag_outside())
	# the floor's bottom edge is already outside
	ia.press(FIRE_BODY, MOUSE_BUTTON_LEFT)
	ia.motion(Vector2(160, 480))
	assert_eq(ia.release(Vector2(160, 480)).type, BoardAction.Type.REMOVE)
	assert_true(g.has_machine(3))


func test_release_outside_refused_for_source() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()
	var ia: BoardInteraction = _bound(g)
	var fixed: String = GraphError.describe(GraphError.Code.NOT_REMOVABLE)
	ia.press(SOURCE_BODY, MOUSE_BUTTON_LEFT)
	assert_eq(ia.drag_id, FactoryGraph.SOURCE_ID)
	ia.motion(Vector2(60, 600))
	assert_true(ia.is_drag_outside())
	assert_eq(ia.refusal_text(), fixed)
	var refused: BoardAction = ia.release(Vector2(60, 600))
	assert_eq(refused.type, BoardAction.Type.NONE)
	assert_eq(refused.refusal, fixed)
	ia.press(Vector2(480, 220), MOUSE_BUTTON_LEFT)       # the Output's body
	assert_eq(ia.drag_id, FactoryGraph.OUTPUT_ID)
	ia.motion(Vector2(600, 220))
	assert_eq(ia.release(Vector2(600, 220)).refusal, fixed)
	assert_eq(g.machine_ids(), PackedInt32Array([1, 2]))


func test_wire_drag_connects_with_magnet() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()
	assert_eq(g.add_machine(MachineCatalog.FIRE, Vector2i(5, 1)), 3)   # input (200, 80), output (280, 80)
	var ia: BoardInteraction = _bound(g)
	assert_eq(ia.press(SOURCE_OUTPUT, MOUSE_BUTTON_LEFT).type, BoardAction.Type.NONE)
	assert_eq(ia.mode, BoardInteraction.Mode.DRAG_WIRE)
	assert_true(ia.wire_from.equals(PortRef.make(FactoryGraph.SOURCE_ID, 0, true)))
	ia.motion(Vector2(300, 300))
	assert_null(ia.wire_target)
	assert_eq(ia.wire_code, GraphError.Code.OK)
	ia.motion(Vector2(210, 95))                          # 18 px from #3's input: snapped
	assert_true(ia.wire_target.equals(PortRef.make(3, 0, false)))
	assert_eq(ia.wire_code, GraphError.Code.OK)
	assert_eq(ia.refusal_text(), "")
	var connect: BoardAction = ia.release(Vector2(210, 95))   # replaces the Source's belt to the Output
	assert_eq(connect.type, BoardAction.Type.CONNECT)
	assert_true(connect.from.equals(PortRef.make(FactoryGraph.SOURCE_ID, 0, true)))
	assert_true(connect.to.equals(PortRef.make(3, 0, false)))
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	assert_null(ia.wire_from)
	assert_null(ia.wire_target)
	# the magnet skips the dragged machine's own input
	ia.press(Vector2(280, 80), MOUSE_BUTTON_LEFT)
	ia.motion(Vector2(205, 80))
	assert_null(ia.wire_target)
	var silent: BoardAction = ia.release(Vector2(205, 80))
	assert_eq(silent.type, BoardAction.Type.NONE)
	assert_eq(silent.refusal, "")
	# the release point decides, even without a motion event before it
	ia.press(Vector2(280, 80), MOUSE_BUTTON_LEFT)
	var direct: BoardAction = ia.release(Vector2(436, 236))
	assert_eq(direct.type, BoardAction.Type.CONNECT)
	assert_true(direct.to.equals(PortRef.make(FactoryGraph.OUTPUT_ID, 0, false)))


func test_ninth_bullet_refusal_text() -> void:
	# Source -> S3 =(both ports)=> S4 =(both)=> S5; S5:0 -> Output; S5:1 -> S6; S6:0 -> Output: 8 paths
	var g: FactoryGraph = FactoryGraph.create_default()
	for cell: Vector2i in [Vector2i(3, 5), Vector2i(5, 5), Vector2i(7, 5), Vector2i(9, 8)]:
		g.add_machine(MachineCatalog.SPLITTER, cell)
	for w: PackedInt32Array in [PackedInt32Array([1, 0, 3, 0]), PackedInt32Array([3, 0, 4, 0]),
			PackedInt32Array([3, 1, 4, 0]), PackedInt32Array([4, 0, 5, 0]), PackedInt32Array([4, 1, 5, 0]),
			PackedInt32Array([5, 0, 2, 0]), PackedInt32Array([5, 1, 6, 0]), PackedInt32Array([6, 0, 2, 0])]:
		assert_eq(g.connect_ports(w[0], w[1], w[2], w[3]), GraphError.Code.OK)
	assert_eq(g.count_live_paths(), 8)
	var ia: BoardInteraction = _bound(g)
	ia.press(Vector2(440, 380), MOUSE_BUTTON_LEFT)       # S6's lower output
	assert_true(ia.wire_from.equals(PortRef.make(6, 1, true)))
	ia.motion(Vector2(440, 245))                          # the Output's input: 4 * (1 + 2) = 12 paths
	assert_eq(ia.wire_code, GraphError.Code.TOO_MANY_BULLETS)
	var text: String = "The gun fires at most 8 bullets per shot. This belt would make 12."
	assert_eq(ia.refusal_text(), text)
	var refused: BoardAction = ia.release(Vector2(440, 245))
	assert_eq(refused.type, BoardAction.Type.NONE)
	assert_eq(refused.refusal, text)
	assert_eq(g.count_live_paths(), 8)
	# other refusals carry no path count
	ia.press(Vector2(360, 220), MOUSE_BUTTON_LEFT)        # S5's upper output feeds the Output...
	ia.motion(Vector2(120, 240))                          # ...back into S3's input: a loop
	assert_eq(ia.refusal_text(), GraphError.describe(GraphError.Code.WOULD_CYCLE))
	assert_eq(ia.release(Vector2(120, 240)).refusal, GraphError.describe(GraphError.Code.WOULD_CYCLE))


func test_wire_drag_without_target_is_silent() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()
	var before: Dictionary = g.to_dict()
	var ia: BoardInteraction = _bound(g)
	ia.press(SOURCE_OUTPUT, MOUSE_BUTTON_LEFT)
	ia.motion(Vector2(300, 400))
	assert_eq(ia.refusal_text(), "")
	var released: BoardAction = ia.release(Vector2(300, 400))
	assert_eq(released.type, BoardAction.Type.NONE)
	assert_eq(released.refusal, "")
	ia.press(SOURCE_OUTPUT, MOUSE_BUTTON_LEFT)           # released off the floor: also silent
	assert_eq(ia.release(Vector2(-50, -50)).refusal, "")
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	assert_eq(g.to_dict(), before)


func test_secondary_actions() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])
	var ia: BoardInteraction = _bound(g)
	var belt: BoardAction = ia.press(ON_BELT_3_2, MOUSE_BUTTON_RIGHT)
	assert_eq(belt.type, BoardAction.Type.DISCONNECT)
	assert_same(belt.wire, g.wire_from(3, 0))
	var output_with_belt: BoardAction = ia.press(FIRE_OUTPUT, MOUSE_BUTTON_RIGHT)
	assert_eq(output_with_belt.type, BoardAction.Type.DISCONNECT)
	assert_eq(output_with_belt.wire.key(), "3:0>2:0")
	for p: Vector2 in [FIRE_BODY, FIRE_INPUT]:
		var removed: BoardAction = ia.press(p, MOUSE_BUTTON_RIGHT)
		assert_eq(removed.type, BoardAction.Type.REMOVE)
		assert_eq(removed.machine_id, 3)
	assert_eq(g.disconnect_wire(g.wire_from(3, 0)), GraphError.Code.OK)
	var beltless_output: BoardAction = ia.press(FIRE_OUTPUT, MOUSE_BUTTON_RIGHT)
	assert_eq(beltless_output.type, BoardAction.Type.REMOVE)
	assert_eq(beltless_output.machine_id, 3)
	var source: BoardAction = ia.press(SOURCE_BODY, MOUSE_BUTTON_RIGHT)
	assert_eq(source.type, BoardAction.Type.NONE)
	assert_eq(source.refusal, GraphError.describe(GraphError.Code.NOT_REMOVABLE))
	assert_eq(ia.secondary(BoardHit.new()).refusal, "")
	assert_eq(ia.secondary(BoardHit.make(BoardHit.Type.OUTSIDE)).refusal, "")
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	# the wheel and other buttons do nothing, unlocked and locked
	for locked: bool in [false, true]:
		ia.set_locked(locked)
		for button: MouseButton in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_MIDDLE]:
			var wheel: BoardAction = ia.press(FIRE_BODY, button)
			assert_eq(wheel.type, BoardAction.Type.NONE)
			assert_eq(wheel.refusal, "")
			assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	ia.set_locked(false)
	# a right press while a gesture runs only cancels it
	ia.press(FIRE_OUTPUT, MOUSE_BUTTON_LEFT)
	assert_eq(ia.mode, BoardInteraction.Mode.DRAG_WIRE)
	var cancel_wire: BoardAction = ia.press(FIRE_BODY, MOUSE_BUTTON_RIGHT)
	assert_eq(cancel_wire.type, BoardAction.Type.NONE)
	assert_eq(cancel_wire.refusal, "")
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	assert_null(ia.wire_from)
	ia.press(FIRE_BODY, MOUSE_BUTTON_LEFT)
	ia.motion(Vector2(200, 100))
	assert_eq(ia.mode, BoardInteraction.Mode.DRAG_MACHINE)
	var cancel_drag: BoardAction = ia.press(FIRE_BODY, MOUSE_BUTTON_RIGHT)
	assert_eq(cancel_drag.type, BoardAction.Type.NONE)
	assert_eq(cancel_drag.refusal, "")
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	assert_eq(ia.drag_id, -1)
	assert_eq(ia.release(FIRE_BODY).type, BoardAction.Type.NONE)   # the left release that follows is ignored
	assert_true(g.has_machine(3))


func test_drop_preview_place_splice_and_reasons() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()   # belt 1:0>2:0 along y 240
	var inv: Inventory = Inventory.from_counts({MachineCatalog.FIRE: 1})
	var ia: BoardInteraction = _bound(g, inv)
	var place: DropPreview = ia.drop_preview(MachineCatalog.FIRE, Vector2(240, 80))
	assert_true(place.valid)
	assert_eq(place.kind, MachineCatalog.FIRE)
	assert_eq(place.cell, Vector2i(5, 1))
	assert_null(place.splice)
	assert_eq(place.reason, "")
	var placed: BoardAction = ia.drop(MachineCatalog.FIRE, Vector2(240, 80))
	assert_eq(placed.type, BoardAction.Type.PLACE)
	assert_eq(placed.kind, MachineCatalog.FIRE)
	assert_eq(placed.cell, Vector2i(5, 1))
	assert_null(placed.splice)
	# within 10 px of a belt: splice
	var splice: DropPreview = ia.drop_preview(MachineCatalog.FIRE, Vector2(280, 250))
	assert_true(splice.valid)
	assert_eq(splice.cell, Vector2i(6, 5))
	assert_same(splice.splice, g.wire_from(1, 0))
	var spliced: BoardAction = ia.drop(MachineCatalog.FIRE, Vector2(280, 250))
	assert_eq(spliced.type, BoardAction.Type.PLACE)
	assert_eq(spliced.cell, Vector2i(6, 5))
	assert_same(spliced.splice, g.wire_from(1, 0))
	# 11 px away: a plain placement on the same cell
	var beside: DropPreview = ia.drop_preview(MachineCatalog.FIRE, Vector2(280, 251))
	assert_true(beside.valid)
	assert_eq(beside.cell, Vector2i(6, 5))
	assert_null(beside.splice)
	# a splice that does not fit falls back to the plain check, and its reason
	var blocked: DropPreview = ia.drop_preview(MachineCatalog.FIRE, Vector2(130, 240))   # cell (2, 5): the Source
	assert_false(blocked.valid)
	assert_null(blocked.splice)
	assert_eq(blocked.reason, GraphError.describe(GraphError.Code.CELL_OCCUPIED))
	assert_eq(ia.drop(MachineCatalog.FIRE, Vector2(130, 240)).refusal, blocked.reason)
	# none left
	var empty: DropPreview = ia.drop_preview(MachineCatalog.ICE, Vector2(240, 80))
	assert_false(empty.valid)
	assert_eq(empty.reason, GraphError.describe(GraphError.Code.OUT_OF_STOCK))
	var refused: BoardAction = ia.drop(MachineCatalog.ICE, Vector2(240, 80))
	assert_eq(refused.type, BoardAction.Type.NONE)
	assert_eq(refused.refusal, empty.reason)
	# locked beats everything
	ia.set_locked(true)
	assert_eq(ia.drop_preview(MachineCatalog.ICE, Vector2(240, 80)).reason, _locked_text)
	assert_eq(ia.drop_preview(MachineCatalog.FIRE, Vector2(240, 80)).reason, _locked_text)
	assert_eq(inv.count(MachineCatalog.FIRE), 1)
	assert_eq(g.machine_ids(), PackedInt32Array([1, 2]))


func test_locked_refuses_everything() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])
	var before: Dictionary = g.to_dict()
	var ia: BoardInteraction = _bound(g)
	ia.press(FIRE_BODY, MOUSE_BUTTON_LEFT)
	ia.motion(Vector2(220, 100))
	assert_eq(ia.mode, BoardInteraction.Mode.DRAG_MACHINE)
	ia.set_locked(true)                                   # locking cancels the gesture
	assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	assert_eq(ia.drag_id, -1)
	assert_eq(ia.release(Vector2(220, 100)).refusal, "")
	for button: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		for p: Vector2 in [FIRE_BODY, FIRE_INPUT, FIRE_OUTPUT, ON_BELT_3_2, Vector2(20, 300), Vector2(-5, -5)]:
			var refused: BoardAction = ia.press(p, button)
			assert_eq(refused.type, BoardAction.Type.NONE)
			assert_eq(refused.refusal, _locked_text)
			assert_eq(ia.mode, BoardInteraction.Mode.IDLE)
	assert_eq(ia.drop(MachineCatalog.FIRE, Vector2(240, 300)).refusal, _locked_text)
	assert_eq(ia.secondary(BoardLayout.hit_test(g, FIRE_BODY)).refusal, _locked_text)
	ia.motion(FIRE_BODY)                                  # hovering still works: the status line explains machines
	assert_true(ia.hover.same_as(BoardHit.make(BoardHit.Type.MACHINE, 3)))
	assert_eq(g.to_dict(), before)
	ia.set_locked(false)
	ia.press(FIRE_BODY, MOUSE_BUTTON_LEFT)
	assert_eq(ia.mode, BoardInteraction.Mode.PRESS_MACHINE)


func _bound(g: FactoryGraph, inv: Inventory = null) -> BoardInteraction:
	var ia: BoardInteraction = BoardInteraction.new()
	ia.bind(g, inv if inv != null else Fixtures.inventory_all(1))
	return ia

extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")


func test_anchors() -> void:
	assert_eq(BoardLayout.bounds(), Rect2(0, 0, 560, 480))
	assert_eq(BoardLayout.machine_rect_at(Vector2i(3, 1)), Rect2(120, 40, 80, 80))
	assert_eq(BoardLayout.input_anchor_at(Vector2i(3, 1)), Vector2(120, 80))
	assert_eq(BoardLayout.output_anchor_at(Vector2i(3, 1), 0, 1), Vector2(200, 80))
	assert_eq(BoardLayout.output_anchor_at(Vector2i(3, 5), 0, 2), Vector2(200, 220))
	assert_eq(BoardLayout.output_anchor_at(Vector2i(3, 5), 1, 2), Vector2(200, 260))
	var g: FactoryGraph = Fixtures.split([], [])   # Splitter #3 at (3, 5)
	assert_eq(BoardLayout.machine_rect(g, 3), Rect2(120, 200, 80, 80))
	assert_eq(BoardLayout.machine_rect(g, FactoryGraph.SOURCE_ID), Rect2(40, 200, 80, 80))
	assert_eq(BoardLayout.port_anchor(g, PortRef.make(3, 0, false)), Vector2(120, 240))
	assert_eq(BoardLayout.port_anchor(g, PortRef.make(3, 1, true)), Vector2(200, 260))
	assert_eq(BoardLayout.port_anchor(g, PortRef.make(FactoryGraph.SOURCE_ID, 0, true)), Vector2(120, 240))
	assert_eq(BoardLayout.port_anchor(g, PortRef.make(FactoryGraph.OUTPUT_ID, 0, false)), Vector2(440, 240))
	assert_eq(_port_names(BoardLayout.ports_of(g, 3)), ["3:0 in", "3:0 out", "3:1 out"])
	assert_eq(_port_names(BoardLayout.ports_of(g, FactoryGraph.SOURCE_ID)), ["1:0 out"])
	assert_eq(_port_names(BoardLayout.ports_of(g, FactoryGraph.OUTPUT_ID)), ["2:0 in"])
	assert_true(BoardLayout.ports_of(g, 99).is_empty())


func test_drop_cell_rounds_and_clamps() -> void:
	assert_eq(BoardLayout.drop_cell(Vector2(240, 80)), Vector2i(5, 1))     # the centre of a machine at (5, 1)
	assert_eq(BoardLayout.drop_cell(Vector2(259, 99)), Vector2i(5, 1))
	assert_eq(BoardLayout.drop_cell(Vector2(260, 100)), Vector2i(6, 2))    # half a tile rounds up
	assert_eq(BoardLayout.drop_cell(Vector2(221, 61)), Vector2i(5, 1))
	assert_eq(BoardLayout.drop_cell(Vector2(219, 59)), Vector2i(4, 0))
	assert_eq(BoardLayout.drop_cell(Vector2(-100, -100)), Vector2i(0, 0))
	assert_eq(BoardLayout.drop_cell(Vector2(5000, 5000)), Vector2i(12, 10))
	assert_eq(BoardLayout.drop_cell(Vector2(20, 470)), Vector2i(0, 10))
	assert_eq(BoardLayout.drop_cell(Vector2(545, 15)), Vector2i(12, 0))


func test_hit_test_priority() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE, MachineCatalog.ICE])   # #3 at (3, 1), #4 at (5, 1)
	# the shared anchor (200, 80): #3's output beats #4's input, and cutting it cuts 3:0>4:0
	var shared: BoardHit = BoardLayout.hit_test(g, Vector2(200, 80))
	assert_eq(shared.type, BoardHit.Type.PORT)
	assert_true(shared.port.equals(PortRef.make(3, 0, true)))
	assert_eq(shared.machine_id, 3)
	assert_true(BoardLayout.hit_test(g, Vector2(205, 85)).port.equals(PortRef.make(3, 0, true)))
	var ia: BoardInteraction = BoardInteraction.new()
	ia.bind(g, Inventory.new())
	var cut: BoardAction = ia.secondary(shared)
	assert_eq(cut.type, BoardAction.Type.DISCONNECT)
	assert_eq(cut.wire.key(), "3:0>4:0")
	# a port beats the machine body it sits on
	var input: BoardHit = BoardLayout.hit_test(g, Vector2(125, 82))
	assert_true(input.same_as(BoardHit.make(BoardHit.Type.PORT, 3, PortRef.make(3, 0, false))))
	assert_true(BoardLayout.hit_test(g, Vector2(115, 240)).port.equals(PortRef.make(FactoryGraph.SOURCE_ID, 0, true)))
	# 12 px is still a port, 13 px is not
	assert_eq(BoardLayout.hit_test(g, Vector2(160, 80)).type, BoardHit.Type.MACHINE)
	assert_eq(BoardLayout.hit_test(g, Vector2(132, 80)).type, BoardHit.Type.PORT)
	assert_eq(BoardLayout.hit_test(g, Vector2(133, 80)).type, BoardHit.Type.MACHINE)
	# a machine beats a belt running under it
	var d: FactoryGraph = FactoryGraph.create_default()
	assert_eq(d.add_machine(MachineCatalog.FIRE, Vector2i(5, 5)), 3)   # on top of the belt 1:0>2:0 at y 240
	assert_true(BoardLayout.hit_test(d, Vector2(240, 240)).same_as(BoardHit.make(BoardHit.Type.MACHINE, 3)))
	var belt: BoardHit = BoardLayout.hit_test(d, Vector2(300, 244))
	assert_eq(belt.type, BoardHit.Type.BELT)
	assert_eq(belt.wire.key(), "1:0>2:0")
	assert_eq(belt.machine_id, -1)
	# overlapping belts: the first in canonical order wins
	var s: FactoryGraph = Fixtures.split([], [])   # 3:0>2:0 and 3:1>2:0 share y 240 from x 324 to the Output
	assert_eq(BoardLayout.hit_test(s, Vector2(380, 240)).wire.key(), "3:0>2:0")
	assert_eq(BoardLayout.hit_test(s, Vector2(324, 252)).wire.key(), "3:1>2:0")
	# nothing, and outside the floor (the end edges are outside)
	assert_eq(BoardLayout.hit_test(g, Vector2(20, 300)).type, BoardHit.Type.EMPTY)
	assert_eq(BoardLayout.hit_test(g, Vector2(0, 0)).type, BoardHit.Type.EMPTY)
	assert_eq(BoardLayout.hit_test(g, Vector2(-1, 10)).type, BoardHit.Type.OUTSIDE)
	assert_eq(BoardLayout.hit_test(g, Vector2(560, 10)).type, BoardHit.Type.OUTSIDE)
	assert_eq(BoardLayout.hit_test(g, Vector2(10, 480)).type, BoardHit.Type.OUTSIDE)


func test_belt_at_and_input_magnet() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()   # belt 1:0>2:0 along y 240, x 120..440
	assert_eq(BoardLayout.belt_at(g, Vector2(300, 248), BoardLayout.BELT_HIT).key(), "1:0>2:0")   # 8 px is in
	assert_null(BoardLayout.belt_at(g, Vector2(300, 249), BoardLayout.BELT_HIT))
	assert_null(BoardLayout.belt_at(g, Vector2(100, 240), BoardLayout.BELT_HIT))
	assert_eq(BoardLayout.belt_at(g, Vector2(300, 250), BoardLayout.SPLICE).key(), "1:0>2:0")
	assert_same(BoardLayout.belt_at(g, Vector2(300, 240), 1.0), g.wire_from(1, 0))   # the graph's own Wire
	assert_eq(g.add_machine(MachineCatalog.FIRE, Vector2i(5, 1)), 3)   # input at (200, 80)
	assert_eq(g.add_machine(MachineCatalog.ICE, Vector2i(5, 3)), 4)    # input at (200, 160)
	var near: PortRef = BoardLayout.nearest_input(g, Vector2(210, 95), BoardLayout.MAGNET, -1)   # 18 px away
	assert_true(near.equals(PortRef.make(3, 0, false)))
	assert_true(BoardLayout.nearest_input(g, Vector2(200, 104), BoardLayout.MAGNET, -1).equals(near))   # 24 px is in
	assert_null(BoardLayout.nearest_input(g, Vector2(200, 105), BoardLayout.MAGNET, -1))
	assert_true(BoardLayout.nearest_input(g, Vector2(200, 140), BoardLayout.MAGNET, -1).equals(PortRef.make(4, 0, false)))
	assert_null(BoardLayout.nearest_input(g, Vector2(205, 80), BoardLayout.MAGNET, 3))   # its own machine is excluded
	assert_true(BoardLayout.nearest_input(g, Vector2(430, 240), BoardLayout.MAGNET, 3).equals(PortRef.make(2, 0, false)))
	assert_null(BoardLayout.nearest_input(g, Vector2(40, 240), BoardLayout.MAGNET, -1))   # the Source has no input


func _port_names(refs: Array[PortRef]) -> Array[String]:
	var out: Array[String] = []
	for r: PortRef in refs:
		out.append("%d:%d %s" % [r.machine_id, r.port, "out" if r.is_output else "in"])
	return out

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
	# the output wins whatever the ids: here the right machine was placed first, so its input is visited first
	var r: FactoryGraph = FactoryGraph.create_default()
	var right: int = r.add_machine(MachineCatalog.ICE, Vector2i(5, 1))
	var left: int = r.add_machine(MachineCatalog.FIRE, Vector2i(3, 1))
	assert_lt(right, left)
	assert_true(BoardLayout.hit_test(r, Vector2(200, 80)).port.equals(PortRef.make(left, 0, true)))
	# a port beats the machine body it sits on
	var input: BoardHit = BoardLayout.hit_test(g, Vector2(125, 82))
	assert_true(input.same_as(BoardHit.make(BoardHit.Type.PORT, 3, PortRef.make(3, 0, false))))
	assert_true(BoardLayout.hit_test(g, Vector2(115, 240)).port.equals(PortRef.make(FactoryGraph.SOURCE_ID, 0, true)))
	# 16 px (a fingertip) is still a port, 17 px is not
	assert_eq(BoardLayout.hit_test(g, Vector2(160, 80)).type, BoardHit.Type.MACHINE)
	assert_eq(BoardLayout.hit_test(g, Vector2(136, 80)).type, BoardHit.Type.PORT)
	assert_eq(BoardLayout.hit_test(g, Vector2(137, 80)).type, BoardHit.Type.MACHINE)
	# a machine beats a belt running under it: the board draws machines over belts (E.2), so a click goes to what
	# the player sees
	var d: FactoryGraph = FactoryGraph.create_default()
	assert_eq(d.add_machine(MachineCatalog.FIRE, Vector2i(5, 5)), 3)   # on top of the belt 1:0>2:0 at y 240
	assert_true(BoardLayout.hit_test(d, Vector2(240, 240)).same_as(BoardHit.make(BoardHit.Type.MACHINE, 3)))
	var belt: BoardHit = BoardLayout.hit_test(d, Vector2(300, 244))
	assert_eq(belt.type, BoardHit.Type.BELT)
	assert_eq(belt.wire.key(), "1:0>2:0")
	assert_eq(belt.machine_id, -1)
	# a column-12 Splitter's port 0 belt goes back under its own right edge, past port 1, which is drawn over it;
	# below the Splitter the belt shows, and is the belt
	var e: FactoryGraph = FactoryGraph.create_default()
	assert_eq(e.add_machine(MachineCatalog.SPLITTER, Vector2i(12, 2)), 3)
	assert_eq(e.add_machine(MachineCatalog.ICE, Vector2i(4, 2)), 4)
	assert_eq(e.connect_ports(3, 0, 4, 0), GraphError.Code.OK)
	assert_true(BoardLayout.hit_test(e, Vector2(554, 140)).port.equals(PortRef.make(3, 1, true)))
	assert_eq(BoardLayout.hit_test(e, Vector2(554, 168)).wire.key(), "3:0>4:0")
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
	assert_eq(BoardLayout.belt_at(g, Vector2(300, 252), BoardLayout.BELT_HIT).key(), "1:0>2:0")   # 12 px is in
	assert_null(BoardLayout.belt_at(g, Vector2(300, 253), BoardLayout.BELT_HIT))
	assert_null(BoardLayout.belt_at(g, Vector2(100, 240), BoardLayout.BELT_HIT))
	assert_eq(BoardLayout.belt_at(g, Vector2(300, 260), BoardLayout.SPLICE).key(), "1:0>2:0")   # 20 px is in
	assert_null(BoardLayout.belt_at(g, Vector2(300, 261), BoardLayout.SPLICE))
	assert_same(BoardLayout.belt_at(g, Vector2(300, 240), 1.0), g.wire_from(1, 0))   # the graph's own Wire
	assert_eq(g.add_machine(MachineCatalog.FIRE, Vector2i(5, 1)), 3)   # input at (200, 80)
	assert_eq(g.add_machine(MachineCatalog.ICE, Vector2i(5, 3)), 4)    # input at (200, 160)
	var near: PortRef = BoardLayout.nearest_input(g, Vector2(210, 95), BoardLayout.MAGNET, -1)   # 18 px away
	assert_true(near.equals(PortRef.make(3, 0, false)))
	assert_true(BoardLayout.nearest_input(g, Vector2(200, 112), BoardLayout.MAGNET, -1).equals(near))   # 32 px is in
	assert_null(BoardLayout.nearest_input(g, Vector2(200, 113), BoardLayout.MAGNET, -1))
	assert_true(BoardLayout.nearest_input(g, Vector2(200, 140), BoardLayout.MAGNET, -1).equals(PortRef.make(4, 0, false)))
	assert_null(BoardLayout.nearest_input(g, Vector2(205, 80), BoardLayout.MAGNET, 3))   # its own machine is excluded
	assert_true(BoardLayout.nearest_input(g, Vector2(430, 240), BoardLayout.MAGNET, 3).equals(PortRef.make(2, 0, false)))
	assert_null(BoardLayout.nearest_input(g, Vector2(40, 240), BoardLayout.MAGNET, -1))   # the Source has no input


## Unrelated belts never run along one line or meet end to end, which would draw a connection that does not exist;
## hover and cuts then find each belt on its own track.
func test_unrelated_belts_keep_their_own_tracks() -> void:
	# Bullet -> Ice #3 goes around up the gap at x 140, where Ice -> Fire #4 (a short Z) would climb too, and the
	# Source's stub would end where Fire's input leg starts: a Bullet -> Fire belt on screen.
	var g: FactoryGraph = FactoryGraph.create_default()
	assert_eq(g.add_machine(MachineCatalog.ICE, Vector2i(1, 8)), 3)
	assert_eq(g.add_machine(MachineCatalog.FIRE, Vector2i(4, 5)), 4)
	_wire(g, [[1, 0, 3, 0], [3, 0, 4, 0], [4, 0, 2, 0]])
	assert_eq(BoardLayout.belt_points(g, g.wire_from(1, 0)), PackedVector2Array([
		Vector2(120, 240), Vector2(140, 240), Vector2(140, 300), Vector2(20, 300), Vector2(20, 360), Vector2(40, 360)]))
	assert_eq(BoardLayout.belt_points(g, g.wire_from(3, 0)), PackedVector2Array([   # one lane over
		Vector2(120, 360), Vector2(148, 360), Vector2(148, 240), Vector2(160, 240)]))
	assert_eq(_shared_lines(g), PackedStringArray())
	assert_eq(BoardLayout.hit_test(g, Vector2(139, 270)).wire.key(), "1:0>3:0")
	assert_eq(BoardLayout.hit_test(g, Vector2(149, 300)).wire.key(), "3:0>4:0")
	# Built in play: Source -> Ice #3 and Size Up #5 -> Fire #4 both went up x 100 and along y 220
	var p: FactoryGraph = FactoryGraph.create_default()
	assert_eq(p.move_machine(FactoryGraph.SOURCE_ID, Vector2i(0, 1)), GraphError.Code.OK)
	assert_eq(p.add_machine(MachineCatalog.ICE, Vector2i(1, 8)), 3)
	assert_eq(p.add_machine(MachineCatalog.FIRE, Vector2i(3, 1)), 4)
	assert_eq(p.add_machine(MachineCatalog.SIZE_UP, Vector2i(11, 8)), 5)
	_wire(p, [[1, 0, 3, 0], [3, 0, 5, 0], [5, 0, 4, 0], [4, 0, 2, 0]])
	assert_eq(BoardLayout.belt_points(p, p.wire_from(1, 0)), PackedVector2Array([
		Vector2(80, 80), Vector2(100, 80), Vector2(100, 220), Vector2(20, 220), Vector2(20, 360), Vector2(40, 360)]))
	assert_eq(BoardLayout.belt_points(p, p.wire_from(5, 0)), PackedVector2Array([
		Vector2(520, 360), Vector2(540, 360), Vector2(540, 228), Vector2(108, 228), Vector2(108, 80), Vector2(120, 80)]))
	assert_eq(BoardLayout.belt_points(p, p.wire_from(3, 0)), PackedVector2Array([Vector2(120, 360), Vector2(440, 360)]))
	assert_eq(_shared_lines(p), PackedStringArray())
	assert_eq(BoardLayout.hit_test(p, Vector2(101, 150)).wire.key(), "1:0>3:0")
	assert_eq(BoardLayout.hit_test(p, Vector2(107, 150)).wire.key(), "5:0>4:0")
	# the board draws the routes that hit-testing uses
	var board: FactoryBoard = FactoryBoard.new()
	add_child_autofree(board)
	board.bind(p, Inventory.new())
	for i: int in board._belts.size():
		assert_eq(board._routes[i], BoardLayout.belt_points(p, board._belts[i]))


## The cases that make belt_routes() move a belt, one each.
func test_belt_routes_move_off_placed_legs() -> void:
	# Straight belts cannot move, so they go first: the around lane of Fire #3 -> Ice #4 moves off the y 160 of
	# Poison #5 -> Pierce #6, though its belt comes first in canonical order.
	var s: FactoryGraph = FactoryGraph.create_default()
	assert_eq(s.disconnect_wire(s.wire_from(FactoryGraph.SOURCE_ID, 0)), GraphError.Code.OK)
	assert_eq(s.add_machine(MachineCatalog.FIRE, Vector2i(5, 1)), 3)
	assert_eq(s.add_machine(MachineCatalog.ICE, Vector2i(4, 5)), 4)
	assert_eq(s.add_machine(MachineCatalog.POISON, Vector2i(0, 3)), 5)
	assert_eq(s.add_machine(MachineCatalog.PIERCE, Vector2i(9, 3)), 6)
	_wire(s, [[3, 0, 4, 0], [5, 0, 6, 0]])
	assert_eq(BoardLayout.belt_points(s, s.wire_from(5, 0)), PackedVector2Array([Vector2(80, 160), Vector2(360, 160)]))
	assert_eq(BoardLayout.belt_points(s, s.wire_from(3, 0)), PackedVector2Array([
		Vector2(280, 80), Vector2(300, 80), Vector2(300, 168), Vector2(140, 168), Vector2(140, 240), Vector2(160, 240)]))
	assert_eq(_shared_lines(s), PackedStringArray())
	# Stubs count too. Splitter #3's belt into Fire #4 would end on the Source's stub (y 240, x 120..140), so its Z
	# moves right; Poison #6's belt into Size Up #7 would start on the end of that belt (y 360, x 136..160), so its
	# Z moves left. Either would show a belt between machines that are not wired.
	var t: FactoryGraph = FactoryGraph.create_default()
	assert_eq(t.add_machine(MachineCatalog.SPLITTER, Vector2i(1, 2)), 3)
	assert_eq(t.add_machine(MachineCatalog.FIRE, Vector2i(4, 5)), 4)
	assert_eq(t.add_machine(MachineCatalog.ICE, Vector2i(1, 8)), 5)
	_wire(t, [[1, 0, 5, 0], [3, 0, 4, 0]])
	assert_eq(BoardLayout.belt_points(t, t.wire_from(3, 0)), PackedVector2Array([
		Vector2(120, 100), Vector2(144, 100), Vector2(144, 240), Vector2(160, 240)]))
	assert_eq(_shared_lines(t), PackedStringArray())
	var u: FactoryGraph = FactoryGraph.create_default()
	assert_eq(u.disconnect_wire(u.wire_from(FactoryGraph.SOURCE_ID, 0)), GraphError.Code.OK)
	assert_eq(u.add_machine(MachineCatalog.SPLITTER, Vector2i(1, 1)), 3)
	assert_eq(u.add_machine(MachineCatalog.FIRE, Vector2i(4, 8)), 4)
	assert_eq(u.add_machine(MachineCatalog.POISON, Vector2i(1, 8)), 5)
	assert_eq(u.add_machine(MachineCatalog.SIZE_UP, Vector2i(4, 5)), 6)
	_wire(u, [[3, 0, 4, 0], [5, 0, 6, 0]])
	assert_eq(BoardLayout.belt_points(u, u.wire_from(3, 0)), PackedVector2Array([
		Vector2(120, 60), Vector2(136, 60), Vector2(136, 360), Vector2(160, 360)]))
	assert_eq(BoardLayout.belt_points(u, u.wire_from(5, 0)), PackedVector2Array([
		Vector2(120, 360), Vector2(132, 360), Vector2(132, 240), Vector2(160, 240)]))
	assert_eq(_shared_lines(u), PackedStringArray())
	# The search tries a lane either way, then two, on the floor and keeping STUB / 2 of stub at a port.
	var z: PackedVector2Array = PackedVector2Array([Vector2(120, 360), Vector2(140, 360), Vector2(140, 240),
			Vector2(160, 240)])
	var taken: Dictionary[String, PackedVector2Array] = {"v140": PackedVector2Array([Vector2(200, 400)]),
			"v148": PackedVector2Array([Vector2(200, 400)])}
	assert_eq(BoardLayout._off_lines(z, taken)[1], Vector2(132, 360))     # +1 is taken: -1
	taken["v132"] = PackedVector2Array([Vector2(200, 400)])
	assert_eq(BoardLayout._off_lines(z, taken)[1], Vector2(140, 360))     # 2 lanes would leave a stub under 10 px
	var around: PackedVector2Array = PackedVector2Array([Vector2(280, 80), Vector2(300, 80), Vector2(300, 160),
			Vector2(140, 160), Vector2(140, 240), Vector2(160, 240)])
	var rows: Dictionary[String, PackedVector2Array] = {"h152": PackedVector2Array([Vector2(0, 560)]),
			"h160": PackedVector2Array([Vector2(0, 560)]), "h168": PackedVector2Array([Vector2(0, 560)])}
	assert_eq(BoardLayout._off_lines(around, rows)[2], Vector2(300, 176))   # both neighbours taken: +2


func _wire(g: FactoryGraph, belts: Array) -> void:
	for b: Array in belts:
		assert_eq(g.connect_ports(b[0], b[1], b[2], b[3]), GraphError.Code.OK)


## "a | b" for each two belts with legs on one line that overlap or touch, but for belts into one input: they
## merge there, so their last stubs always meet.
func _shared_lines(g: FactoryGraph) -> PackedStringArray:
	var out: PackedStringArray = []
	var wires: Array[Wire] = g.wires()
	for i: int in wires.size():
		for j: int in range(i + 1, wires.size()):
			if wires[i].to_id == wires[j].to_id:
				continue
			var a: PackedVector2Array = BoardLayout.belt_points(g, wires[i])
			var b: PackedVector2Array = BoardLayout.belt_points(g, wires[j])
			for s: int in a.size() - 1:
				for t: int in b.size() - 1:
					if _on_one_line(a[s], a[s + 1], b[t], b[t + 1]):
						out.append("%s | %s" % [wires[i].key(), wires[j].key()])
	return out


func _on_one_line(p: Vector2, q: Vector2, r: Vector2, s: Vector2) -> bool:
	if p == q or r == s:
		return false
	if p.x == q.x and r.x == s.x and p.x == r.x:
		return minf(p.y, q.y) <= maxf(r.y, s.y) and minf(r.y, s.y) <= maxf(p.y, q.y)
	if p.y == q.y and r.y == s.y and p.y == r.y:
		return minf(p.x, q.x) <= maxf(r.x, s.x) and minf(r.x, s.x) <= maxf(p.x, q.x)
	return false


func _port_names(refs: Array[PortRef]) -> Array[String]:
	var out: Array[String] = []
	for r: PortRef in refs:
		out.append("%d:%d %s" % [r.machine_id, r.port, "out" if r.is_output else "in"])
	return out

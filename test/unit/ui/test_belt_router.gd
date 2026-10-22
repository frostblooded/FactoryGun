extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")

var _bounds: Rect2 = BoardLayout.bounds()


func test_straight() -> void:
	var source: Rect2 = Rect2(40, 200, 80, 80)
	var output: Rect2 = Rect2(440, 200, 80, 80)
	var r: PackedVector2Array = BeltRouter.route(Vector2(120, 240), Vector2(440, 240), source, output, 0.0, _bounds)
	assert_eq(r, PackedVector2Array([Vector2(120, 240), Vector2(440, 240)]))
	assert_almost_eq(BeltRouter.length(r), 320.0, 1e-4)
	# a lane offset never bends a straight belt
	assert_eq(BeltRouter.route(Vector2(120, 240), Vector2(440, 240), source, output, 4.0, _bounds).size(), 2)
	# side-by-side machines: a zero-length belt
	var touching: PackedVector2Array = BeltRouter.route(Vector2(200, 80), Vector2(200, 80), Rect2(120, 40, 80, 80),
			Rect2(200, 40, 80, 80), 0.0, _bounds)
	assert_eq(touching, PackedVector2Array([Vector2(200, 80), Vector2(200, 80)]))
	assert_almost_eq(BeltRouter.length(touching), 0.0, 1e-4)
	# the default factory's belt
	assert_eq(BoardLayout.belt_points(FactoryGraph.create_default(), Wire.make(1, 0, 2, 0)), r)


func test_z_route_snapped_and_clamped() -> void:
	var from_rect: Rect2 = Rect2(40, 200, 80, 80)
	var to_rect: Rect2 = Rect2(200, 80, 80, 80)
	assert_eq(BeltRouter.route(Vector2(120, 240), Vector2(200, 120), from_rect, to_rect, 0.0, _bounds),
			PackedVector2Array([Vector2(120, 240), Vector2(160, 240), Vector2(160, 120), Vector2(200, 120)]))
	# the middle leg snaps to a 20 px grid: (120 + 250) / 2 = 185 -> 180
	assert_eq(BeltRouter.route(Vector2(120, 240), Vector2(250, 100), from_rect, to_rect, 0.0, _bounds)[1], Vector2(180, 240))
	# the lane is added after snapping
	assert_eq(BeltRouter.route(Vector2(120, 240), Vector2(200, 120), from_rect, to_rect, 4.0, _bounds)[1], Vector2(164, 240))
	# and the leg stays STUB / 2 away from both ends
	assert_eq(BeltRouter.route(Vector2(120, 240), Vector2(200, 120), from_rect, to_rect, 100.0, _bounds)[2], Vector2(190, 120))
	assert_eq(BeltRouter.route(Vector2(120, 240), Vector2(200, 120), from_rect, to_rect, -100.0, _bounds)[2], Vector2(130, 120))
	# exactly 2 * STUB apart is still a Z
	var tight: PackedVector2Array = BeltRouter.route(Vector2(120, 240), Vector2(160, 120), from_rect, to_rect, 0.0, _bounds)
	assert_eq(tight, PackedVector2Array([Vector2(120, 240), Vector2(140, 240), Vector2(140, 120), Vector2(160, 120)]))
	assert_almost_eq(BeltRouter.length(tight), 160.0, 1e-4)


func test_backward_route_goes_around() -> void:
	# same rows: under both machines, STUB below the lower bottom edge
	var right: Rect2 = Rect2(320, 200, 80, 80)
	var left: Rect2 = Rect2(120, 200, 80, 80)
	assert_eq(BeltRouter.route(Vector2(400, 240), Vector2(120, 240), right, left, 0.0, _bounds), PackedVector2Array([
		Vector2(400, 240), Vector2(420, 240), Vector2(420, 300), Vector2(100, 300), Vector2(100, 240), Vector2(120, 240)]))
	# from above to: through the middle of the vertical gap (y 120..200)
	assert_eq(BeltRouter.route(Vector2(400, 80), Vector2(120, 240), Rect2(320, 40, 80, 80), left, 0.0, _bounds)[2],
			Vector2(420, 160))
	# to above from, with a lane: gap 120..320, so 220 + 4
	var up: PackedVector2Array = BeltRouter.route(Vector2(400, 360), Vector2(120, 80), Rect2(320, 320, 80, 80),
			Rect2(120, 40, 80, 80), 4.0, _bounds)
	assert_eq(up, PackedVector2Array([
		Vector2(400, 360), Vector2(420, 360), Vector2(420, 224), Vector2(100, 224), Vector2(100, 80), Vector2(120, 80)]))
	# on the bottom row the lane is clamped 6 px above the floor's edge
	assert_eq(BeltRouter.route(Vector2(400, 440), Vector2(120, 440), Rect2(320, 400, 80, 80), Rect2(120, 400, 80, 80),
			0.0, _bounds)[2], Vector2(420, 474))
	# a forward hop shorter than 2 * STUB also goes around: Splitter #3 port 0 -> a machine right above it
	var g: FactoryGraph = Fixtures.split([MachineCatalog.FIRE], [])   # Fire #4 at (5, 2)
	assert_eq(BoardLayout.belt_points(g, g.wire_from(3, 0)), PackedVector2Array([
		Vector2(200, 220), Vector2(220, 220), Vector2(220, 176), Vector2(180, 176), Vector2(180, 120), Vector2(200, 120)]))


func test_edge_ports_stay_on_the_floor() -> void:
	# Fire #3 at (0, 8): its input is on the floor's left edge; Ice #4 at (12, 9): its output is on the right edge
	var g: FactoryGraph = FactoryGraph.create_default()
	assert_eq(g.add_machine(MachineCatalog.FIRE, Vector2i(0, 8)), 3)
	assert_eq(g.add_machine(MachineCatalog.ICE, Vector2i(12, 9)), 4)
	for w: PackedInt32Array in [PackedInt32Array([1, 0, 3, 0]), PackedInt32Array([3, 0, 4, 0]), PackedInt32Array([4, 0, 2, 0])]:
		assert_eq(g.connect_ports(w[0], w[1], w[2], w[3]), GraphError.Code.OK)
	# around into a column-0 input: the last leg runs down the machine's own left edge, 6 px in
	assert_eq(BoardLayout.belt_points(g, g.wire_from(1, 0)), PackedVector2Array([
		Vector2(120, 240), Vector2(140, 240), Vector2(140, 300), Vector2(6, 300), Vector2(6, 360), Vector2(0, 360)]))
	# around out of a column-12 output: the first leg runs up the machine's own right edge, 6 px in
	assert_eq(BoardLayout.belt_points(g, g.wire_from(4, 0)), PackedVector2Array([
		Vector2(560, 400), Vector2(554, 400), Vector2(554, 320), Vector2(420, 320), Vector2(420, 240), Vector2(440, 240)]))
	for w: Wire in g.wires():
		for p: Vector2 in BoardLayout.belt_points(g, w):
			assert_true(_bounds.grow(0.001).has_point(p), "%s at %s" % [w.key(), p])
	# a stub with room keeps its STUB: column 11's output
	assert_eq(BeltRouter.route(Vector2(520, 80), Vector2(120, 240), Rect2(440, 40, 80, 80), Rect2(120, 200, 80, 80),
			0.0, _bounds)[1], Vector2(540, 80))


func test_splitter_lanes_differ() -> void:
	assert_eq(BeltRouter.lane_offset(0, 2), -4.0)
	assert_eq(BeltRouter.lane_offset(1, 2), 4.0)
	assert_eq(BeltRouter.lane_offset(0, 1), 0.0)
	# both outputs of Splitter #3 run to the Output: their middle legs sit 8 px apart
	var g: FactoryGraph = Fixtures.split([], [])
	var upper: PackedVector2Array = BoardLayout.belt_points(g, g.wire_from(3, 0))
	var lower: PackedVector2Array = BoardLayout.belt_points(g, g.wire_from(3, 1))
	assert_eq(upper, PackedVector2Array([Vector2(200, 220), Vector2(316, 220), Vector2(316, 240), Vector2(440, 240)]))
	assert_eq(lower, PackedVector2Array([Vector2(200, 260), Vector2(324, 260), Vector2(324, 240), Vector2(440, 240)]))


func test_distance_to() -> void:
	var pts: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 50)])
	assert_almost_eq(BeltRouter.distance_to(pts, Vector2(50, 10)), 10.0, 1e-4)
	assert_almost_eq(BeltRouter.distance_to(pts, Vector2(110, 25)), 10.0, 1e-4)
	assert_almost_eq(BeltRouter.distance_to(pts, Vector2(-30, -40)), 50.0, 1e-4)   # past the start: to the end point
	assert_almost_eq(BeltRouter.distance_to(pts, Vector2(100, 0)), 0.0, 1e-4)
	assert_almost_eq(BeltRouter.distance_to(PackedVector2Array([Vector2(5, 5), Vector2(5, 5)]), Vector2(8, 9)), 5.0, 1e-4)
	assert_eq(BeltRouter.distance_to(PackedVector2Array([Vector2(5, 5)]), Vector2(5, 5)), INF)
	# sample walks the same polyline by arc length, clamped to its ends
	assert_almost_eq(BeltRouter.length(pts), 150.0, 1e-4)
	assert_eq(BeltRouter.sample(pts, 40.0), [Vector2(40, 0), Vector2.RIGHT])
	assert_eq(BeltRouter.sample(pts, 120.0), [Vector2(100, 20), Vector2.DOWN])
	assert_eq(BeltRouter.sample(pts, -5.0), [Vector2(0, 0), Vector2.RIGHT])
	assert_eq(BeltRouter.sample(pts, 1000.0), [Vector2(100, 50), Vector2.DOWN])
	assert_eq(BeltRouter.sample(PackedVector2Array([Vector2(5, 5), Vector2(5, 5)]), 3.0), [Vector2(5, 5), Vector2.RIGHT])


func test_sample_every_walks_once_like_sample() -> void:
	var pts: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 50)])
	var marks: PackedVector2Array = BeltRouter.sample_every(pts, 5.0, 12.0)
	assert_eq(marks.size(), 2 * 13)                       # arc lengths 5, 17, ..., 149: all below the length 150
	for i: int in 13:
		var at: Array[Vector2] = BeltRouter.sample(pts, 5.0 + 12.0 * i)
		assert_almost_eq(marks[2 * i], at[0], Vector2(1e-4, 1e-4))
		assert_eq(marks[2 * i + 1], at[1])
	# zero-length segments are skipped, and a zero-length belt (touching machines) has no marks
	var bend: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 0), Vector2(10, 10)])
	assert_eq(BeltRouter.sample_every(bend, 0.0, 4.0), PackedVector2Array([Vector2(0, 0), Vector2.RIGHT, Vector2(4, 0),
			Vector2.RIGHT, Vector2(8, 0), Vector2.RIGHT, Vector2(10, 2), Vector2.DOWN, Vector2(10, 6), Vector2.DOWN]))
	assert_true(BeltRouter.sample_every(PackedVector2Array([Vector2(5, 5), Vector2(5, 5)]), 0.0, 12.0).is_empty())

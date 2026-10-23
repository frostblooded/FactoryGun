extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")


func test_default_graph() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()
	assert_eq(g.machine_ids(), PackedInt32Array([1, 2]))
	assert_eq(g.kind_of(FactoryGraph.SOURCE_ID), MachineCatalog.SOURCE)
	assert_eq(g.kind_of(FactoryGraph.OUTPUT_ID), MachineCatalog.OUTPUT)
	assert_eq(g.get_machine(FactoryGraph.SOURCE_ID).cell, Vector2i(1, 5))
	assert_eq(g.get_machine(FactoryGraph.OUTPUT_ID).cell, Vector2i(11, 5))
	assert_eq(g.get_machine(FactoryGraph.OUTPUT_ID).footprint(), Rect2i(11, 5, 2, 2))
	assert_eq(_keys(g.wires()), ["1:0>2:0"])
	assert_eq(g.wire_from(FactoryGraph.SOURCE_ID, 0).key(), "1:0>2:0")
	assert_eq(g.wires_into(FactoryGraph.OUTPUT_ID).size(), 1)
	assert_eq(g.count_live_paths(), 1)
	assert_eq(g.live_ids(), {1: true, 2: true})
	assert_true(g.reaches(1, 2))
	assert_false(g.reaches(2, 1))
	assert_true(g.reaches(2, 2))
	assert_eq(g.machine_at(Vector2i(2, 6)), FactoryGraph.SOURCE_ID)
	assert_eq(g.machine_at(Vector2i(12, 5)), FactoryGraph.OUTPUT_ID)
	assert_eq(g.machine_at(Vector2i(3, 5)), -1)
	assert_eq(g.count_kind(MachineCatalog.SOURCE), 1)
	assert_false(g.has_machine(3))
	assert_null(g.get_machine(3))
	assert_null(g.def_of(3))
	assert_eq(g.kind_of(3), &"")
	assert_eq(g.def_of(FactoryGraph.SOURCE_ID).output_ports, 1)
	_assert_consistent(g)


func test_add_validation_order() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()
	assert_eq(g.add_machine(MachineCatalog.FIRE, Vector2i(12, 0)), 3)   # the top-right corner
	var before: Dictionary = g.to_dict()
	# Each refused case also fails every later check, so only the order explains its code.
	assert_eq(g.can_add_machine(&"laser", Vector2i(13, 0)), GraphError.Code.UNKNOWN_KIND)
	assert_eq(g.can_add_machine(MachineCatalog.SOURCE, Vector2i(13, 0)), GraphError.Code.NOT_PLACEABLE)
	assert_eq(g.can_add_machine(MachineCatalog.ICE, Vector2i(13, 0)), GraphError.Code.OUT_OF_BOUNDS)
	assert_eq(g.can_add_machine(MachineCatalog.ICE, Vector2i(-1, 0)), GraphError.Code.OUT_OF_BOUNDS)
	assert_eq(g.can_add_machine(MachineCatalog.ICE, Vector2i(0, 11)), GraphError.Code.OUT_OF_BOUNDS)
	assert_eq(g.can_add_machine(MachineCatalog.ICE, Vector2i(2, 6)), GraphError.Code.CELL_OCCUPIED)
	assert_eq(g.add_machine(MachineCatalog.ICE, Vector2i(2, 6)), -1)
	assert_eq(g.add_machine(&"laser", Vector2i(0, 0)), -1)
	assert_eq(g.to_dict(), before)
	assert_eq(g.can_add_machine(MachineCatalog.ICE, Vector2i(12, 10)), GraphError.Code.OK)
	assert_true(g.is_inside(Vector2i(12, 10)))
	assert_false(g.is_area_free(Vector2i(11, 5)))
	assert_true(g.is_area_free(Vector2i(11, 5), FactoryGraph.OUTPUT_ID))
	# ids grow and are never reused, even after removing the newest machine
	assert_eq(g.add_machine(MachineCatalog.ICE, Vector2i(0, 0)), 4)
	assert_eq(g.remove_machine(4), GraphError.Code.OK)
	assert_eq(g.add_machine(MachineCatalog.SPLITTER, Vector2i(0, 0)), 5)
	assert_eq(g.machine_ids(), PackedInt32Array([1, 2, 3, 5]))
	assert_eq(g.count_kind(MachineCatalog.SPLITTER), 1)
	_assert_consistent(g)


func test_move_machine_belts_follow() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])   # Fire #3 at (3, 1)
	watch_signals(g)
	assert_eq(g.move_machine(3, Vector2i(6, 8)), GraphError.Code.OK)
	assert_eq(g.get_machine(3).cell, Vector2i(6, 8))
	assert_eq(g.machine_at(Vector2i(3, 1)), -1)
	assert_eq(g.machine_at(Vector2i(7, 9)), 3)
	assert_eq(_keys(g.wires()), ["1:0>3:0", "3:0>2:0"])
	assert_eq(g.count_live_paths(), 1)
	assert_signal_emit_count(g, "changed", 1)
	assert_eq(g.move_machine(3, Vector2i(6, 8)), GraphError.Code.OK)   # its own cell: no change, no signal
	assert_signal_emit_count(g, "changed", 1)
	assert_eq(g.move_machine(3, Vector2i(7, 8)), GraphError.Code.OK)   # overlapping only itself is fine
	assert_signal_emit_count(g, "changed", 2)
	_assert_consistent(g)
	var before: Dictionary = g.to_dict()
	assert_eq(g.move_machine(99, Vector2i(-5, -5)), GraphError.Code.NO_SUCH_MACHINE)
	assert_eq(g.move_machine(3, Vector2i(13, 0)), GraphError.Code.OUT_OF_BOUNDS)
	assert_eq(g.move_machine(3, Vector2i(2, 5)), GraphError.Code.CELL_OCCUPIED)
	assert_eq(g.to_dict(), before)
	assert_signal_emit_count(g, "changed", 2)
	assert_eq(g.move_machine(FactoryGraph.SOURCE_ID, Vector2i(0, 0)), GraphError.Code.OK)   # fixed, but movable
	assert_eq(_keys(g.wires()), ["1:0>3:0", "3:0>2:0"])
	_assert_consistent(g)


func test_remove_heals_simple_chain() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE, MachineCatalog.ICE])   # 1 -> 3 -> 4 -> 2
	assert_eq(g.remove_machine(3), GraphError.Code.OK)
	assert_false(g.has_machine(3))
	assert_eq(g.machine_at(Vector2i(3, 1)), -1)
	assert_eq(_keys(g.wires()), ["1:0>4:0", "4:0>2:0"])
	assert_eq(g.count_live_paths(), 1)
	_assert_consistent(g)
	assert_eq(g.remove_machine(4), GraphError.Code.OK)
	assert_eq(_keys(g.wires()), ["1:0>2:0"])
	_assert_consistent(g)
	# the heal keeps A's port and B's port: the Splitter's lower output feeds the Output again
	var s: FactoryGraph = Fixtures.split([], [MachineCatalog.FIRE])   # Splitter #3, Fire #4 on port 1
	assert_eq(_keys(s.wires()), ["1:0>3:0", "3:0>2:0", "3:1>4:0", "4:0>2:0"])
	assert_eq(s.remove_machine(4), GraphError.Code.OK)
	assert_eq(_keys(s.wires()), ["1:0>3:0", "3:0>2:0", "3:1>2:0"])
	assert_eq(s.count_live_paths(), 2)
	_assert_consistent(s)


func test_remove_does_not_heal_merge_or_fork() -> void:
	# merge: Ice #5 takes the Splitter's lower output and Fire #4
	var m: FactoryGraph = Fixtures.split([MachineCatalog.FIRE], [MachineCatalog.ICE])
	assert_eq(m.connect_ports(4, 0, 5, 0), GraphError.Code.OK)
	assert_eq(_keys(m.wires()), ["1:0>3:0", "3:0>4:0", "3:1>5:0", "4:0>5:0", "5:0>2:0"])
	assert_eq(m.count_live_paths(), 2)
	assert_eq(m.remove_machine(5), GraphError.Code.OK)
	assert_eq(_keys(m.wires()), ["1:0>3:0", "3:0>4:0"])
	assert_eq(m.count_live_paths(), 0)
	_assert_consistent(m)
	# fork: a Splitter with both outputs used
	var f: FactoryGraph = Fixtures.split([MachineCatalog.FIRE], [MachineCatalog.ICE])
	assert_eq(f.remove_machine(3), GraphError.Code.OK)
	assert_eq(_keys(f.wires()), ["4:0>2:0", "5:0>2:0"])
	assert_eq(f.count_live_paths(), 0)
	_assert_consistent(f)
	# a dead end (one belt in, none out) has nothing to heal
	var d: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])
	var ice: int = d.add_machine(MachineCatalog.ICE, Vector2i(6, 8))
	assert_eq(d.connect_ports(3, 0, ice, 0), GraphError.Code.OK)
	assert_eq(d.remove_machine(ice), GraphError.Code.OK)
	assert_eq(_keys(d.wires()), ["1:0>3:0"])
	_assert_consistent(d)


func test_remove_refuses_source_and_output() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()
	var before: Dictionary = g.to_dict()
	watch_signals(g)
	assert_eq(g.remove_machine(FactoryGraph.SOURCE_ID), GraphError.Code.NOT_REMOVABLE)
	assert_eq(g.remove_machine(FactoryGraph.OUTPUT_ID), GraphError.Code.NOT_REMOVABLE)
	assert_eq(g.remove_machine(99), GraphError.Code.NO_SUCH_MACHINE)
	assert_eq(g.to_dict(), before)
	assert_signal_emit_count(g, "changed", 0)
	_assert_consistent(g)


func test_connect_validation_order() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE, MachineCatalog.ICE])   # 1 -> 3 -> 4 -> 2
	var splitter: int = g.add_machine(MachineCatalog.SPLITTER, Vector2i(6, 8))     # #5, unconnected
	var before: Dictionary = g.to_dict()
	watch_signals(g)
	# [from_id, from_port, to_id, to_port, expected]: each case also fails later checks where it can
	var cases: Array[Array] = [
		[99, 7, 3, 0, GraphError.Code.NO_SUCH_MACHINE],
		[3, 0, 99, 0, GraphError.Code.NO_SUCH_MACHINE],
		[2, 0, 3, 0, GraphError.Code.NO_SUCH_PORT],          # the Output has no output port (and 3 reaches 2)
		[splitter, 2, 3, 0, GraphError.Code.NO_SUCH_PORT],
		[3, -1, 4, 0, GraphError.Code.NO_SUCH_PORT],
		[4, 0, 1, 0, GraphError.Code.NO_SUCH_PORT],          # the Source has no input port (and 1 reaches 4)
		[3, 0, 4, 1, GraphError.Code.NO_SUCH_PORT],
		[3, 0, 3, 0, GraphError.Code.SELF_LOOP],
		[3, 0, 4, 0, GraphError.Code.DUPLICATE_WIRE],
		[4, 0, 3, 0, GraphError.Code.WOULD_CYCLE],
	]
	for c: Array in cases:
		var label: String = "%d:%d>%d:%d" % [c[0], c[1], c[2], c[3]]
		assert_eq(g.can_connect(c[0], c[1], c[2], c[3]), c[4], label)
		assert_eq(g.connect_ports(c[0], c[1], c[2], c[3]), c[4], label)
	assert_eq(g.to_dict(), before)
	assert_signal_emit_count(g, "changed", 0)
	var full: FactoryGraph = _splitter_chain(3)
	assert_eq(full.can_connect(1, 0, 2, 0), GraphError.Code.OK)   # 1 path, replacing the 8
	var extra: int = full.add_machine(MachineCatalog.SPLITTER, Vector2i(3, 8))
	assert_eq(full.connect_ports(extra, 0, 2, 0), GraphError.Code.OK)
	assert_eq(full.connect_ports(extra, 1, 2, 0), GraphError.Code.OK)
	assert_eq(full.can_connect(5, 0, extra, 0), GraphError.Code.TOO_MANY_BULLETS)   # 12 paths
	assert_eq(g.can_connect(splitter, 1, 2, 0), GraphError.Code.OK)
	_assert_consistent(g)
	_assert_consistent(full)


func test_connect_replaces_busy_output() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])   # 1 -> 3 -> 2
	var ice: int = g.add_machine(MachineCatalog.ICE, Vector2i(6, 8))
	watch_signals(g)
	assert_eq(g.connect_ports(FactoryGraph.SOURCE_ID, 0, ice, 0), GraphError.Code.OK)
	assert_eq(g.wire_from(FactoryGraph.SOURCE_ID, 0).key(), "1:0>4:0")
	assert_eq(_keys(g.wires()), ["1:0>4:0", "3:0>2:0"])
	assert_eq(g.count_live_paths(), 0)
	assert_signal_emit_count(g, "changed", 1)
	assert_eq(g.connect_ports(ice, 0, 3, 0), GraphError.Code.OK)
	assert_eq(_keys(g.wires()), ["1:0>4:0", "3:0>2:0", "4:0>3:0"])
	assert_eq(g.count_live_paths(), 1)
	_assert_consistent(g)


func test_input_port_accepts_many_belts() -> void:
	var g: FactoryGraph = Fixtures.split([], [])   # both Splitter outputs into the Output's one input
	assert_eq(_keys(g.wires()), ["1:0>3:0", "3:0>2:0", "3:1>2:0"])
	assert_eq(g.wires_into(FactoryGraph.OUTPUT_ID).size(), 2)
	assert_eq(g.count_live_paths(), 2)
	var fire: int = g.add_machine(MachineCatalog.FIRE, Vector2i(6, 8))
	assert_eq(g.connect_ports(3, 0, fire, 0), GraphError.Code.OK)
	assert_eq(g.connect_ports(3, 1, fire, 0), GraphError.Code.OK)
	assert_eq(g.connect_ports(fire, 0, FactoryGraph.OUTPUT_ID, 0), GraphError.Code.OK)
	assert_eq(_keys(g.wires_into(fire)), ["3:0>4:0", "3:1>4:0"])
	assert_eq(g.count_live_paths(), 2)   # streams merge, but each path stays a bullet
	_assert_consistent(g)


func test_cycle_refused() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE, MachineCatalog.ICE, MachineCatalog.POISON])
	assert_true(g.reaches(3, 5))
	assert_false(g.reaches(5, 3))
	assert_eq(g.connect_ports(5, 0, 3, 0), GraphError.Code.WOULD_CYCLE)
	assert_eq(g.connect_ports(4, 0, 3, 0), GraphError.Code.WOULD_CYCLE)
	var speed: int = g.add_machine(MachineCatalog.SPEED_UP, Vector2i(6, 8))   # #6, outside the chain
	assert_eq(g.connect_ports(speed, 0, 3, 0), GraphError.Code.OK)
	assert_eq(g.connect_ports(5, 0, speed, 0), GraphError.Code.WOULD_CYCLE)   # 6 -> 3 -> 4 -> 5 -> 6
	assert_eq(_keys(g.wires()), ["1:0>3:0", "3:0>4:0", "4:0>5:0", "5:0>2:0", "6:0>3:0"])
	_assert_consistent(g)


func test_path_count_with_merges() -> void:
	assert_eq(_splitter_chain(1).count_live_paths(), 2)
	var g: FactoryGraph = _splitter_chain(2)   # Source -> #3, both outputs -> #4, both outputs -> Output
	assert_eq(g.count_live_paths(), 4)
	assert_eq(g.wires_into(4).size(), 2)
	assert_eq(g.live_ids(), {1: true, 2: true, 3: true, 4: true})
	_assert_consistent(g)
	assert_eq(_splitter_chain(3).count_live_paths(), 8)


func test_ninth_bullet_refused_and_graph_unchanged() -> void:
	var g: FactoryGraph = _splitter_chain(3)                                   # 8 paths
	var front: int = g.add_machine(MachineCatalog.SPLITTER, Vector2i(3, 8))   # #6
	assert_eq(g.connect_ports(front, 0, 3, 0), GraphError.Code.OK)
	assert_eq(g.connect_ports(FactoryGraph.SOURCE_ID, 0, front, 0), GraphError.Code.OK)   # Source -> #6 -> #3
	assert_eq(g.count_live_paths(), 8)
	var before: Dictionary = g.to_dict()
	watch_signals(g)
	assert_eq(g.live_paths_if_connected(front, 1, FactoryGraph.OUTPUT_ID, 0), 9)
	assert_eq(g.connect_ports(front, 1, FactoryGraph.OUTPUT_ID, 0), GraphError.Code.TOO_MANY_BULLETS)
	assert_eq(g.to_dict(), before)
	assert_eq(g.count_live_paths(), 8)
	assert_signal_emit_count(g, "changed", 0)
	_assert_consistent(g)


func test_splice_keeps_path_count() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])   # 1 -> 3 -> 2
	var belt: Wire = Wire.make(3, 0, 2, 0)                         # a copy: splicing matches by same_as()
	var gone: Wire = Wire.make(3, 0, 9, 0)
	assert_eq(g.can_splice(&"laser", Vector2i(13, 0), gone), GraphError.Code.UNKNOWN_KIND)
	assert_eq(g.can_splice(MachineCatalog.OUTPUT, Vector2i(13, 0), gone), GraphError.Code.NOT_PLACEABLE)
	assert_eq(g.can_splice(MachineCatalog.SPLITTER, Vector2i(13, 0), gone), GraphError.Code.NO_SUCH_WIRE)
	assert_eq(g.can_splice(MachineCatalog.SPLITTER, Vector2i(13, 0), belt), GraphError.Code.OUT_OF_BOUNDS)
	assert_eq(g.can_splice(MachineCatalog.SPLITTER, Vector2i(3, 1), belt), GraphError.Code.CELL_OCCUPIED)
	assert_eq(g.splice_machine(MachineCatalog.SPLITTER, Vector2i(3, 1), belt), -1)
	watch_signals(g)
	var id: int = g.splice_machine(MachineCatalog.SPLITTER, Vector2i(7, 8), belt)
	assert_eq(id, 4)
	assert_eq(_keys(g.wires()), ["1:0>3:0", "3:0>4:0", "4:0>2:0"])
	assert_null(g.wire_from(id, 1))
	assert_eq(g.count_live_paths(), 1)
	assert_signal_emit_count(g, "changed", 1)
	_assert_consistent(g)
	var s: FactoryGraph = Fixtures.split([], [])
	var fire: int = s.splice_machine(MachineCatalog.FIRE, Vector2i(7, 8), s.wire_from(3, 1))
	assert_eq(_keys(s.wires()), ["1:0>3:0", "3:0>2:0", "3:1>%d:0" % fire, "%d:0>2:0" % fire])
	assert_eq(s.count_live_paths(), 2)
	_assert_consistent(s)


func test_changed_once_per_success_never_on_refusal() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()
	watch_signals(g)
	var fire: int = g.add_machine(MachineCatalog.FIRE, Vector2i(5, 1))
	assert_signal_emit_count(g, "changed", 1)
	g.add_machine(MachineCatalog.FIRE, Vector2i(5, 1))                       # occupied
	assert_signal_emit_count(g, "changed", 1)
	g.move_machine(fire, Vector2i(5, 8))
	assert_signal_emit_count(g, "changed", 2)
	g.move_machine(fire, Vector2i(5, 8))                                      # own cell
	g.move_machine(fire, Vector2i(1, 5))                                      # occupied
	assert_signal_emit_count(g, "changed", 2)
	g.connect_ports(FactoryGraph.SOURCE_ID, 0, fire, 0)                       # replace: one step
	assert_signal_emit_count(g, "changed", 3)
	g.connect_ports(FactoryGraph.SOURCE_ID, 0, fire, 0)                       # duplicate
	assert_signal_emit_count(g, "changed", 3)
	g.connect_ports(fire, 0, FactoryGraph.OUTPUT_ID, 0)
	assert_signal_emit_count(g, "changed", 4)
	g.disconnect_wire(Wire.make(fire, 0, FactoryGraph.OUTPUT_ID, 0))
	assert_signal_emit_count(g, "changed", 5)
	g.disconnect_wire(Wire.make(fire, 0, FactoryGraph.OUTPUT_ID, 0))         # gone
	assert_signal_emit_count(g, "changed", 5)
	g.connect_ports(fire, 0, FactoryGraph.OUTPUT_ID, 0)
	var splitter: int = g.splice_machine(MachineCatalog.SPLITTER, Vector2i(8, 8), Wire.make(fire, 0, 2, 0))
	assert_signal_emit_count(g, "changed", 7)
	g.splice_machine(MachineCatalog.SPLITTER, Vector2i(8, 1), Wire.make(fire, 0, 2, 0))   # belt gone
	assert_signal_emit_count(g, "changed", 7)
	g.remove_machine(splitter)                                                # remove + heal: one step
	assert_signal_emit_count(g, "changed", 8)
	g.remove_machine(splitter)
	g.remove_machine(FactoryGraph.SOURCE_ID)
	assert_signal_emit_count(g, "changed", 8)
	g.assign_from(FactoryGraph.create_default())
	assert_signal_emit_count(g, "changed", 9)
	_assert_consistent(g)


func test_live_ids_excludes_dead_end_and_idle() -> void:
	var g: FactoryGraph = Fixtures.split([], [MachineCatalog.FIRE])   # Splitter #3, Fire #4 on port 1
	assert_eq(g.disconnect_wire(Wire.make(4, 0, 2, 0)), GraphError.Code.OK)   # Fire #4: a dead end
	var ice: int = g.add_machine(MachineCatalog.ICE, Vector2i(7, 8))         # idle, feeds the Output
	var poison: int = g.add_machine(MachineCatalog.POISON, Vector2i(9, 0))   # idle, feeds the idle Ice
	g.add_machine(MachineCatalog.PIERCE, Vector2i(0, 10))                    # idle, no belts
	assert_eq(g.connect_ports(ice, 0, FactoryGraph.OUTPUT_ID, 0), GraphError.Code.OK)
	assert_eq(g.connect_ports(poison, 0, ice, 0), GraphError.Code.OK)
	assert_eq(g.live_ids(), {1: true, 2: true, 3: true})
	assert_eq(g.count_live_paths(), 1)
	assert_true(g.reaches(FactoryGraph.SOURCE_ID, 4))
	assert_false(g.reaches(FactoryGraph.SOURCE_ID, ice))
	_assert_consistent(g)


func test_assign_from_and_to_dict() -> void:
	assert_eq(FactoryGraph.create_default().to_dict(), {
		"next_id": 3,
		"machines": [{"id": 1, "kind": "source", "cell": [1, 5]}, {"id": 2, "kind": "output", "cell": [11, 5]}],
		"wires": ["1:0>2:0"],
	})
	var src: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE, MachineCatalog.ICE])
	assert_eq(src.remove_machine(3), GraphError.Code.OK)
	assert_eq(src.to_dict(), {
		"next_id": 5,
		"machines": [{"id": 1, "kind": "source", "cell": [1, 5]}, {"id": 2, "kind": "output", "cell": [11, 5]},
				{"id": 4, "kind": "ice", "cell": [5, 1]}],
		"wires": ["1:0>4:0", "4:0>2:0"],
	})
	var copy: FactoryGraph = FactoryGraph.create_default()
	watch_signals(copy)
	copy.assign_from(src)
	assert_signal_emit_count(copy, "changed", 1)
	assert_eq(copy.to_dict(), src.to_dict())
	assert_not_same(copy.get_machine(4), src.get_machine(4))
	assert_eq(src.move_machine(4, Vector2i(6, 8)), GraphError.Code.OK)
	assert_eq(copy.get_machine(4).cell, Vector2i(5, 1))                      # a deep copy
	assert_eq(copy.add_machine(MachineCatalog.POISON, Vector2i(0, 0)), 5)    # ids continue from the copy
	_assert_consistent(copy)
	copy.assign_from(FactoryGraph.create_default())                          # a restart resets ids
	assert_eq(copy.to_dict(), FactoryGraph.create_default().to_dict())
	assert_eq(copy.add_machine(MachineCatalog.POISON, Vector2i(0, 0)), 3)
	var own: Dictionary = src.to_dict()
	src.assign_from(src)
	assert_eq(src.to_dict(), own)
	_assert_consistent(src)


func test_wire_key_and_canonical_order() -> void:
	var w: Wire = Wire.make(12, 1, 3, 0)
	assert_eq(w.key(), "12:1>3:0")
	assert_true(w.same_as(Wire.make(12, 1, 3, 0)))
	assert_false(w.same_as(Wire.make(11, 1, 3, 0)))
	assert_false(w.same_as(Wire.make(12, 0, 3, 0)))
	assert_false(w.same_as(Wire.make(12, 1, 4, 0)))
	assert_false(w.same_as(Wire.make(12, 1, 3, 1)))
	assert_false(w.same_as(null))
	assert_false(Wire.less(w, w))
	var list: Array[Wire] = [Wire.make(10, 0, 2, 0), Wire.make(9, 1, 2, 0), Wire.make(9, 0, 4, 0),
			Wire.make(9, 0, 3, 1), Wire.make(9, 0, 3, 0)]
	list.sort_custom(Wire.less)
	assert_eq(_keys(list), ["9:0>3:0", "9:0>3:1", "9:0>4:0", "9:1>2:0", "10:0>2:0"])   # numbers, not text
	var g: FactoryGraph = Fixtures.split([MachineCatalog.FIRE], [])   # belts added out of order
	assert_eq(_keys(g.wires()), ["1:0>3:0", "3:0>4:0", "3:1>2:0", "4:0>2:0"])
	var copy: Array[Wire] = g.wires()
	copy.clear()
	assert_eq(g.wires().size(), 4)
	assert_true(g.has_wire(Wire.make(3, 1, 2, 0)))
	assert_false(g.has_wire(Wire.make(3, 1, 2, 1)))
	assert_false(g.has_wire(null))
	assert_eq(g.can_disconnect(Wire.make(3, 1, 2, 1)), GraphError.Code.NO_SUCH_WIRE)


func test_error_texts() -> void:
	for code: GraphError.Code in GraphError.Code.values():
		assert_eq(GraphError.describe(code).is_empty(), code == GraphError.Code.OK, str(code))
	assert_eq(GraphError.describe(GraphError.Code.TOO_MANY_BULLETS), "The gun fires at most 8 bullets per shot.")
	assert_eq(GraphError.describe(GraphError.Code.WOULD_CYCLE), "That would make a loop: bullets can't go backwards.")


func test_invariant_check_reports_corruption() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])
	g._wires.append(Wire.make(3, 0, 1, 0))   # a second belt on 3:0, into the Source (no input), closing a cycle
	g._owner.erase(Vector2i(3, 1))
	g._next_id = 3
	var problems: String = "\n".join(g.debug_check_invariants())
	for part: String in ["owner map", "carries two belts", "missing machine or port", "cycle", "next id"]:
		assert_string_contains(problems, part)
	g._machines.erase(FactoryGraph.OUTPUT_ID)
	assert_string_contains("\n".join(g.debug_check_invariants()), "Source or the Output")


## Source -> #3, both outputs -> #4's input, ..., both outputs of the last -> Output: 2^n paths.
func _splitter_chain(n: int) -> FactoryGraph:
	var g: FactoryGraph = FactoryGraph.create_default()
	var prev: int = FactoryGraph.SOURCE_ID
	var ports: int = 1
	for i: int in n:
		var splitter: int = g.add_machine(MachineCatalog.SPLITTER, Vector2i(3 + 2 * i, 5))
		for p: int in ports:
			g.connect_ports(prev, p, splitter, 0)
		prev = splitter
		ports = 2
	for p: int in ports:
		g.connect_ports(prev, p, FactoryGraph.OUTPUT_ID, 0)
	return g


func _keys(list: Array[Wire]) -> Array[String]:
	var out: Array[String] = []
	for w: Wire in list:
		out.append(w.key())
	return out


func _assert_consistent(g: FactoryGraph) -> void:
	var problems: PackedStringArray = g.debug_check_invariants()
	assert_true(problems.is_empty(), "\n".join(problems))

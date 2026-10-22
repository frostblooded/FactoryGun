extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")
const PLAIN: String = "DMG 10.0 · SPD 600 · SIZE 5.0"


func test_default_plan() -> void:
	var plan: ShotPlan = FactoryCompiler.compile(FactoryGraph.create_default())
	assert_true(plan.is_valid())
	assert_eq(_descs(plan), [PLAIN])
	assert_eq(plan.bullets[0].angle_offset, 0.0)
	assert_eq(plan.bullets[0].real_splits, 0)
	assert_eq(plan.statuses, {1: ShotPlan.MachineStatus.ACTIVE, 2: ShotPlan.MachineStatus.ACTIVE})
	assert_true(plan.issues.is_empty())
	assert_eq(plan.live_wire_keys, {"1:0>2:0": true})
	assert_eq(plan.wire_streams.keys(), ["1:0>2:0"])
	assert_eq(_stream_texts(plan, "1:0>2:0"), [PLAIN])
	assert_eq(plan.summary_lines(), PackedStringArray(["1 bullet/shot · 4 shots/s · 10.0 dmg/shot", "#1 " + PLAIN]))


func test_chain_stacks_modifiers() -> void:
	# C.8: Source -> Speed Up -> Size Up -> Fire -> Output
	var plan: ShotPlan = FactoryCompiler.compile(Fixtures.chain([MachineCatalog.SPEED_UP, MachineCatalog.SIZE_UP,
			MachineCatalog.FIRE]))
	assert_eq(plan.bullets.size(), 1)
	var b: BulletSpec = plan.bullets[0]
	assert_almost_eq(b.damage, 13.75, 1e-4)    # 10 · 1.1 · 1.25
	assert_almost_eq(b.speed, 729.0, 1e-4)     # 600 · 1.35 · 0.9
	assert_almost_eq(b.radius, 7.5, 1e-4)
	assert_eq([b.speed_level, b.size_level, b.fire_level, b.ice_level, b.poison_level, b.pierce, b.real_splits],
			[1, 1, 1, 0, 0, 0, 0])
	for id: int in [3, 4, 5]:
		assert_eq(plan.status_of(id), ShotPlan.MachineStatus.ACTIVE, str(id))
	assert_true(plan.issues.is_empty())
	# repeats of a kind on one path stack
	var stacked: ShotPlan = FactoryCompiler.compile(Fixtures.chain([MachineCatalog.PIERCE, MachineCatalog.ICE,
			MachineCatalog.PIERCE, MachineCatalog.POISON, MachineCatalog.ICE]))
	assert_eq(_descs(stacked), [PLAIN + " · ICE II · POISON I · PIERCE 2"])


func test_order_on_path_does_not_change_stats() -> void:
	var kinds: Array[StringName] = [MachineCatalog.SPEED_UP, MachineCatalog.SIZE_UP, MachineCatalog.FIRE]
	for order: Array in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
		var chain: Array[StringName] = []
		for i: int in order:
			chain.append(kinds[i])
		var b: BulletSpec = FactoryCompiler.compile(Fixtures.chain(chain)).bullets[0]
		assert_almost_eq(b.damage, 13.75, 1e-4, str(chain))
		assert_almost_eq(b.speed, 729.0, 1e-4, str(chain))
		assert_almost_eq(b.radius, 7.5, 1e-4, str(chain))
		assert_eq(b.fire_level, 1, str(chain))
	# over a cap, the order only decides which Fire is the useless one: the one nearest the Output
	var ice_first: ShotPlan = FactoryCompiler.compile(Fixtures.chain([MachineCatalog.ICE, MachineCatalog.FIRE,
			MachineCatalog.FIRE, MachineCatalog.FIRE, MachineCatalog.FIRE]))      # Ice #3, Fires #4..#7
	var ice_last: ShotPlan = FactoryCompiler.compile(Fixtures.chain([MachineCatalog.FIRE, MachineCatalog.FIRE,
			MachineCatalog.FIRE, MachineCatalog.FIRE, MachineCatalog.ICE]))       # Fires #3..#6, Ice #7
	assert_eq(_descs(ice_first), [PLAIN + " · FIRE III · ICE I"])
	assert_eq(_descs(ice_last), _descs(ice_first))
	assert_eq(_statuses(ice_first, [3, 4, 5, 6, 7]), [ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.ACTIVE,
			ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.CAPPED])
	assert_eq(_statuses(ice_last, [3, 4, 5, 6, 7]), [ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.ACTIVE,
			ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.CAPPED, ShotPlan.MachineStatus.ACTIVE])


func test_cap_marks_later_machines_capped() -> void:
	# C.8: Source -> Fire ×4 -> Output
	var plan: ShotPlan = FactoryCompiler.compile(Fixtures.chain([MachineCatalog.FIRE, MachineCatalog.FIRE,
			MachineCatalog.FIRE, MachineCatalog.FIRE]))
	assert_eq(plan.bullets[0].fire_level, 3)
	assert_eq(_statuses(plan, [3, 4, 5, 6]), [ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.ACTIVE,
			ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.CAPPED])
	assert_eq(plan.issues.size(), 1)
	assert_eq(plan.issues[0].code, PlanIssue.Code.CAPPED)
	assert_eq(plan.issues[0].machine_id, 6)
	assert_eq(plan.issues[0].severity(), PlanIssue.Severity.WARNING)
	assert_eq(plan.summary_lines(), PackedStringArray([
		"1 bullet/shot · 4 shots/s · 10.0 dmg/shot",
		"#1 " + PLAIN + " · FIRE III",
		"! Fire #6 adds nothing: Fire is capped at 3 per bullet.",
	]))
	# Pierce stacks to 4
	var pierce: ShotPlan = FactoryCompiler.compile(Fixtures.chain([MachineCatalog.PIERCE, MachineCatalog.PIERCE,
			MachineCatalog.PIERCE, MachineCatalog.PIERCE, MachineCatalog.PIERCE]))   # #3..#7
	assert_eq(pierce.bullets[0].pierce, 4)
	assert_eq(pierce.status_of(6), ShotPlan.MachineStatus.ACTIVE)
	assert_eq(_issue_texts(pierce), ["Pierce #7 adds nothing: Pierce is capped at 4 per bullet."])
	# useful on another path, so not CAPPED: Fire #7 is the 4th Fire of the upper path and the 1st of the lower
	var g: FactoryGraph = Fixtures.split([MachineCatalog.FIRE, MachineCatalog.FIRE, MachineCatalog.FIRE], [])
	var fire: int = g.splice_machine(MachineCatalog.FIRE, Vector2i(9, 8), Wire.make(6, 0, FactoryGraph.OUTPUT_ID, 0))
	assert_eq(g.connect_ports(3, 1, fire, 0), GraphError.Code.OK)
	var shared: ShotPlan = FactoryCompiler.compile(g)
	assert_eq(_descs(shared), ["DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE III", "DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE I"])
	assert_eq(shared.status_of(fire), ShotPlan.MachineStatus.ACTIVE)
	assert_true(shared.issues.is_empty())


func test_real_split_penalty_and_fan() -> void:
	var g: FactoryGraph = Fixtures.split([MachineCatalog.FIRE], [MachineCatalog.ICE])   # Splitter #3, Fire #4, Ice #5
	var plan: ShotPlan = FactoryCompiler.compile(g)
	# bullet 0 is the upper branch (port 0), at the counter-clockwise -5°
	assert_eq(_descs(plan), ["DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE I", "DMG 7.0 · SPD 600 · SIZE 5.0 · ICE I"])
	_assert_degrees(_angles(plan), [-5.0, 5.0])
	assert_eq(plan.bullets[0].real_splits, 1)
	assert_almost_eq(plan.bullets[1].damage, 7.0, 1e-4)
	assert_true(FactoryCompiler.is_real_split(g, g.live_ids(), 3))
	assert_false(FactoryCompiler.is_real_split(g, g.live_ids(), 4))   # one output only
	assert_eq(plan.status_of(3), ShotPlan.MachineStatus.ACTIVE)
	assert_true(plan.issues.is_empty())
	assert_eq(plan.summary_lines()[0], "2 bullets/shot · 4 shots/s · 14.0 dmg/shot")
	assert_eq(_stream_texts(plan, "1:0>3:0"), [PLAIN])                   # no penalty before the split
	assert_eq(_stream_texts(plan, "3:0>4:0"), ["DMG 7.0 · SPD 600 · SIZE 5.0"])


func test_modifiers_before_split_apply_to_both() -> void:
	# C.8: Source -> Fire -> Splitter; upper: Speed Up -> Output; lower: Pierce -> Output
	var g: FactoryGraph = Fixtures.split([MachineCatalog.SPEED_UP], [MachineCatalog.PIERCE])   # #3, #4, #5
	var fire: int = g.splice_machine(MachineCatalog.FIRE, Vector2i(1, 1), Wire.make(FactoryGraph.SOURCE_ID, 0, 3, 0))
	var plan: ShotPlan = FactoryCompiler.compile(g)
	assert_eq(_descs(plan), ["DMG 7.7 · SPD 810 · SIZE 5.0 · FIRE I", "DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE I · PIERCE 1"])
	assert_almost_eq(plan.bullets[0].damage, 7.7, 1e-4)
	assert_almost_eq(plan.bullets[0].speed, 810.0, 1e-4)
	assert_almost_eq(plan.bullets[1].damage, 7.0, 1e-4)
	assert_eq(plan.bullets[1].pierce, 1)
	_assert_degrees(_angles(plan), [-5.0, 5.0])
	assert_eq(_statuses(plan, [fire, 3, 4, 5]), [ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.ACTIVE,
			ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.ACTIVE])
	assert_eq(_stream_texts(plan, "%d:0>3:0" % fire), [PLAIN + " · FIRE I"])


func test_one_sided_splitter_is_free() -> void:
	# C.8: Source -> Splitter; upper -> Output; lower unconnected
	var g: FactoryGraph = Fixtures.split([], [])
	assert_eq(g.disconnect_wire(Wire.make(3, 1, FactoryGraph.OUTPUT_ID, 0)), GraphError.Code.OK)
	var plan: ShotPlan = FactoryCompiler.compile(g)
	assert_eq(_descs(plan), [PLAIN])
	assert_eq(plan.bullets[0].real_splits, 0)
	assert_eq(plan.bullets[0].angle_offset, 0.0)
	assert_eq(plan.status_of(3), ShotPlan.MachineStatus.ONE_SIDED)
	assert_eq(_issue_texts(plan), ["Splitter #3 uses one output, so it does not split."])
	assert_eq(plan.issues[0].code, PlanIssue.Code.ONE_SIDED)
	assert_eq(plan.issues[0].machine_id, 3)
	assert_eq(plan.issues[0].severity(), PlanIssue.Severity.INFO)
	# a spliced Splitter uses output 0 only (C.5)
	var spliced: FactoryGraph = FactoryGraph.create_default()
	var splitter: int = spliced.splice_machine(MachineCatalog.SPLITTER, Vector2i(5, 5),
			Wire.make(FactoryGraph.SOURCE_ID, 0, FactoryGraph.OUTPUT_ID, 0))
	var spliced_plan: ShotPlan = FactoryCompiler.compile(spliced)
	assert_eq(_descs(spliced_plan), [PLAIN])
	assert_eq(spliced_plan.status_of(splitter), ShotPlan.MachineStatus.ONE_SIDED)
	# an output into a dead end does not split either
	var dead: FactoryGraph = Fixtures.split([], [MachineCatalog.FIRE])   # Fire #4 on port 1
	assert_eq(dead.disconnect_wire(Wire.make(4, 0, FactoryGraph.OUTPUT_ID, 0)), GraphError.Code.OK)
	var dead_plan: ShotPlan = FactoryCompiler.compile(dead)
	assert_eq(_descs(dead_plan), [PLAIN])
	assert_false(FactoryCompiler.is_real_split(dead, dead.live_ids(), 3))
	assert_eq(_statuses(dead_plan, [3, 4]), [ShotPlan.MachineStatus.ONE_SIDED, ShotPlan.MachineStatus.DEAD_END])
	assert_eq(_issue_texts(dead_plan), [                                 # WARNING before INFO
		"Fire #4 is a dead end: its belt never reaches the Output.",
		"Splitter #3 uses one output, so it does not split.",
	])


func test_merge_gives_one_bullet_per_path() -> void:
	# Fire #4 (upper) merges into Ice #5 (lower): two paths run through Ice, so two bullets
	var g: FactoryGraph = Fixtures.split([MachineCatalog.FIRE], [MachineCatalog.ICE])
	assert_eq(g.connect_ports(4, 0, 5, 0), GraphError.Code.OK)
	var plan: ShotPlan = FactoryCompiler.compile(g)
	var both: Array[String] = ["DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE I · ICE I", "DMG 7.0 · SPD 600 · SIZE 5.0 · ICE I"]
	assert_eq(_descs(plan), both)
	assert_eq(plan.bullets.size(), g.count_live_paths())
	assert_eq(_stream_texts(plan, "5:0>2:0"), both)
	# identical streams show as one belt item, but each path still fires
	var twin: FactoryGraph = Fixtures.split([], [])
	var fire: int = twin.add_machine(MachineCatalog.FIRE, Vector2i(7, 8))
	assert_eq(twin.connect_ports(3, 0, fire, 0), GraphError.Code.OK)
	assert_eq(twin.connect_ports(3, 1, fire, 0), GraphError.Code.OK)
	assert_eq(twin.connect_ports(fire, 0, FactoryGraph.OUTPUT_ID, 0), GraphError.Code.OK)
	var twin_plan: ShotPlan = FactoryCompiler.compile(twin)
	var fired: String = "DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE I"
	assert_eq(_descs(twin_plan), [fired, fired])
	assert_eq(_stream_texts(twin_plan, "%d:0>2:0" % fire), [fired])
	# C.8: two chained Splitters, both outputs into the next: 4 bullets of 10 · 0.7²
	var four: ShotPlan = FactoryCompiler.compile(_splitter_chain(2))
	assert_eq(four.bullets.size(), 4)
	for b: BulletSpec in four.bullets:
		assert_almost_eq(b.damage, 4.9, 1e-4)
		assert_eq(b.real_splits, 2)
	_assert_degrees(_angles(four), [-15.0, -5.0, 5.0, 15.0])   # 50° / 3 is clamped to a 10° step
	# three of them: 8 bullets of 10 · 0.7³
	var eight: ShotPlan = FactoryCompiler.compile(_splitter_chain(3))
	assert_eq(eight.bullets.size(), 8)
	for b: BulletSpec in eight.bullets:
		assert_almost_eq(b.damage, 3.43, 1e-4)


func test_fan_angles() -> void:
	assert_eq(FactoryCompiler.fan_angles(0).size(), 0)
	_assert_degrees(FactoryCompiler.fan_angles(1), [0.0])
	_assert_degrees(FactoryCompiler.fan_angles(2), [-5.0, 5.0])                   # (n - 1) / 2.0, not an int division
	_assert_degrees(FactoryCompiler.fan_angles(4), [-15.0, -5.0, 5.0, 15.0])      # 10° step
	_assert_degrees(FactoryCompiler.fan_angles(6), [-25.0, -15.0, -5.0, 5.0, 15.0, 25.0])
	var step: float = 50.0 / 7.0                                                    # 8 bullets keep a 50° span
	_assert_degrees(FactoryCompiler.fan_angles(8), [-3.5 * step, -2.5 * step, -1.5 * step, -0.5 * step,
			0.5 * step, 1.5 * step, 2.5 * step, 3.5 * step])
	var eight: PackedFloat64Array = FactoryCompiler.fan_angles(8)
	assert_almost_eq(rad_to_deg(eight[7] - eight[0]), 50.0, 1e-4)
	assert_eq(FactoryCompiler.fan_angles(-1).size(), 0)


func test_dead_end_and_idle_statuses_and_issues() -> void:
	# Fire #3 -> Ice #4 -> Output with nothing into #3; the default belt is kept
	var g: FactoryGraph = FactoryGraph.create_default()
	var fire: int = g.add_machine(MachineCatalog.FIRE, Vector2i(5, 1))
	var ice: int = g.add_machine(MachineCatalog.ICE, Vector2i(8, 1))
	assert_eq(g.connect_ports(fire, 0, ice, 0), GraphError.Code.OK)
	assert_eq(g.connect_ports(ice, 0, FactoryGraph.OUTPUT_ID, 0), GraphError.Code.OK)
	var plan: ShotPlan = FactoryCompiler.compile(g)
	assert_eq(_descs(plan), [PLAIN])
	assert_eq(_statuses(plan, [1, 2, fire, ice]), [ShotPlan.MachineStatus.ACTIVE, ShotPlan.MachineStatus.ACTIVE,
			ShotPlan.MachineStatus.IDLE, ShotPlan.MachineStatus.IDLE])
	assert_eq(_issue_texts(plan), ["Fire #3 is idle: no bullets reach it.", "Ice #4 is idle: no bullets reach it."])
	for issue: PlanIssue in plan.issues:
		assert_eq(issue.code, PlanIssue.Code.IDLE)
		assert_eq(issue.severity(), PlanIssue.Severity.WARNING)
	assert_eq(plan.live_wire_keys, {"1:0>2:0": true})
	assert_eq(plan.wire_streams.keys(), ["1:0>2:0"])
	# dead ends are reached from the Source but never reach the Output, even behind another dead end
	var d: FactoryGraph = Fixtures.split([MachineCatalog.FIRE], [])   # Splitter #3, Fire #4 on port 0
	assert_eq(d.disconnect_wire(Wire.make(4, 0, FactoryGraph.OUTPUT_ID, 0)), GraphError.Code.OK)
	var poison: int = d.add_machine(MachineCatalog.POISON, Vector2i(9, 1))
	assert_eq(d.connect_ports(4, 0, poison, 0), GraphError.Code.OK)
	var pierce: int = d.add_machine(MachineCatalog.PIERCE, Vector2i(0, 10))   # no belts at all
	var dead: ShotPlan = FactoryCompiler.compile(d)
	assert_eq(_descs(dead), [PLAIN])
	assert_eq(_statuses(dead, [3, 4, poison, pierce]), [ShotPlan.MachineStatus.ONE_SIDED,
			ShotPlan.MachineStatus.DEAD_END, ShotPlan.MachineStatus.DEAD_END, ShotPlan.MachineStatus.IDLE])
	assert_eq(_issue_texts(dead), [
		"Fire #4 is a dead end: its belt never reaches the Output.",
		"Poison #5 is a dead end: its belt never reaches the Output.",
		"Pierce #6 is idle: no bullets reach it.",
		"Splitter #3 uses one output, so it does not split.",
	])
	assert_eq(dead.live_wire_keys, {"1:0>3:0": true, "3:1>2:0": true})
	assert_false(dead.wire_streams.has("3:0>4:0"))


func test_no_path_plan() -> void:
	var g: FactoryGraph = FactoryGraph.create_default()
	assert_eq(g.disconnect_wire(Wire.make(FactoryGraph.SOURCE_ID, 0, FactoryGraph.OUTPUT_ID, 0)), GraphError.Code.OK)
	var plan: ShotPlan = FactoryCompiler.compile(g)
	assert_false(plan.is_valid())
	assert_true(plan.bullets.is_empty())
	assert_eq(plan.issues.size(), 1)
	assert_eq(plan.issues[0].code, PlanIssue.Code.NO_PATH)
	assert_eq(plan.issues[0].severity(), PlanIssue.Severity.ERROR)
	assert_eq(plan.issues[0].machine_id, -1)
	assert_eq(plan.issues[0].text, "Connect the Basic Bullet to the Output.")
	# the Basic Bullet and the Output get a lamp status like any machine, but never an issue
	assert_eq(_statuses(plan, [1, 2]), [ShotPlan.MachineStatus.DEAD_END, ShotPlan.MachineStatus.IDLE])
	assert_true(plan.live_wire_keys.is_empty())
	assert_true(plan.wire_streams.is_empty())
	assert_eq(plan.summary_lines(), PackedStringArray(["NO PATH: connect the Basic Bullet to the Output"]))
	# the ERROR sorts first; the readout lists only the others
	var d: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])
	assert_eq(d.disconnect_wire(Wire.make(3, 0, FactoryGraph.OUTPUT_ID, 0)), GraphError.Code.OK)
	var dead: ShotPlan = FactoryCompiler.compile(d)
	assert_eq(dead.issues.size(), 2)
	assert_eq(dead.issues[0].code, PlanIssue.Code.NO_PATH)
	assert_eq(dead.issues[1].code, PlanIssue.Code.DEAD_END)
	assert_eq(dead.summary_lines(), PackedStringArray(["NO PATH: connect the Basic Bullet to the Output",
			"! Fire #3 is a dead end: its belt never reaches the Output."]))


func test_live_wire_keys_and_streams() -> void:
	var g: FactoryGraph = Fixtures.chain([MachineCatalog.FIRE])   # 1 -> 3 -> 2
	var ice: int = g.add_machine(MachineCatalog.ICE, Vector2i(6, 8))
	assert_eq(g.connect_ports(ice, 0, 3, 0), GraphError.Code.OK)  # an idle Ice into the live Fire: not a live belt
	var plan: ShotPlan = FactoryCompiler.compile(g)
	assert_eq(plan.live_wire_keys, {"1:0>3:0": true, "3:0>2:0": true})
	assert_true(plan.is_live_wire(Wire.make(1, 0, 3, 0)))
	assert_false(plan.is_live_wire(Wire.make(ice, 0, 3, 0)))
	assert_eq(plan.wire_streams.size(), 2)
	var into_fire: Array[BulletSpec] = plan.streams_on(Wire.make(1, 0, 3, 0))
	var after_fire: Array[BulletSpec] = plan.streams_on(Wire.make(3, 0, FactoryGraph.OUTPUT_ID, 0))
	assert_eq(into_fire.size(), 1)
	assert_eq(into_fire[0].fire_level, 0)
	assert_eq(after_fire.size(), 1)
	assert_eq(after_fire[0].fire_level, 1)                         # the belt after Fire carries fire_level 1
	assert_true(plan.streams_on(Wire.make(ice, 0, 3, 0)).is_empty())
	# one belt shows at most 4 distinct streams, the earliest bullets first
	var mix: ShotPlan = FactoryCompiler.compile(_three_way_mix())
	assert_eq(mix.bullets.size(), 8)
	assert_eq(_descs(mix).size(), 8)
	var last: Array[String] = _stream_texts(mix, "9:0>2:0")
	assert_eq(last, _descs(mix).slice(0, 4))
	for text: String in last:
		assert_string_contains(text, "FIRE I")
	assert_eq(_stream_texts(mix, "7:1>9:0").size(), 4)            # (F,I), (F), (I) and the plain stream
	assert_eq(_stream_texts(mix, "1:0>3:0").size(), 1)


func test_compile_is_deterministic() -> void:
	var g: FactoryGraph = _three_way_mix()
	g.add_machine(MachineCatalog.PIERCE, Vector2i(0, 10))         # an idle machine, so there is an issue too
	var before: Dictionary = g.to_dict()
	watch_signals(g)
	var first: Dictionary = _snapshot(FactoryCompiler.compile(g))
	assert_eq(_snapshot(FactoryCompiler.compile(g)), first)
	var copy: FactoryGraph = FactoryGraph.create_default()
	copy.assign_from(g)
	assert_eq(_snapshot(FactoryCompiler.compile(copy)), first)
	assert_eq(g.to_dict(), before)                                 # compiling never edits the graph
	assert_signal_emit_count(g, "changed", 0)
	assert_eq(first["bullets"].size(), 8)
	assert_eq(first["issues"], ["Pierce #10 is idle: no bullets reach it."])


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


## Three real splits in a row, each with a modifier on its upper branch only, all merging into
## Speed Up #9: 8 distinct bullets. Splitters #3, #5, #7; Fire #4, Ice #6, Poison #8.
func _three_way_mix() -> FactoryGraph:
	var g: FactoryGraph = FactoryGraph.create_default()
	var kinds: Array[StringName] = [MachineCatalog.SPLITTER, MachineCatalog.FIRE, MachineCatalog.SPLITTER,
			MachineCatalog.ICE, MachineCatalog.SPLITTER, MachineCatalog.POISON, MachineCatalog.SPEED_UP]
	var cells: Array[Vector2i] = [Vector2i(3, 5), Vector2i(3, 1), Vector2i(5, 5), Vector2i(5, 1), Vector2i(7, 5),
			Vector2i(7, 1), Vector2i(9, 5)]
	for i: int in kinds.size():
		assert_eq(g.add_machine(kinds[i], cells[i]), 3 + i)
	# [from, from port, to]: every belt goes into input port 0
	var belts: Array[Array] = [[1, 0, 3], [3, 0, 4], [3, 1, 5], [4, 0, 5], [5, 0, 6], [5, 1, 7], [6, 0, 7],
			[7, 0, 8], [7, 1, 9], [8, 0, 9], [9, 0, 2]]
	for b: Array in belts:
		assert_eq(g.connect_ports(b[0], b[1], b[2], 0), GraphError.Code.OK, str(b))
	return g


func _descs(plan: ShotPlan) -> Array[String]:
	var out: Array[String] = []
	for b: BulletSpec in plan.bullets:
		out.append(b.describe())
	return out


func _angles(plan: ShotPlan) -> PackedFloat64Array:
	var out: PackedFloat64Array = []
	for b: BulletSpec in plan.bullets:
		out.append(b.angle_offset)
	return out


func _assert_degrees(radians: PackedFloat64Array, degrees: Array[float]) -> void:
	assert_eq(radians.size(), degrees.size())
	for i: int in mini(radians.size(), degrees.size()):
		assert_almost_eq(rad_to_deg(radians[i]), degrees[i], 1e-4, "angle %d" % i)


func _statuses(plan: ShotPlan, ids: Array[int]) -> Array[ShotPlan.MachineStatus]:
	var out: Array[ShotPlan.MachineStatus] = []
	for id: int in ids:
		out.append(plan.status_of(id))
	return out


func _issue_texts(plan: ShotPlan) -> Array[String]:
	var out: Array[String] = []
	for issue: PlanIssue in plan.issues:
		out.append(issue.text)
	return out


func _stream_texts(plan: ShotPlan, key: String) -> Array[String]:
	var out: Array[String] = []
	var streams: Array = plan.wire_streams.get(key, [])
	for s: BulletSpec in streams:
		out.append(s.describe())
	return out


## Everything a compiled plan exposes, as plain comparable values.
func _snapshot(plan: ShotPlan) -> Dictionary:
	var streams: Dictionary[String, Array] = {}
	for key: String in plan.wire_streams:
		streams[key] = _stream_texts(plan, key)
	return {
		"bullets": _descs(plan),
		"angles": _angles(plan),
		"statuses": plan.statuses,
		"live": plan.live_wire_keys,
		"streams": streams,
		"issues": _issue_texts(plan),
	}

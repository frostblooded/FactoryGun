extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")


func test_empty_plan_invalid_with_no_path() -> void:
	var plan: ShotPlan = ShotPlan.empty()
	assert_false(plan.is_valid())
	assert_true(plan.has_issue(PlanIssue.Code.NO_PATH))
	assert_false(plan.has_issue(PlanIssue.Code.IDLE))
	assert_eq(plan.issues.size(), 1)
	assert_eq(plan.issues[0].severity(), PlanIssue.Severity.ERROR)
	assert_eq(plan.issues[0].machine_id, -1)
	assert_eq(plan.issues[0].text, "Connect the Basic Bullet to the Output.")
	assert_eq(plan.summary_lines(), PackedStringArray(["NO PATH: connect the Basic Bullet to the Output"]))
	assert_almost_eq(plan.damage_per_shot(), 0.0, 1e-4)
	assert_false(ShotPlan.new().is_valid())
	assert_false(ShotPlan.new().has_issue(PlanIssue.Code.NO_PATH))


func test_summary_lines_format() -> void:
	var one: ShotPlan = Fixtures.plan_of([BulletSpec.new()])
	assert_true(one.is_valid())
	assert_eq(one.summary_lines(), PackedStringArray([
		"1 bullet/shot · 4 shots/s · 10.0 dmg/shot",
		"#1 DMG 10.0 · SPD 600 · SIZE 5.0",
	]))
	# C.8: Source -> Fire -> Splitter; upper: Speed Up -> Output; lower: Pierce -> Output
	var two: ShotPlan = Fixtures.plan_of([
		BulletSpec.from_counts({MachineCatalog.FIRE: 1, MachineCatalog.SPEED_UP: 1}, 1),
		BulletSpec.from_counts({MachineCatalog.FIRE: 1, MachineCatalog.PIERCE: 1}, 1),
	])
	assert_almost_eq(two.damage_per_shot(), 14.7, 1e-4)
	assert_eq(two.summary_lines(), PackedStringArray([
		"2 bullets/shot · 4 shots/s · 14.7 dmg/shot",
		"#1 DMG 7.7 · SPD 810 · SIZE 5.0 · FIRE I",
		"#2 DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE I · PIERCE 1",
	]))


func test_issue_order_and_cap() -> void:
	var plan: ShotPlan = Fixtures.plan_of([BulletSpec.new()])
	plan.issues.append(PlanIssue.make(PlanIssue.Code.ONE_SIDED, 3, "one-sided 3"))
	plan.issues.append(PlanIssue.make(PlanIssue.Code.IDLE, 7, "idle 7"))
	plan.issues.append(PlanIssue.make(PlanIssue.Code.NO_PATH, -1, "no path"))   # ERROR: never listed or counted
	plan.issues.append(PlanIssue.make(PlanIssue.Code.CAPPED, 5, "capped 5"))
	plan.issues.append(PlanIssue.make(PlanIssue.Code.DEAD_END, 5, "dead end 5"))
	assert_eq(plan.summary_lines().slice(2), PackedStringArray(["! dead end 5", "! capped 5", "… 2 more"]))
	var sorted: Array[PlanIssue] = plan.issues.duplicate()
	sorted.sort_custom(PlanIssue.before)   # severity desc, then machine id, then code
	var texts: Array[String] = []
	for i: PlanIssue in sorted:
		texts.append(i.text)
	assert_eq(texts, ["no path", "dead end 5", "capped 5", "idle 7", "one-sided 3"])
	assert_eq(PlanIssue.make(PlanIssue.Code.ONE_SIDED, 3, "").severity(), PlanIssue.Severity.INFO)
	assert_eq(PlanIssue.make(PlanIssue.Code.CAPPED, 3, "").severity(), PlanIssue.Severity.WARNING)
	# 8 bullets and 5 non-ERROR issues: 1 + 8 + 2 + 1 = 12 lines, the readout's worst case
	var specs: Array[BulletSpec] = []
	for i: int in 8:
		specs.append(BulletSpec.new())
	var full: ShotPlan = Fixtures.plan_of(specs)
	for id: int in range(3, 8):
		full.issues.append(PlanIssue.make(PlanIssue.Code.IDLE, id, "idle %d" % id))
	var lines: PackedStringArray = full.summary_lines()
	assert_eq(lines.size(), 12)
	assert_eq(lines[0], "8 bullets/shot · 4 shots/s · 80.0 dmg/shot")
	assert_eq(lines[8], "#8 DMG 10.0 · SPD 600 · SIZE 5.0")
	assert_eq(lines[11], "… 3 more")
	full.issues.resize(2)
	assert_eq(full.summary_lines().size(), 11)   # exactly 2 issues: no "more" line


func test_streams_on_returns_typed_array() -> void:
	var plan: ShotPlan = ShotPlan.new()
	var spec: BulletSpec = BulletSpec.from_counts({MachineCatalog.FIRE: 1}, 0)
	plan.wire_streams["1:0>2:0"] = [spec]
	plan.live_wire_keys["1:0>2:0"] = true
	var streams: Array[BulletSpec] = plan.streams_on(Wire.make(1, 0, 2, 0))
	assert_true(streams.is_typed())
	assert_same(streams.get_typed_script(), BulletSpec)
	assert_eq(streams.size(), 1)
	assert_same(streams[0], spec)
	streams.clear()
	assert_eq(plan.wire_streams["1:0>2:0"].size(), 1)   # a copy
	var none: Array[BulletSpec] = plan.streams_on(Wire.make(3, 0, 2, 0))
	assert_true(none.is_empty())
	assert_true(none.is_typed())
	assert_true(plan.is_live_wire(Wire.make(1, 0, 2, 0)))
	assert_false(plan.is_live_wire(Wire.make(3, 0, 2, 0)))
	plan.statuses[3] = ShotPlan.MachineStatus.CAPPED
	assert_eq(plan.status_of(3), ShotPlan.MachineStatus.CAPPED)
	assert_eq(plan.status_of(4), ShotPlan.MachineStatus.IDLE)

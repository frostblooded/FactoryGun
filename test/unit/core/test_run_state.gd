extends GutTest

const START_COUNTS: Dictionary = {"fire": 1, "speed_up": 1}   # Inventory.to_dict() of Tuning.START_INVENTORY
const DEFAULT_HEADLINE: String = "1 bullet/shot · 4 shots/s · 10.0 dmg/shot"
const PLAIN: String = "DMG 10.0 · SPD 600 · SIZE 5.0"
const FIRED: String = PLAIN + " · FIRE I"

var _probe_run: RunState = null
var _seen: Array[String] = []


func test_initial_state() -> void:
	var run: RunState = RunState.new(42)
	assert_eq(run.run_seed, 42)
	assert_eq(run.graph.to_dict(), FactoryGraph.create_default().to_dict())
	assert_eq(run.inventory.to_dict(), START_COUNTS)
	assert_eq(run.inventory.kinds_ever_owned(), [MachineCatalog.FIRE, MachineCatalog.SPEED_UP])
	assert_eq(run.flow.state, GameFlow.State.BUILD)
	assert_eq(run.flow.wave, 1)
	assert_eq(run.plan.summary_lines()[0], DEFAULT_HEADLINE)
	assert_false(run.active_plan.is_valid())
	assert_true(run.active_plan.has_issue(PlanIssue.Code.NO_PATH))
	assert_eq(run.player_hp, Tuning.PLAYER_MAX_HP)
	assert_eq(run.total_kills, 0)
	assert_true(run.offers.is_empty())
	assert_true(run.can_start_wave())
	assert_eq(run.start_reason(), "")
	assert_eq(run.owned(MachineCatalog.FIRE), 1)
	assert_eq(run.owned(MachineCatalog.SPEED_UP), 1)
	assert_eq(run.owned(MachineCatalog.SPLITTER), 0)
	assert_eq(run.owned(MachineCatalog.SOURCE), 1)                 # on the floor
	assert_eq(RunState.new().run_seed, 0)


func test_place_consumes_remove_refunds() -> void:
	var run: RunState = RunState.new(1)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1)), GraphError.Code.OK)
	assert_eq(run.graph.kind_of(3), MachineCatalog.FIRE)
	assert_eq(run.inventory.count(MachineCatalog.FIRE), 0)
	assert_eq(run.owned(MachineCatalog.FIRE), 1)
	assert_eq(run.try_connect(FactoryGraph.SOURCE_ID, 0, 3, 0), GraphError.Code.OK)
	assert_eq(run.try_connect(3, 0, FactoryGraph.OUTPUT_ID, 0), GraphError.Code.OK)
	assert_eq(run.plan.bullets[0].fire_level, 1)
	assert_eq(run.try_move_machine(3, Vector2i(5, 8)), GraphError.Code.OK)
	assert_eq(run.graph.get_machine(3).cell, Vector2i(5, 8))
	assert_eq(run.try_remove_machine(3), GraphError.Code.OK)
	assert_false(run.graph.has_machine(3))
	assert_eq(run.inventory.count(MachineCatalog.FIRE), 1)
	assert_eq(run.owned(MachineCatalog.FIRE), 1)
	assert_eq(_keys(run.graph), ["1:0>2:0"])                         # the remove healed the chain
	assert_eq(run.try_remove_machine(FactoryGraph.SOURCE_ID), GraphError.Code.NOT_REMOVABLE)
	assert_eq(run.try_remove_machine(3), GraphError.Code.NO_SUCH_MACHINE)
	assert_eq(run.inventory.to_dict(), START_COUNTS)                 # refused removes refund nothing
	assert_eq(run.owned(MachineCatalog.SOURCE), 1)
	_assert_consistent(run)


func test_out_of_stock() -> void:
	var run: RunState = RunState.new(1)
	var before: Dictionary = run.graph.to_dict()
	assert_eq(run.try_place_machine(MachineCatalog.ICE, Vector2i(5, 1)), GraphError.Code.OUT_OF_STOCK)
	assert_eq(run.try_place_machine(MachineCatalog.ICE, Vector2i(99, 99)), GraphError.Code.OUT_OF_STOCK)   # first
	assert_eq(run.try_place_machine(MachineCatalog.SPLITTER, Vector2i(5, 1), Wire.make(1, 0, 2, 0)),
			GraphError.Code.OUT_OF_STOCK)
	assert_eq(run.try_place_machine(&"laser", Vector2i(5, 1)), GraphError.Code.UNKNOWN_KIND)   # never "out of stock"
	assert_eq(run.try_place_machine(MachineCatalog.SOURCE, Vector2i(5, 1)), GraphError.Code.NOT_PLACEABLE)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(13, 0)), GraphError.Code.OUT_OF_BOUNDS)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(1, 5)), GraphError.Code.CELL_OCCUPIED)
	assert_eq(run.graph.to_dict(), before)
	assert_eq(run.inventory.to_dict(), START_COUNTS)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1)), GraphError.Code.OK)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(8, 1)), GraphError.Code.OUT_OF_STOCK)   # the only one
	assert_eq(run.graph.count_kind(MachineCatalog.FIRE), 1)
	_assert_consistent(run)


func test_place_with_splice() -> void:
	var run: RunState = RunState.new(1)
	var belt: Wire = Wire.make(FactoryGraph.SOURCE_ID, 0, FactoryGraph.OUTPUT_ID, 0)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(13, 0), belt), GraphError.Code.OUT_OF_BOUNDS)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1), Wire.make(1, 0, 9, 0)),
			GraphError.Code.NO_SUCH_WIRE)
	assert_eq(run.inventory.to_dict(), START_COUNTS)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1), belt), GraphError.Code.OK)
	assert_eq(_keys(run.graph), ["1:0>3:0", "3:0>2:0"])
	assert_eq(run.inventory.count(MachineCatalog.FIRE), 0)
	assert_eq(run.try_place_machine(MachineCatalog.SPEED_UP, Vector2i(8, 1), run.graph.wire_from(3, 0)),
			GraphError.Code.OK)
	assert_eq(_keys(run.graph), ["1:0>3:0", "3:0>4:0", "4:0>2:0"])
	assert_eq(run.plan.bullets[0].describe(), "DMG 11.0 · SPD 810 · SIZE 5.0 · FIRE I")
	assert_eq(run.inventory.to_dict(), {})
	assert_eq(run.owned(MachineCatalog.SPEED_UP), 1)
	_assert_consistent(run)


func test_edits_locked_outside_build() -> void:
	var run: RunState = RunState.new(1)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1)), GraphError.Code.OK)   # Fire #3, unwired
	assert_true(run.start_wave())
	_assert_locked(run, "PLAY")
	assert_true(run.complete_wave(70.0, 5))
	_assert_locked(run, "REWARD")
	assert_true(run.choose_offer(0))
	assert_true(run.start_wave())
	assert_true(run.fail_wave(2))
	_assert_locked(run, "GAME_OVER")


func test_plan_changed_after_each_edit() -> void:
	var run: RunState = RunState.new(1)
	watch_signals(run)
	var plans: Array[ShotPlan] = [run.plan]
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1)), GraphError.Code.OK)
	_assert_new_plan(run, plans)
	assert_eq(run.try_connect(FactoryGraph.SOURCE_ID, 0, 3, 0), GraphError.Code.OK)   # replaces the default belt
	_assert_new_plan(run, plans)
	assert_false(run.plan.is_valid())
	assert_eq(run.try_connect(3, 0, FactoryGraph.OUTPUT_ID, 0), GraphError.Code.OK)
	_assert_new_plan(run, plans)
	assert_eq(run.plan.bullets[0].fire_level, 1)
	assert_eq(run.try_move_machine(3, Vector2i(5, 8)), GraphError.Code.OK)
	_assert_new_plan(run, plans)
	assert_eq(run.try_disconnect(Wire.make(3, 0, FactoryGraph.OUTPUT_ID, 0)), GraphError.Code.OK)
	_assert_new_plan(run, plans)
	assert_eq(run.try_remove_machine(3), GraphError.Code.OK)                          # a dead end: nothing to heal
	_assert_new_plan(run, plans)
	assert_false(run.plan.is_valid())
	assert_eq(run.try_connect(FactoryGraph.SOURCE_ID, 0, FactoryGraph.OUTPUT_ID, 0), GraphError.Code.OK)
	_assert_new_plan(run, plans)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1), Wire.make(1, 0, 2, 0)), GraphError.Code.OK)
	_assert_new_plan(run, plans)                                                      # a splice is one edit
	assert_signal_emit_count(run, "plan_changed", 8)
	# refusals and a move onto its own cell compile nothing
	assert_eq(run.try_place_machine(MachineCatalog.ICE, Vector2i(8, 1)), GraphError.Code.OUT_OF_STOCK)
	assert_eq(run.try_connect(4, 0, 4, 0), GraphError.Code.SELF_LOOP)
	assert_eq(run.try_move_machine(4, Vector2i(5, 1)), GraphError.Code.OK)
	assert_eq(run.try_remove_machine(FactoryGraph.SOURCE_ID), GraphError.Code.NOT_REMOVABLE)
	assert_eq(run.try_disconnect(Wire.make(4, 0, 4, 0)), GraphError.Code.NO_SUCH_WIRE)
	assert_signal_emit_count(run, "plan_changed", 8)
	assert_same(run.plan, plans[-1])


func test_start_wave_requires_path_and_reason_text() -> void:
	var run: RunState = RunState.new(1)
	watch_signals(run.flow)
	assert_eq(run.try_disconnect(Wire.make(1, 0, 2, 0)), GraphError.Code.OK)
	assert_false(run.can_start_wave())
	assert_eq(run.start_reason(), "Connect the Basic Bullet to the Output first.")
	assert_false(run.start_wave())
	assert_eq(run.flow.state, GameFlow.State.BUILD)
	assert_false(run.active_plan.is_valid())
	assert_signal_emit_count(run.flow, "state_changed", 0)
	assert_eq(run.try_connect(1, 0, 2, 0), GraphError.Code.OK)
	assert_true(run.can_start_wave())
	assert_eq(run.start_reason(), "")
	assert_true(run.start_wave())
	assert_eq(run.flow.state, GameFlow.State.PLAY)
	assert_signal_emit_count(run.flow, "state_changed", 1)
	assert_false(run.can_start_wave())                             # BUILD only
	assert_false(run.start_wave())
	assert_signal_emit_count(run.flow, "state_changed", 1)


func test_start_wave_freezes_active_plan() -> void:
	var run: RunState = RunState.new(1)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1), Wire.make(1, 0, 2, 0)), GraphError.Code.OK)
	var plan: ShotPlan = run.plan
	_probe(run)
	assert_true(run.start_wave())
	_unprobe(run)
	assert_same(run.active_plan, plan)
	assert_eq(_seen, ["PLAY | wave 1 | 0 offers | hp 100.0 | active " + FIRED + " | plan " + FIRED])   # set before the signal
	# the graph can still change underneath (a restart does); the frozen plan does not
	run.graph.assign_from(FactoryGraph.create_default())
	assert_eq(run.plan.bullets[0].fire_level, 0)
	assert_same(run.active_plan, plan)
	assert_eq(run.active_plan.bullets[0].fire_level, 1)


func test_complete_wave_offers_then_reward() -> void:
	var run: RunState = RunState.new(5)
	assert_false(run.complete_wave(50.0, 3))                       # BUILD
	assert_true(run.offers.is_empty())
	assert_eq(run.total_kills, 0)
	assert_true(run.start_wave())
	_probe(run)
	assert_true(run.complete_wave(64.5, 6))
	_unprobe(run)
	assert_eq(_seen, ["REWARD | wave 1 | 3 offers | hp 64.5 | active " + PLAIN + " | plan " + PLAIN])
	assert_eq(run.flow.state, GameFlow.State.REWARD)
	assert_eq(run.flow.wave, 1)
	assert_almost_eq(run.player_hp, 64.5, 1e-4)
	assert_eq(run.total_kills, 6)
	assert_eq(_labels(run.offers), _labels(RewardGenerator.generate(5, 1, run.inventory.kinds_ever_owned())))
	assert_eq(run.offers[-1].kind, MachineCatalog.SPLITTER)       # the first reward always offers one
	assert_false(run.complete_wave(10.0, 1))                       # not PLAY any more
	assert_false(run.fail_wave(1))
	assert_eq(run.total_kills, 6)
	assert_eq(run.flow.state, GameFlow.State.REWARD)


func test_choose_offer_adds_heals_capped_and_advances() -> void:
	var run: RunState = RunState.new(5)
	assert_false(run.choose_offer(0))                              # BUILD
	assert_true(run.start_wave())
	assert_true(run.complete_wave(50.0, 3))
	var shown: Array[RewardOffer] = run.offers                     # what an overlay keeps
	var offer: RewardOffer = run.offers[0]
	var owned_before: int = run.owned(offer.kind)
	assert_false(run.choose_offer(-1))
	assert_false(run.choose_offer(3))
	assert_eq(run.flow.state, GameFlow.State.REWARD)
	assert_almost_eq(run.player_hp, 50.0, 1e-4)
	assert_true(run.choose_offer(0))
	assert_eq(run.owned(offer.kind), owned_before + offer.amount)
	assert_true(run.inventory.ever_owned(offer.kind))
	assert_almost_eq(run.player_hp, 75.0, 1e-4)
	assert_true(run.offers.is_empty())
	assert_eq(shown.size(), 3)                                     # replaced, not cleared in place
	assert_eq(run.flow.state, GameFlow.State.BUILD)
	assert_eq(run.flow.wave, 2)
	assert_false(run.choose_offer(0))
	# healing stops at full HP
	assert_true(run.start_wave())
	assert_true(run.complete_wave(90.0, 1))
	assert_true(run.choose_offer(2))
	assert_almost_eq(run.player_hp, Tuning.PLAYER_MAX_HP, 1e-4)
	assert_eq(run.flow.wave, 3)
	assert_eq(run.total_kills, 4)


func test_fail_wave_game_over() -> void:
	var run: RunState = RunState.new(5)
	assert_false(run.fail_wave(1))                                 # BUILD
	assert_true(run.start_wave())
	assert_true(run.complete_wave(80.0, 7))
	assert_true(run.choose_offer(1))
	assert_true(run.start_wave())
	_probe(run)
	assert_true(run.fail_wave(4))
	_unprobe(run)
	assert_eq(_seen, ["GAME_OVER | wave 2 | 0 offers | hp 0.0 | active " + PLAIN + " | plan " + PLAIN])
	assert_eq(run.flow.state, GameFlow.State.GAME_OVER)
	assert_eq(run.player_hp, 0.0)
	assert_eq(run.total_kills, 11)
	assert_true(run.offers.is_empty())
	assert_false(run.fail_wave(1))
	assert_false(run.complete_wave(50.0, 1))
	assert_false(run.choose_offer(0))
	assert_false(run.can_start_wave())
	assert_false(run.start_wave())
	assert_eq(run.total_kills, 11)
	assert_eq(run.flow.state, GameFlow.State.GAME_OVER)


func test_restart_resets_same_instances() -> void:
	var run: RunState = RunState.new(5)
	var ids: Array[int] = _instance_ids(run)
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1), Wire.make(1, 0, 2, 0)), GraphError.Code.OK)
	assert_true(run.start_wave())
	assert_true(run.complete_wave(40.0, 6))
	assert_true(run.choose_offer(0))
	assert_true(run.start_wave())
	assert_true(run.fail_wave(3))
	assert_eq(run.total_kills, 9)
	_probe(run)
	run.restart(77)
	_unprobe(run)
	assert_eq(_instance_ids(run), ids)                             # views bound to these never rebind
	assert_eq(_seen, ["BUILD | wave 1 | 0 offers | hp 100.0 | active - | plan " + PLAIN])   # all reset first
	assert_eq(run.run_seed, 77)
	assert_eq(run.player_hp, Tuning.PLAYER_MAX_HP)
	assert_eq(run.total_kills, 0)
	assert_true(run.offers.is_empty())
	assert_false(run.active_plan.is_valid())
	assert_eq(run.inventory.to_dict(), START_COUNTS)
	assert_eq(run.inventory.kinds_ever_owned(), [MachineCatalog.FIRE, MachineCatalog.SPEED_UP])
	assert_eq(run.graph.to_dict(), FactoryGraph.create_default().to_dict())
	assert_eq(run.plan.summary_lines(), PackedStringArray([DEFAULT_HEADLINE, "#1 " + PLAIN]))
	assert_eq(run.flow.state, GameFlow.State.BUILD)
	assert_eq(run.flow.wave, 1)
	assert_eq(run.wave_seed(), Seeds.derive(77, 1, Seeds.WAVE))
	assert_eq(run.try_place_machine(MachineCatalog.FIRE, Vector2i(5, 1)), GraphError.Code.OK)   # ids restart at 3
	assert_eq(run.graph.kind_of(3), MachineCatalog.FIRE)
	_assert_consistent(run)
	# no reference cycle: dropping the run frees it, its graph and its plan
	var refs: Array[WeakRef] = [weakref(run), weakref(run.graph), weakref(run.plan)]
	run = null
	for r: WeakRef in refs:
		assert_null(r.get_ref())


func test_wave_seed_differs_per_wave() -> void:
	var run: RunState = RunState.new(9)
	var first: int = run.wave_seed()
	assert_eq(first, Seeds.derive(9, 1, Seeds.WAVE))
	assert_true(run.start_wave())
	assert_eq(run.wave_seed(), first)                              # the arena gets the same seed while playing
	assert_true(run.complete_wave(80.0, 6))
	assert_true(run.choose_offer(1))
	assert_eq(run.flow.wave, 2)
	assert_ne(run.wave_seed(), first)
	assert_eq(run.wave_seed(), Seeds.derive(9, 2, Seeds.WAVE))
	assert_ne(RunState.new(10).wave_seed(), first)                 # another run
	assert_ne(first, Seeds.derive(9, 1, Seeds.REWARD))             # waves and rewards use separate seeds


func _assert_locked(run: RunState, label: String) -> void:
	var graph: Dictionary = run.graph.to_dict()
	var inventory: Dictionary = run.inventory.to_dict()
	var plan: ShotPlan = run.plan
	var locked: GraphError.Code = GraphError.Code.LOCKED
	assert_false(run.flow.is_editing_allowed(), label)
	assert_false(run.can_start_wave(), label)
	assert_eq(run.try_place_machine(MachineCatalog.SPEED_UP, Vector2i(8, 1)), locked, label)
	assert_eq(run.try_place_machine(MachineCatalog.POISON, Vector2i(99, 99)), locked, label)   # LOCKED comes first
	assert_eq(run.try_place_machine(MachineCatalog.SPEED_UP, Vector2i(8, 1), Wire.make(1, 0, 2, 0)), locked, label)
	assert_eq(run.try_move_machine(3, Vector2i(5, 8)), locked, label)
	assert_eq(run.try_remove_machine(3), locked, label)
	assert_eq(run.try_connect(3, 0, FactoryGraph.OUTPUT_ID, 0), locked, label)
	assert_eq(run.try_disconnect(Wire.make(1, 0, 2, 0)), locked, label)
	assert_eq(run.graph.to_dict(), graph, label)
	assert_eq(run.inventory.to_dict(), inventory, label)
	assert_same(run.plan, plan, label)


func _assert_new_plan(run: RunState, plans: Array[ShotPlan]) -> void:
	assert_signal_emit_count(run, "plan_changed", plans.size())
	assert_signal_emitted_with_parameters(run, "plan_changed", [run.plan])
	assert_false(plans.has(run.plan), "each edit compiles a new plan")
	plans.append(run.plan)
	_assert_consistent(run)


func _assert_consistent(run: RunState) -> void:
	var problems: PackedStringArray = run.graph.debug_check_invariants()
	assert_true(problems.is_empty(), "\n".join(problems))


func _keys(graph: FactoryGraph) -> Array[String]:
	var out: Array[String] = []
	for w: Wire in graph.wires():
		out.append(w.key())
	return out


func _labels(offers: Array[RewardOffer]) -> String:
	var out: PackedStringArray = []
	for o: RewardOffer in offers:
		out.append(o.label())
	return ", ".join(out)


func _instance_ids(run: RunState) -> Array[int]:
	return [run.graph.get_instance_id(), run.inventory.get_instance_id(), run.flow.get_instance_id()]


## Records what a state_changed listener sees of the run (by method: a lambda would capture the run).
func _probe(run: RunState) -> void:
	_probe_run = run
	_seen = []
	run.flow.state_changed.connect(_record_state)


func _unprobe(run: RunState) -> void:
	run.flow.state_changed.disconnect(_record_state)
	_probe_run = null


func _record_state(_previous: GameFlow.State, current: GameFlow.State) -> void:
	_seen.append("%s | wave %d | %d offers | hp %.1f | active %s | plan %s" % [GameFlow.State.keys()[current],
			_probe_run.flow.wave, _probe_run.offers.size(), _probe_run.player_hp, _shots(_probe_run.active_plan),
			_shots(_probe_run.plan)])


## The plan's bullets, or "-" when it has none.
func _shots(plan: ShotPlan) -> String:
	var out: PackedStringArray = []
	for b: BulletSpec in plan.bullets:
		out.append(b.describe())
	return " / ".join(out) if not out.is_empty() else "-"

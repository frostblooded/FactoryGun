extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")
const OPS_PER_SEED: int = 400

var _op: String = ""                      # what the last random edit tried, for failure messages


func test_random_edits_keep_invariants() -> void:
	var codes_seen: Dictionary[GraphError.Code, bool] = {}
	var most_bullets: int = 0
	for fuzz_seed: int in [11, 22, 33]:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = fuzz_seed
		var run: RunState = RunState.new(fuzz_seed)
		run.inventory.assign_from(Fixtures.inventory_all(3))
		run.inventory.add(MachineCatalog.SPLITTER, 12)
		# start forked, with two free Splitter outputs, so the edits soon reach multi-bullet shots
		run.graph.assign_from(Fixtures.split([MachineCatalog.SPLITTER, MachineCatalog.FIRE],
				[MachineCatalog.SPLITTER, MachineCatalog.ICE]))
		var owned: Dictionary[StringName, int] = _owned(run)
		for i: int in OPS_PER_SEED:
			var graph_before: Dictionary = run.graph.to_dict()
			var inventory_before: Dictionary = run.inventory.to_dict()
			var code: GraphError.Code = _random_edit(run, rng)
			var label: String = "seed %d, op %d: %s -> %s" % [fuzz_seed, i, _op, GraphError.Code.keys()[code]]
			var problems: PackedStringArray = run.graph.debug_check_invariants()
			assert_true(problems.is_empty(), label + "\n" + "\n".join(problems))
			# plain == below: GUT's assert_eq builds a deep diff of dictionaries even when they match
			assert_true(_owned(run) == owned, label + ": only rewards may change what the player owns")
			assert_eq(run.plan.bullets.size(), run.graph.count_live_paths(), label)
			assert_lte(run.plan.bullets.size(), Tuning.MAX_BULLETS_PER_SHOT, label)
			assert_true(run.plan.summary_lines() == FactoryCompiler.compile(run.graph).summary_lines(),
					label + ": the plan is stale")
			if code != GraphError.Code.OK:
				assert_true(run.graph.to_dict() == graph_before and run.inventory.to_dict() == inventory_before,
						label + ": a refused edit changed something")
			codes_seen[code] = true
			most_bullets = maxi(most_bullets, run.plan.bullets.size())
	# the edits really explored: every refusal a BUILD-phase edit can give, and a full 8-bullet shot
	for code: GraphError.Code in GraphError.Code.values():
		if code != GraphError.Code.LOCKED:
			assert_true(codes_seen.has(code), "never saw " + GraphError.Code.keys()[code])
	assert_eq(most_bullets, Tuning.MAX_BULLETS_PER_SHOT)


## One random try_* with random arguments, valid or not; sets _op. Almost half are growing edits, so
## the factory keeps reaching multi-bullet shots and the cap instead of decaying into loose machines.
func _random_edit(run: RunState, rng: RandomNumberGenerator) -> GraphError.Code:
	var graph: FactoryGraph = run.graph
	var cell: Vector2i = _random_cell(graph, rng)
	var a: int = _random_id(graph, rng)
	var b: int = _random_id(graph, rng)
	var roll: int = rng.randi_range(0, 19)
	if roll < 4:
		var kind: StringName = _random_kind(rng)
		var splice: Wire = _random_wire(run, rng) if rng.randf() < 0.5 else null
		_op = "place %s at %s%s" % [kind, cell, "" if splice == null else " onto " + splice.key()]
		return run.try_place_machine(kind, cell, splice)
	if roll < 6:
		_op = "move #%d to %s" % [a, cell]
		return run.try_move_machine(a, cell)
	if roll == 6:
		_op = "remove #%d" % a
		return run.try_remove_machine(a)
	if roll == 7:
		var w: Wire = _random_wire(run, rng)
		_op = "disconnect " + w.key()
		return run.try_disconnect(w)
	if roll < 11:
		var from_port: int = rng.randi_range(-1, 2)
		var to_port: int = rng.randi_range(-1, 1)
		if rng.randf() < 0.2:                      # the same belt again
			var again: Wire = _random_wire(run, rng)
			a = again.from_id
			from_port = again.from_port
			b = again.to_id
			to_port = again.to_port
		_op = "connect %d:%d>%d:%d" % [a, from_port, b, to_port]
		return run.try_connect(a, from_port, b, to_port)
	return _grow(run, rng, cell)


## Connects a free output of a fed machine into the live part, or, when there is none, splices a
## Splitter onto a belt (mostly a live one), which makes one.
func _grow(run: RunState, rng: RandomNumberGenerator, cell: Vector2i) -> GraphError.Code:
	var graph: FactoryGraph = run.graph
	var from: int = _pick(rng, graph.machine_ids(), func(id: int) -> bool:   # fed: reached from the Source
			return run.plan.status_of(id) != ShotPlan.MachineStatus.IDLE and _free_port(graph, id) != -1, -1)
	if from == -1:
		var w: Wire = _random_wire(run, rng)
		_op = "grow: place splitter at %s onto %s" % [cell, w.key()]
		return run.try_place_machine(MachineCatalog.SPLITTER, cell, w)
	var live: Dictionary[int, bool] = graph.live_ids()
	var to: int = _pick(rng, graph.machine_ids(), func(id: int) -> bool:
			return live.has(id) and id != FactoryGraph.SOURCE_ID, FactoryGraph.OUTPUT_ID)
	_op = "grow: connect %d:%d>%d:0" % [from, _free_port(graph, from), to]
	return run.try_connect(from, _free_port(graph, from), to, 0)


## Mostly a free spot on the floor, sometimes anywhere, even off the floor.
func _random_cell(graph: FactoryGraph, rng: RandomNumberGenerator) -> Vector2i:
	var free: Array[Vector2i] = []
	for x: int in Tuning.GRID_COLS - 1:
		for y: int in Tuning.GRID_ROWS - 1:
			if graph.is_area_free(Vector2i(x, y)):
				free.append(Vector2i(x, y))
	if free.is_empty() or rng.randf() < 0.2:
		return Vector2i(rng.randi_range(-2, Tuning.GRID_COLS), rng.randi_range(-2, Tuning.GRID_ROWS))
	return free[rng.randi_range(0, free.size() - 1)]


## Mostly a machine on the floor, sometimes an id that does not exist.
func _random_id(graph: FactoryGraph, rng: RandomNumberGenerator) -> int:
	var ids: PackedInt32Array = graph.machine_ids()
	if rng.randf() < 0.85:
		return ids[rng.randi_range(0, ids.size() - 1)]
	return rng.randi_range(-1, 60)


## Mostly a placeable kind (a Splitter a third of the time), sometimes a fixed or unknown one.
func _random_kind(rng: RandomNumberGenerator) -> StringName:
	var kinds: Array[StringName] = MachineCatalog.placeable_kinds()
	var roll: float = rng.randf()
	if roll < 0.15:
		kinds = [MachineCatalog.SOURCE, MachineCatalog.OUTPUT, &"laser"]
	elif roll < 0.45:
		kinds = [MachineCatalog.SPLITTER]
	return kinds[rng.randi_range(0, kinds.size() - 1)]


## Mostly a belt on the floor (a live one when there is one), sometimes one that does not exist.
func _random_wire(run: RunState, rng: RandomNumberGenerator) -> Wire:
	var wires: Array[Wire] = run.graph.wires()
	var live: Array[Wire] = wires.filter(func(w: Wire) -> bool: return run.plan.is_live_wire(w))
	if not live.is_empty() and rng.randf() < 0.6:
		return live[rng.randi_range(0, live.size() - 1)]
	if not wires.is_empty() and rng.randf() < 0.8:
		return wires[rng.randi_range(0, wires.size() - 1)]
	return Wire.make(_random_id(run.graph, rng), rng.randi_range(-1, 2), _random_id(run.graph, rng),
			rng.randi_range(-1, 1))


## A random id among those that pass keep, or fallback when none does.
func _pick(rng: RandomNumberGenerator, ids: PackedInt32Array, keep: Callable, fallback: int) -> int:
	var kept: Array[int] = []
	for id: int in ids:
		if keep.call(id):
			kept.append(id)
	return fallback if kept.is_empty() else kept[rng.randi_range(0, kept.size() - 1)]


## The first output port of id without a belt, or -1.
func _free_port(graph: FactoryGraph, id: int) -> int:
	for port: int in graph.def_of(id).output_ports:
		if graph.wire_from(id, port) == null:
			return port
	return -1


func _owned(run: RunState) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for kind: StringName in MachineCatalog.placeable_kinds() + [MachineCatalog.SOURCE, MachineCatalog.OUTPUT]:
		out[kind] = run.owned(kind)
	return out

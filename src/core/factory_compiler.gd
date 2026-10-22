class_name FactoryCompiler
extends RefCounted
## Turns the factory into the ShotPlan one trigger pull fires (docs/DESIGN.md C.6, C.7, D.2).

const MAX_STREAMS_PER_BELT: int = 4


static func compile(graph: FactoryGraph) -> ShotPlan:
	var plan: ShotPlan = ShotPlan.new()
	var live: Dictionary[int, bool] = graph.live_ids()
	for w: Wire in graph.wires():
		if live.has(w.from_id) and live.has(w.to_id):
			plan.live_wire_keys[w.key()] = true
	var paths: Array[PackedInt32Array] = []      # machine ids, Source .. Output
	var ports: Array[PackedInt32Array] = []      # output port taken at each step (size = path size - 1)
	if live.has(FactoryGraph.SOURCE_ID):
		_walk(graph, live, FactoryGraph.SOURCE_ID, PackedInt32Array([FactoryGraph.SOURCE_ID]),
				PackedInt32Array(), paths, ports)
	var angles: PackedFloat64Array = fan_angles(paths.size())
	var useful: Dictionary[int, bool] = {}       # modifier counted within its cap on some path
	var capped: Dictionary[int, bool] = {}       # modifier beyond its cap on some path
	for bi: int in paths.size():
		var counts: Dictionary[StringName, int] = {}
		var splits: int = 0
		for j: int in paths[bi].size():
			var id: int = paths[bi][j]
			var def: MachineDef = graph.def_of(id)
			if def.is_splitter():
				if is_real_split(graph, live, id):
					splits += 1
			elif def.is_modifier():
				var n: int = counts.get(def.kind, 0) + 1
				counts[def.kind] = n
				if n > def.max_stacks:
					capped[id] = true
				else:
					useful[id] = true
			if j < ports[bi].size():               # the belt leaving this machine carries the partial stream
				_add_stream(plan, graph.wire_from(id, ports[bi][j]).key(), BulletSpec.from_counts(counts, splits))
		var spec: BulletSpec = BulletSpec.from_counts(counts, splits)
		spec.angle_offset = angles[bi]
		plan.bullets.append(spec)
	for id: int in graph.machine_ids():
		plan.statuses[id] = _status(graph, live, id, useful, capped)
	_collect_issues(graph, plan)
	return plan


## Radians, increasing, so bullet 0 is the most counter-clockwise: a 10° step, narrowed to keep the span at 50°.
static func fan_angles(count: int) -> PackedFloat64Array:
	var angles: PackedFloat64Array = []
	var step: float = 0.0
	if count > 1:
		step = deg_to_rad(minf(Tuning.FAN_STEP_DEG, Tuning.FAN_MAX_DEG / (count - 1)))
	for i: int in count:
		angles.append((i - (count - 1) / 2.0) * step)   # 2.0: an int division would truncate
	return angles


## Both outputs feed live machines. Only a real split costs damage.
static func is_real_split(graph: FactoryGraph, live: Dictionary[int, bool], id: int) -> bool:
	var a: Wire = graph.wire_from(id, 0)
	var b: Wire = graph.wire_from(id, 1)
	return a != null and b != null and live.has(a.to_id) and live.has(b.to_id)


## Depth-first, output ports in ascending order, following only belts into live machines.
## Live machines all reach the Output and the graph is acyclic, so every branch ends in a path.
static func _walk(graph: FactoryGraph, live: Dictionary[int, bool], id: int, path: PackedInt32Array,
		path_ports: PackedInt32Array, paths: Array[PackedInt32Array], ports: Array[PackedInt32Array]) -> void:
	if id == FactoryGraph.OUTPUT_ID:
		paths.append(path)
		ports.append(path_ports)
		return
	for port: int in graph.def_of(id).output_ports:
		var w: Wire = graph.wire_from(id, port)
		if w == null or not live.has(w.to_id):
			continue
		var next_path: PackedInt32Array = path.duplicate()
		next_path.append(w.to_id)
		var next_ports: PackedInt32Array = path_ports.duplicate()
		next_ports.append(port)
		_walk(graph, live, w.to_id, next_path, next_ports, paths, ports)


## Keeps at most MAX_STREAMS_PER_BELT partial specs per belt, skipping one that looks the same.
static func _add_stream(plan: ShotPlan, key: String, spec: BulletSpec) -> void:
	var streams: Array = plan.wire_streams.get(key, [])
	if streams.size() >= MAX_STREAMS_PER_BELT:
		return
	for s: BulletSpec in streams:
		if s.describe() == spec.describe():
			return
	streams.append(spec)
	plan.wire_streams[key] = streams


## C.7, first match wins.
static func _status(graph: FactoryGraph, live: Dictionary[int, bool], id: int, useful: Dictionary[int, bool],
		capped: Dictionary[int, bool]) -> ShotPlan.MachineStatus:
	if not live.has(id):
		if graph.reaches(FactoryGraph.SOURCE_ID, id):
			return ShotPlan.MachineStatus.DEAD_END
		return ShotPlan.MachineStatus.IDLE
	if graph.def_of(id).is_splitter() and not is_real_split(graph, live, id):
		return ShotPlan.MachineStatus.ONE_SIDED
	if capped.has(id) and not useful.has(id):
		return ShotPlan.MachineStatus.CAPPED
	return ShotPlan.MachineStatus.ACTIVE


## C.7: NO_PATH without bullets, one issue per removable machine that is not ACTIVE; then sorted.
static func _collect_issues(graph: FactoryGraph, plan: ShotPlan) -> void:
	if plan.bullets.is_empty():
		plan.issues.append_array(ShotPlan.empty().issues)   # the NO_PATH issue, with its one text
	for id: int in graph.machine_ids():
		var def: MachineDef = graph.def_of(id)
		if not def.removable:
			continue
		match plan.statuses[id]:
			ShotPlan.MachineStatus.DEAD_END:
				plan.issues.append(PlanIssue.make(PlanIssue.Code.DEAD_END, id,
						"%s #%d is a dead end: its belt never reaches the Output." % [def.display_name, id]))
			ShotPlan.MachineStatus.IDLE:
				plan.issues.append(PlanIssue.make(PlanIssue.Code.IDLE, id,
						"%s #%d is idle: no bullets reach it." % [def.display_name, id]))
			ShotPlan.MachineStatus.ONE_SIDED:
				plan.issues.append(PlanIssue.make(PlanIssue.Code.ONE_SIDED, id,
						"Splitter #%d uses one output, so it does not split." % id))
			ShotPlan.MachineStatus.CAPPED:
				plan.issues.append(PlanIssue.make(PlanIssue.Code.CAPPED, id,
						"%s #%d adds nothing: %s is capped at %d per bullet." % [def.display_name, id,
						def.display_name, def.max_stacks]))
	plan.issues.sort_custom(PlanIssue.before)

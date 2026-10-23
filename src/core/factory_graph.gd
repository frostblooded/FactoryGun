class_name FactoryGraph
extends RefCounted
## The player's factory: machines on the grid and the belts between their ports. Pure rules.

signal changed                            # exactly once per successful mutation; never on a refusal

const SOURCE_ID: int = 1
const OUTPUT_ID: int = 2
const SOURCE_CELL: Vector2i = Vector2i(1, 5)
const OUTPUT_CELL: Vector2i = Vector2i(11, 5)

var _machines: Dictionary[int, MachineInstance] = {}
var _owner: Dictionary[Vector2i, int] = {}     # every covered cell -> machine id
var _wires: Array[Wire] = []                    # kept in canonical order (Wire.less)
var _next_id: int = 3                           # ids grow and are never reused within a graph's life


## Source + Output + belt 1:0>2:0.
static func create_default() -> FactoryGraph:
	var g: FactoryGraph = FactoryGraph.new()
	g._put(MachineInstance.make(SOURCE_ID, MachineCatalog.SOURCE, SOURCE_CELL))
	g._put(MachineInstance.make(OUTPUT_ID, MachineCatalog.OUTPUT, OUTPUT_CELL))
	g._wires.append(Wire.make(SOURCE_ID, 0, OUTPUT_ID, 0))
	return g


func has_machine(id: int) -> bool:
	return _machines.has(id)


## null if none; callers must not mutate it.
func get_machine(id: int) -> MachineInstance:
	return _machines.get(id)


func kind_of(id: int) -> StringName:
	return _machines[id].kind if _machines.has(id) else &""


func def_of(id: int) -> MachineDef:
	return MachineCatalog.get_def(_machines[id].kind) if _machines.has(id) else null


func machine_ids() -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array(_machines.keys())
	ids.sort()
	return ids


## -1 if no machine covers cell.
func machine_at(cell: Vector2i) -> int:
	return _owner.get(cell, -1)


## A 2x2 footprint at cell fits the floor.
func is_inside(cell: Vector2i) -> bool:
	return Rect2i(0, 0, Tuning.GRID_COLS, Tuning.GRID_ROWS).encloses(Rect2i(cell, MachineCatalog.FOOTPRINT))


## Inside and overlaps no machine other than ignore_id.
func is_area_free(cell: Vector2i, ignore_id: int = -1) -> bool:
	if not is_inside(cell):
		return false
	for c: Vector2i in _cells(cell):
		if machine_at(c) != -1 and machine_at(c) != ignore_id:
			return false
	return true


func count_kind(kind: StringName) -> int:
	var n: int = 0
	for m: MachineInstance in _machines.values():
		if m.kind == kind:
			n += 1
	return n


## A sorted copy (Wire.less); the Wire objects are shared.
func wires() -> Array[Wire]:
	return _wires.duplicate()


## The belt on that output port, or null.
func wire_from(id: int, port: int) -> Wire:
	for w: Wire in _wires:
		if w.from_id == id and w.from_port == port:
			return w
	return null


func wires_into(id: int) -> Array[Wire]:
	return _wires.filter(func(w: Wire) -> bool: return w.to_id == id)


func has_wire(w: Wire) -> bool:
	return w != null and _wires.any(func(x: Wire) -> bool: return x.same_as(w))


## A directed path exists; from_id == to_id is true.
func reaches(from_id: int, to_id: int) -> bool:
	return _closure(from_id, true, _wires).has(to_id)


## Machines on at least one Source -> Output path.
func live_ids() -> Dictionary[int, bool]:
	var fwd: Dictionary[int, bool] = _closure(SOURCE_ID, true, _wires)
	var bwd: Dictionary[int, bool] = _closure(OUTPUT_ID, false, _wires)
	var live: Dictionary[int, bool] = {}
	for id: int in fwd:
		if bwd.has(id):
			live[id] = true
	return live


func count_live_paths() -> int:
	var memo: Dictionary[int, int] = {}
	return _paths_from(SOURCE_ID, _wires, memo)


## The path count if (from_id, from_port) were connected to (to_id, to_port), replacing its belt.
func live_paths_if_connected(from_id: int, from_port: int, to_id: int, to_port: int) -> int:
	var trial: Array[Wire] = _wires.filter(func(w: Wire) -> bool:
			return w.from_id != from_id or w.from_port != from_port)
	trial.append(Wire.make(from_id, from_port, to_id, to_port))
	var memo: Dictionary[int, int] = {}
	return _paths_from(SOURCE_ID, trial, memo)


func can_add_machine(kind: StringName, cell: Vector2i) -> GraphError.Code:
	var code: GraphError.Code = _check_kind(kind)
	if code != GraphError.Code.OK:
		return code
	return _check_area(cell, -1)


func can_move_machine(id: int, cell: Vector2i) -> GraphError.Code:
	if not has_machine(id):
		return GraphError.Code.NO_SUCH_MACHINE
	return _check_area(cell, id)


func can_remove_machine(id: int) -> GraphError.Code:
	if not has_machine(id):
		return GraphError.Code.NO_SUCH_MACHINE
	if not def_of(id).removable:
		return GraphError.Code.NOT_REMOVABLE
	return GraphError.Code.OK


func can_connect(from_id: int, from_port: int, to_id: int, to_port: int) -> GraphError.Code:
	if not has_machine(from_id) or not has_machine(to_id):
		return GraphError.Code.NO_SUCH_MACHINE
	if from_port < 0 or from_port >= def_of(from_id).output_ports:
		return GraphError.Code.NO_SUCH_PORT
	if to_port < 0 or to_port >= def_of(to_id).input_ports:
		return GraphError.Code.NO_SUCH_PORT
	if from_id == to_id:
		return GraphError.Code.SELF_LOOP
	var old: Wire = wire_from(from_id, from_port)
	if old != null and old.to_id == to_id and old.to_port == to_port:
		return GraphError.Code.DUPLICATE_WIRE
	if reaches(to_id, from_id):
		return GraphError.Code.WOULD_CYCLE
	if live_paths_if_connected(from_id, from_port, to_id, to_port) > Tuning.MAX_BULLETS_PER_SHOT:
		return GraphError.Code.TOO_MANY_BULLETS
	return GraphError.Code.OK


func can_disconnect(w: Wire) -> GraphError.Code:
	return GraphError.Code.OK if has_wire(w) else GraphError.Code.NO_SUCH_WIRE


func can_splice(kind: StringName, cell: Vector2i, w: Wire) -> GraphError.Code:
	var code: GraphError.Code = _check_kind(kind)
	if code != GraphError.Code.OK:
		return code
	if not has_wire(w):
		return GraphError.Code.NO_SUCH_WIRE
	return _check_area(cell, -1)


## New id, or -1.
func add_machine(kind: StringName, cell: Vector2i) -> int:
	if can_add_machine(kind, cell) != GraphError.Code.OK:
		return -1
	var id: int = _new_machine(kind, cell)
	changed.emit()
	return id


## Belts follow the machine. Its own cell is OK with no signal.
func move_machine(id: int, cell: Vector2i) -> GraphError.Code:
	var code: GraphError.Code = can_move_machine(id, cell)
	if code != GraphError.Code.OK or _machines[id].cell == cell:
		return code
	var m: MachineInstance = _machines[id]
	_vacate(m)
	m.cell = cell
	_put(m)
	changed.emit()
	return GraphError.Code.OK


## Removes its belts, then heals A->X->B into A->B (C.5).
func remove_machine(id: int) -> GraphError.Code:
	var code: GraphError.Code = can_remove_machine(id)
	if code != GraphError.Code.OK:
		return code
	var ins: Array[Wire] = wires_into(id)
	var outs: Array[Wire] = _wires.filter(func(w: Wire) -> bool: return w.from_id == id)
	_wires = _wires.filter(func(w: Wire) -> bool: return w.from_id != id and w.to_id != id)
	if ins.size() == 1 and outs.size() == 1:
		_add_wire(Wire.make(ins[0].from_id, ins[0].from_port, outs[0].to_id, outs[0].to_port))
	_vacate(_machines[id])
	_machines.erase(id)
	changed.emit()
	return GraphError.Code.OK


## Replaces the belt already on (from_id, from_port), if any, in the same step.
func connect_ports(from_id: int, from_port: int, to_id: int, to_port: int) -> GraphError.Code:
	var code: GraphError.Code = can_connect(from_id, from_port, to_id, to_port)
	if code != GraphError.Code.OK:
		return code
	_wires = _wires.filter(func(w: Wire) -> bool: return w.from_id != from_id or w.from_port != from_port)
	_add_wire(Wire.make(from_id, from_port, to_id, to_port))
	changed.emit()
	return GraphError.Code.OK


## Matches by same_as().
func disconnect_wire(w: Wire) -> GraphError.Code:
	var code: GraphError.Code = can_disconnect(w)
	if code != GraphError.Code.OK:
		return code
	_wires = _wires.filter(func(x: Wire) -> bool: return not x.same_as(w))
	changed.emit()
	return GraphError.Code.OK


## Drops a new machine N onto belt A->B, which becomes A->N:0 and N:0->B. New id, or -1.
func splice_machine(kind: StringName, cell: Vector2i, w: Wire) -> int:
	if can_splice(kind, cell, w) != GraphError.Code.OK:
		return -1
	var id: int = _new_machine(kind, cell)
	_wires = _wires.filter(func(x: Wire) -> bool: return not x.same_as(w))
	_add_wire(Wire.make(w.from_id, w.from_port, id, 0))
	_add_wire(Wire.make(id, 0, w.to_id, w.to_port))
	changed.emit()
	return id


## Deep copy into this instance (ids included); emits changed once.
func assign_from(other: FactoryGraph) -> void:
	var machines: Array[MachineInstance] = other._machines.values()   # read first: other may be self
	_wires = other._wires.duplicate()            # Wires are immutable, so sharing them is safe
	_next_id = other._next_id
	_machines.clear()
	_owner.clear()
	for m: MachineInstance in machines:
		_put(MachineInstance.make(m.id, m.kind, m.cell))
	changed.emit()


## {"next_id", "machines": [{id, kind, cell: [x, y]}] by id, "wires": [keys] in canonical order}.
func to_dict() -> Dictionary:
	var machines: Array[Dictionary] = []
	for id: int in machine_ids():
		var m: MachineInstance = _machines[id]
		machines.append({"id": id, "kind": String(m.kind), "cell": [m.cell.x, m.cell.y]})
	var keys: Array[String] = []
	for w: Wire in _wires:
		keys.append(w.key())
	return {"next_id": _next_id, "machines": machines, "wires": keys}


## Empty when consistent (C.1 invariants).
func debug_check_invariants() -> PackedStringArray:
	var problems: PackedStringArray = []
	if kind_of(SOURCE_ID) != MachineCatalog.SOURCE or kind_of(OUTPUT_ID) != MachineCatalog.OUTPUT:
		problems.append("the Source or the Output is missing")
	var expected_owner: Dictionary[Vector2i, int] = {}
	for id: int in _machines:
		var m: MachineInstance = _machines[id]
		if not is_inside(m.cell):
			problems.append("machine %d at %s is outside the floor" % [id, m.cell])
		if id >= _next_id:
			problems.append("machine %d has an id >= next id %d" % [id, _next_id])
		for c: Vector2i in _cells(m.cell):
			if expected_owner.has(c):
				problems.append("machines %d and %d overlap at %s" % [expected_owner[c], id, c])
			expected_owner[c] = id
	if expected_owner != _owner:
		problems.append("the cell owner map does not match the footprints")
	var used_outputs: Dictionary[String, bool] = {}
	for w: Wire in _wires:
		var from_def: MachineDef = def_of(w.from_id)
		var to_def: MachineDef = def_of(w.to_id)
		if from_def == null or to_def == null or w.from_port < 0 or w.from_port >= from_def.output_ports \
				or w.to_port < 0 or w.to_port >= to_def.input_ports:
			problems.append("belt %s touches a missing machine or port" % w.key())
		var port: String = "%d:%d" % [w.from_id, w.from_port]
		if used_outputs.has(port):
			problems.append("output port %s carries two belts" % port)
		used_outputs[port] = true
		if reaches(w.to_id, w.from_id):
			problems.append("belt %s closes a cycle" % w.key())
	if count_live_paths() > Tuning.MAX_BULLETS_PER_SHOT:
		problems.append("%d paths exceed the bullet cap" % count_live_paths())
	return problems


static func _cells(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx: int in MachineCatalog.FOOTPRINT.x:
		for dy: int in MachineCatalog.FOOTPRINT.y:
			out.append(cell + Vector2i(dx, dy))
	return out


## Every id reachable from start, following belts forward or backward; start included.
static func _closure(start: int, forward: bool, wire_list: Array[Wire]) -> Dictionary[int, bool]:
	var seen: Dictionary[int, bool] = {start: true}
	var todo: Array[int] = [start]
	while not todo.is_empty():
		var id: int = todo.pop_back()
		for w: Wire in wire_list:
			var a: int = w.from_id if forward else w.to_id
			var b: int = w.to_id if forward else w.from_id
			if a == id and not seen.has(b):
				seen[b] = true
				todo.append(b)
	return seen


## Number of id -> Output paths: memoised DP over the DAG.
static func _paths_from(id: int, wire_list: Array[Wire], memo: Dictionary[int, int]) -> int:
	if id == OUTPUT_ID:
		return 1
	if memo.has(id):
		return memo[id]
	memo[id] = 0                          # guards against corrupt (cyclic) data
	var total: int = 0
	for w: Wire in wire_list:
		if w.from_id == id:
			total += _paths_from(w.to_id, wire_list, memo)
	memo[id] = total
	return total


func _check_kind(kind: StringName) -> GraphError.Code:
	var def: MachineDef = MachineCatalog.get_def(kind)
	if def == null:
		return GraphError.Code.UNKNOWN_KIND
	if not def.placeable:
		return GraphError.Code.NOT_PLACEABLE
	return GraphError.Code.OK


func _check_area(cell: Vector2i, ignore_id: int) -> GraphError.Code:
	if not is_inside(cell):
		return GraphError.Code.OUT_OF_BOUNDS
	if not is_area_free(cell, ignore_id):
		return GraphError.Code.CELL_OCCUPIED
	return GraphError.Code.OK


func _new_machine(kind: StringName, cell: Vector2i) -> int:
	var id: int = _next_id
	_next_id += 1
	_put(MachineInstance.make(id, kind, cell))
	return id


func _put(m: MachineInstance) -> void:
	_machines[m.id] = m
	for c: Vector2i in _cells(m.cell):
		_owner[c] = m.id


func _vacate(m: MachineInstance) -> void:
	for c: Vector2i in _cells(m.cell):
		_owner.erase(c)


func _add_wire(w: Wire) -> void:
	_wires.append(w)
	_wires.sort_custom(Wire.less)

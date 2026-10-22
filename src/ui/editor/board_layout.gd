class_name BoardLayout
extends RefCounted
## Board geometry in board-local pixels (docs/DESIGN.md E.3): cells, port anchors, belt routes, hit tests.

const TILE: float = 40.0
const MACHINE_SIZE: Vector2 = Vector2(80, 80)
const PORT_HIT: float = 12.0
const MAGNET: float = 24.0
const BELT_HIT: float = 8.0
const SPLICE: float = TILE / 2.0          # drop_cell puts the ports on any belt this close, so the drop splices into it
const DRAG_THRESHOLD: float = 6.0


static func bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(Tuning.GRID_COLS, Tuning.GRID_ROWS) * TILE)


static func machine_rect_at(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * TILE, MACHINE_SIZE)


static func machine_rect(graph: FactoryGraph, id: int) -> Rect2:
	return machine_rect_at(graph.get_machine(id).cell)


## The middle of the left edge.
static func input_anchor_at(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(0, 40)


## On the right edge: the middle for one output; y 20 and 60 for a Splitter's ports 0 and 1.
static func output_anchor_at(cell: Vector2i, port: int, port_count: int) -> Vector2:
	if port_count == 2:
		return Vector2(cell) * TILE + Vector2(80, 20 + 40 * port)
	return Vector2(cell) * TILE + Vector2(80, 40)


static func port_anchor(graph: FactoryGraph, ref: PortRef) -> Vector2:
	var cell: Vector2i = graph.get_machine(ref.machine_id).cell
	if ref.is_output:
		return output_anchor_at(cell, ref.port, graph.def_of(ref.machine_id).output_ports)
	return input_anchor_at(cell)


## Inputs first, then outputs in port order.
static func ports_of(graph: FactoryGraph, id: int) -> Array[PortRef]:
	var out: Array[PortRef] = []
	var def: MachineDef = graph.def_of(id)
	if def == null:
		return out
	for port: int in def.input_ports:
		out.append(PortRef.make(id, port, false))
	for port: int in def.output_ports:
		out.append(PortRef.make(id, port, true))
	return out


## The top-left cell of a machine centred near center, clamped so the 2x2 footprint stays on the floor.
static func drop_cell(center: Vector2) -> Vector2i:
	var cell: Vector2i = Vector2i((center / TILE - Vector2(1, 1)).round())
	return cell.clamp(Vector2i.ZERO, Vector2i(Tuning.GRID_COLS, Tuning.GRID_ROWS) - MachineCatalog.FOOTPRINT)


static func belt_points(graph: FactoryGraph, w: Wire) -> PackedVector2Array:
	var from_cell: Vector2i = graph.get_machine(w.from_id).cell
	var to_cell: Vector2i = graph.get_machine(w.to_id).cell
	var outputs: int = graph.def_of(w.from_id).output_ports
	return BeltRouter.route(output_anchor_at(from_cell, w.from_port, outputs), input_anchor_at(to_cell),
			machine_rect_at(from_cell), machine_rect_at(to_cell), BeltRouter.lane_offset(w.from_port, outputs), bounds())


## OUTSIDE > PORT > MACHINE > BELT > EMPTY, first match wins.
static func hit_test(graph: FactoryGraph, p: Vector2) -> BoardHit:
	if not bounds().has_point(p):
		return BoardHit.make(BoardHit.Type.OUTSIDE)
	var port: PortRef = _nearest_port(graph, p)
	if port != null:
		return BoardHit.make(BoardHit.Type.PORT, port.machine_id, port)
	var id: int = graph.machine_at(Vector2i((p / TILE).floor()))
	if id != -1:
		return BoardHit.make(BoardHit.Type.MACHINE, id)
	var w: Wire = belt_at(graph, p, BELT_HIT)
	if w != null:
		return BoardHit.make(BoardHit.Type.BELT, -1, null, w)
	return BoardHit.make(BoardHit.Type.EMPTY)


## The nearest belt within max_dist, or null. Ties go to the first belt in canonical order.
static func belt_at(graph: FactoryGraph, p: Vector2, max_dist: float) -> Wire:
	var best: Wire = null
	var best_d: float = INF
	for w: Wire in graph.wires():
		var d: float = BeltRouter.distance_to(belt_points(graph, w), p)
		if d <= max_dist and d < best_d:
			best = w
			best_d = d
	return best


## The nearest input port within max_dist on any machine but exclude_id, or null.
static func nearest_input(graph: FactoryGraph, p: Vector2, max_dist: float, exclude_id: int) -> PortRef:
	var best: PortRef = null
	var best_d: float = INF
	for id: int in graph.machine_ids():
		if id == exclude_id:
			continue
		for port: int in graph.def_of(id).input_ports:
			var d: float = p.distance_to(input_anchor_at(graph.get_machine(id).cell))
			if d <= max_dist and d < best_d:
				best = PortRef.make(id, port, false)
				best_d = d
	return best


## Side-by-side machines share an anchor: the left machine's output wins that tie (E.3 "Port ties").
static func _nearest_port(graph: FactoryGraph, p: Vector2) -> PortRef:
	var best: PortRef = null
	var best_d: float = INF
	for id: int in graph.machine_ids():
		for ref: PortRef in ports_of(graph, id):
			var d: float = p.distance_to(port_anchor(graph, ref))
			if d <= PORT_HIT and (d < best_d or (d == best_d and ref.is_output and not best.is_output)):
				best = ref
				best_d = d
	return best

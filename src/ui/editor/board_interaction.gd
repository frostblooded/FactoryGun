class_name BoardInteraction
extends RefCounted
## The board's pointer state machine (docs/DESIGN.md E.4). Takes board-local positions and returns
## BoardActions. It reads the graph and the inventory and never mutates them.

enum Mode { IDLE, PRESS_MACHINE, DRAG_MACHINE, DRAG_WIRE }

var mode: Mode = Mode.IDLE
var locked: bool = false
var graph: FactoryGraph = FactoryGraph.create_default()
var inventory: Inventory = Inventory.new()
var hover: BoardHit = BoardHit.new()
var cursor: Vector2 = Vector2.ZERO
var drag_id: int = -1
var drag_grab: Vector2 = Vector2.ZERO     # cursor minus the dragged machine's top-left, fixed at press
var wire_from: PortRef = null
var wire_target: PortRef = null           # magnet-snapped input port, or null
var wire_code: GraphError.Code = GraphError.Code.OK
var selected: Wire = null                 # the tapped belt the Cut button cuts, or null
var selected_at: Vector2 = Vector2.ZERO   # where it was tapped
var _press_at: Vector2 = Vector2.ZERO


func bind(p_graph: FactoryGraph, p_inventory: Inventory) -> void:
	graph = p_graph
	inventory = p_inventory
	cancel()


## true also cancels.
func set_locked(value: bool) -> void:
	locked = value
	if value:
		cancel()


func cancel() -> void:
	_end_gesture()
	selected = null
	refresh_hover()


func press(p: Vector2, button: MouseButton) -> BoardAction:
	cursor = p
	if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
		return BoardAction.none()
	if button == MOUSE_BUTTON_RIGHT and mode != Mode.IDLE:
		cancel()
		return BoardAction.none()
	if locked:
		return BoardAction.none(GraphError.describe(GraphError.Code.LOCKED))
	var hit: BoardHit = BoardLayout.hit_test(graph, p)
	if button == MOUSE_BUTTON_RIGHT:
		return secondary(hit)
	_end_gesture()
	selected = null                       # any left press drops the selection; a belt tap makes a new one
	_press_at = p
	if hit.type == BoardHit.Type.BELT:
		_select(hit.wire, p)
	elif hit.type == BoardHit.Type.PORT and hit.port.is_output:
		mode = Mode.DRAG_WIRE
		wire_from = hit.port
		_aim_wire()
	elif hit.type == BoardHit.Type.PORT or hit.type == BoardHit.Type.MACHINE:
		mode = Mode.PRESS_MACHINE
		drag_id = hit.machine_id
		drag_grab = p - BoardLayout.machine_rect(graph, drag_id).position
	return BoardAction.none()


func motion(p: Vector2) -> void:
	cursor = p
	match mode:
		Mode.IDLE:
			refresh_hover()
		Mode.PRESS_MACHINE:
			if p.distance_to(_press_at) > BoardLayout.DRAG_THRESHOLD:
				mode = Mode.DRAG_MACHINE
		Mode.DRAG_WIRE:
			_aim_wire()


## Left button only (the board ignores other releases).
func release(p: Vector2) -> BoardAction:
	cursor = p
	if mode == Mode.DRAG_WIRE:
		_aim_wire()
	var refusal: String = refusal_text()
	var action: BoardAction = BoardAction.none(refusal)
	if refusal == "" and mode == Mode.DRAG_MACHINE:
		action = BoardAction.make_remove(drag_id) if is_drag_outside() else BoardAction.make_move(drag_id, ghost_cell())
	elif refusal == "" and mode == Mode.DRAG_WIRE and wire_target != null:
		action = BoardAction.make_connect(wire_from, wire_target)
	elif mode == Mode.DRAG_WIRE and p.distance_to(_press_at) <= BoardLayout.DRAG_THRESHOLD:
		# A tap on an output port selects its belt: the only target of a zero-length belt (E.3).
		_select(graph.wire_from(wire_from.machine_id, wire_from.port), p)
	_end_gesture()
	return action


func refresh_hover() -> void:
	if mode == Mode.IDLE and BoardLayout.bounds().has_point(cursor):
		hover = BoardLayout.hit_test(graph, cursor)
	else:
		hover = BoardHit.new()


## The Cut button: DISCONNECT the selected belt, which stays selected only if the cut is refused.
func cut_selected() -> BoardAction:
	if selected == null:
		return BoardAction.none()
	if locked:
		return BoardAction.none(GraphError.describe(GraphError.Code.LOCKED))
	var action: BoardAction = BoardAction.make_disconnect(selected)
	selected = null
	return action


## After a graph change: forget a selected belt that no longer exists.
func drop_stale_selection() -> void:
	if selected != null and not graph.has_wire(selected):
		selected = null


## Right-click and Delete/X semantics: cut a belt, or remove a machine (refunded by RunState).
func secondary(hit: BoardHit) -> BoardAction:
	if hit.type == BoardHit.Type.EMPTY or hit.type == BoardHit.Type.OUTSIDE:
		return BoardAction.none()
	if locked:
		return BoardAction.none(GraphError.describe(GraphError.Code.LOCKED))
	if hit.type == BoardHit.Type.BELT:
		return BoardAction.make_disconnect(hit.wire)
	if hit.type == BoardHit.Type.PORT and hit.port.is_output:
		var w: Wire = graph.wire_from(hit.port.machine_id, hit.port.port)
		if w != null:
			return BoardAction.make_disconnect(w)
	return _remove(hit.machine_id)


## Where the dragged machine would land: the drop cell of its centre.
func ghost_cell() -> Vector2i:
	return BoardLayout.drop_cell(cursor - drag_grab + BoardLayout.MACHINE_SIZE / 2)


func ghost_valid() -> bool:
	return graph.can_move_machine(drag_id, ghost_cell()) == GraphError.Code.OK


func is_drag_outside() -> bool:
	return mode == Mode.DRAG_MACHINE and not BoardLayout.bounds().has_point(cursor)


func drop_preview(kind: StringName, p: Vector2) -> DropPreview:
	var cell: Vector2i = BoardLayout.drop_cell(p)
	var splice: Wire = null
	var code: GraphError.Code = GraphError.Code.OK
	if locked:
		code = GraphError.Code.LOCKED
	elif inventory.count(kind) == 0:
		code = GraphError.Code.OUT_OF_STOCK
	else:
		var w: Wire = BoardLayout.belt_at(graph, p, BoardLayout.SPLICE)
		if w != null and graph.can_splice(kind, cell, w) == GraphError.Code.OK:
			splice = w
		else:
			code = graph.can_add_machine(kind, cell)
	return DropPreview.make(kind, cell, code == GraphError.Code.OK, splice, GraphError.describe(code))


func drop(kind: StringName, p: Vector2) -> BoardAction:
	var preview: DropPreview = drop_preview(kind, p)
	if preview.valid:
		return BoardAction.make_place(kind, preview.cell, preview.splice)
	return BoardAction.none(preview.reason)


## Why releasing the running gesture here would be refused; "" if it would succeed or do nothing.
func refusal_text() -> String:
	if mode == Mode.DRAG_MACHINE:
		if is_drag_outside():
			return GraphError.describe(graph.can_remove_machine(drag_id))
		return GraphError.describe(graph.can_move_machine(drag_id, ghost_cell()))
	if mode == Mode.DRAG_WIRE and wire_target != null and wire_code != GraphError.Code.OK:
		var text: String = GraphError.describe(wire_code)
		if wire_code == GraphError.Code.TOO_MANY_BULLETS:
			text += " This belt would make %d." % graph.live_paths_if_connected(wire_from.machine_id,
					wire_from.port, wire_target.machine_id, wire_target.port)
		return text
	return ""


func _end_gesture() -> void:
	mode = Mode.IDLE
	drag_id = -1
	wire_from = null
	wire_target = null
	wire_code = GraphError.Code.OK


## w may be null (an output port with no belt).
func _select(w: Wire, p: Vector2) -> void:
	selected = w
	selected_at = p


func _aim_wire() -> void:
	wire_target = BoardLayout.nearest_input(graph, cursor, BoardLayout.MAGNET, wire_from.machine_id)
	wire_code = GraphError.Code.OK
	if wire_target != null:
		wire_code = graph.can_connect(wire_from.machine_id, wire_from.port, wire_target.machine_id, wire_target.port)


func _remove(id: int) -> BoardAction:
	var code: GraphError.Code = graph.can_remove_machine(id)
	return BoardAction.make_remove(id) if code == GraphError.Code.OK else BoardAction.none(GraphError.describe(code))

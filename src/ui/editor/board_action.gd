class_name BoardAction
extends RefCounted
## What a board gesture asks for. FactoryBoard turns it into a *_requested signal, or refused(refusal).
## The constructors use a make_ prefix because Object already has connect() and disconnect().

enum Type { NONE, PLACE, MOVE, REMOVE, CONNECT, DISCONNECT }

var type: Type = Type.NONE
var kind: StringName = &""
var machine_id: int = -1
var cell: Vector2i = Vector2i.ZERO
var splice: Wire = null
var from: PortRef = null
var to: PortRef = null
var wire: Wire = null
var refusal: String = ""                  # NONE only: why the gesture was refused; "" for a silent no-op


static func none(p_refusal: String = "") -> BoardAction:
	var a: BoardAction = BoardAction.new()
	a.refusal = p_refusal
	return a


## p_splice may be null (a plain placement).
static func make_place(p_kind: StringName, p_cell: Vector2i, p_splice: Wire) -> BoardAction:
	var a: BoardAction = BoardAction.new()
	a.type = Type.PLACE
	a.kind = p_kind
	a.cell = p_cell
	a.splice = p_splice
	return a


static func make_move(p_machine_id: int, p_cell: Vector2i) -> BoardAction:
	var a: BoardAction = BoardAction.new()
	a.type = Type.MOVE
	a.machine_id = p_machine_id
	a.cell = p_cell
	return a


static func make_remove(p_machine_id: int) -> BoardAction:
	var a: BoardAction = BoardAction.new()
	a.type = Type.REMOVE
	a.machine_id = p_machine_id
	return a


static func make_connect(p_from: PortRef, p_to: PortRef) -> BoardAction:
	var a: BoardAction = BoardAction.new()
	a.type = Type.CONNECT
	a.from = p_from
	a.to = p_to
	return a


static func make_disconnect(p_wire: Wire) -> BoardAction:
	var a: BoardAction = BoardAction.new()
	a.type = Type.DISCONNECT
	a.wire = p_wire
	return a

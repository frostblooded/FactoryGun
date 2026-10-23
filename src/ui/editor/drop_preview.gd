class_name DropPreview
extends RefCounted
## Where a palette drag over the board would land, and whether it may (BoardInteraction.drop_preview).

var kind: StringName = &""
var cell: Vector2i = Vector2i.ZERO
var valid: bool = false
var splice: Wire = null                   # the belt the drop splices into, or null
var reason: String = ""                   # the refusal text when not valid


static func make(p_kind: StringName, p_cell: Vector2i, p_valid: bool, p_splice: Wire, p_reason: String) -> DropPreview:
	var d: DropPreview = DropPreview.new()
	d.kind = p_kind
	d.cell = p_cell
	d.valid = p_valid
	d.splice = p_splice
	d.reason = p_reason
	return d

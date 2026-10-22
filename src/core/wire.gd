class_name Wire
extends RefCounted
## One belt: output port from_port of from_id feeds input port to_port of to_id. Immutable once made.

var from_id: int
var from_port: int
var to_id: int
var to_port: int


static func make(p_from_id: int, p_from_port: int, p_to_id: int, p_to_port: int) -> Wire:
	var w: Wire = Wire.new()
	w.from_id = p_from_id
	w.from_port = p_from_port
	w.to_id = p_to_id
	w.to_port = p_to_port
	return w


## Canonical order: from_id, from_port, to_id, to_port (arrays compare element by element).
static func less(a: Wire, b: Wire) -> bool:
	return [a.from_id, a.from_port, a.to_id, a.to_port] < [b.from_id, b.from_port, b.to_id, b.to_port]


func key() -> String:
	return "%d:%d>%d:%d" % [from_id, from_port, to_id, to_port]


func same_as(other: Wire) -> bool:
	return other != null and other.from_id == from_id and other.from_port == from_port \
			and other.to_id == to_id and other.to_port == to_port

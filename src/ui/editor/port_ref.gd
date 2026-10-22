class_name PortRef
extends RefCounted
## One port of one placed machine: an input (left edge) or an output (right edge).

var machine_id: int = -1
var port: int = 0
var is_output: bool = false


static func make(p_machine_id: int, p_port: int, p_is_output: bool) -> PortRef:
	var r: PortRef = PortRef.new()
	r.machine_id = p_machine_id
	r.port = p_port
	r.is_output = p_is_output
	return r


## Same three fields; false for null.
func equals(other: PortRef) -> bool:
	return other != null and other.machine_id == machine_id and other.port == port \
			and other.is_output == is_output

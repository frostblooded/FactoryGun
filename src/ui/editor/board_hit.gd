class_name BoardHit
extends RefCounted
## What lies under a board point (BoardLayout.hit_test). BoardHit.new() means "nothing hovered".

enum Type { EMPTY, PORT, MACHINE, BELT, OUTSIDE }

var type: Type = Type.EMPTY
var machine_id: int = -1                  # the machine hit, or the machine of the port hit
var port: PortRef = null
var wire: Wire = null


static func make(p_type: Type, p_machine_id: int = -1, p_port: PortRef = null, p_wire: Wire = null) -> BoardHit:
	var h: BoardHit = BoardHit.new()
	h.type = p_type
	h.machine_id = p_machine_id
	h.port = p_port
	h.wire = p_wire
	return h


func same_as(other: BoardHit) -> bool:
	return other != null and other.type == type and other.machine_id == machine_id \
			and (port.equals(other.port) if port != null else other.port == null) \
			and (wire.same_as(other.wire) if wire != null else other.wire == null)

class_name MachineInstance
extends RefCounted
## One placed machine. Mutated only by FactoryGraph.

var id: int
var kind: StringName
var cell: Vector2i                        # top-left tile of the 2x2 footprint


static func make(p_id: int, p_kind: StringName, p_cell: Vector2i) -> MachineInstance:
	var m: MachineInstance = MachineInstance.new()
	m.id = p_id
	m.kind = p_kind
	m.cell = p_cell
	return m


func footprint() -> Rect2i:
	return Rect2i(cell, MachineCatalog.FOOTPRINT)

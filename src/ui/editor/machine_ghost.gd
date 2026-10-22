class_name MachineGhost
extends Control
## The palette drag preview (docs/DESIGN.md E.6): the machine at alpha 0.7, centred on the cursor.

var kind: StringName = &""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	MachinePainter.draw_machine(self, kind, Rect2(-BoardLayout.MACHINE_SIZE / 2, BoardLayout.MACHINE_SIZE), -1,
			ShotPlan.MachineStatus.IDLE, 0.7, 0.0)


static func make(p_kind: StringName) -> MachineGhost:
	var g: MachineGhost = MachineGhost.new()
	g.kind = p_kind
	return g

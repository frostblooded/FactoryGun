class_name MachineDef
extends RefCounted
## Immutable description of one kind. Created only by MachineCatalog.

var kind: StringName
var display_name: String
var short_name: String
var description: String
var input_ports: int
var output_ports: int
var color: Color
var removable: bool
var placeable: bool
var max_stacks: int


func is_modifier() -> bool:
	return placeable and not is_splitter()


func is_splitter() -> bool:
	return kind == MachineCatalog.SPLITTER

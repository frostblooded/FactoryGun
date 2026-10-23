class_name MachineCatalog
extends RefCounted
## The nine machine kinds and their fixed stats (docs/DESIGN.md B.2).

const SOURCE: StringName = &"source"
const OUTPUT: StringName = &"output"
const FIRE: StringName = &"fire"
const ICE: StringName = &"ice"
const POISON: StringName = &"poison"
const SPEED_UP: StringName = &"speed_up"
const SIZE_UP: StringName = &"size_up"
const PIERCE: StringName = &"pierce"
const SPLITTER: StringName = &"splitter"
const FOOTPRINT: Vector2i = Vector2i(2, 2)
const PALETTE_ORDER: Array[StringName] = [FIRE, ICE, POISON, SPEED_UP, SIZE_UP, PIERCE, SPLITTER]

static var _defs: Dictionary[StringName, MachineDef] = {}   # built lazily on first get_def()


static func get_def(kind: StringName) -> MachineDef:
	if _defs.is_empty():
		_build()
	return _defs.get(kind)


static func has_kind(kind: StringName) -> bool:
	return get_def(kind) != null


static func placeable_kinds() -> Array[StringName]:
	return PALETTE_ORDER.duplicate()


static func palette_index(kind: StringName) -> int:
	return PALETTE_ORDER.find(kind)


static func _build() -> void:
	_add(SOURCE, "Basic Bullet", "BULLET", 0, 1, "d9b45a", 0,
			"Every shot starts here: one plain bullet (10 damage, 600 px/s).")
	_add(OUTPUT, "Output", "OUTPUT", 1, 0, "9aa3ad", 0,
			"The gun muzzle. Every bullet stream that reaches it is fired.")
	_add(FIRE, "Fire", "FIRE", 1, 1, "ff7a2f", 3,
			"Sets targets on fire: 6 damage/s per level for 3 s.")
	_add(ICE, "Ice", "ICE", 1, 1, "6fd8ff", 3,
			"Chills targets: -20% speed per level for 2 s.")
	_add(POISON, "Poison", "POISON", 1, 1, "8ee04f", 3,
			"Each hit adds 1 poison stack per level (1.5 damage/s each, 4 s, up to 15).")
	_add(SPEED_UP, "Speed Up", "SPEED", 1, 1, "ffe14d", 3,
			"Bullet speed ×1.35 and damage ×1.1 per level.")
	_add(SIZE_UP, "Size Up", "SIZE", 1, 1, "c08bff", 3,
			"Bullet size ×1.5 and damage ×1.25 per level, speed ×0.9.")
	_add(PIERCE, "Pierce", "PIERCE", 1, 1, "f0f0f0", 4,
			"The bullet passes through 1 more enemy per level.")
	_add(SPLITTER, "Splitter", "SPLIT", 1, 2, "ff9f3a", 0,
			"Forks the stream: each output fires its own bullets. ×0.7 damage when both outputs are used.")


static func _add(kind: StringName, display_name: String, short_name: String, input_ports: int,
		output_ports: int, color: String, max_stacks: int, description: String) -> void:
	var def: MachineDef = MachineDef.new()
	def.kind = kind
	def.display_name = display_name
	def.short_name = short_name
	def.description = description
	def.input_ports = input_ports
	def.output_ports = output_ports
	def.color = Color(color)
	def.removable = kind != SOURCE and kind != OUTPUT
	def.placeable = def.removable
	def.max_stacks = max_stacks
	_defs[kind] = def

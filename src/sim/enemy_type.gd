class_name EnemyType
extends RefCounted
## Base stats of one enemy kind (docs/DESIGN.md F.3). Shared instances; never mutated.

enum Kind { GRUNT, RUNNER, BRUTE }

static var _types: Dictionary[Kind, EnemyType] = {}   # built lazily on first get_type()

var kind: Kind
var display_name: String
var max_hp: float
var speed: float
var radius: float
var contact_damage: float
var sides: int
var color: Color


static func get_type(p_kind: Kind) -> EnemyType:
	if _types.is_empty():
		_add(Kind.GRUNT, "Grunt", 30.0, 70.0, 14.0, 10.0, 6, "b5502f")
		_add(Kind.RUNNER, "Runner", 16.0, 130.0, 10.0, 6.0, 3, "d9a33a")
		_add(Kind.BRUTE, "Brute", 150.0, 42.0, 24.0, 22.0, 8, "7d4fb3")
	return _types[p_kind]


static func _add(p_kind: Kind, p_name: String, p_max_hp: float, p_speed: float, p_radius: float,
		p_contact_damage: float, p_sides: int, p_color: String) -> void:
	var t: EnemyType = EnemyType.new()
	t.kind = p_kind
	t.display_name = p_name
	t.max_hp = p_max_hp
	t.speed = p_speed
	t.radius = p_radius
	t.contact_damage = p_contact_damage
	t.sides = p_sides
	t.color = Color(p_color)
	_types[p_kind] = t

class_name EnemyState
extends RefCounted
## One enemy in the arena. max_hp and speed already include the wave scaling (F.3).

var id: int = 0
var type: EnemyType
var pos: Vector2 = Vector2.ZERO
var hp: float = 0.0
var max_hp: float = 0.0
var speed: float = 0.0
var status: StatusEffects = StatusEffects.new()


func radius() -> float:
	return type.radius

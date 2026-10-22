class_name PlayerState
extends RefCounted
## The player in the arena (F.2).

var pos: Vector2 = Vector2.ZERO
var hp: float = 0.0
var invuln: float = 0.0                   # seconds of contact invulnerability left
var aim_dir: Vector2 = Vector2.RIGHT

class_name PlayerIntent
extends RefCounted
## What the player wants for one step. aim is an arena-local target POINT, not a direction (F.2).

var move: Vector2 = Vector2.ZERO
var aim: Vector2 = Vector2.ZERO
var fire: bool = false


## move is limited to length 1, so diagonals are no faster.
static func make(p_move: Vector2, p_aim: Vector2, p_fire: bool) -> PlayerIntent:
	var i: PlayerIntent = PlayerIntent.new()
	i.move = p_move.limit_length(1.0)
	i.aim = p_aim
	i.fire = p_fire
	return i

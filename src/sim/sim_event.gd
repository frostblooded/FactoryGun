class_name SimEvent
extends RefCounted
## Something that happened during one ArenaWorld.step(). The view turns events into effects.
## HIT: colour = bullet primary colour, entity_id = enemy. KILL and PLAYER_HIT: colour = enemy colour,
## entity_id = enemy. SHOT: pos = muzzle.

enum Type { SHOT, HIT, KILL, PLAYER_HIT, WAVE_CLEARED, PLAYER_DIED }

var type: Type = Type.SHOT
var pos: Vector2 = Vector2.ZERO
var color: Color = Color.WHITE
var entity_id: int = -1


static func make(p_type: Type, p_pos: Vector2, p_color: Color = Color.WHITE, p_entity_id: int = -1) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.type = p_type
	e.pos = p_pos
	e.color = p_color
	e.entity_id = p_entity_id
	return e

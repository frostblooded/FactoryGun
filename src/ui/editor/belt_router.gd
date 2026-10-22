class_name BeltRouter
extends RefCounted
## Orthogonal belt routes between two port anchors, and arc-length helpers over them (docs/DESIGN.md E.3).

const STUB: float = 20.0
const LANE_STEP: float = 8.0


## a: the output anchor; b: the input anchor; the rects are the two machines; lane shifts the middle leg.
static func route(a: Vector2, b: Vector2, from_rect: Rect2, to_rect: Rect2, lane: float, bounds: Rect2) -> PackedVector2Array:
	if a.y == b.y and b.x >= a.x:
		return PackedVector2Array([a, b])
	if b.x - a.x >= 2.0 * STUB:           # Z route
		var mx: float = clampf(snappedf((a.x + b.x) / 2.0, STUB) + lane, a.x + STUB / 2.0, b.x - STUB / 2.0)
		return PackedVector2Array([a, Vector2(mx, a.y), Vector2(mx, b.y), b])
	var lane_y: float                     # around: through the vertical gap, or below both machines
	if from_rect.end.y <= to_rect.position.y:
		lane_y = (from_rect.end.y + to_rect.position.y) / 2.0
	elif to_rect.end.y <= from_rect.position.y:
		lane_y = (to_rect.end.y + from_rect.position.y) / 2.0
	else:
		lane_y = minf(maxf(from_rect.end.y, to_rect.end.y) + STUB, bounds.end.y - 6.0)
	lane_y += lane
	var x1: float = a.x + STUB
	var x2: float = b.x - STUB
	return PackedVector2Array([a, Vector2(x1, a.y), Vector2(x1, lane_y), Vector2(x2, lane_y), Vector2(x2, b.y), b])


## -4 and +4 for a Splitter's two ports, 0 for a single output.
static func lane_offset(from_port: int, port_count: int) -> float:
	return (float(from_port) - (port_count - 1) / 2.0) * LANE_STEP


static func length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


## INF for fewer than 2 points.
static func distance_to(points: PackedVector2Array, p: Vector2) -> float:
	var best: float = INF
	for i: int in range(points.size() - 1):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])))
	return best


## [position, unit direction] at arc length d, clamped to the route. A zero-length route points right.
static func sample(points: PackedVector2Array, d: float) -> Array[Vector2]:
	var left: float = maxf(d, 0.0)
	var dir: Vector2 = Vector2.RIGHT
	for i: int in range(points.size() - 1):
		var seg: float = points[i].distance_to(points[i + 1])
		if seg <= 0.0:
			continue
		dir = (points[i + 1] - points[i]) / seg
		if left <= seg:
			return [points[i] + dir * left, dir]
		left -= seg
	return [points[points.size() - 1] if not points.is_empty() else Vector2.ZERO, dir]

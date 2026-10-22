class_name CollisionMath
extends RefCounted
## Swept circle tests (docs/DESIGN.md D.4). Not Geometry2D.segment_intersects_circle: for a segment that
## starts inside the circle it returns the exit fraction, or -1 (L.1 #17).


## The fraction t in [0, 1] at which a point moving a -> b first comes within r of c:
## 0.0 if it starts inside, -1.0 if it never comes that close during the step.
static func first_contact(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var f: Vector2 = a - c
	var k: float = f.dot(f) - r * r            # |a + t(b - a) - c|^2 = r^2 is qa t^2 + qb t + k = 0
	if k <= 0.0:
		return 0.0
	var d: Vector2 = b - a
	var qa: float = d.dot(d)
	if qa == 0.0:
		return -1.0
	var qb: float = 2.0 * f.dot(d)
	var disc: float = qb * qb - 4.0 * qa * k
	if disc < 0.0:
		return -1.0
	var t: float = (-qb - sqrt(disc)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else -1.0

extends GutTest


func test_head_on_fraction() -> void:
	assert_almost_eq(CollisionMath.first_contact(Vector2(0, 0), Vector2(100, 0), Vector2(60, 0), 10.0), 0.5, 1e-4)
	assert_almost_eq(CollisionMath.first_contact(Vector2(0, 0), Vector2(0, 100), Vector2(0, 100), 10.0), 0.9, 1e-4)
	# a diagonal pass that grazes the circle: the contact is the smaller root
	var t: float = CollisionMath.first_contact(Vector2(0, 0), Vector2(100, 0), Vector2(50, 6), 10.0)
	assert_almost_eq(t, 0.42, 1e-4)
	assert_almost_eq(Vector2(t * 100.0, 0).distance_to(Vector2(50, 6)), 10.0, 1e-3)


func test_miss() -> void:
	assert_eq(CollisionMath.first_contact(Vector2(0, 0), Vector2(100, 0), Vector2(50, 20), 10.0), -1.0)
	assert_eq(CollisionMath.first_contact(Vector2(0, 0), Vector2(100, 0), Vector2(-50, 0), 10.0), -1.0)   # behind
	assert_eq(CollisionMath.first_contact(Vector2(0, 0), Vector2(100, 0), Vector2(150, 0), 10.0), -1.0)   # not reached yet


func test_start_inside_is_zero() -> void:
	assert_eq(CollisionMath.first_contact(Vector2(55, 0), Vector2(155, 0), Vector2(60, 0), 10.0), 0.0)
	# leaving the circle still counts as touching at the start (segment_intersects_circle would say exit)
	assert_eq(CollisionMath.first_contact(Vector2(60, 0), Vector2(-40, 0), Vector2(60, 0), 10.0), 0.0)


func test_fast_bullet_does_not_tunnel() -> void:
	# 1476 px/s (Speed Up III) at 60 steps/s still moves less than this; a small target in the middle is hit
	assert_almost_eq(CollisionMath.first_contact(Vector2(0, 0), Vector2(1000, 0), Vector2(500, 0), 5.0), 0.495, 1e-4)
	assert_gt(CollisionMath.first_contact(Vector2(0, 0), Vector2(1000, 0), Vector2(500, 4.9), 5.0), 0.0)


func test_zero_length_segment() -> void:
	assert_eq(CollisionMath.first_contact(Vector2(10, 10), Vector2(10, 10), Vector2(100, 100), 5.0), -1.0)
	assert_eq(CollisionMath.first_contact(Vector2(10, 10), Vector2(10, 10), Vector2(12, 10), 5.0), 0.0)

extends GutTest

const G: EnemyType.Kind = EnemyType.Kind.GRUNT
const R: EnemyType.Kind = EnemyType.Kind.RUNNER
const B: EnemyType.Kind = EnemyType.Kind.BRUTE


func test_counts_per_wave() -> void:
	var expected: Dictionary[int, Array] = {
		1: [6, 0, 0], 2: [8, 2, 0], 3: [10, 4, 0], 4: [12, 6, 1], 5: [14, 8, 1], 6: [16, 10, 2], 10: [24, 18, 4],
	}
	for wave: int in expected:
		var c: Dictionary[EnemyType.Kind, int] = WavePlan.counts(wave)
		assert_eq([c[G], c[R], c[B]], expected[wave], "wave %d" % wave)
	# the enemy table (F.3)
	var grunt: EnemyType = EnemyType.get_type(G)
	assert_eq([grunt.display_name, grunt.max_hp, grunt.speed, grunt.radius, grunt.contact_damage, grunt.sides],
			["Grunt", 30.0, 70.0, 14.0, 10.0, 6])
	assert_eq(grunt.color, Color("b5502f"))
	var runner: EnemyType = EnemyType.get_type(R)
	assert_eq([runner.display_name, runner.max_hp, runner.speed, runner.radius, runner.contact_damage, runner.sides],
			["Runner", 16.0, 130.0, 10.0, 6.0, 3])
	assert_eq(runner.color, Color("d9a33a"))
	var brute: EnemyType = EnemyType.get_type(B)
	assert_eq([brute.display_name, brute.max_hp, brute.speed, brute.radius, brute.contact_damage, brute.sides],
			["Brute", 150.0, 42.0, 24.0, 22.0, 8])
	assert_eq(brute.color, Color("7d4fb3"))
	assert_same(EnemyType.get_type(B), brute)   # cached
	assert_eq([grunt.kind, runner.kind, brute.kind], [G, R, B])


func test_order_is_seeded_shuffle_of_counts() -> void:
	for wave: int in [1, 4, 9]:
		var order: Array[EnemyType.Kind] = WavePlan.order(wave, _rng(wave))
		var c: Dictionary[EnemyType.Kind, int] = WavePlan.counts(wave)
		assert_eq(order.size(), c[G] + c[R] + c[B])
		for kind: EnemyType.Kind in c:
			assert_eq(order.count(kind), c[kind], "wave %d kind %d" % [wave, kind])
		assert_eq(order, WavePlan.order(wave, _rng(wave)), "same seed, same order")
		# Fisher-Yates over Kind order: i from n-1 down to 1, j = randi_range(0, i)
		var expected: Array[EnemyType.Kind] = []
		for kind: EnemyType.Kind in c:
			for i: int in c[kind]:
				expected.append(kind)
		var rng: RandomNumberGenerator = _rng(wave)
		for i: int in range(expected.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var swap: EnemyType.Kind = expected[i]
			expected[i] = expected[j]
			expected[j] = swap
		assert_eq(order, expected)
	var other: RandomNumberGenerator = RandomNumberGenerator.new()
	other.seed = Seeds.derive(2, 9, Seeds.WAVE)
	assert_ne(WavePlan.order(9, other), WavePlan.order(9, _rng(9)))


func test_scaling_functions() -> void:
	assert_almost_eq(SimTuning.hp_mult(1), 1.0, 1e-4)
	assert_almost_eq(SimTuning.hp_mult(5), 1.6, 1e-4)
	assert_almost_eq(SimTuning.speed_mult(1), 1.0, 1e-4)
	assert_almost_eq(SimTuning.speed_mult(5), 1.12, 1e-4)
	assert_almost_eq(SimTuning.speed_mult(14), 1.39, 1e-4)
	assert_almost_eq(SimTuning.speed_mult(30), 1.4, 1e-4)    # capped
	assert_almost_eq(SimTuning.spawn_interval(1), 1.0, 1e-4)
	assert_almost_eq(SimTuning.spawn_interval(5), 0.8, 1e-4)
	assert_almost_eq(SimTuning.spawn_interval(30), 0.3, 1e-4)  # floor
	assert_almost_eq(WavePlan.spawn_time(1, 0), 1.0, 1e-4)
	assert_almost_eq(WavePlan.spawn_time(1, 5), 6.0, 1e-4)
	assert_almost_eq(WavePlan.spawn_time(5, 3), 1.0 + 3.0 * 0.8, 1e-4)
	# spawned enemies carry the wave's scaling
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(5, ShotPlan.empty(), 1, 100.0)
	var id: int = world.spawn_enemy(B, Vector2(100, 100))
	var e: EnemyState = world.enemies[world.enemies.size() - 1]
	assert_eq(e.id, id)
	assert_almost_eq(e.max_hp, 240.0, 1e-4)
	assert_almost_eq(e.hp, 240.0, 1e-4)
	assert_almost_eq(e.speed, 47.04, 1e-4)
	assert_almost_eq(e.radius(), 24.0, 1e-4)


func _rng(wave: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Seeds.derive(1, wave, Seeds.WAVE)
	return rng

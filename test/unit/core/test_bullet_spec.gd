extends GutTest


func test_base_stats() -> void:
	for s: BulletSpec in [BulletSpec.new(), BulletSpec.from_counts({}, 0)]:
		assert_almost_eq(s.damage, 10.0, 1e-4)
		assert_almost_eq(s.speed, 600.0, 1e-4)
		assert_almost_eq(s.radius, 5.0, 1e-4)
		assert_almost_eq(s.lifetime, 1.4, 1e-4)
		assert_almost_eq(s.angle_offset, 0.0, 1e-4)
		assert_eq([s.pierce, s.fire_level, s.ice_level, s.poison_level, s.speed_level, s.size_level, s.real_splits],
				[0, 0, 0, 0, 0, 0, 0])
		assert_eq(s.describe(), "DMG 10.0 · SPD 600 · SIZE 5.0")


func test_from_counts_formulas() -> void:
	var s: BulletSpec = BulletSpec.from_counts({MachineCatalog.SPEED_UP: 2, MachineCatalog.SIZE_UP: 1}, 1)
	assert_almost_eq(s.damage, 10.5875, 1e-4)
	assert_almost_eq(s.speed, 984.15, 1e-4)
	assert_almost_eq(s.radius, 7.5, 1e-4)
	assert_almost_eq(s.lifetime, 1.4, 1e-4)
	assert_eq([s.speed_level, s.size_level, s.real_splits], [2, 1, 1])
	# C.8: Source -> Speed Up -> Size Up -> Fire -> Output
	var c8: BulletSpec = BulletSpec.from_counts(
			{MachineCatalog.SPEED_UP: 1, MachineCatalog.SIZE_UP: 1, MachineCatalog.FIRE: 1}, 0)
	assert_almost_eq(c8.damage, 13.75, 1e-4)
	assert_almost_eq(c8.speed, 729.0, 1e-4)
	assert_almost_eq(c8.radius, 7.5, 1e-4)
	assert_eq(c8.fire_level, 1)
	assert_almost_eq(BulletSpec.from_counts({}, 2).damage, 4.9, 1e-4)


func test_levels_clamped_to_caps() -> void:
	var s: BulletSpec = BulletSpec.from_counts({
		MachineCatalog.FIRE: 5, MachineCatalog.ICE: 4, MachineCatalog.POISON: 9, MachineCatalog.SPEED_UP: 7,
		MachineCatalog.SIZE_UP: 4, MachineCatalog.PIERCE: 6, MachineCatalog.SPLITTER: 2,
	}, 0)
	assert_eq([s.fire_level, s.ice_level, s.poison_level, s.speed_level, s.size_level, s.pierce], [3, 3, 3, 3, 3, 4])
	assert_eq(s.real_splits, 0)
	assert_almost_eq(s.damage, 10.0 * 1.331 * 1.953125, 1e-4)
	assert_almost_eq(s.speed, 600.0 * 2.460375 * 0.729, 1e-4)
	assert_almost_eq(s.radius, 16.875, 1e-4)


func test_effect_numbers() -> void:
	var none: BulletSpec = BulletSpec.new()
	assert_almost_eq(none.burn_dps(), 0.0, 1e-4)
	assert_almost_eq(none.slow_fraction(), 0.0, 1e-4)
	assert_eq(none.poison_stacks_per_hit(), 0)
	var s: BulletSpec = BulletSpec.from_counts(
			{MachineCatalog.FIRE: 2, MachineCatalog.ICE: 3, MachineCatalog.POISON: 2}, 0)
	assert_almost_eq(s.burn_dps(), 12.0, 1e-4)
	assert_almost_eq(s.slow_fraction(), 0.6, 1e-4)
	assert_eq(s.poison_stacks_per_hit(), 2)


func test_describe_format() -> void:
	assert_eq(BulletSpec.from_counts({MachineCatalog.FIRE: 1, MachineCatalog.PIERCE: 1}, 1).describe(),
			"DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE I · PIERCE 1")
	assert_eq(BulletSpec.from_counts({MachineCatalog.PIERCE: 4, MachineCatalog.POISON: 1, MachineCatalog.ICE: 2,
			MachineCatalog.FIRE: 3}, 0).describe(),
			"DMG 10.0 · SPD 600 · SIZE 5.0 · FIRE III · ICE II · POISON I · PIERCE 4")
	assert_eq(BulletSpec.from_counts({MachineCatalog.SPEED_UP: 2, MachineCatalog.SIZE_UP: 1}, 1).describe(),
			"DMG 10.6 · SPD 984 · SIZE 7.5")   # speed is rounded, not truncated
	assert_eq(BulletSpec.from_counts({MachineCatalog.SPEED_UP: 1}, 0).describe(), "DMG 11.0 · SPD 810 · SIZE 5.0")


func test_primary_color_priority() -> void:
	var order: Array[StringName] = [MachineCatalog.FIRE, MachineCatalog.POISON, MachineCatalog.ICE,
			MachineCatalog.PIERCE, MachineCatalog.SPEED_UP, MachineCatalog.SIZE_UP]
	var counts: Dictionary[StringName, int] = {}
	for kind: StringName in order:
		counts[kind] = 1
	for kind: StringName in order:
		assert_eq(BulletSpec.from_counts(counts, 0).primary_color(), MachineCatalog.get_def(kind).color, String(kind))
		counts.erase(kind)
	assert_eq(BulletSpec.from_counts(counts, 0).primary_color(), Color("d9b45a"))

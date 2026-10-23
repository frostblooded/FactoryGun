extends GutTest


func test_burn_total_is_exact() -> void:
	var s: StatusEffects = StatusEffects.new()
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.FIRE: 2}, 0))
	assert_true(s.is_burning())
	assert_almost_eq(s.burn_dps, 12.0, 1e-4)
	var total: float = 0.0
	for i: int in 300:                    # 5 s of 1/60 steps; the burn lasts 3 s
		total += s.tick(SimTuning.STEP)
	assert_almost_eq(total, 36.0, 1e-4)
	assert_false(s.is_burning())
	assert_almost_eq(s.burn_dps, 0.0, 1e-4)


func test_burn_refresh_keeps_strongest() -> void:
	var s: StatusEffects = StatusEffects.new()
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.FIRE: 2}, 0))
	s.tick(1.0)
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.FIRE: 1}, 0))
	assert_almost_eq(s.burn_dps, 12.0, 1e-4)  # the weaker hit refreshes the time, not the strength
	assert_almost_eq(s.burn_time, 3.0, 1e-4)
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.FIRE: 3}, 0))
	assert_almost_eq(s.burn_dps, 18.0, 1e-4)
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.ICE: 1}, 0))   # no fire level: burn untouched
	assert_almost_eq(s.burn_dps, 18.0, 1e-4)
	assert_almost_eq(s.tick(3.5), 54.0, 1e-4)
	assert_false(s.is_burning())
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.FIRE: 1}, 0))   # expired: the old strength is gone
	assert_almost_eq(s.burn_dps, 6.0, 1e-4)


func test_chill_slow_and_expiry() -> void:
	var s: StatusEffects = StatusEffects.new()
	assert_almost_eq(s.speed_multiplier(), 1.0, 1e-4)
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.ICE: 2}, 0))
	assert_true(s.is_chilled())
	assert_almost_eq(s.slow, 0.4, 1e-4)
	assert_almost_eq(s.speed_multiplier(), 0.6, 1e-4)
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.ICE: 1}, 0))
	assert_almost_eq(s.slow, 0.4, 1e-4)       # keeps the strongest
	assert_almost_eq(s.slow_time, 2.0, 1e-4)
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.ICE: 3}, 0))
	assert_almost_eq(s.speed_multiplier(), 0.4, 1e-4)   # max 60% slow
	assert_almost_eq(s.tick(1.9), 0.0, 1e-4)  # chill does no damage
	assert_true(s.is_chilled())
	s.tick(0.2)
	assert_false(s.is_chilled())
	assert_almost_eq(s.slow, 0.0, 1e-4)
	assert_almost_eq(s.speed_multiplier(), 1.0, 1e-4)


func test_poison_stacks_and_cap() -> void:
	var s: StatusEffects = StatusEffects.new()
	var hit: BulletSpec = BulletSpec.from_counts({MachineCatalog.POISON: 3}, 0)
	s.apply_hit(hit)
	assert_true(s.is_poisoned())
	assert_eq(s.poison_stacks, 3)
	for i: int in 4:
		s.apply_hit(hit)
	assert_eq(s.poison_stacks, 15)
	s.apply_hit(hit)
	assert_eq(s.poison_stacks, 15)            # capped
	assert_almost_eq(s.tick(1.0), 22.5, 1e-4)
	s.tick(3.0)
	assert_false(s.is_poisoned())
	assert_eq(s.poison_stacks, 0)
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.POISON: 1}, 0))
	assert_eq(s.poison_stacks, 1)             # stacks restart after expiry


func test_poison_refresh_all_stacks() -> void:
	var s: StatusEffects = StatusEffects.new()
	var hit: BulletSpec = BulletSpec.from_counts({MachineCatalog.POISON: 1}, 0)
	s.apply_hit(hit)
	var total: float = s.tick(3.0)
	s.apply_hit(hit)
	assert_eq(s.poison_stacks, 2)
	assert_almost_eq(s.poison_time, 4.0, 1e-4)   # the new hit refreshes the old stack too
	total += s.tick(3.9)
	assert_true(s.is_poisoned())
	total += s.tick(1.0)
	assert_false(s.is_poisoned())
	assert_almost_eq(total, 1.5 * 3.0 + 2.0 * 1.5 * 4.0, 1e-4)


func test_large_delta_is_exact() -> void:
	var s: StatusEffects = StatusEffects.new()
	s.apply_hit(BulletSpec.from_counts({MachineCatalog.FIRE: 2, MachineCatalog.ICE: 1, MachineCatalog.POISON: 2}, 0))
	assert_almost_eq(s.tick(10.0), 12.0 * 3.0 + 2.0 * 1.5 * 4.0, 1e-4)
	assert_false(s.is_burning() or s.is_chilled() or s.is_poisoned())
	assert_almost_eq(s.tick(10.0), 0.0, 1e-4)
	var stepped: StatusEffects = StatusEffects.new()
	stepped.apply_hit(BulletSpec.from_counts({MachineCatalog.FIRE: 2, MachineCatalog.POISON: 2}, 0))
	var total: float = 0.0
	for i: int in 7:                          # uneven steps give the same total
		total += stepped.tick(0.7)
	assert_almost_eq(total, 48.0, 1e-4)

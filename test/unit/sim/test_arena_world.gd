extends GutTest

const Bot = preload("res://test/helpers/bot.gd")
const Fixtures = preload("res://test/helpers/fixtures.gd")
const GRUNT: EnemyType.Kind = EnemyType.Kind.GRUNT
const BRUTE: EnemyType.Kind = EnemyType.Kind.BRUTE
const STEP: float = SimTuning.STEP
const CENTRE: Vector2 = Vector2(500, 450)
const AIM_RIGHT: Vector2 = Vector2(900, 450)
const FAR: Vector2 = Vector2(-5000, -5000)    # a parked enemy here is out of every bullet's reach
const NEAR: Vector2 = Vector2(1e-2, 1e-2)     # Vector2 tolerance: positions are 32-bit floats


func test_idle_world_does_not_step() -> void:
	var world: ArenaWorld = ArenaWorld.new()
	assert_false(world.is_running())
	assert_false(world.is_finished())
	assert_eq(world.player.pos, CENTRE)
	assert_almost_eq(world.player.hp, Tuning.PLAYER_MAX_HP, 1e-4)
	assert_eq(world.enemies_remaining(), 0)
	var frozen: int = world.state_hash()
	assert_true(world.step(STEP, PlayerIntent.make(Vector2.RIGHT, AIM_RIGHT, true)).is_empty())
	assert_eq(world.state_hash(), frozen)
	assert_eq(world.time, 0.0)
	# reset_idle after some play: idle again with nothing left over, but wave and plan kept
	world.begin_wave(2, Fixtures.plan_of([BulletSpec.new()]), 9, 80.0)
	_run(world, 90, PlayerIntent.make(Vector2.UP, AIM_RIGHT, true))
	world.spawn_enemy(GRUNT, FAR)
	assert_false(world.bullets.is_empty())
	assert_false(world.enemies.is_empty())
	world.reset_idle(60.0)
	assert_false(world.is_running())
	assert_false(world.is_finished())
	assert_eq(world.wave, 2)
	assert_true(world.plan.is_valid())
	assert_true(world.enemies.is_empty())
	assert_true(world.bullets.is_empty())
	assert_eq(world.enemies_remaining(), 0)
	assert_eq(world.kills, 0)
	assert_eq(world.time, 0.0)
	assert_eq(world.player.pos, CENTRE)
	assert_almost_eq(world.player.hp, 60.0, 1e-4)
	assert_eq(world.player.invuln, 0.0)
	assert_eq(world.player.aim_dir, Vector2.RIGHT)
	assert_true(world.step(STEP, PlayerIntent.make(Vector2.RIGHT, AIM_RIGHT, true)).is_empty())
	assert_eq(world.player.pos, CENTRE)


func test_player_moves_and_is_clamped() -> void:
	var world: ArenaWorld = _world(ShotPlan.empty())
	_run(world, 60, PlayerIntent.make(Vector2.RIGHT, AIM_RIGHT, false))
	assert_almost_eq(world.player.pos, Vector2(740, 450), NEAR)   # 240 px/s
	assert_almost_eq(PlayerIntent.make(Vector2(3, 4), Vector2.ZERO, false).move, Vector2(0.6, 0.8), Vector2(1e-6, 1e-6))
	var before: Vector2 = world.player.pos
	_run(world, 30, PlayerIntent.make(Vector2(-1, 1), AIM_RIGHT, false))
	assert_almost_eq(world.player.pos.distance_to(before), 120.0, 1e-2)   # diagonals are normalised
	_run(world, 600, PlayerIntent.make(Vector2(1, 1), AIM_RIGHT, false))
	assert_eq(world.player.pos, Vector2(987, 887))
	_run(world, 600, PlayerIntent.make(Vector2(-1, -1), AIM_RIGHT, false))
	assert_eq(world.player.pos, Vector2(13, 13))
	# aim_dir points at the aim point; closer than 1 px it keeps the previous direction
	_run(world, 1, PlayerIntent.make(Vector2.ZERO, Vector2(13, 413), false))
	assert_almost_eq(world.player.aim_dir, Vector2.DOWN, Vector2(1e-6, 1e-6))
	_run(world, 1, PlayerIntent.make(Vector2.ZERO, Vector2(13.6, 13.6), false))
	assert_almost_eq(world.player.aim_dir, Vector2.DOWN, Vector2(1e-6, 1e-6))


func test_gun_fires_four_times_per_second() -> void:
	var world: ArenaWorld = _world(Fixtures.plan_of([BulletSpec.new()]))
	var fire: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, true)
	var shot_steps: Array[int] = []
	for i: int in 60:
		if not _of(world.step(STEP, fire), SimEvent.Type.SHOT).is_empty():
			shot_steps.append(i + 1)
	assert_eq(shot_steps, [1, 16, 31, 46])
	assert_eq(_of(world.step(STEP, fire), SimEvent.Type.SHOT).size(), 1)   # step 61
	# released right after a shot, then held again: the cooldown kept falling, so one shot at once, never a burst
	assert_true(_of(_run(world, 60, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)), SimEvent.Type.SHOT).is_empty())
	assert_eq(_of(world.step(STEP, fire), SimEvent.Type.SHOT).size(), 1)
	assert_eq(_of(_run(world, 14, fire), SimEvent.Type.SHOT).size(), 0)
	assert_eq(_of(world.step(STEP, fire), SimEvent.Type.SHOT).size(), 1)


func test_no_fire_without_valid_plan() -> void:
	for plan: ShotPlan in [ShotPlan.empty(), ShotPlan.new()]:
		var world: ArenaWorld = _world(plan)
		assert_true(_of(_run(world, 60, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, true)), SimEvent.Type.SHOT).is_empty())
		assert_true(world.bullets.is_empty())


func test_bullets_use_muzzle_and_fan() -> void:
	var upper: BulletSpec = BulletSpec.from_counts({MachineCatalog.SPEED_UP: 1}, 1)
	upper.angle_offset = deg_to_rad(-5.0)
	var lower: BulletSpec = BulletSpec.from_counts({MachineCatalog.PIERCE: 2}, 1)
	lower.angle_offset = deg_to_rad(5.0)
	var world: ArenaWorld = _world(Fixtures.plan_of([upper, lower]))
	var events: Array[SimEvent] = world.step(STEP, PlayerIntent.make(Vector2.ZERO, CENTRE + Vector2(100, -100), true))
	var dir: Vector2 = Vector2(1, -1).normalized()
	var muzzle: Vector2 = CENTRE + dir * SimTuning.MUZZLE_OFFSET
	var shots: Array[SimEvent] = _of(events, SimEvent.Type.SHOT)
	assert_eq(shots.size(), 1)                # one SHOT for the whole fan
	assert_almost_eq(shots[0].pos, muzzle, NEAR)
	assert_eq(world.bullets.size(), 2)
	var specs: Array[BulletSpec] = [upper, lower]
	for i: int in 2:
		var b: BulletState = world.bullets[i]
		var vel: Vector2 = dir.rotated(specs[i].angle_offset) * specs[i].speed
		assert_eq(b.id, i + 1)
		assert_same(b.spec, specs[i])
		assert_almost_eq(b.vel, vel, NEAR)
		assert_almost_eq(b.pos, muzzle + vel * STEP, NEAR)   # fired, then moved in the same step
		assert_eq(b.pierce_left, specs[i].pierce)
		assert_almost_eq(b.life, Tuning.BASE_LIFETIME - STEP, 1e-4)
	assert_lt(world.bullets[0].vel.angle(), world.bullets[1].vel.angle())   # bullet 0 is counter-clockwise
	assert_almost_eq(world.bullets[0].vel.length(), 810.0, 1e-2)


func test_hit_applies_damage_and_status() -> void:
	var spec: BulletSpec = BulletSpec.from_counts(
			{MachineCatalog.FIRE: 1, MachineCatalog.ICE: 1, MachineCatalog.POISON: 1}, 0)
	var world: ArenaWorld = _world(Fixtures.plan_of([spec]))
	var id: int = world.spawn_enemy(GRUNT, Vector2(540, 450))
	var target: EnemyState = world.enemies[1]
	var hits: Array[SimEvent] = _of(world.step(STEP, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, true)),
			SimEvent.Type.HIT)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].entity_id, id)
	assert_eq(hits[0].color, spec.primary_color())
	assert_almost_eq(hits[0].pos, Vector2(522, 450), NEAR)   # already in contact at the muzzle: t = 0
	assert_almost_eq(target.hp, 30.0 - 10.0 - 6.0 * STEP - 1.5 * STEP, 1e-4)   # the hit, then this step's DoT
	assert_true(target.status.is_burning() and target.status.is_chilled() and target.status.is_poisoned())
	assert_almost_eq(target.status.burn_dps, 6.0, 1e-4)
	assert_almost_eq(target.status.slow, 0.2, 1e-4)
	assert_eq(target.status.poison_stacks, 1)
	assert_true(world.bullets.is_empty())     # no pierce: the bullet died at the hit
	# No overkill: once the first bullet of a volley kills, the second one skips the body and flies on.
	var pair: ArenaWorld = _world(Fixtures.plan_of([BulletSpec.new(), BulletSpec.new()]))
	var victim: int = pair.spawn_enemy(GRUNT, Vector2(540, 450))
	pair.enemies[1].hp = 4.0
	var events: Array[SimEvent] = pair.step(STEP, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, true))
	assert_eq(_of(events, SimEvent.Type.HIT).size(), 1)
	assert_eq(_of(events, SimEvent.Type.KILL)[0].entity_id, victim)
	assert_eq(pair.bullets.size(), 1)
	assert_eq(pair.bullets[0].id, 2)


func test_pierce_hits_n_plus_one_in_order() -> void:
	var spec: BulletSpec = BulletSpec.from_counts({MachineCatalog.PIERCE: 2}, 0)
	spec.speed = 6000.0                       # 100 px per step: all four enemies are inside one sweep
	var world: ArenaWorld = _world(Fixtures.plan_of([spec]))
	var ids: Array[int] = []
	for x: float in [640.0, 620.0, 590.0, 560.0]:   # far to near, so id order is not hit order
		ids.append(world.spawn_enemy(GRUNT, Vector2(x, 450)))
	var hit_ids: Array[int] = []
	for e: SimEvent in _of(world.step(STEP, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, true)), SimEvent.Type.HIT):
		hit_ids.append(e.entity_id)
	assert_eq(hit_ids, [ids[3], ids[2], ids[1]])   # pierce 2: three enemies, nearest first
	assert_true(world.bullets.is_empty())          # it died at the third hit
	assert_almost_eq(world.enemies[1].hp, 30.0, 1e-4)   # the farthest was never touched
	assert_eq(world.enemies[1].id, ids[0])


func test_bullet_hits_each_enemy_once() -> void:
	# Size Up III is slow and wide, so the bullet overlaps the Brute for about ten steps.
	var spec: BulletSpec = BulletSpec.from_counts({MachineCatalog.PIERCE: 1, MachineCatalog.SIZE_UP: 3}, 0)
	var world: ArenaWorld = _world(Fixtures.plan_of([spec]))
	var id: int = world.spawn_enemy(BRUTE, Vector2(620, 450))
	var events: Array[SimEvent] = world.step(STEP, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, true))
	events.append_array(_run(world, 60, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)))
	var hits: Array[SimEvent] = _of(events, SimEvent.Type.HIT)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].entity_id, id)
	assert_almost_eq(world.enemies[1].hp, 150.0 - spec.damage, 1e-3)
	assert_true(world.bullets.is_empty() or world.bullets[0].pierce_left == 0)   # it passed through


func test_bullets_expire_or_leave_the_arena() -> void:
	var slow: BulletSpec = BulletSpec.new()
	slow.speed = 100.0                        # stays inside: removed when its 1.4 s run out
	var world: ArenaWorld = _world(Fixtures.plan_of([slow, BulletSpec.new()]))
	world.step(STEP, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, true))
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)
	_run(world, 52, idle)                     # the fast one is at x 1052, inside the 60 px margin
	assert_eq(world.bullets.size(), 2)
	_run(world, 2, idle)                      # and leaves it
	assert_eq(world.bullets.size(), 1)
	assert_same(world.bullets[0].spec, slow)
	_run(world, 28, idle)                     # 83 steps: 1/60 s of life left
	assert_eq(world.bullets.size(), 1)
	_run(world, 2, idle)
	assert_true(world.bullets.is_empty())


func test_enemies_separate() -> void:
	var world: ArenaWorld = _world(ShotPlan.empty())
	world.spawn_enemy(GRUNT, Vector2(100, 100))
	world.spawn_enemy(GRUNT, Vector2(110, 100))
	world.spawn_enemy(GRUNT, Vector2(800, 700))
	world.spawn_enemy(GRUNT, Vector2(800, 700))   # same centre: pushed apart along a fixed axis
	for i: int in range(1, 5):
		world.enemies[i].speed = 0.0
	world.step(STEP, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false))
	# each enemy of a pair moves SEPARATION / 2 of the overlap: 18 px overlap -> 4.5 px each
	assert_almost_eq(world.enemies[1].pos, Vector2(95.5, 100), NEAR)
	assert_almost_eq(world.enemies[2].pos, Vector2(114.5, 100), NEAR)
	assert_almost_eq(world.enemies[3].pos, Vector2(793, 700), NEAR)
	assert_almost_eq(world.enemies[4].pos, Vector2(807, 700), NEAR)
	_run(world, 60, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false))
	assert_almost_eq(world.enemies[1].pos.distance_to(world.enemies[2].pos), 28.0, 1e-2)   # no overlap left


func test_ice_slows_movement() -> void:
	var world: ArenaWorld = _world(ShotPlan.empty())
	world.spawn_enemy(GRUNT, Vector2(100, 450))
	world.spawn_enemy(GRUNT, Vector2(900, 450))
	var plain: EnemyState = world.enemies[1]
	var chilled: EnemyState = world.enemies[2]
	chilled.status.apply_hit(BulletSpec.from_counts({MachineCatalog.ICE: 2}, 0))
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)
	_run(world, 60, idle)
	assert_almost_eq(plain.pos, Vector2(170, 450), NEAR)
	assert_almost_eq(chilled.pos, Vector2(900.0 - 70.0 * 0.6, 450), NEAR)
	_run(world, 61, idle)                     # the 2 s chill wears off
	assert_false(chilled.status.is_chilled())
	var x: float = chilled.pos.x
	_run(world, 1, idle)
	assert_almost_eq(x - chilled.pos.x, 70.0 * STEP, 1e-3)


func test_dot_kills_count() -> void:
	var world: ArenaWorld = _world(ShotPlan.empty())
	var id: int = world.spawn_enemy(GRUNT, Vector2(900, 450))
	world.enemies[1].status.apply_hit(BulletSpec.from_counts({MachineCatalog.FIRE: 3, MachineCatalog.POISON: 3}, 0))
	var kills: Array[SimEvent] = []
	for i: int in 120:
		kills = _of(world.step(STEP, PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)), SimEvent.Type.KILL)
		if not kills.is_empty():
			break
	assert_eq(kills.size(), 1)
	assert_eq(kills[0].entity_id, id)
	assert_eq(kills[0].color, EnemyType.get_type(GRUNT).color)
	assert_eq(world.kills, 1)
	assert_eq(world.enemies.size(), 1)        # only the parked one is left
	assert_almost_eq(world.time, 30.0 / 22.5, 2.0 * STEP)   # 18 burn + 4.5 poison damage/s


func test_contact_damage_and_invulnerability() -> void:
	var world: ArenaWorld = _world(ShotPlan.empty())
	var id: int = world.spawn_enemy(GRUNT, Vector2(520, 450))
	var grunt: EnemyState = world.enemies[1]
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)
	var hits: Array[SimEvent] = _of(world.step(STEP, idle), SimEvent.Type.PLAYER_HIT)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].entity_id, id)
	assert_eq(hits[0].color, EnemyType.get_type(GRUNT).color)
	assert_almost_eq(world.player.hp, 90.0, 1e-4)
	assert_almost_eq(world.player.invuln, SimTuning.PLAYER_INVULN, 1e-4)
	# it walked 70/60 px in, then was pushed 30 px straight away from the player
	assert_almost_eq(grunt.pos, Vector2(520.0 - 70.0 * STEP + 30.0, 450), NEAR)
	# It walks back into contact while the player is invulnerable: pushed again, no damage.
	var pushes: int = 0
	var step_of_next_hit: int = 0
	for i: int in 120:
		var dist: float = grunt.pos.distance_to(world.player.pos)
		var damaged: bool = not _of(world.step(STEP, idle), SimEvent.Type.PLAYER_HIT).is_empty()
		if grunt.pos.distance_to(world.player.pos) > dist + 20.0:
			pushes += 1
		if damaged:
			step_of_next_hit = i + 2              # counting the first hit's step as 1
			break
	assert_eq(pushes, 2)                      # one push without damage, then the damaging one
	assert_gt(step_of_next_hit, 36)           # 0.6 s of invulnerability
	assert_almost_eq(world.player.hp, 80.0, 1e-4)


func test_spawns_outside_and_away_from_player() -> void:
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(6, ShotPlan.empty(), Seeds.derive(3, 6, Seeds.WAVE), 1e9)   # the player outlives the wave
	world.player.pos = Vector2(13, 13)        # in a corner, many edge points are too close
	var corner: PlayerIntent = PlayerIntent.make(Vector2(-1, -1), Vector2.ZERO, false)
	var lo: float = -SimTuning.SPAWN_OUTSIDE
	var hi: Vector2 = SimTuning.ARENA_SIZE + Vector2.ONE * SimTuning.SPAWN_OUTSIDE
	var seen: Dictionary[int, bool] = {}
	var bad: PackedStringArray = []
	while world.enemies_remaining() > world.enemies.size() and world.time < 60.0:
		world.step(STEP, corner)
		for e: EnemyState in world.enemies:
			if seen.has(e.id):
				continue
			seen[e.id] = true
			var p: Vector2 = e.pos
			var slack: float = e.speed * STEP + 1e-2   # it already walked one step toward the player
			var edge_gap: float = minf(minf(absf(p.x - lo), absf(p.x - hi.x)), minf(absf(p.y - lo), absf(p.y - hi.y)))
			var in_band: bool = p.x > lo - slack and p.x < hi.x + slack and p.y > lo - slack and p.y < hi.y + slack
			if edge_gap > slack or not in_band or p.distance_to(world.player.pos) < SimTuning.SPAWN_MIN_PLAYER_DIST - slack:
				bad.append("#%d at %s" % [e.id, p])
	assert_eq(seen.size(), 28)                # wave 6: 16 + 10 + 2
	assert_eq(bad, PackedStringArray())


## F.3: spawn k arrives alone, on the first step at or after 1.0 + k · spawn_interval(w).
func test_spawns_follow_the_schedule() -> void:
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)
	for wave: int in [1, 10]:                 # spawns 1.0 s and 0.55 s apart
		var world: ArenaWorld = ArenaWorld.new()
		world.begin_wave(wave, ShotPlan.empty(), Seeds.derive(7, wave, Seeds.WAVE), 1e9)   # the player outlives the wave
		# nobody dies, so past 40 alive the cap holds the rest back (test_live_enemy_cap)
		var due: int = mini(world.enemies_remaining(), SimTuning.MAX_LIVE_ENEMIES)
		var wrong: PackedStringArray = []
		var before: float = 0.0               # the previous step's time
		while world.enemies.size() < due and world.time < 60.0:
			var k: int = world.enemies.size()
			world.step(STEP, idle)
			var arrived: int = world.enemies.size() - k
			var at: float = SimTuning.FIRST_SPAWN_DELAY + k * SimTuning.spawn_interval(wave)
			if arrived > 0 and (arrived != 1 or before >= at or world.time < at):
				wrong.append("wave %d: %d at %.3f s; spawn %d is due at %.3f s" % [wave, arrived, world.time, k, at])
			before = world.time
		assert_eq(world.enemies.size(), due)
		assert_eq(wrong, PackedStringArray())


func test_live_enemy_cap() -> void:
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(1, ShotPlan.empty(), Seeds.derive(1, 1, Seeds.WAVE), Tuning.PLAYER_MAX_HP)
	for i: int in SimTuning.MAX_LIVE_ENEMIES:
		world.spawn_enemy(GRUNT, FAR + Vector2(0, 60 * i))
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)
	_run(world, 210, idle)                    # 3.5 s: three scheduled spawns are due, but 40 are alive
	assert_eq(world.enemies.size(), 40)
	assert_eq(world.enemies_remaining(), 46)
	for i: int in 3:
		world.enemies[i].hp = 0.0
	world.step(STEP, idle)
	assert_eq(world.enemies.size(), 37)
	assert_eq(world.kills, 3)
	world.step(STEP, idle)
	assert_eq(world.enemies.size(), 40)       # the three overdue spawns arrive together
	assert_eq(world.enemies_remaining(), 43)


func test_wave_clears_after_grace() -> void:
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)
	# no enemies alive before the first spawn, but unspawned ones keep the wave going
	var scheduled: ArenaWorld = ArenaWorld.new()
	scheduled.begin_wave(1, ShotPlan.empty(), 5, 100.0)
	assert_true(_of(_run(scheduled, 120, idle), SimEvent.Type.WAVE_CLEARED).is_empty())
	assert_true(scheduled.is_running())
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(1, ShotPlan.empty(), 5, 100.0)
	world.cancel_spawns()
	world.spawn_enemy(GRUNT, Vector2(900, 450))
	world.enemies[0].hp = 0.0
	assert_eq(_of(world.step(STEP, idle), SimEvent.Type.KILL).size(), 1)   # the grace starts with this step
	var cleared_at: int = -1
	for i: int in 120:
		var cleared: Array[SimEvent] = _of(world.step(STEP, idle), SimEvent.Type.WAVE_CLEARED)
		if not cleared.is_empty():
			cleared_at = i + 2
			break
	assert_between(cleared_at, 60, 61)        # 1 s of grace in 1/60 s steps
	assert_true(world.is_finished())
	assert_false(world.is_running())
	assert_eq(world.kills, 1)
	assert_eq(world.enemies_remaining(), 0)
	assert_true(world.step(STEP, idle).is_empty())   # finished: nothing more happens


## The clear needs everything spawned, not just an empty field: between two spawns nobody may be alive.
func test_wave_clear_waits_for_every_spawn() -> void:
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(1, ShotPlan.empty(), Seeds.derive(1, 1, Seeds.WAVE), Tuning.PLAYER_MAX_HP)
	while world.enemies.is_empty() and world.time < 2.0:
		world.step(STEP, idle)
	assert_eq(world.enemies.size(), 1)        # the first Grunt, at 1 s
	world.enemies[0].hp = 0.0
	var gap: Array[SimEvent] = _run(world, 50, idle)
	assert_lt(world.time, 2.0)                # the second one is due at 2 s
	assert_eq(_of(gap, SimEvent.Type.KILL).size(), 1)
	assert_true(_of(gap, SimEvent.Type.WAVE_CLEARED).is_empty())
	assert_true(world.is_running())
	assert_true(world.enemies.is_empty())
	assert_eq(world.enemies_remaining(), 5)
	# The other five die as they arrive: the clear still waits the whole grace after the last kill.
	var last_kill: int = -1
	var cleared_at: int = -1
	for i: int in 600:
		for e: EnemyState in world.enemies:
			e.hp = 0.0
		var events: Array[SimEvent] = world.step(STEP, idle)
		if not _of(events, SimEvent.Type.KILL).is_empty():
			last_kill = i
		if not _of(events, SimEvent.Type.WAVE_CLEARED).is_empty():
			cleared_at = i
			break
	assert_eq(world.kills, 6)
	assert_between(cleared_at - last_kill + 1, 60, 61)   # counting the kill's step as 1, as above


func test_death_wins_over_clear() -> void:
	# The clear needs a second without enemies, and only enemies hurt the player, so drop the HP of one of two
	# identical worlds right before the step on which the other one clears.
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)
	var clearing: ArenaWorld = _empty_wave()
	var dying: ArenaWorld = _empty_wave()
	var steps: int = 0
	while _of(clearing.step(STEP, idle), SimEvent.Type.WAVE_CLEARED).is_empty() and steps < 120:
		dying.step(STEP, idle)
		steps += 1
	assert_true(clearing.is_finished())
	dying.player.hp = -3.0
	var events: Array[SimEvent] = dying.step(STEP, idle)
	assert_eq(_types(events), [SimEvent.Type.PLAYER_DIED])
	assert_eq(dying.player.hp, 0.0)
	assert_true(dying.is_finished())
	assert_false(dying.is_running())
	assert_true(dying.step(STEP, idle).is_empty())
	# A real death in a running wave: the contact kills, then the wave ends at once.
	var world: ArenaWorld = _world(ShotPlan.empty())
	world.player.hp = 10.0
	world.spawn_enemy(GRUNT, Vector2(520, 450))
	assert_eq(_types(world.step(STEP, idle)), [SimEvent.Type.PLAYER_HIT, SimEvent.Type.PLAYER_DIED])
	assert_eq(world.player.hp, 0.0)


## The game keeps one world for every wave (ArenaController), so begin_wave must leave nothing of the last wave
## behind (F.5): neither the gun's cooldown nor the clear grace already served.
func test_begin_wave_on_a_used_world_starts_fresh() -> void:
	var fire: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, true)
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, AIM_RIGHT, false)
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(1, Fixtures.plan_of([BulletSpec.new()]), 5, Tuning.PLAYER_MAX_HP)
	world.cancel_spawns()
	_run(world, 50, idle)
	var shots: int = 0
	for i: int in 70:                         # fire through the end of the grace
		if not world.is_running():
			break
		shots += _of(world.step(STEP, fire), SimEvent.Type.SHOT).size()
	assert_true(world.is_finished())
	assert_eq(shots, 1)                       # on step 51: the gun was still cooling down at the clear
	world.begin_wave(2, world.plan, 6, Tuning.PLAYER_MAX_HP)
	assert_eq(_of(world.step(STEP, fire), SimEvent.Type.SHOT).size(), 1)   # step 1 fires, as in any wave
	world.cancel_spawns()
	var cleared_at: int = -1
	for i: int in 120:
		if not _of(world.step(STEP, idle), SimEvent.Type.WAVE_CLEARED).is_empty():
			cleared_at = i + 1
			break
	assert_between(cleared_at, 60, 61)        # a whole grace again


func test_determinism_same_seed_same_hash_different_seed_differs() -> void:
	var fire: BulletSpec = BulletSpec.from_counts({MachineCatalog.FIRE: 1, MachineCatalog.PIERCE: 1}, 1)
	fire.angle_offset = deg_to_rad(-5.0)
	var poison: BulletSpec = BulletSpec.from_counts({MachineCatalog.POISON: 2, MachineCatalog.ICE: 1}, 1)
	poison.angle_offset = deg_to_rad(5.0)
	var plan: ShotPlan = Fixtures.plan_of([fire, poison])
	var a: ArenaWorld = _seeded(plan, 99)
	var b: ArenaWorld = _seeded(plan, 99)
	var c: ArenaWorld = _seeded(plan, 100)
	var same: bool = true
	var differed: bool = false
	for i: int in 600:
		var ea: Array[SimEvent] = a.step(STEP, Bot.intent(a))
		var eb: Array[SimEvent] = b.step(STEP, Bot.intent(b))
		c.step(STEP, Bot.intent(c))
		same = same and a.state_hash() == b.state_hash() and _signature(ea) == _signature(eb)
		differed = differed or a.state_hash() != c.state_hash()
	assert_true(same, "same seed and intents: same events and state_hash() every step")
	assert_true(differed, "a different seed gives a different run")
	assert_gt(a.kills, 0)
	# the hash covers enemies, bullets and the player
	for i: int in 600:
		if not a.enemies.is_empty() and not a.bullets.is_empty():
			break
		a.step(STEP, Bot.intent(a))
	assert_false(a.enemies.is_empty() or a.bullets.is_empty())
	var h: int = a.state_hash()
	a.enemies[0].hp -= 1.0
	assert_ne(a.state_hash(), h)
	h = a.state_hash()
	a.bullets[0].pierce_left += 1
	assert_ne(a.state_hash(), h)
	h = a.state_hash()
	a.player.invuln += 0.5
	assert_ne(a.state_hash(), h)
	# No reference cycles: once dropped, the world and everything in it is freed.
	var refs: Array[WeakRef] = _refs(a)
	a = null
	for r: WeakRef in refs:
		assert_null(r.get_ref())


## Wave 1 with the schedule dropped and one enemy parked out of reach at speed 0, so the wave never clears.
func test_nearest_enemy_is_the_auto_aim_target() -> void:
	var world: ArenaWorld = _empty_wave()
	assert_null(world.nearest_enemy())
	var far_id: int = world.spawn_enemy(GRUNT, Vector2(900, 450))
	var near_id: int = world.spawn_enemy(GRUNT, Vector2(500, 200))
	world.spawn_enemy(GRUNT, Vector2(500, 700))           # as near as near_id: the lower id wins
	assert_eq(world.nearest_enemy().id, near_id)
	world.enemies[1].hp = 0.0                             # dead, not yet removed
	assert_eq(world.nearest_enemy().id, near_id + 1)
	world.enemies[2].hp = 0.0
	assert_eq(world.nearest_enemy().id, far_id)


func _world(plan: ShotPlan) -> ArenaWorld:
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(1, plan, Seeds.derive(1, 1, Seeds.WAVE), Tuning.PLAYER_MAX_HP)
	world.cancel_spawns()
	world.spawn_enemy(GRUNT, FAR)
	world.enemies[0].speed = 0.0
	return world


## A running wave with nothing scheduled and nobody alive: it clears after the grace.
func _empty_wave() -> ArenaWorld:
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(1, ShotPlan.empty(), 5, Tuning.PLAYER_MAX_HP)
	world.cancel_spawns()
	return world


func _seeded(plan: ShotPlan, run_seed: int) -> ArenaWorld:
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(3, plan, Seeds.derive(run_seed, 3, Seeds.WAVE), Tuning.PLAYER_MAX_HP)
	return world


func _run(world: ArenaWorld, steps: int, intent: PlayerIntent) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	for i: int in steps:
		events.append_array(world.step(STEP, intent))
	return events


func _of(events: Array[SimEvent], type: SimEvent.Type) -> Array[SimEvent]:
	return events.filter(func(e: SimEvent) -> bool: return e.type == type)


func _types(events: Array[SimEvent]) -> Array[SimEvent.Type]:
	var out: Array[SimEvent.Type] = []
	for e: SimEvent in events:
		out.append(e.type)
	return out


func _signature(events: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in events:
		out.append([e.type, e.pos, e.color, e.entity_id])
	return out


## Weakrefs to the world and everything it owns. A separate function, so no local keeps a reference.
func _refs(world: ArenaWorld) -> Array[WeakRef]:
	var refs: Array[WeakRef] = [weakref(world), weakref(world.player)]
	for e: EnemyState in world.enemies:
		refs.append(weakref(e))
		refs.append(weakref(e.status))
	for b: BulletState in world.bullets:
		refs.append(weakref(b))
	return refs

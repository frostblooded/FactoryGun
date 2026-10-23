extends GutTest
## Balance floor (docs/DESIGN.md H.4). On failure tune only test/helpers/bot.gd: Tuning and SimTuning are frozen.

const Bot = preload("res://test/helpers/bot.gd")
const Fixtures = preload("res://test/helpers/fixtures.gd")


func test_default_gun_bot_clears_waves_1_and_2() -> void:
	for run_seed: int in [1, 2, 3, 4, 5]:     # several runs: WP4's integration test plays an arbitrary seed
		var world: ArenaWorld = ArenaWorld.new()
		var hp: float = Tuning.PLAYER_MAX_HP
		for wave: int in [1, 2]:
			world.begin_wave(wave, Fixtures.plan_of([BulletSpec.new()]), Seeds.derive(run_seed, wave, Seeds.WAVE), hp)
			Bot.play(world, 90.0)
			assert_true(world.is_finished() and world.player.hp > 0.0, "seed %d wave %d: %.1f s, hp %.1f, %d left"
					% [run_seed, wave, world.time, world.player.hp, world.enemies_remaining()])
			hp = world.player.hp              # no reward heal in between: stricter than the game


func test_idle_player_dies_in_wave_1() -> void:
	var world: ArenaWorld = ArenaWorld.new()
	world.begin_wave(1, Fixtures.plan_of([BulletSpec.new()]), Seeds.derive(1, 1, Seeds.WAVE), Tuning.PLAYER_MAX_HP)
	var idle: PlayerIntent = PlayerIntent.make(Vector2.ZERO, Vector2.ZERO, false)
	var died: bool = false
	for i: int in 3600:
		var events: Array[SimEvent] = world.step(SimTuning.STEP, idle)
		if events.any(func(e: SimEvent) -> bool: return e.type == SimEvent.Type.PLAYER_DIED):
			died = true
			break
	assert_true(died)
	assert_eq(world.player.hp, 0.0)
	assert_false(world.is_running())
	assert_eq(world.kills, 0)

extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")
const STEP: float = SimTuning.STEP

var _idled_on_death: ArenaController = null
var _died_kills: int = -1


func test_start_wave_runs_and_updates_hud() -> void:
	var arena: ArenaController = _arena()
	assert_false(arena.is_running())
	assert_same(arena.view.world, arena.world)
	assert_eq(arena.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(arena.view.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(arena.hud.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(arena.mouse_default_cursor_shape, Control.CURSOR_CROSS)
	assert_true(arena.clip_contents)
	arena.start_wave(3, Fixtures.plan_of([BulletSpec.new()]), 42, 80.0)
	assert_true(arena.is_running())
	assert_eq(arena.world.wave, 3)
	assert_eq([arena.hud.wave, arena.hud.running, arena.hud.banner_text], [3, true, "WAVE 3"])
	assert_almost_eq(arena.hud.banner_left, 1.5, 1e-4)
	assert_almost_eq(arena.hud.hp, 80.0, 1e-4)
	assert_eq(arena.hud.enemies_left, 14)     # wave 3: 10 Grunts + 4 Runners
	arena.intent_override = PlayerIntent.make(Vector2.UP, Vector2(900, 450), true)
	for i: int in 90:
		arena.step(STEP)
	assert_almost_eq(arena.world.time, 1.5, 1e-6)
	assert_lt(arena.world.player.pos.y, 450.0)   # the override drives the world
	assert_false(arena.world.bullets.is_empty())
	assert_false(arena.view._fx.is_empty())   # SHOT events reached the view
	assert_eq(arena.hud.enemies_left, arena.world.enemies_remaining())
	assert_almost_eq(arena.hud.hp, arena.world.player.hp, 1e-4)


func test_wave_cleared_emitted_once_with_hp_and_kills() -> void:
	var arena: ArenaController = _arena()
	arena.start_wave(1, Fixtures.plan_of([BulletSpec.new()]), 7, 90.0)
	arena.world.cancel_spawns()
	arena.world.spawn_enemy(EnemyType.Kind.GRUNT, Vector2(800, 450))
	arena.intent_override = PlayerIntent.make(Vector2.ZERO, Vector2(800, 450), true)
	watch_signals(arena)
	for i: int in 600:                        # the kill, the 1 s grace, then idle steps that must stay silent
		arena.step(STEP)
	assert_signal_emit_count(arena, "wave_cleared", 1)
	assert_signal_emitted_with_parameters(arena, "wave_cleared", [90.0, 1])
	assert_signal_not_emitted(arena, "player_died")
	assert_false(arena.is_running())
	assert_eq(arena.hud.enemies_left, 0)


func test_player_died_emitted() -> void:
	var arena: ArenaController = _arena()
	arena.start_wave(1, ShotPlan.empty(), 7, 10.0)
	arena.world.cancel_spawns()
	arena.world.spawn_enemy(EnemyType.Kind.GRUNT, Vector2(520, 450))   # touching the player
	arena.intent_override = PlayerIntent.make(Vector2.ZERO, Vector2.ZERO, false)
	watch_signals(arena)
	_idled_on_death = arena
	arena.player_died.connect(_go_idle_on_death)   # handlers may call go_idle() from inside step()
	arena.step(STEP)
	assert_signal_emit_count(arena, "player_died", 1)
	assert_signal_emitted_with_parameters(arena, "player_died", [0])
	assert_signal_not_emitted(arena, "wave_cleared")
	assert_eq(_died_kills, 0)
	assert_false(arena.is_running())
	assert_almost_eq(arena.world.player.hp, 100.0, 1e-4)   # the handler's go_idle() had the last word
	assert_false(arena.hud.running)
	arena.step(STEP)
	assert_signal_emit_count(arena, "player_died", 1)


func test_go_idle_resets() -> void:
	var arena: ArenaController = _arena()
	arena.start_wave(2, Fixtures.plan_of([BulletSpec.new()]), 5, 70.0)
	arena.intent_override = PlayerIntent.make(Vector2.RIGHT, Vector2(900, 100), true)
	for i: int in 150:
		arena.step(STEP)
	assert_false(arena.world.bullets.is_empty())
	assert_false(arena.world.enemies.is_empty())
	assert_false(arena.view._fx.is_empty())
	arena.go_idle(55.0, 3)
	var w: ArenaWorld = arena.world
	assert_false(arena.is_running())
	assert_true(w.enemies.is_empty() and w.bullets.is_empty())
	assert_eq(w.enemies_remaining(), 0)
	assert_eq([w.time, w.kills], [0.0, 0])
	assert_eq(w.player.pos, Vector2(500, 450))
	assert_almost_eq(w.player.hp, 55.0, 1e-4)
	assert_eq(w.player.aim_dir, Vector2.RIGHT)
	assert_eq([arena.hud.wave, arena.hud.running, arena.hud.enemies_left], [3, false, 0])
	assert_almost_eq(arena.hud.hp, 55.0, 1e-4)
	assert_true(arena.view._fx.is_empty())
	var frozen: int = w.state_hash()
	arena.step(STEP)                          # idle: nothing moves and the gun is locked
	assert_eq(w.state_hash(), frozen)


func test_render_smoke() -> void:
	var arena: ArenaController = _arena()
	var all: BulletSpec = BulletSpec.from_counts({MachineCatalog.FIRE: 1, MachineCatalog.ICE: 1,
			MachineCatalog.POISON: 3, MachineCatalog.PIERCE: 2, MachineCatalog.SIZE_UP: 2}, 1)
	all.angle_offset = 0.1
	arena.start_wave(4, Fixtures.plan_of([BulletSpec.new(), all]), 11, 100.0)
	var w: ArenaWorld = arena.world
	w.cancel_spawns()
	var effects: Array[BulletSpec] = [BulletSpec.new(), BulletSpec.from_counts({MachineCatalog.FIRE: 2}, 0),
			BulletSpec.from_counts({MachineCatalog.ICE: 1}, 0), BulletSpec.from_counts({MachineCatalog.POISON: 3}, 0), all]
	var kinds: Array[EnemyType.Kind] = [EnemyType.Kind.GRUNT, EnemyType.Kind.RUNNER, EnemyType.Kind.BRUTE]
	for k: int in kinds.size():
		for s: int in effects.size():
			w.spawn_enemy(kinds[k], Vector2(120 + 190 * s, 150 + 300 * k))
			var e: EnemyState = w.enemies[w.enemies.size() - 1]
			e.status.apply_hit(effects[s])
			e.hp -= 1.0                       # damaged: HP bar
	w.spawn_enemy(EnemyType.Kind.RUNNER, Vector2(560, 450))   # in the line of fire: HIT and KILL
	w.spawn_enemy(EnemyType.Kind.GRUNT, Vector2(500, 475))    # touching the player: PLAYER_HIT, blinking
	arena.intent_override = PlayerIntent.make(Vector2.ZERO, Vector2(900, 450), true)
	for i: int in 20:
		arena.step(STEP)
	arena.view.add_events([SimEvent.make(SimEvent.Type.SHOT, Vector2(522, 450), Color.ORANGE),
			SimEvent.make(SimEvent.Type.HIT, Vector2(600, 450), Color.CYAN, w.enemies[0].id),
			SimEvent.make(SimEvent.Type.KILL, Vector2(700, 450), Color.PURPLE, 999),
			SimEvent.make(SimEvent.Type.PLAYER_HIT, w.player.pos, Color.RED, 998)])
	assert_gt(w.kills, 0)
	assert_gt(w.player.invuln, 0.0)
	assert_false(w.bullets.is_empty())
	await wait_process_frames(2)
	assert_eq(arena.view.size, Vector2(1000, 900))   # full-rect children follow the arena
	assert_eq(arena.hud.size, Vector2(1000, 900))
	arena.go_idle(20.0, 5)                    # idle HUD: hint, BUILD PHASE, low-HP bar
	await wait_process_frames(2)
	assert_false(arena.is_running())


func _arena() -> ArenaController:
	var arena: ArenaController = ArenaController.new()
	add_child_autofree(arena)
	arena.set_physics_process(false)          # after _ready, which turns it on; tests drive step() directly
	arena.size = Vector2(1000, 900)
	return arena


func _go_idle_on_death(kills: int) -> void:
	_died_kills = kills
	_idled_on_death.go_idle(100.0, 1)

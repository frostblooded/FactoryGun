extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")
const Mouse = preload("res://test/helpers/mouse.gd")
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
	assert_eq(arena.stick.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(arena.mouse_default_cursor_shape, Control.CURSOR_ARROW, "nothing to aim: the gun aims itself")
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


func test_physics_tick_reads_real_input() -> void:
	await Mouse.prepare(self)
	InputSetup.ensure_actions()
	var arena: ArenaController = _arena()
	arena.position = Vector2(100, 0)          # local != global, as in the game
	arena.start_wave(1, Fixtures.plan_of([BulletSpec.new()]), 7, 100.0)
	arena.world.cancel_spawns()
	var w: InputEventKey = InputEventKey.new()
	w.physical_keycode = KEY_W
	w.pressed = true
	Input.parse_input_event(w)                # real events, so the InputSetup bindings are covered
	await wait_process_frames(1)
	arena._physics_process(STEP)
	assert_lt(arena.world.player.pos.y, 450.0, "W moves up")
	assert_eq(arena.world.bullets.size(), 0, "no enemy: no shot")
	arena.world.spawn_enemy(EnemyType.Kind.GRUNT, Vector2(500, 0))     # above the player, farther
	arena.world.spawn_enemy(EnemyType.Kind.GRUNT, Vector2(900, 450))   # nearer: right of the player
	arena._physics_process(STEP)
	assert_almost_eq(arena.world.player.aim_dir.x, 1.0, 0.01, "aims at the nearest enemy")
	assert_eq(arena.world.bullets.size(), 1, "and fires on its own")
	w.pressed = false
	Input.parse_input_event(w)
	await wait_process_frames(1)


func test_touch_stick_moves_the_player() -> void:
	await Mouse.prepare(self)
	var arena: ArenaController = _arena()
	arena.position = Vector2(600, 0)
	_touch(0, Vector2(800, 600), true)
	await wait_process_frames(1)
	assert_false(arena.stick.is_active(), "no stick between waves")
	_touch(0, Vector2(800, 600), false)
	arena.start_wave(1, Fixtures.plan_of([BulletSpec.new()]), 7, 100.0)
	arena.world.cancel_spawns()
	_touch(0, Vector2(300, 600), true)        # over the editor
	await wait_process_frames(1)
	assert_false(arena.stick.is_active(), "a touch on the editor is not the stick")
	_touch(0, Vector2(300, 600), false)
	_touch(1, Vector2(800, 600), true)
	await wait_process_frames(1)
	assert_true(arena.stick.is_active())
	assert_eq(arena.stick.origin, Vector2(200, 600), "arena-local")
	_drag(2, Vector2(1000, 600))              # another finger does not steer it
	_drag(1, Vector2(800 + TouchStick.RADIUS * 3, 600))
	await wait_process_frames(1)
	assert_eq(arena.stick.vector(), Vector2.RIGHT, "clamped to full speed")
	var x: float = arena.world.player.pos.x
	arena._physics_process(STEP)
	assert_almost_eq(arena.world.player.pos.x - x, SimTuning.PLAYER_SPEED * STEP, 1e-3)
	_touch(1, Vector2(1000, 600), false)
	await wait_process_frames(1)
	assert_false(arena.stick.is_active())
	assert_eq(arena.stick.vector(), Vector2.ZERO)
	_touch(3, Vector2(800, 600), true)
	await wait_process_frames(1)
	arena.go_idle(100.0, 2)
	assert_false(arena.stick.is_active(), "going idle drops the stick")
	_touch(3, Vector2(800, 600), false)
	await wait_process_frames(1)


func test_effects_and_banner_expire() -> void:
	var arena: ArenaController = _arena()
	var view: ArenaView = arena.view
	view.add_events([SimEvent.make(SimEvent.Type.SHOT, Vector2(522, 450), Color.ORANGE),
			SimEvent.make(SimEvent.Type.HIT, Vector2(600, 450), Color.CYAN, 5),
			SimEvent.make(SimEvent.Type.KILL, Vector2(700, 450), Color.PURPLE, 6),
			SimEvent.make(SimEvent.Type.PLAYER_HIT, Vector2(500, 450), Color.RED, 7)])
	assert_eq(view._fx.size(), 3)
	assert_true(view._hit_flash.has(5), "the enemy hit flashes white")
	view._process(0.1)                        # the muzzle flash and the white hit flash are over
	assert_eq(view._fx.size(), 2)
	assert_true(view._hit_flash.is_empty())
	assert_gt(view._edge_flash, 0.0)
	view._process(1.0)
	assert_true(view._fx.is_empty())
	assert_eq(view._edge_flash, 0.0)
	arena.hud.show_banner("WAVE 2")
	arena.hud._process(1.0)
	assert_almost_eq(arena.hud.banner_left, 0.5, 1e-4)
	arena.hud._process(1.0)
	assert_eq(arena.hud.banner_left, 0.0)


## Nothing else asks these views to redraw: the arena repaints itself every frame, and the HUD on every new stat.
func test_arena_and_hud_repaint() -> void:
	var arena: ArenaController = _arena()
	await wait_process_frames(2)
	watch_signals(arena.view)
	watch_signals(arena.hud)
	arena.start_wave(1, Fixtures.plan_of([BulletSpec.new()]), 7, 100.0)
	await wait_process_frames(3)
	assert_gte(get_signal_emit_count(arena.view, "draw"), 2, "the arena is drawn every frame")
	arena.hud._process(Hud.BANNER_TIME)       # the banner is over, so it no longer redraws the HUD
	await wait_process_frames(2)
	var hud_draws: int = get_signal_emit_count(arena.hud, "draw")
	await wait_process_frames(2)
	assert_signal_emit_count(arena.hud, "draw", hud_draws, "nothing new to show")
	arena.world.cancel_spawns()
	arena.world.spawn_enemy(EnemyType.Kind.GRUNT, Vector2(520, 450))   # touching the player
	arena.intent_override = PlayerIntent.make(Vector2.ZERO, Vector2.ZERO, false)
	arena.step(STEP)
	assert_lt(arena.hud.hp, 100.0)
	await wait_process_frames(2)
	assert_signal_emit_count(arena.hud, "draw", hud_draws + 1, "the new HP is drawn")


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	Input.parse_input_event(e)


func _arena() -> ArenaController:
	var arena: ArenaController = ArenaController.new()
	add_child_autofree(arena)
	arena.set_physics_process(false)          # after _ready, which turns it on; tests drive step() directly
	arena.size = Vector2(1000, 900)
	return arena


func _go_idle_on_death(kills: int) -> void:
	_died_kills = kills
	_idled_on_death.go_idle(100.0, 1)

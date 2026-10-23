extends GutTest

const Bot = preload("res://test/helpers/bot.gd")
const Mouse = preload("res://test/helpers/mouse.gd")
const MainScene = preload("res://src/main/main.tscn")

const SEED: int = 4242
const STEP: float = SimTuning.STEP
const BOARD: Vector2 = FactoryPanel.BOARD_POS   # the panel sits at (0, 0), so board-local + BOARD = screen
const SLOT_FIRE: Vector2 = Vector2(56, 626)     # palette slot centres: PALETTE_POS + (36 + 78 * i, 44)
const SLOT_SPEED: Vector2 = Vector2(290, 626)
const NO_PATH: String = "Connect the Basic Bullet to the Output first."


func test_boot_layout_and_initial_state() -> void:
	var main: Main = _main()
	var run: RunState = main.run
	assert_eq(main.get_child_count(), 5)
	var order: Array[Control] = [main.panel, main.arena, main.reward_overlay, main.game_over_overlay, main.rotate_hint]
	var rects: Array[Rect2] = [Main.PANEL_RECT, Main.ARENA_RECT, Main.ARENA_RECT, Main.ARENA_RECT, Main.SCREEN_RECT]
	for i: int in order.size():               # the overlays come after the arena, so they draw on top
		assert_same(main.get_child(i), order[i])
		assert_eq(Rect2(order[i].position, order[i].size), rects[i])
	assert_eq(main.theme.default_font_size, FactoryTheme.FONT_SIZE)
	assert_eq([run.flow.state, run.flow.wave, run.total_kills], [GameFlow.State.BUILD, 1, 0])
	assert_almost_eq(run.player_hp, Tuning.PLAYER_MAX_HP, 1e-4)
	assert_eq(run.inventory.to_dict(), Inventory.from_counts(Tuning.START_INVENTORY).to_dict())
	assert_eq(run.graph.to_dict(), FactoryGraph.create_default().to_dict())
	var board: FactoryBoard = main.panel.board
	assert_same(board.interaction.graph, run.graph)
	assert_same(board.interaction.inventory, run.inventory)
	assert_false(board.interaction.locked)
	assert_eq(main.panel.start_button.text, "START WAVE 1  [Space]")
	assert_false(main.panel.start_button.disabled)
	assert_eq([main.panel.slots[0].count, main.panel.slots[3].count], [1, 1])   # Fire, Speed Up
	assert_eq(main.panel.readout.label.text, "1 bullet/shot · 4 shots/s · 10.0 dmg/shot\n#1 DMG 10.0 · SPD 600 · SIZE 5.0")
	assert_false(main.arena.is_running())
	assert_eq([main.arena.hud.wave, main.arena.hud.running], [1, false])
	assert_almost_eq(main.arena.hud.hp, Tuning.PLAYER_MAX_HP, 1e-4)
	assert_false(main.reward_overlay.visible)
	assert_false(main.rotate_hint.visible, "headless has no touch screen")
	assert_false(main.game_over_overlay.visible)
	await wait_process_frames(2)
	assert_eq(main.arena.view.size, Vector2(1000, 900))   # full-rect children follow the arena's size
	assert_eq(main.arena.hud.size, Vector2(1000, 900))


## Each draw_circle is a draw call of its own, where rects batch: the floor's 336 bolts as circles took Main idle on
## the default board to about 500 draw calls a frame. The dummy renderer of a headless run counts no draw calls, so
## this checks only in a run with a renderer (for example under xvfb-run, without --headless).
func test_default_board_stays_in_its_draw_call_budget() -> void:
	if DisplayServer.get_name() == "headless":
		pending("headless: the dummy renderer counts no draw calls")
		return
	var main: Main = _main()
	main.visible = false
	await wait_process_frames(3)
	var others: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)   # GUT's own window
	main.visible = true
	await wait_process_frames(3)
	assert_lt(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME) - others, 150.0)


func test_no_path_disables_start_with_reason() -> void:
	var main: Main = _main()
	var run: RunState = main.run
	main.panel.board.disconnect_requested.emit(run.graph.wire_from(FactoryGraph.SOURCE_ID, 0))
	assert_true(run.graph.wires().is_empty())
	assert_false(run.can_start_wave())
	assert_true(main.panel.start_button.disabled)
	assert_eq(main.panel.readout.label.text, "NO PATH: connect the Basic Bullet to the Output")
	main.panel._process(0.0)
	assert_eq(main.panel.status_label.text, NO_PATH)       # the status line says why
	assert_eq(main.panel.status_label.get_theme_color("font_color"), UiColors.WARN)
	_key(main, KEY_SPACE)
	main.panel.start_wave_requested.emit()
	assert_eq(run.flow.state, GameFlow.State.BUILD)
	assert_false(main.arena.is_running())
	main.panel._process(0.0)
	assert_eq(main.panel.status_label.text, NO_PATH)       # now as a refusal
	assert_eq(main.panel.status_label.get_theme_color("font_color"), UiColors.ERROR)
	main.panel.board.connect_requested.emit(FactoryGraph.SOURCE_ID, 0, FactoryGraph.OUTPUT_ID, 0)
	assert_true(run.can_start_wave())
	assert_false(main.panel.start_button.disabled)
	_key(main, KEY_ENTER)
	assert_eq(run.flow.state, GameFlow.State.PLAY)
	await wait_process_frames(2)


func test_space_starts_wave_and_locks_editor() -> void:
	var main: Main = _main()
	var run: RunState = main.run
	run.restart(SEED)
	var before: Dictionary = run.graph.to_dict()
	_key(main, KEY_SPACE)
	assert_eq(run.flow.state, GameFlow.State.PLAY)
	assert_same(run.active_plan, run.plan)
	assert_true(main.arena.is_running())
	assert_same(main.arena.world.plan, run.active_plan)
	assert_eq(main.arena.world.wave, 1)
	# seeded with this wave's seed: the same start in a fresh world gives the same state, rng included
	var fresh: ArenaWorld = ArenaWorld.new()
	fresh.begin_wave(1, run.active_plan, run.wave_seed(), run.player_hp)
	assert_eq(main.arena.world.state_hash(), fresh.state_hash())
	assert_eq([main.arena.hud.wave, main.arena.hud.running, main.arena.hud.banner_text], [1, true, "WAVE 1"])
	assert_eq(main.panel.board._lock_text, "LOCKED · WAVE 1 IN PROGRESS")
	assert_true(main.panel.board.interaction.locked)
	assert_true(main.panel.start_button.disabled)
	for slot: PaletteSlot in main.panel.slots:
		assert_true(slot.locked)
	var locked: String = GraphError.describe(GraphError.Code.LOCKED)
	watch_signals(main.panel.board)
	main.panel.board._gui_input(_press(Vector2(60, 220)))   # a board press on the Basic Bullet
	assert_signal_emitted_with_parameters(main.panel.board, "refused", [locked])
	assert_signal_not_emitted(main.panel.board, "move_requested")
	# requests that slip past the board are refused by the run and reported
	main.panel.board.disconnect_requested.emit(run.graph.wire_from(FactoryGraph.SOURCE_ID, 0))
	main.panel.board.place_requested.emit(MachineCatalog.FIRE, Vector2i(5, 1), null)
	assert_eq(run.graph.to_dict(), before)
	assert_eq(run.inventory.count(MachineCatalog.FIRE), 1)
	main.panel._process(0.0)
	assert_eq(main.panel.status_label.text, locked)
	assert_eq(main.panel.status_label.get_theme_color("font_color"), UiColors.ERROR)   # the run's refusal, in red
	main.arena.intent_override = PlayerIntent.make(Vector2.ZERO, Vector2(900, 450), true)
	for i: int in 30:
		main.arena.step(STEP)
	for key: Key in [KEY_SPACE, KEY_X, KEY_1, KEY_R, KEY_ESCAPE]:   # none of them restarts or ends the wave
		_key(main, key)
	assert_eq(run.flow.state, GameFlow.State.PLAY)
	assert_almost_eq(main.arena.world.time, 0.5, 1e-6)
	assert_eq(run.graph.to_dict(), before)
	await wait_process_frames(2)


func test_x_deletes_hovered_and_escape_cancels() -> void:
	var main: Main = _main()
	var run: RunState = main.run
	var board: FactoryBoard = main.panel.board
	board.place_requested.emit(MachineCatalog.FIRE, Vector2i(5, 1), null)
	assert_eq(run.inventory.count(MachineCatalog.FIRE), 0)
	board.interaction.motion(Vector2(240, 80))                       # hover Fire #3
	_key(main, KEY_X)
	assert_false(run.graph.has_machine(3))
	assert_eq(run.inventory.count(MachineCatalog.FIRE), 1)          # refunded
	board.interaction.press(Vector2(120, 240), MOUSE_BUTTON_LEFT)    # the Source's output: a wire drag
	assert_eq(board.interaction.mode, BoardInteraction.Mode.DRAG_WIRE)
	_key(main, KEY_ESCAPE)
	assert_eq(board.interaction.mode, BoardInteraction.Mode.IDLE)
	assert_eq(run.graph.machine_ids(), PackedInt32Array([1, 2]))
	assert_eq(run.graph.to_dict()["wires"], ["1:0>2:0"])            # the cancelled drag connected nothing
	await wait_process_frames(2)


## The board gets no motion once the mouse has left it, so leaving must drop the hover (E.5): X over the arena
## must not remove the machine the mouse was last over.
func test_leaving_the_board_drops_the_hover() -> void:
	await Mouse.prepare(self)
	var main: Main = _main()
	var run: RunState = main.run
	var board: FactoryBoard = main.panel.board
	board.place_requested.emit(MachineCatalog.FIRE, Vector2i(5, 1), null)
	Mouse.move(BOARD + Vector2(240, 80), BOARD + Vector2(240, 80), 0)   # onto Fire #3
	await wait_process_frames(1)
	assert_true(board.interaction.hover.same_as(BoardHit.make(BoardHit.Type.MACHINE, 3)))
	Mouse.move(Vector2(700, 450), BOARD + Vector2(240, 80), 0)          # over the arena in one motion
	await wait_process_frames(1)
	assert_eq(board.interaction.hover.type, BoardHit.Type.EMPTY)
	_key(main, KEY_X)
	assert_true(run.graph.has_machine(3))
	await wait_process_frames(2)


func test_full_loop_build_play_reward_build() -> void:
	var main: Main = _main()
	var run: RunState = main.run
	run.restart(SEED)
	# Fire spliced into the default belt: every shot should burn
	main.panel.board.place_requested.emit(MachineCatalog.FIRE, Vector2i(6, 5), run.graph.wire_from(FactoryGraph.SOURCE_ID, 0))
	assert_eq(run.graph.kind_of(3), MachineCatalog.FIRE)
	assert_eq(run.inventory.count(MachineCatalog.FIRE), 0)
	assert_eq(main.panel.slots[0].count, 0)
	assert_eq([run.plan.bullets.size(), run.plan.bullets[0].fire_level], [1, 1])
	assert_eq(main.panel.readout.label.text, "\n".join(run.plan.summary_lines()))
	run.player_hp = 60.0                      # start hurt, so the reward's heal shows
	main.panel.start_button.pressed.emit()
	assert_eq(run.flow.state, GameFlow.State.PLAY)
	assert_same(main.arena.world.plan, run.active_plan)
	assert_almost_eq(main.arena.world.player.hp, 60.0, 1e-4)
	main.arena.world.player.hp = 47.0         # hurt in the wave: the run must take the arena's HP, not keep its own
	watch_signals(main.arena)
	var burned: bool = false
	var steps: int = 0
	while run.flow.state == GameFlow.State.PLAY and steps < 5400:
		main.arena.intent_override = Bot.intent(main.arena.world)
		main.arena.step(STEP)
		steps += 1
		for e: EnemyState in main.arena.world.enemies:
			burned = burned or e.status.is_burning()
	assert_true(burned, "the compiled Fire reached the gun: enemies burned")
	assert_eq(run.flow.state, GameFlow.State.REWARD)
	assert_eq(run.total_kills, 6)             # wave 1 is 6 Grunts
	assert_eq(run.offers.size(), Tuning.OFFER_COUNT)
	var kinds: Array[StringName] = []
	for offer: RewardOffer in run.offers:
		kinds.append(offer.kind)
	assert_has(kinds, MachineCatalog.SPLITTER)
	assert_true(main.reward_overlay.visible)
	assert_false(main.game_over_overlay.visible)
	assert_eq(main.reward_overlay.offers, run.offers)
	assert_false(main.arena.is_running())
	assert_true(main.arena.world.bullets.is_empty(), "the arena went idle: no frozen last frame")
	assert_true(main.arena.view._fx.is_empty())
	assert_true(main.panel.board.interaction.locked)
	assert_eq(main.panel.board._lock_text, "CHOOSE A REWARD")
	assert_eq(main.reward_overlay._wave_cleared, 1)
	assert_true(main.panel.start_button.disabled)
	assert_signal_emit_count(main.arena, "wave_cleared", 1)
	var hp_left: float = get_signal_parameters(main.arena, "wave_cleared")[0]
	assert_between(hp_left, 1.0, 47.0)
	assert_almost_eq(run.player_hp, hp_left, 1e-4)
	await wait_process_frames(2)              # the reward screen draws
	var pick: RewardOffer = run.offers[0]
	var had: int = run.inventory.count(pick.kind)
	_key(main, KEY_1)
	assert_eq([run.flow.state, run.flow.wave], [GameFlow.State.BUILD, 2])
	assert_eq(run.inventory.count(pick.kind), had + pick.amount)
	assert_eq(main.panel.slots[MachineCatalog.palette_index(pick.kind)].count, had + pick.amount)
	assert_almost_eq(run.player_hp, hp_left + Tuning.HEAL_ON_REWARD, 1e-4)
	assert_almost_eq(main.arena.hud.hp, run.player_hp, 1e-4)
	assert_eq([main.arena.hud.wave, main.arena.hud.running], [2, false])
	assert_false(main.arena.is_running())
	assert_false(main.reward_overlay.visible)
	assert_false(main.panel.board.interaction.locked)
	assert_eq(main.panel.start_button.text, "START WAVE 2  [Space]")
	assert_false(main.panel.start_button.disabled)
	var stock: Dictionary = run.inventory.to_dict()
	_key(main, KEY_2)                         # no reward is up any more
	assert_eq(run.inventory.to_dict(), stock)
	await wait_process_frames(2)
	# wave 2 with the player idle: the run ends, and the result counts wave 1 and its kills
	_key(main, KEY_SPACE)
	assert_eq(main.panel.board._lock_text, "LOCKED · WAVE 2 IN PROGRESS")
	main.arena.intent_override = PlayerIntent.make(Vector2.ZERO, Vector2.ZERO, false)
	steps = 0
	while run.flow.state == GameFlow.State.PLAY and steps < 3600:
		main.arena.step(STEP)
		steps += 1
	assert_eq(run.flow.state, GameFlow.State.GAME_OVER)
	assert_eq(main.panel.board._lock_text, "GAME OVER")
	assert_eq(main.game_over_overlay.result_text, "Survived 1 wave · 6 kills")
	await wait_process_frames(2)


func test_death_then_restart() -> void:
	var main: Main = _main()
	var run: RunState = main.run
	run.restart(SEED)
	main.panel.board.place_requested.emit(MachineCatalog.SPEED_UP, Vector2i(5, 1), null)   # an edit the restart undoes
	assert_eq(run.graph.machine_ids(), PackedInt32Array([1, 2, 3]))
	_key(main, KEY_SPACE)
	main.arena.intent_override = PlayerIntent.make(Vector2.ZERO, Vector2.ZERO, false)
	var steps: int = 0
	while run.flow.state == GameFlow.State.PLAY and steps < 3600:
		main.arena.step(STEP)
		steps += 1
	assert_eq(run.flow.state, GameFlow.State.GAME_OVER)
	assert_true(main.game_over_overlay.visible)
	assert_false(main.reward_overlay.visible)
	assert_eq(main.game_over_overlay.result_text, "Survived 0 waves · 0 kills")
	assert_true(main.panel.board.interaction.locked)
	assert_true(main.panel.start_button.disabled)
	var world: ArenaWorld = main.arena.world
	assert_false(world.enemies.is_empty())    # frozen on the last frame, not reset
	var frozen: int = world.state_hash()
	main.arena.step(STEP)
	assert_eq(world.state_hash(), frozen)
	await wait_process_frames(2)
	for key: Key in [KEY_SPACE, KEY_1]:       # neither starts a wave nor picks anything now
		_key(main, key)
	assert_eq(run.flow.state, GameFlow.State.GAME_OVER)
	_key(main, KEY_R)
	assert_eq([run.flow.state, run.flow.wave, run.total_kills], [GameFlow.State.BUILD, 1, 0])
	assert_eq(run.graph.to_dict(), FactoryGraph.create_default().to_dict())
	assert_eq(run.inventory.to_dict(), Inventory.from_counts(Tuning.START_INVENTORY).to_dict())
	assert_almost_eq(run.player_hp, Tuning.PLAYER_MAX_HP, 1e-4)
	assert_false(main.game_over_overlay.visible)
	assert_false(main.panel.board.interaction.locked)
	assert_eq(main.panel.start_button.text, "START WAVE 1  [Space]")
	assert_false(main.panel.start_button.disabled)
	assert_false(main.arena.is_running())
	assert_true(world.enemies.is_empty())
	assert_almost_eq(world.player.hp, Tuning.PLAYER_MAX_HP, 1e-4)
	await wait_process_frames(2)
	# the overlay's Restart button does the same as R
	assert_true(run.start_wave())
	assert_true(run.fail_wave(0))
	assert_true(main.game_over_overlay.visible)
	main.game_over_overlay.restart_button.pressed.emit()
	assert_eq(run.flow.state, GameFlow.State.BUILD)
	assert_false(main.game_over_overlay.visible)


func test_real_mouse_builds_and_wires_a_burning_gun() -> void:
	await Mouse.prepare(self)
	var main: Main = _main()
	var run: RunState = main.run
	await Mouse.drag(self, SLOT_FIRE, BOARD + Vector2(280, 244))       # onto the default belt: a splice
	assert_eq(run.graph.kind_of(3), MachineCatalog.FIRE)
	assert_eq(run.graph.get_machine(3).cell, Vector2i(6, 5))
	assert_eq(run.inventory.count(MachineCatalog.FIRE), 0)
	await Mouse.drag(self, SLOT_SPEED, BOARD + Vector2(360, 80))       # Speed Up onto the empty cell (8, 1)
	assert_eq(run.graph.get_machine(4).cell, Vector2i(8, 1))
	await Mouse.drag(self, BOARD + Vector2(320, 240), BOARD + Vector2(322, 84))   # Fire's output -> Speed Up
	await Mouse.drag(self, BOARD + Vector2(400, 80), BOARD + Vector2(442, 238))   # Speed Up -> the Output
	assert_eq(run.graph.to_dict()["wires"], ["1:0>3:0", "3:0>4:0", "4:0>2:0"])
	var spec: BulletSpec = run.plan.bullets[0]
	assert_eq([run.plan.bullets.size(), spec.fire_level, spec.speed_level], [1, 1, 1])
	assert_eq(main.panel.readout.label.text.get_slice("\n", 1), "#1 " + spec.describe())
	await Mouse.drag(self, BOARD + Vector2(360, 80), BOARD + Vector2(360, 360))   # Speed Up down to (8, 8)
	assert_eq(run.graph.get_machine(4).cell, Vector2i(8, 8))
	assert_eq(run.graph.to_dict()["wires"], ["1:0>3:0", "3:0>4:0", "4:0>2:0"])   # its belts followed
	assert_eq(run.inventory.count(MachineCatalog.SPEED_UP), 0)
	await Mouse.click(self, BOARD + Vector2(360, 340), MOUSE_BUTTON_RIGHT)   # remove Speed Up: refund and heal
	assert_false(run.graph.has_machine(4))
	assert_eq(run.inventory.count(MachineCatalog.SPEED_UP), 1)
	assert_eq(run.graph.to_dict()["wires"], ["1:0>3:0", "3:0>2:0"])


## Main from its scene, as the game boots it. The arena is stepped by hand (I.2.6).
func _main() -> Main:
	var main: Main = MainScene.instantiate() as Main
	add_child_autofree(main)
	main.arena.set_physics_process(false)     # after _ready, which turned it on
	return main


func _key(main: Main, key: Key) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = key
	e.pressed = true
	main._unhandled_input(e)


func _press(at: Vector2) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	return e

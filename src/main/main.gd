class_name Main
extends Control
## The game's root (docs/DESIGN.md G.3): the factory panel on the left, the arena on the right and the
## overlays over the arena. Views only ask: Main turns each request into a RunState call, and _sync()
## brings every view in line with the run's state.

const PANEL_RECT: Rect2 = Rect2(0, 0, 600, 900)
const ARENA_RECT: Rect2 = Rect2(600, 0, 1000, 900)

var run: RunState = RunState.new(randi())   # randi() is allowed outside core/sim
var panel: FactoryPanel = FactoryPanel.new()
var arena: ArenaController = ArenaController.new()
var reward_overlay: RewardOverlay = RewardOverlay.new()
var game_over_overlay: GameOverOverlay = GameOverOverlay.new()


func _ready() -> void:
	InputSetup.ensure_actions()
	theme = FactoryTheme.build()
	_add(panel, PANEL_RECT)
	_add(arena, ARENA_RECT)
	_add(reward_overlay, ARENA_RECT)        # overlays after the arena: drawn on top
	_add(game_over_overlay, ARENA_RECT)
	panel.bind(run.graph, run.inventory)
	run.plan_changed.connect(_on_plan_changed)
	run.flow.state_changed.connect(_on_state_changed)
	panel.start_wave_requested.connect(_try_start_wave)
	panel.board.place_requested.connect(_on_place_requested)
	panel.board.move_requested.connect(_on_move_requested)
	panel.board.remove_requested.connect(_on_remove_requested)
	panel.board.connect_requested.connect(_on_connect_requested)
	panel.board.disconnect_requested.connect(_on_disconnect_requested)
	arena.wave_cleared.connect(_on_wave_cleared)
	arena.player_died.connect(_on_player_died)
	reward_overlay.offer_chosen.connect(_on_offer_chosen)
	game_over_overlay.restart_requested.connect(_on_restart)
	_sync(run.flow.state)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputSetup.START_WAVE):
		_try_start_wave()
	elif event.is_action_pressed(InputSetup.DELETE_HOVERED):
		panel.board.delete_hovered()
	elif event.is_action_pressed(InputSetup.CANCEL):
		panel.board.cancel_interaction()
	elif event.is_action_pressed(InputSetup.RESTART) and run.flow.state == GameFlow.State.GAME_OVER:
		run.restart(randi())
	else:
		for i: int in InputSetup.PICK.size():
			if event.is_action_pressed(InputSetup.PICK[i]) and run.flow.state == GameFlow.State.REWARD:
				reward_overlay.choose(i)


## Default anchors, so setting the size does not warn (A.4.5).
func _add(c: Control, rect: Rect2) -> void:
	add_child(c)
	c.position = rect.position
	c.size = rect.size


func _report(code: GraphError.Code) -> void:
	if code != GraphError.Code.OK:
		panel.show_message(GraphError.describe(code), true)


func _try_start_wave() -> void:
	if run.flow.state == GameFlow.State.BUILD and not run.start_wave():
		panel.show_message(run.start_reason(), true)


func _sync(state: GameFlow.State) -> void:
	var wave: int = run.flow.wave
	reward_overlay.visible = state == GameFlow.State.REWARD
	game_over_overlay.visible = state == GameFlow.State.GAME_OVER
	match state:
		GameFlow.State.BUILD:
			panel.set_locked(false, "")
			arena.go_idle(run.player_hp, wave)
		GameFlow.State.PLAY:
			panel.set_locked(true, "LOCKED · WAVE %d IN PROGRESS" % wave)
			arena.start_wave(wave, run.active_plan, run.wave_seed(), run.player_hp)
		GameFlow.State.REWARD:
			panel.set_locked(true, "CHOOSE A REWARD")
			arena.go_idle(run.player_hp, wave)
			reward_overlay.show_offers(run.offers, wave)
		GameFlow.State.GAME_OVER:
			panel.set_locked(true, "GAME OVER")   # the arena stays frozen on its last frame
			game_over_overlay.show_result(wave - 1, run.total_kills)
	panel.set_plan(run.plan)
	panel.set_start_state(wave, run.can_start_wave(), run.start_reason())


func _on_plan_changed(plan: ShotPlan) -> void:
	panel.set_plan(plan)
	panel.set_start_state(run.flow.wave, run.can_start_wave(), run.start_reason())


func _on_state_changed(_previous: GameFlow.State, current: GameFlow.State) -> void:
	_sync(current)


func _on_place_requested(kind: StringName, cell: Vector2i, splice: Wire) -> void:
	_report(run.try_place_machine(kind, cell, splice))


func _on_move_requested(machine_id: int, cell: Vector2i) -> void:
	_report(run.try_move_machine(machine_id, cell))


func _on_remove_requested(machine_id: int) -> void:
	_report(run.try_remove_machine(machine_id))


func _on_connect_requested(from_id: int, from_port: int, to_id: int, to_port: int) -> void:
	_report(run.try_connect(from_id, from_port, to_id, to_port))


func _on_disconnect_requested(wire: Wire) -> void:
	_report(run.try_disconnect(wire))


func _on_wave_cleared(hp_left: float, kills: int) -> void:
	run.complete_wave(hp_left, kills)


func _on_player_died(kills: int) -> void:
	run.fail_wave(kills)


func _on_offer_chosen(index: int) -> void:
	run.choose_offer(index)


func _on_restart() -> void:
	run.restart(randi())

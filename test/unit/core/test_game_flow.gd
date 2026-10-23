extends GutTest

var _flow: GameFlow = null
var _waves_seen: Array[int] = []


func test_happy_path_and_wave_counter() -> void:
	var flow: GameFlow = GameFlow.new()
	_assert_at(flow, GameFlow.State.BUILD, 1)
	assert_true(flow.is_editing_allowed())
	watch_signals(flow)
	_flow = flow
	flow.state_changed.connect(_record_wave)
	assert_true(flow.start_wave())
	_assert_at(flow, GameFlow.State.PLAY, 1)
	assert_false(flow.is_editing_allowed())
	assert_signal_emitted_with_parameters(flow, "state_changed", [GameFlow.State.BUILD, GameFlow.State.PLAY])
	assert_true(flow.clear_wave())
	_assert_at(flow, GameFlow.State.REWARD, 1)                     # the wave just cleared
	assert_false(flow.is_editing_allowed())
	assert_signal_emitted_with_parameters(flow, "state_changed", [GameFlow.State.PLAY, GameFlow.State.REWARD])
	assert_true(flow.finish_reward())
	_assert_at(flow, GameFlow.State.BUILD, 2)
	assert_true(flow.is_editing_allowed())
	assert_signal_emitted_with_parameters(flow, "state_changed", [GameFlow.State.REWARD, GameFlow.State.BUILD])
	assert_eq(_waves_seen, [1, 1, 2])                              # listeners already see the next wave
	assert_true(flow.start_wave())
	assert_true(flow.clear_wave())
	assert_true(flow.finish_reward())
	assert_true(flow.start_wave())
	_assert_at(flow, GameFlow.State.PLAY, 3)
	assert_true(flow.lose())
	_assert_at(flow, GameFlow.State.GAME_OVER, 3)
	assert_false(flow.is_editing_allowed())
	assert_signal_emitted_with_parameters(flow, "state_changed", [GameFlow.State.PLAY, GameFlow.State.GAME_OVER])
	assert_signal_emit_count(flow, "state_changed", 8)
	flow.state_changed.disconnect(_record_wave)
	_flow = null


func test_illegal_transitions_return_false_without_signal() -> void:
	var flow: GameFlow = GameFlow.new()
	watch_signals(flow)
	assert_false(flow.clear_wave())
	assert_false(flow.lose())
	assert_false(flow.finish_reward())
	_assert_at(flow, GameFlow.State.BUILD, 1)
	assert_true(flow.start_wave())
	assert_false(flow.start_wave())
	assert_false(flow.finish_reward())
	_assert_at(flow, GameFlow.State.PLAY, 1)
	assert_true(flow.clear_wave())
	assert_false(flow.start_wave())
	assert_false(flow.clear_wave())
	assert_false(flow.lose())
	_assert_at(flow, GameFlow.State.REWARD, 1)
	assert_true(flow.finish_reward())
	assert_true(flow.start_wave())
	assert_true(flow.lose())
	assert_false(flow.start_wave())
	assert_false(flow.clear_wave())
	assert_false(flow.lose())
	assert_false(flow.finish_reward())
	_assert_at(flow, GameFlow.State.GAME_OVER, 2)
	assert_signal_emit_count(flow, "state_changed", 5)             # the five legal moves only


func test_restart_always_emits() -> void:
	var flow: GameFlow = GameFlow.new()
	watch_signals(flow)
	flow.restart()                                                 # already in BUILD: views still reset
	assert_signal_emit_count(flow, "state_changed", 1)
	assert_signal_emitted_with_parameters(flow, "state_changed", [GameFlow.State.BUILD, GameFlow.State.BUILD])
	_assert_at(flow, GameFlow.State.BUILD, 1)
	assert_true(flow.start_wave())
	assert_true(flow.clear_wave())
	assert_true(flow.finish_reward())
	assert_true(flow.start_wave())
	assert_true(flow.lose())
	_assert_at(flow, GameFlow.State.GAME_OVER, 2)
	flow.restart()
	assert_signal_emitted_with_parameters(flow, "state_changed", [GameFlow.State.GAME_OVER, GameFlow.State.BUILD])
	_assert_at(flow, GameFlow.State.BUILD, 1)
	assert_true(flow.start_wave())
	flow.restart()
	assert_signal_emitted_with_parameters(flow, "state_changed", [GameFlow.State.PLAY, GameFlow.State.BUILD])
	assert_true(flow.start_wave())
	assert_true(flow.clear_wave())
	flow.restart()
	assert_signal_emitted_with_parameters(flow, "state_changed", [GameFlow.State.REWARD, GameFlow.State.BUILD])
	_assert_at(flow, GameFlow.State.BUILD, 1)
	assert_signal_emit_count(flow, "state_changed", 12)


func _assert_at(flow: GameFlow, state: GameFlow.State, wave: int) -> void:
	assert_eq(flow.state, state, "state")
	assert_eq(flow.wave, wave, "wave")


func _record_wave(_previous: GameFlow.State, _current: GameFlow.State) -> void:
	_waves_seen.append(_flow.wave)

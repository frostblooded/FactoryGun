class_name GameFlow
extends RefCounted
## The phase of the run (docs/DESIGN.md G.1), driven only through RunState:
## BUILD -> PLAY -> REWARD -> BUILD (next wave), or PLAY -> GAME_OVER -> restart -> BUILD (wave 1).
## A transition that does not start from its expected state returns false and emits nothing.

signal state_changed(previous: State, current: State)

enum State { BUILD, PLAY, REWARD, GAME_OVER }

var state: State = State.BUILD
var wave: int = 1                         # the wave being built for, played, or just cleared (1-based)


func is_editing_allowed() -> bool:
	return state == State.BUILD


func start_wave() -> bool:
	return _go(State.BUILD, State.PLAY)


func clear_wave() -> bool:
	return _go(State.PLAY, State.REWARD)


func lose() -> bool:
	return _go(State.PLAY, State.GAME_OVER)


## The wave counter moves on before state_changed, so listeners already see the next wave.
func finish_reward() -> bool:
	if state != State.REWARD:
		return false
	wave += 1
	return _go(State.REWARD, State.BUILD)


## From any state, and it always emits, even from BUILD, so views reset.
func restart() -> void:
	var previous: State = state
	state = State.BUILD
	wave = 1
	state_changed.emit(previous, state)


func _go(from: State, to: State) -> bool:
	if state != from:
		return false
	state = to
	state_changed.emit(from, to)
	return true

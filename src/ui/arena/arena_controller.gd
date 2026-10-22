class_name ArenaController
extends Control
## Glue between engine input, the pure ArenaWorld and the views.

signal wave_cleared(hp_left: float, kills: int)
signal player_died(kills: int)

var world: ArenaWorld = ArenaWorld.new()
var view: ArenaView                       # child, mouse IGNORE, view.world = world
var hud: Hud                              # child, mouse IGNORE
var intent_override: PlayerIntent = null  # tests set this instead of real input


func _init() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_PASS
	mouse_default_cursor_shape = CURSOR_CROSS
	view = ArenaView.new()
	view.world = world
	hud = Hud.new()
	# Full-rect children follow this control's size; setting their size would warn (A.4.5).
	for child: Control in [view, hud]:
		child.mouse_filter = MOUSE_FILTER_IGNORE
		child.set_anchors_preset(PRESET_FULL_RECT)
		add_child(child)


func _physics_process(delta: float) -> void:
	step(delta)


func start_wave(wave: int, plan: ShotPlan, wave_seed: int, hp: float) -> void:
	world.begin_wave(wave, plan, wave_seed, hp)
	view.clear_fx()
	hud.set_wave(wave, true)
	hud.set_stats(hp, world.enemies_remaining())
	hud.show_banner("WAVE %d" % wave)


func go_idle(hp: float, next_wave: int) -> void:
	world.reset_idle(hp)
	view.clear_fx()
	hud.set_wave(next_wave, false)
	hud.set_stats(hp, 0)


func is_running() -> bool:
	return world.is_running()


func step(delta: float) -> void:
	if not world.is_running():
		return
	var intent: PlayerIntent = intent_override if intent_override != null else _read_intent()
	view.add_events(world.step(delta, intent))
	hud.set_stats(world.player.hp, world.enemies_remaining())
	if world.is_finished():               # emitting is the LAST statement: handlers may call go_idle()
		if world.player.hp <= 0.0:
			player_died.emit(world.kills)
		else:
			wave_cleared.emit(world.player.hp, world.kills)


func _read_intent() -> PlayerIntent:
	var aim: Vector2 = get_local_mouse_position()
	# Fire only over the arena, so clicking the locked editor never shoots.
	var fire: bool = Input.is_action_pressed(InputSetup.FIRE) and Rect2(Vector2.ZERO, size).has_point(aim)
	return PlayerIntent.make(Input.get_vector(InputSetup.MOVE_LEFT, InputSetup.MOVE_RIGHT,
			InputSetup.MOVE_UP, InputSetup.MOVE_DOWN), aim, fire)

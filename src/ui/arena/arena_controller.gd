class_name ArenaController
extends Control
## Glue between engine input, the pure ArenaWorld and the views. It fills the screen: the arena is scaled to fit
## the middle, with the HUD on the wings either side, and a finger anywhere drives the move stick.

signal wave_cleared(hp_left: float, kills: int)
signal player_died(kills: int)

const WING_MIN: float = 260.0             # each side keeps at least this much for the HUD

var world: ArenaWorld = ArenaWorld.new()
var view: ArenaView                       # child, mouse IGNORE, view.world = world
var hud: Hud                              # child, mouse IGNORE
var stick: TouchStick                     # child, mouse IGNORE, over the HUD
var intent_override: PlayerIntent = null  # tests set this instead of real input


func _init() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_PASS
	view = ArenaView.new()
	view.world = world
	hud = Hud.new()
	stick = TouchStick.new()
	view.size = SimTuning.ARENA_SIZE      # placed and scaled by _layout()
	# Full-rect children follow this control's size; setting their size would warn (A.4.5).
	for child: Control in [view, hud, stick]:
		child.mouse_filter = MOUSE_FILTER_IGNORE
		if child != view:
			child.set_anchors_preset(PRESET_FULL_RECT)
		add_child(child)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and view != null:
		_layout()


## The wings' backdrop, under the children.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiColors.PANEL_BG)


func _physics_process(delta: float) -> void:
	step(delta)


## Touches, not emulated mouse events, drive the stick, so a second finger cannot steal it. A finger lands on it
## only during a wave, so tapping a reward card or Restart never shows it.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = make_input_local(event)
		if not touch.pressed:
			stick.release(touch.index)
		elif world.is_running() and Rect2(Vector2.ZERO, size).has_point(touch.position):
			stick.press(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var touch_drag: InputEventScreenDrag = make_input_local(event)
		stick.drag(touch_drag.index, touch_drag.position)


func start_wave(wave: int, plan: ShotPlan, wave_seed: int, hp: float) -> void:
	world.begin_wave(wave, plan, wave_seed, hp)
	stick.reset()
	view.clear_fx()
	hud.set_wave(wave, true)
	hud.set_stats(hp, world.enemies_remaining())
	hud.show_banner("WAVE %d" % wave)


func go_idle(hp: float, next_wave: int) -> void:
	world.reset_idle(hp)
	stick.reset()
	view.clear_fx()
	hud.set_wave(next_wave, false)
	hud.set_stats(hp, 0)


## Controller-local: where the arena is drawn.
func arena_rect() -> Rect2:
	var s: float = arena_scale()
	var drawn: Vector2 = SimTuning.ARENA_SIZE * s
	return Rect2(((size - drawn) / 2.0).round(), drawn)


## As big as fits the height, leaving WING_MIN either side.
func arena_scale() -> float:
	var arena: Vector2 = SimTuning.ARENA_SIZE
	return maxf(minf(size.y / arena.y, (size.x - 2.0 * WING_MIN) / arena.x), 0.1)


func is_running() -> bool:
	return world.is_running()


func _layout() -> void:
	var r: Rect2 = arena_rect()
	view.position = r.position
	view.scale = Vector2.ONE * arena_scale()
	hud.arena = r
	hud.queue_redraw()


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


## The gun aims at the nearest enemy and fires whenever there is one; the player only moves (F.8).
func _read_intent() -> PlayerIntent:
	var move: Vector2 = Input.get_vector(InputSetup.MOVE_LEFT, InputSetup.MOVE_RIGHT, InputSetup.MOVE_UP,
			InputSetup.MOVE_DOWN) + stick.vector()
	var target: EnemyState = world.nearest_enemy()
	if target == null:
		return PlayerIntent.make(move, world.player.pos + world.player.aim_dir, false)
	return PlayerIntent.make(move, target.pos, true)

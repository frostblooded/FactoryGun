class_name TouchStick
extends Control
## The floating move stick (docs/DESIGN.md F.8). A finger that lands in the arena during a wave becomes its
## centre; dragging away from it moves the player. Only that finger drives it until it lifts. Draws itself.

const RADIUS: float = 70.0                # a drag this far from the centre is full speed
const KNOB_RADIUS: float = 26.0

var touch_index: int = -1                 # the finger driving the stick, or -1
var origin: Vector2 = Vector2.ZERO
var knob: Vector2 = Vector2.ZERO          # within RADIUS of origin


func _draw() -> void:
	if not is_active():
		return
	draw_circle(origin, RADIUS, Color(UiColors.PANEL_BG, 0.35))
	draw_arc(origin, RADIUS, 0.0, TAU, 48, Color(UiColors.TEXT, 0.4), 2.0)
	draw_circle(knob, KNOB_RADIUS, Color(UiColors.ACCENT, 0.6))


func is_active() -> bool:
	return touch_index != -1


## Ignored while another finger drives the stick.
func press(index: int, p: Vector2) -> void:
	if is_active():
		return
	touch_index = index
	origin = p
	knob = p
	queue_redraw()


func drag(index: int, p: Vector2) -> void:
	if index != touch_index:
		return
	knob = origin + (p - origin).limit_length(RADIUS)
	queue_redraw()


func release(index: int) -> void:
	if index == touch_index:
		reset()


func reset() -> void:
	touch_index = -1
	queue_redraw()


## Length 0 to 1, pointing from the centre to the knob.
func vector() -> Vector2:
	return (knob - origin) / RADIUS if is_active() else Vector2.ZERO

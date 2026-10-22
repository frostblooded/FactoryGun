class_name ShotReadout
extends Control
## What one trigger pull fires (docs/DESIGN.md E.7): the plan's summary lines and a fan diagram.

const READOUT_SIZE: Vector2 = Vector2(560, 214)
const FAN_BOX: Rect2 = Rect2(432, 45, 120, 120)
const FAN_ORIGIN: Vector2 = Vector2(10, 60)   # inside FAN_BOX
const RAY_LENGTH: float = 100.0

var label: Label
var _plan: ShotPlan = ShotPlan.empty()


func _init() -> void:
	size = READOUT_SIZE
	label = Label.new()
	label.position = Vector2(8, 6)
	label.size = Vector2(420, 204)
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 12)
	# 12 lines at the default spacing (3) need 237 px; with 0 they fill the 204 px label exactly.
	label.add_theme_constant_override("line_spacing", 0)
	add_child(label)
	set_plan(_plan)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiColors.STEEL_DARK)
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), UiColors.PANEL_EDGE, false, 2.0)
	draw_rect(FAN_BOX, UiColors.PANEL_EDGE, false, 1.0)
	draw_string(get_theme_default_font(), FAN_BOX.position + Vector2(0, -6), "FAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			UiColors.TEXT_DIM)
	var origin: Vector2 = FAN_BOX.position + FAN_ORIGIN
	for spec: BulletSpec in _plan.bullets:
		var tip: Vector2 = origin + Vector2.RIGHT.rotated(spec.angle_offset) * RAY_LENGTH
		draw_line(origin, tip, spec.primary_color(), 2.0)
		draw_circle(tip, clampf(spec.radius, 3.0, 10.0), spec.primary_color())


func set_plan(plan: ShotPlan) -> void:
	_plan = plan
	label.text = "\n".join(plan.summary_lines())
	queue_redraw()

class_name ShotReadout
extends Control
## What one trigger pull fires (docs/DESIGN.md E.7): a fan diagram over the plan's summary lines.

const READOUT_SIZE: Vector2 = Vector2(340, 440)
const FAN_BOX: Rect2 = Rect2(12, 12, 316, 124)
const FAN_ORIGIN: Vector2 = Vector2(24, 62)   # inside FAN_BOX
const RAY_LENGTH: float = 104.0
const FONT_SIZE: int = 17

var label: Label
var _plan: ShotPlan = ShotPlan.empty()


func _init() -> void:
	size = READOUT_SIZE
	label = Label.new()
	label.position = Vector2(14, 146)
	label.size = Vector2(312, 288)
	label.clip_text = true                # a long plan wraps past the box's bottom; the first lines matter most
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_constant_override("line_spacing", 0)
	add_child(label)
	set_plan(_plan)


func _draw() -> void:
	draw_style_box(FactoryTheme.box(UiColors.STEEL_DARK, UiColors.PANEL_EDGE, FactoryTheme.BORDER),
			Rect2(Vector2.ZERO, size))
	draw_rect(FAN_BOX, UiColors.OUTLINE)
	draw_string(get_theme_default_font(), FAN_BOX.position + Vector2(FAN_BOX.size.x - 120, 26), "YOUR GUN",
			HORIZONTAL_ALIGNMENT_RIGHT, 110, 18, UiColors.TEXT_DIM)
	var origin: Vector2 = FAN_BOX.position + FAN_ORIGIN
	for spec: BulletSpec in _plan.bullets:
		var tip: Vector2 = origin + Vector2.RIGHT.rotated(spec.angle_offset) * RAY_LENGTH
		draw_line(origin, tip, spec.primary_color(), 4.0)
		draw_circle(tip, clampf(spec.radius * 1.5, 5.0, 14.0), spec.primary_color())


func set_plan(plan: ShotPlan) -> void:
	_plan = plan
	label.text = "\n".join(plan.summary_lines())
	queue_redraw()

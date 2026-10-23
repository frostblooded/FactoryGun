class_name TrashBin
extends Control
## The drop target for removing a machine (docs/DESIGN.md E.10). A machine released anywhere off the floor is
## removed (E.4); the bin makes that visible. It lights up while a removable machine is dragged, and fills when
## the drag is over it. It takes no input of its own. Draws itself.

const BIN_SIZE: Vector2 = Vector2(150, 36)

var armed: bool = false                   # a removable machine is being dragged
var hot: bool = false                     # ...and is over the bin


func _init() -> void:
	size = BIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var box: Rect2 = Rect2(Vector2.ZERO, BIN_SIZE)
	var ink: Color = UiColors.ERROR if armed else UiColors.TEXT_DIM
	draw_rect(box, Color(UiColors.ERROR, 0.35) if hot else UiColors.STEEL_DARK)
	draw_rect(box.grow(-1.0), ink, false, 2.0)
	# A bin: lid, handle and a tapered body with two ribs.
	var c: Vector2 = Vector2(22, 18)
	draw_line(c + Vector2(-9, -8), c + Vector2(9, -8), ink, 2.0)
	draw_line(c + Vector2(-3, -11), c + Vector2(3, -11), ink, 2.0)
	draw_polyline(PackedVector2Array([c + Vector2(-7, -5), c + Vector2(-5, 10), c + Vector2(5, 10),
			c + Vector2(7, -5)]), ink, 2.0)
	draw_line(c + Vector2(-2, -2), c + Vector2(-2, 7), ink, 1.5)
	draw_line(c + Vector2(2, -2), c + Vector2(2, 7), ink, 1.5)
	draw_string(get_theme_default_font(), Vector2(38, 23), "DROP TO REMOVE" if armed else "REMOVE",
			HORIZONTAL_ALIGNMENT_LEFT, BIN_SIZE.x - 42, 12, ink)


func set_state(p_armed: bool, p_hot: bool) -> void:
	if p_armed == armed and p_hot == hot:
		return
	armed = p_armed
	hot = p_hot
	queue_redraw()

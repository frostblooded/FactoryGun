class_name TrashBin
extends Control
## The drop target for removing a machine (docs/DESIGN.md E.10), a tile at the end of the palette. A machine
## released anywhere off the floor is removed (E.4); the bin makes that visible. It lights up while a removable
## machine is dragged, and fills when the drag is over it. It takes no input of its own. Draws itself.

const BIN_SIZE: Vector2 = PaletteSlot.SLOT_SIZE

var armed: bool = false                   # a removable machine is being dragged
var hot: bool = false                     # ...and is over the bin


func _init() -> void:
	size = BIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var box: Rect2 = Rect2(Vector2.ZERO, BIN_SIZE)
	var ink: Color = UiColors.ERROR if armed else UiColors.TEXT_DIM
	var bg: Color = Color(UiColors.ERROR, 0.45) if hot else (Color(UiColors.ERROR, 0.15) if armed else UiColors.STEEL_DARK)
	draw_style_box(FactoryTheme.box(bg, ink if armed else UiColors.TILE_LIP, FactoryTheme.LIP), box)
	# A bin: lid, handle and a tapered body with two ribs.
	var c: Vector2 = Vector2(BIN_SIZE.x / 2, 66)
	draw_line(c + Vector2(-26, -24), c + Vector2(26, -24), ink, 5.0)
	draw_line(c + Vector2(-9, -32), c + Vector2(9, -32), ink, 5.0)
	draw_polyline(PackedVector2Array([c + Vector2(-20, -15), c + Vector2(-14, 30), c + Vector2(14, 30),
			c + Vector2(20, -15)]), ink, 5.0)
	draw_line(c + Vector2(-6, -6), c + Vector2(-5, 21), ink, 4.0)
	draw_line(c + Vector2(6, -6), c + Vector2(5, 21), ink, 4.0)
	draw_string(get_theme_default_font(), Vector2(0, 136), "DROP!" if hot else "REMOVE",
			HORIZONTAL_ALIGNMENT_CENTER, BIN_SIZE.x, 22, ink)


func set_state(p_armed: bool, p_hot: bool) -> void:
	if p_armed == armed and p_hot == hot:
		return
	armed = p_armed
	hot = p_hot
	queue_redraw()

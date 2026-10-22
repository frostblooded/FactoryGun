class_name PaletteSlot
extends Control
## One palette entry (docs/DESIGN.md E.6). Dragging it onto the board places that machine.

const SLOT_SIZE: Vector2 = Vector2(72, 88)
const ICON_CENTRE: Vector2 = Vector2(36, 30)
const ICON_SIZE: float = 14.0

var kind: StringName
var count: int = 0
var ever_owned: bool = false
var locked: bool = false


func _init() -> void:
	size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _get_drag_data(_at: Vector2) -> Variant:
	if not can_drag():
		return null
	# set_drag_preview errors outside a real drag, and get_viewport() is null off-tree (direct test calls)
	if is_inside_tree() and get_viewport().gui_is_dragging():
		set_drag_preview(MachineGhost.make(kind))
	return make_drag_data()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, SLOT_SIZE), UiColors.STEEL_DARK)
	draw_rect(Rect2(Vector2.ONE, SLOT_SIZE - Vector2(2, 2)), UiColors.PANEL_EDGE, false, 2.0)
	if not ever_owned:
		draw_string(font, Vector2(0, 42), "?", HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE.x, 32, UiColors.TEXT_DIM)
		draw_string(font, Vector2(0, 70), "???", HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE.x, 12, UiColors.TEXT_DIM)
		return
	MachinePainter.draw_icon(self, kind, ICON_CENTRE, ICON_SIZE, 1.0 if count > 0 else 0.35, 0.0)
	draw_string(font, Vector2(0, 62), MachineCatalog.get_def(kind).short_name, HORIZONTAL_ALIGNMENT_CENTER,
			SLOT_SIZE.x, 11, UiColors.TEXT)
	draw_string(font, Vector2(0, 80), "×%d" % count, HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE.x, 13,
			UiColors.ACCENT if count > 0 else UiColors.TEXT_DIM)


func setup(p_kind: StringName) -> void:
	kind = p_kind
	set_state(count, ever_owned, locked)


## Also sets the cursor shape and the tooltip.
func set_state(p_count: int, p_ever_owned: bool, p_locked: bool) -> void:
	count = p_count
	ever_owned = p_ever_owned
	locked = p_locked
	mouse_default_cursor_shape = Control.CURSOR_DRAG if can_drag() else Control.CURSOR_ARROW
	var def: MachineDef = MachineCatalog.get_def(kind)
	if ever_owned:
		tooltip_text = def.display_name + "\n" + def.description
	else:
		tooltip_text = "Not found yet. Clear waves to earn new machines."
	queue_redraw()


func can_drag() -> bool:
	return not locked and count > 0


func make_drag_data() -> Dictionary:
	return {"type": FactoryBoard.DRAG_TYPE, "kind": kind}

class_name PaletteSlot
extends Control
## One palette entry (docs/DESIGN.md E.6): a big tile. Tap it to pick the machine up, then tap the floor to place
## it; or drag it onto the board. Draws itself.

signal tapped(kind: StringName)

const SLOT_SIZE: Vector2 = Vector2(142, 172)
const ICON_CENTRE: Vector2 = Vector2(71, 66)
const ICON_SIZE: float = 26.0
const TAP_SLOP: float = 16.0              # a press that moves further than this is a drag, not a tap

var kind: StringName
var count: int = 0
var ever_owned: bool = false
var locked: bool = false
var armed: bool = false                   # picked up by a tap: the next floor tap places it
var ghost_scale: float = 1.0              # the board's scale, so the drag preview matches the board
var _press_at: Vector2 = Vector2.ZERO
var _pressed: bool = false


func _init() -> void:
	size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_pressed = true
			_press_at = button.position
		elif _pressed:
			_pressed = false
			if button.position.distance_to(_press_at) <= TAP_SLOP and Rect2(Vector2.ZERO, size).has_point(button.position):
				tapped.emit(kind)


func _get_drag_data(_at: Vector2) -> Variant:
	_pressed = false
	if not can_drag():
		return null
	# set_drag_preview errors outside a real drag, and get_viewport() is null off-tree (direct test calls)
	if is_inside_tree() and get_viewport().gui_is_dragging():
		var ghost: MachineGhost = MachineGhost.make(kind)
		ghost.scale = Vector2.ONE * ghost_scale
		set_drag_preview(ghost)
	return make_drag_data()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var tile: Rect2 = Rect2(Vector2.ZERO, SLOT_SIZE)
	var lit: bool = armed and can_drag()
	var bg: Color = UiColors.TILE_BG if ever_owned and count > 0 and not locked else UiColors.STEEL_DARK
	draw_style_box(FactoryTheme.box(Color(UiColors.ACCENT, 0.3) if lit else bg,
			UiColors.HAZARD if lit else UiColors.TILE_LIP, FactoryTheme.LIP), tile)
	if not ever_owned:
		draw_string(font, Vector2(0, 92), "?", HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE.x, 64, UiColors.TEXT_DIM)
		draw_string(font, Vector2(0, 138), "LOCKED", HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE.x, 20, UiColors.TEXT_DIM)
		return
	MachinePainter.draw_icon(self, kind, ICON_CENTRE, ICON_SIZE, 1.0 if count > 0 else 0.35, 0.0)
	draw_string(font, Vector2(0, 128), MachineCatalog.get_def(kind).short_name, HORIZONTAL_ALIGNMENT_CENTER,
			SLOT_SIZE.x, 22, UiColors.TEXT if count > 0 else UiColors.TEXT_DIM)
	# the count badge, top right
	var badge: Rect2 = Rect2(SLOT_SIZE.x - 54, 8, 46, 34)
	draw_style_box(_badge(count > 0), badge)
	draw_string(font, badge.position + Vector2(0, 26), "×%d" % count, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 22,
			UiColors.INK if count > 0 else UiColors.TEXT_DIM)


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


func set_armed(value: bool) -> void:
	if value != armed:
		armed = value
		queue_redraw()


func can_drag() -> bool:
	return not locked and count > 0


func make_drag_data() -> Dictionary:
	return {"type": FactoryBoard.DRAG_TYPE, "kind": kind}


static func _badge(full: bool) -> StyleBoxFlat:
	var b: StyleBoxFlat = StyleBoxFlat.new()
	b.bg_color = UiColors.HAZARD if full else UiColors.STEEL_DARK
	b.set_corner_radius_all(10)
	return b

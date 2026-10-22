class_name FactoryBoard
extends Control
## The factory floor editor (docs/DESIGN.md E.2, E.5). It never mutates the model: every gesture becomes a
## *_requested signal, or refused(reason).

signal place_requested(kind: StringName, cell: Vector2i, splice: Wire)   # splice may be null
signal move_requested(machine_id: int, cell: Vector2i)
signal remove_requested(machine_id: int)
signal connect_requested(from_id: int, from_port: int, to_id: int, to_port: int)
signal disconnect_requested(wire: Wire)
signal refused(reason: String)

const DRAG_TYPE: String = "factorygun.machine"
const BELT_SPEED_BUILD: float = 40.0
const BELT_SPEED_PLAY: float = 100.0
const REASON_FONT_SIZE: int = 12
const HAZARD_BAND: float = 14.0

var interaction: BoardInteraction = BoardInteraction.new()
var _plan: ShotPlan = ShotPlan.empty()
var _lock_text: String = ""
var _scroll: float = 0.0                  # how far live belts have moved, px
var _icon_time: float = 0.0
var _drop: DropPreview = null             # the palette drag hovering the board, drawn as a ghost
var _drop_at: Vector2 = Vector2.ZERO


func _init() -> void:
	size = BoardLayout.bounds().size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var floor_layer: FloorLayer = FloorLayer.new()
	floor_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(floor_layer)
	mouse_exited.connect(_on_mouse_exited)


func _process(delta: float) -> void:
	_scroll += delta * (BELT_SPEED_PLAY if interaction.locked else BELT_SPEED_BUILD)
	_icon_time += delta
	if _drop != null and (not get_viewport().gui_is_dragging()
			or not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())):
		_drop = null
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed:
			_apply(interaction.press(button.position, button.button_index))
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_apply(interaction.release(button.position))
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		interaction.motion(motion.position)


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("type") == DRAG_TYPE):
		return false
	var drag: Dictionary = data
	_drop = interaction.drop_preview(drag["kind"], at)
	_drop_at = at
	return true


func _drop_data(at: Vector2, data: Variant) -> void:
	var drag: Dictionary = data
	_drop = null
	_apply(interaction.drop(drag["kind"], at))


func _draw() -> void:
	var graph: FactoryGraph = interaction.graph
	var hover: BoardHit = interaction.hover
	for w: Wire in graph.wires():
		var live: bool = _plan.is_live_wire(w)
		var lit: bool = (hover.type == BoardHit.Type.BELT and hover.wire.same_as(w)) \
				or (_drop != null and _drop.splice != null and _drop.splice.same_as(w))
		var colors: Array[Color] = []
		for spec: BulletSpec in _plan.streams_on(w):
			colors.append(spec.primary_color())
		BeltPainter.draw_belt(self, BoardLayout.belt_points(graph, w), live, _scroll if live else 0.0, colors, lit)
	var dragged: int = interaction.drag_id if interaction.mode == BoardInteraction.Mode.DRAG_MACHINE else -1
	for id: int in graph.machine_ids():
		var rect: Rect2 = BoardLayout.machine_rect(graph, id)
		MachinePainter.draw_machine(self, graph.kind_of(id), rect, id, _plan.status_of(id),
				0.35 if id == dragged else 1.0, _icon_time)
	if hover.type == BoardHit.Type.MACHINE or (hover.type == BoardHit.Type.PORT and not hover.port.is_output):
		draw_rect(BoardLayout.machine_rect(graph, hover.machine_id).grow(-1.0), UiColors.ACCENT, false, 2.0)
	elif hover.type == BoardHit.Type.PORT:
		draw_arc(BoardLayout.port_anchor(graph, hover.port) - Vector2(5, 0), 8.0, 0.0, TAU, 20, UiColors.ACCENT, 2.0)
	_draw_gesture()
	if interaction.locked:
		_draw_lock()


func bind(graph: FactoryGraph, inventory: Inventory) -> void:
	interaction.bind(graph, inventory)
	graph.changed.connect(_on_graph_changed)


func set_plan(plan: ShotPlan) -> void:
	_plan = plan
	queue_redraw()


func set_locked(locked: bool, text: String) -> void:
	interaction.set_locked(locked)
	_lock_text = text
	if locked and is_inside_tree() and get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	queue_redraw()


func cancel_interaction() -> void:
	interaction.cancel()
	queue_redraw()


## The Delete / X key: a right-click on whatever is hovered.
func delete_hovered() -> void:
	if interaction.mode == BoardInteraction.Mode.IDLE:
		_apply(interaction.secondary(interaction.hover))


func _apply(action: BoardAction) -> void:
	match action.type:
		BoardAction.Type.PLACE:
			place_requested.emit(action.kind, action.cell, action.splice)
		BoardAction.Type.MOVE:
			move_requested.emit(action.machine_id, action.cell)
		BoardAction.Type.REMOVE:
			remove_requested.emit(action.machine_id)
		BoardAction.Type.CONNECT:
			connect_requested.emit(action.from.machine_id, action.from.port, action.to.machine_id, action.to.port)
		BoardAction.Type.DISCONNECT:
			disconnect_requested.emit(action.wire)
		BoardAction.Type.NONE:
			if action.refusal != "":
				refused.emit(action.refusal)
	interaction.refresh_hover()
	queue_redraw()


## Every graph mutation emits changed synchronously, so hover never names a removed machine or belt.
func _on_graph_changed() -> void:
	interaction.refresh_hover()
	queue_redraw()


## Forget the last point, so a later graph change cannot re-hover a spot the mouse has left.
func _on_mouse_exited() -> void:
	if interaction.mode == BoardInteraction.Mode.IDLE:
		interaction.cursor = Vector2(-1, -1)
		interaction.refresh_hover()


func _draw_gesture() -> void:
	var graph: FactoryGraph = interaction.graph
	match interaction.mode:
		BoardInteraction.Mode.DRAG_MACHINE:
			if interaction.is_drag_outside():
				var old: Rect2 = BoardLayout.machine_rect(graph, interaction.drag_id)
				draw_rect(old.grow(-1.0), UiColors.ERROR, false, 2.0)
				if graph.def_of(interaction.drag_id).removable:   # the Source and Output get the refusal box instead
					var label: Rect2 = Rect2(old.get_center() - Vector2(60, 9), Vector2(120, 18))
					draw_rect(label, Color(UiColors.PANEL_BG, 0.92))
					draw_string(get_theme_default_font(), label.position + Vector2(0, 13), "RELEASE TO REMOVE",
							HORIZONTAL_ALIGNMENT_CENTER, label.size.x, 11, UiColors.ERROR)
			else:
				_draw_ghost(graph.kind_of(interaction.drag_id), interaction.ghost_cell(), interaction.ghost_valid())
		BoardInteraction.Mode.DRAG_WIRE:
			var color: Color = UiColors.CHEVRON
			var end: Vector2 = interaction.cursor
			if interaction.wire_target != null:
				color = UiColors.OK if interaction.wire_code == GraphError.Code.OK else UiColors.ERROR
				end = BoardLayout.port_anchor(graph, interaction.wire_target)
			draw_line(BoardLayout.port_anchor(graph, interaction.wire_from), end, color, 4.0)
	_draw_reason(interaction.refusal_text(), interaction.cursor)
	if _drop != null:
		_draw_ghost(_drop.kind, _drop.cell, _drop.valid)
		_draw_reason(_drop.reason, _drop_at)


func _draw_ghost(kind: StringName, cell: Vector2i, valid: bool) -> void:
	var rect: Rect2 = BoardLayout.machine_rect_at(cell)
	MachinePainter.draw_machine(self, kind, rect, -1, ShotPlan.MachineStatus.IDLE, 0.6, _icon_time)
	draw_rect(rect.grow(-1.0), UiColors.OK if valid else UiColors.ERROR, false, 2.0)


## The refusal box next to the cursor, kept inside the board.
func _draw_reason(text: String, at: Vector2) -> void:
	if text == "":
		return
	var font: Font = get_theme_default_font()
	var box: Rect2 = Rect2(at + Vector2(14, 14),
			font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, REASON_FONT_SIZE) + Vector2(12, 6))
	box.position = box.position.clamp(Vector2.ZERO, (size - box.size).max(Vector2.ZERO))
	draw_rect(box, Color(UiColors.PANEL_BG, 0.92))
	draw_rect(box, UiColors.ERROR, false, 1.0)
	draw_string(font, box.position + Vector2(6, 3 + font.get_ascent(REASON_FONT_SIZE)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, REASON_FONT_SIZE, UiColors.TEXT)


func _draw_lock() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiColors.PANEL_BG, 0.45))
	for top: float in [0.0, size.y - HAZARD_BAND]:
		draw_rect(Rect2(0, top, size.x, HAZARD_BAND), UiColors.OUTLINE)
		var x: float = -HAZARD_BAND
		while x < size.x:
			draw_colored_polygon(PackedVector2Array([Vector2(x, top + HAZARD_BAND), Vector2(x + HAZARD_BAND, top),
					Vector2(x + 2 * HAZARD_BAND, top), Vector2(x + HAZARD_BAND, top + HAZARD_BAND)]), UiColors.HAZARD)
			x += 2 * HAZARD_BAND
	draw_string(get_theme_default_font(), Vector2(0, size.y / 2 + 7), _lock_text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, 20, UiColors.HAZARD)

class_name FactoryBoard
extends Control
## The factory floor editor (docs/DESIGN.md E.2, E.5). It never mutates the model: every gesture becomes a
## *_requested signal, or refused(reason).
## A frame must stay cheap however big the factory grows, so drawing is split over layers, back to front as in
## E.2: the floor; the belt beds, redrawn only when what they show changes; the moving chevrons and items of live
## belts, every frame; the machines with the belt couplers over them, redrawn only when they change; the
## flickering Fire flames, every frame; this board's own _draw every frame (hover, gesture); and the lock overlay,
## redrawn by set_locked. Machines cover the belts under them, so what is on top is what hit_test finds first.

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
const CURSOR_GAP: float = 14.0            # the refusal box keeps this far from the cursor...
const PREVIEW_GAP: float = 44.0           # ...and from a palette drag's 80x80 preview, centred on the cursor

var interaction: BoardInteraction = BoardInteraction.new()
var _plan: ShotPlan = ShotPlan.empty()
var _lock_text: String = ""
var _scroll: float = 0.0                  # how far live belts have moved, px
var _icon_time: float = 0.0
var _drop: DropPreview = null             # the palette drag hovering the board, drawn as a ghost
var _drop_at: Vector2 = Vector2.ZERO
var _belt_layer: Control = Control.new()      # belt beds and the still chevrons of dead belts
var _flow_layer: Control = Control.new()      # the moving chevrons and items of live belts, every frame
var _machine_layer: Control = Control.new()   # machines without their animated icons, then the belt couplers
var _flame_layer: Control = Control.new()     # the Fire flames, every frame
var _lock_layer: Control = Control.new()
var _static_look: String = ""             # _look() when the machine and belt layers were last redrawn
var _belts: Array[Wire] = []              # dead belts first, so live items stay on top where routes overlap
var _first_live: int = 0                  # the index of the first live belt in _belts
var _routes: Array[PackedVector2Array] = []   # per belt in _belts
var _items: Array[PackedColorArray] = []      # per belt: one item colour per stream; empty on dead belts


func _init() -> void:
	size = BoardLayout.bounds().size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var floor_layer: FloorLayer = FloorLayer.new()
	floor_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(floor_layer)
	for layer: Control in [_belt_layer, _flow_layer, _machine_layer, _flame_layer, _lock_layer]:
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.show_behind_parent = layer != _lock_layer   # all but the lock go under this board's own drawing
		add_child(layer)
	_belt_layer.draw.connect(_draw_belts)
	_flow_layer.draw.connect(_draw_flow)
	_machine_layer.draw.connect(_draw_machines)
	_flame_layer.draw.connect(_draw_flames)
	_lock_layer.draw.connect(_draw_lock)
	mouse_exited.connect(_on_mouse_exited)
	_rebuild_belts()


func _process(delta: float) -> void:
	_scroll += delta * (BELT_SPEED_PLAY if interaction.locked else BELT_SPEED_BUILD)
	_icon_time += delta
	if _drop != null and (not get_viewport().gui_is_dragging()
			or not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())):
		_drop = null
	if _look() != _static_look:
		_redraw_static()
	_flow_layer.queue_redraw()
	_flame_layer.queue_redraw()
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


## Losing focus drops this board's mouse focus, and no release reaches _gui_input after that, so the gesture ends
## here; otherwise its ghost would follow a cursor with no button held.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_interaction()


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


## Every frame, over the machines: the hover and the gesture.
func _draw() -> void:
	var graph: FactoryGraph = interaction.graph
	var hover: BoardHit = interaction.hover
	if hover.type == BoardHit.Type.MACHINE or (hover.type == BoardHit.Type.PORT and not hover.port.is_output):
		draw_rect(BoardLayout.machine_rect(graph, hover.machine_id).grow(-1.0), UiColors.ACCENT, false, 2.0)
	elif hover.type == BoardHit.Type.PORT:
		draw_arc(BoardLayout.port_anchor(graph, hover.port) - Vector2(5, 0), 8.0, 0.0, TAU, 20, UiColors.ACCENT, 2.0)
	_draw_gesture()


func bind(graph: FactoryGraph, inventory: Inventory) -> void:
	interaction.bind(graph, inventory)
	graph.changed.connect(_on_graph_changed)
	_rebuild_belts()


func set_plan(plan: ShotPlan) -> void:
	_plan = plan
	_rebuild_belts()


func set_locked(locked: bool, text: String) -> void:
	interaction.set_locked(locked)
	_lock_text = text
	if locked and is_inside_tree() and get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	_lock_layer.queue_redraw()
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
	_rebuild_belts()


## Forget the last point, so a later graph change cannot re-hover a spot the mouse has left.
func _on_mouse_exited() -> void:
	if interaction.mode == BoardInteraction.Mode.IDLE:
		interaction.cursor = Vector2(-1, -1)
		interaction.refresh_hover()


## The belts' draw order, routes and item colours depend only on the graph and the plan.
func _rebuild_belts() -> void:
	var live: Array[Wire] = []
	_belts.clear()
	for w: Wire in interaction.graph.wires():
		if _plan.is_live_wire(w):
			live.append(w)
		else:
			_belts.append(w)
	_first_live = _belts.size()
	_belts.append_array(live)
	_routes.clear()
	_items.clear()
	var routes: Dictionary[String, PackedVector2Array] = BoardLayout.belt_routes(interaction.graph)
	for i: int in _belts.size():
		_routes.append(routes[_belts[i].key()])
		var colors: PackedColorArray = []
		if i >= _first_live:
			for spec: BulletSpec in _plan.streams_on(_belts[i]):
				colors.append(spec.primary_color())
		_items.append(colors)
	_redraw_static()
	queue_redraw()


func _redraw_static() -> void:
	_static_look = _look()
	_machine_layer.queue_redraw()
	_belt_layer.queue_redraw()


## What the machine and belt layers show besides the graph and the plan: the dragged machine and the lit belts.
func _look() -> String:
	var hovered: String = interaction.hover.wire.key() if interaction.hover.type == BoardHit.Type.BELT else ""
	var splice: String = _drop.splice.key() if _drop != null and _drop.splice != null else ""
	return "%d %s %s" % [_dragged(), hovered, splice]


func _dragged() -> int:
	return interaction.drag_id if interaction.mode == BoardInteraction.Mode.DRAG_MACHINE else -1


## The hovered belt, and the belt a palette drag would splice into, are drawn brightened.
func _is_lit(w: Wire) -> bool:
	return (interaction.hover.type == BoardHit.Type.BELT and interaction.hover.wire.same_as(w)) \
			or (_drop != null and _drop.splice != null and _drop.splice.same_as(w))


## The couplers go over the machines: a coupler marks every wired port, and is all a zero-length belt between
## touching machines shows. They sit on port anchors, where hit_test finds the port first.
func _draw_machines() -> void:
	var graph: FactoryGraph = interaction.graph
	var dragged: int = _dragged()
	for id: int in graph.machine_ids():
		MachinePainter.draw_machine(_machine_layer, graph.kind_of(id), BoardLayout.machine_rect(graph, id), id,
				_plan.status_of(id), 0.35 if id == dragged else 1.0, 0.0, true)
	for i: int in _belts.size():
		BeltPainter.draw_coupler(_machine_layer, _routes[i][0], i >= _first_live)
		BeltPainter.draw_coupler(_machine_layer, _routes[i][_routes[i].size() - 1], i >= _first_live)


func _draw_flames() -> void:
	var graph: FactoryGraph = interaction.graph
	var dragged: int = _dragged()
	for id: int in graph.machine_ids():
		if MachinePainter.animates(graph.kind_of(id)):
			MachinePainter.draw_machine_icon(_flame_layer, graph.kind_of(id), BoardLayout.machine_rect(graph, id),
					0.35 if id == dragged else 1.0, _icon_time)


## Under the machines (E.2): a belt crossing a machine runs beneath it, where hit_test finds the machine.
func _draw_belts() -> void:
	for i: int in _belts.size():
		var lit: bool = _is_lit(_belts[i])
		BeltPainter.draw_bed(_belt_layer, _routes[i], lit)
		if i < _first_live:
			BeltPainter.draw_chevrons(_belt_layer, _routes[i], 0.0, BeltPainter.tint(UiColors.CHEVRON_DIM, lit))


func _draw_flow() -> void:
	for i: int in range(_first_live, _belts.size()):
		var lit: bool = _is_lit(_belts[i])
		BeltPainter.draw_chevrons(_flow_layer, _routes[i], _scroll, BeltPainter.tint(UiColors.CHEVRON, lit))
		BeltPainter.draw_items(_flow_layer, _routes[i], _scroll, _items[i], lit)


func _draw_gesture() -> void:
	var graph: FactoryGraph = interaction.graph
	match interaction.mode:
		BoardInteraction.Mode.DRAG_MACHINE:
			if interaction.is_drag_outside():
				var old: Rect2 = BoardLayout.machine_rect(graph, interaction.drag_id)
				draw_rect(old.grow(-1.0), UiColors.ERROR, false, 2.0)
				if graph.def_of(interaction.drag_id).removable:   # the Source and Output get the refusal box instead
					var label: Rect2 = _release_label(old)
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
	_draw_reason(interaction.refusal_text(), interaction.cursor, CURSOR_GAP)
	if _drop != null:
		_draw_ghost(_drop.kind, _drop.cell, _drop.valid)
		_draw_reason(_drop.reason, _drop_at, PREVIEW_GAP)


func _draw_ghost(kind: StringName, cell: Vector2i, valid: bool) -> void:
	var rect: Rect2 = BoardLayout.machine_rect_at(cell)
	MachinePainter.draw_machine(self, kind, rect, -1, ShotPlan.MachineStatus.IDLE, 0.6, _icon_time)
	draw_rect(rect.grow(-1.0), UiColors.OK if valid else UiColors.ERROR, false, 2.0)


## The "RELEASE TO REMOVE" label, centred on the machine and kept inside the board.
func _release_label(machine: Rect2) -> Rect2:
	return _inside(Rect2(machine.get_center() - Vector2(60, 9), Vector2(120, 18)))


## The refusal box next to the cursor, kept inside the board.
func _draw_reason(text: String, at: Vector2, gap: float) -> void:
	if text == "":
		return
	var font: Font = get_theme_default_font()
	var box: Rect2 = _reason_box(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, REASON_FONT_SIZE)
			+ Vector2(12, 6), at, gap)
	draw_rect(box, Color(UiColors.PANEL_BG, 0.92))
	draw_rect(box, UiColors.ERROR, false, 1.0)
	draw_string(font, box.position + Vector2(6, 3 + font.get_ascent(REASON_FONT_SIZE)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, REASON_FONT_SIZE, UiColors.TEXT)


## Below and right of at by gap, or above it when there is no room below, so it never covers what sits on the
## cursor (a palette drag's preview is drawn over the board); then kept inside the board.
func _reason_box(box_size: Vector2, at: Vector2, gap: float) -> Rect2:
	var box: Rect2 = Rect2(at + Vector2(gap, gap), box_size)
	if box.end.y > size.y:
		box.position.y = at.y - gap - box_size.y
	return _inside(box)


## r moved, not resized, to lie inside the board as far as it fits.
func _inside(r: Rect2) -> Rect2:
	r.position = r.position.clamp(Vector2.ZERO, (size - r.size).max(Vector2.ZERO))
	return r


## On the lock layer, over everything the board draws.
func _draw_lock() -> void:
	if not interaction.locked:
		return
	_lock_layer.draw_rect(Rect2(Vector2.ZERO, size), Color(UiColors.PANEL_BG, 0.45))
	for top: float in [0.0, size.y - HAZARD_BAND]:
		_lock_layer.draw_rect(Rect2(0, top, size.x, HAZARD_BAND), UiColors.OUTLINE)
		var x: float = -HAZARD_BAND
		while x < size.x:
			_lock_layer.draw_colored_polygon(PackedVector2Array([Vector2(x, top + HAZARD_BAND), Vector2(x + HAZARD_BAND, top),
					Vector2(x + 2 * HAZARD_BAND, top), Vector2(x + HAZARD_BAND, top + HAZARD_BAND)]), UiColors.HAZARD)
			x += 2 * HAZARD_BAND
	_lock_layer.draw_string(get_theme_default_font(), Vector2(0, size.y / 2 + 7), _lock_text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, 20, UiColors.HAZARD)

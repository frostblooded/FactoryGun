class_name FactoryPanel
extends Panel
## The build screen (docs/DESIGN.md E.1, E.8, E.9): it fills the screen between waves. A top bar (title, next
## wave, HP); the palette as big tiles down the left with the remove bin last; the board, scaled up to fill the
## middle; and down the right the shot readout, the status text and a big Start button. No containers: _layout()
## places everything from the panel's size, so tests can compute every rect.

signal start_wave_requested

const PANEL_SIZE: Vector2 = Vector2(1600, 900)
const MARGIN: float = 20.0
const TOP_BAR: float = 96.0
const GAP: float = 12.0
const DOCK_COLUMNS: int = 2
const SIDE_WIDTH: float = 340.0           # the right column: readout, status, Start
const START_HEIGHT: float = 170.0
const STATUS_FONT_SIZE: int = 22
const MESSAGE_TIME: float = 2.5
const HINT: String = "Tap a machine, then tap the floor to place it. Drag from a port to wire. Drag a machine to the bin to remove."

var board: FactoryBoard
var start_button: Button
var trash: TrashBin
var status_label: Label
var slots: Array[PaletteSlot] = []        # PALETTE_ORDER
var readout: ShotReadout
var _title: Label
var _inventory: Inventory = Inventory.new()
var _plan: ShotPlan = ShotPlan.empty()
var _locked: bool = false
var _start_enabled: bool = false
var _start_reason: String = ""
var _wave: int = 1
var _hp: float = Tuning.PLAYER_MAX_HP
var _message: String = ""
var _message_is_error: bool = false
var _message_left: float = 0.0
var _status_color: Color = Color.TRANSPARENT


func _init() -> void:
	_title = Label.new()
	_title.text = "FACTORY"
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 48)
	_title.add_theme_color_override("font_color", UiColors.ACCENT)
	add_child(_title)
	for i: int in MachineCatalog.PALETTE_ORDER.size():
		var slot: PaletteSlot = PaletteSlot.new()
		slot.setup(MachineCatalog.PALETTE_ORDER[i])
		slot.tapped.connect(_on_slot_tapped)
		slots.append(slot)
		add_child(slot)
	trash = TrashBin.new()
	add_child(trash)
	board = FactoryBoard.new()
	board.refused.connect(_on_board_refused)
	add_child(board)
	readout = ShotReadout.new()
	add_child(readout)
	status_label = Label.new()
	status_label.clip_text = true
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override("font_size", STATUS_FONT_SIZE)
	add_child(status_label)
	start_button = Button.new()
	start_button.theme_type_variation = FactoryTheme.BIG_BUTTON
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.pressed.connect(_on_start_pressed)
	add_child(start_button)
	size = PANEL_SIZE
	_layout()
	set_start_state(1, false, "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and board != null:
		_layout()


## Rebuilt every frame from the message timer, the hover, the plan and the start state, so never stale.
func _process(delta: float) -> void:
	_message_left = maxf(_message_left - delta, 0.0)
	var ia: BoardInteraction = board.interaction
	var hover: BoardHit = ia.hover
	_refresh_trash()
	for slot: PaletteSlot in slots:
		slot.set_armed(slot.kind == ia.armed)
	var text: String = HINT
	var color: Color = UiColors.TEXT_DIM
	if _message_left > 0.0:
		text = _message
		color = UiColors.ERROR if _message_is_error else UiColors.TEXT
	elif ia.armed != &"" and not _locked:
		var machine: String = MachineCatalog.get_def(ia.armed).display_name
		text = "Tap the floor to place %s. Tap its tile again to put it back." % machine
		color = UiColors.ACCENT
	elif hover.type == BoardHit.Type.MACHINE or (hover.type == BoardHit.Type.PORT and not hover.port.is_output):
		text = _machine_text(hover.machine_id)
		color = UiColors.TEXT
	elif hover.type == BoardHit.Type.PORT:
		text = "Output port: drag to an input port to connect."
		color = UiColors.TEXT
	elif hover.type == BoardHit.Type.BELT:
		text = "Belt: tap to cut, or right-click or X."
		color = UiColors.TEXT
	elif not _locked and not _start_enabled and _start_reason != "":
		text = _start_reason
		color = UiColors.WARN
	status_label.text = text
	if color != _status_color:
		_status_color = color
		status_label.add_theme_color_override("font_color", color)


## The top bar's wave and HP.
func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(0, 62), "NEXT: WAVE %d" % _wave, HORIZONTAL_ALIGNMENT_CENTER, size.x, 36, UiColors.TEXT)
	var bar: Rect2 = hp_bar_rect()
	draw_style_box(FactoryTheme.box(UiColors.STEEL_DARK, UiColors.OUTLINE, FactoryTheme.BORDER), bar)
	var inner: Rect2 = bar.grow(-FactoryTheme.BORDER)
	inner.size.x *= clampf(_hp / Tuning.PLAYER_MAX_HP, 0.0, 1.0)
	draw_rect(inner, UiColors.ERROR if _hp < Hud.LOW_HP else UiColors.OK)
	draw_string(font, bar.position + Vector2(0, 32), "HP %d" % ceili(_hp), HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 26,
			UiColors.INK)


## Call once. The palette follows inventory.changed from then on.
func bind(graph: FactoryGraph, inventory: Inventory) -> void:
	board.bind(graph, inventory)
	_inventory = inventory
	inventory.changed.connect(_refresh_palette)
	_refresh_palette()


func set_plan(plan: ShotPlan) -> void:
	_plan = plan
	board.set_plan(plan)
	readout.set_plan(plan)


func set_locked(locked: bool, text: String) -> void:
	_locked = locked
	board.set_locked(locked, text)
	_refresh_palette()
	_refresh_start_button()


func set_start_state(wave: int, enabled: bool, reason: String) -> void:
	start_button.text = "START WAVE %d" % wave
	_wave = wave
	_start_enabled = enabled
	_start_reason = reason
	_refresh_start_button()
	queue_redraw()


func set_hp(hp: float) -> void:
	_hp = hp
	queue_redraw()


## Shown on the status line for MESSAGE_TIME seconds.
func show_message(text: String, is_error: bool) -> void:
	_message = text
	_message_is_error = is_error
	_message_left = MESSAGE_TIME


## Panel-local, top right, over the right column.
func hp_bar_rect() -> Rect2:
	return Rect2(size.x - MARGIN - SIDE_WIDTH, 24, SIDE_WIDTH, 48)


## The board's scale: as big as fits between the palette and the right column.
func board_scale() -> float:
	var room: Vector2 = _board_room().size
	var floor_size: Vector2 = BoardLayout.bounds().size
	return minf(room.x / floor_size.x, room.y / floor_size.y)


func _board_room() -> Rect2:
	var left: float = MARGIN + DOCK_COLUMNS * PaletteSlot.SLOT_SIZE.x + (DOCK_COLUMNS - 1) * GAP + MARGIN
	var right: float = size.x - MARGIN - SIDE_WIDTH - MARGIN
	var top: float = TOP_BAR + GAP
	return Rect2(left, top, maxf(right - left, 1.0), maxf(size.y - MARGIN - top, 1.0))


func _layout() -> void:
	_title.position = Vector2(MARGIN, 8)
	_title.size = Vector2(400, TOP_BAR - 16)
	var top: float = TOP_BAR + GAP
	var tiles: Array[Control] = []
	tiles.assign(slots)
	tiles.append(trash)
	for i: int in tiles.size():
		tiles[i].position = Vector2(MARGIN + (i % DOCK_COLUMNS) * (PaletteSlot.SLOT_SIZE.x + GAP),
				top + (i / DOCK_COLUMNS) * (PaletteSlot.SLOT_SIZE.y + GAP))
	var s: float = board_scale()
	var room: Rect2 = _board_room()
	board.scale = Vector2(s, s)
	board.position = (room.position + (room.size - board.size * s) / 2.0).round()
	for slot: PaletteSlot in slots:
		slot.ghost_scale = s
	var side: float = size.x - MARGIN - SIDE_WIDTH
	readout.position = Vector2(side, top)
	start_button.position = Vector2(side, size.y - MARGIN - START_HEIGHT)
	start_button.size = Vector2(SIDE_WIDTH, START_HEIGHT)
	var status_top: float = top + ShotReadout.READOUT_SIZE.y + GAP
	status_label.position = Vector2(side + 4, status_top)
	status_label.size = Vector2(SIDE_WIDTH - 8, maxf(start_button.position.y - GAP - status_top, 30.0))
	queue_redraw()


func _refresh_palette() -> void:
	for slot: PaletteSlot in slots:
		slot.set_state(_inventory.count(slot.kind), _inventory.ever_owned(slot.kind), _locked)
	var armed: StringName = board.interaction.armed
	if armed != &"" and (_locked or _inventory.count(armed) == 0):
		board.arm(&"")


func _refresh_trash() -> void:
	var ia: BoardInteraction = board.interaction
	var armed: bool = ia.mode == BoardInteraction.Mode.DRAG_MACHINE and ia.graph.def_of(ia.drag_id).removable
	var at: Vector2 = board.position + ia.cursor * board.scale
	trash.set_state(armed, armed and Rect2(trash.position, trash.size).has_point(at))


func _refresh_start_button() -> void:
	start_button.disabled = _locked or not _start_enabled


## The status tag goes before the description: the label trims the end.
func _machine_text(id: int) -> String:
	var def: MachineDef = board.interaction.graph.def_of(id)
	var text: String = def.display_name
	if def.removable:
		text += " #%d" % id
	match _plan.status_of(id):
		ShotPlan.MachineStatus.CAPPED:
			text += " [capped]"
		ShotPlan.MachineStatus.ONE_SIDED:
			text += " [one-sided]"
		ShotPlan.MachineStatus.DEAD_END:
			text += " [dead end]"
		ShotPlan.MachineStatus.IDLE:
			text += " [idle]"
	return text + ": " + def.description


## A tap picks the machine up, or puts it back; the next floor tap places it.
func _on_slot_tapped(kind: StringName) -> void:
	if _locked:
		return
	if board.interaction.armed == kind:
		board.arm(&"")
	elif _inventory.count(kind) > 0:
		board.arm(kind)
	elif _inventory.ever_owned(kind):
		show_message("No %s left. Take it off the floor, or win more." % MachineCatalog.get_def(kind).display_name, true)
	else:
		show_message("Not found yet. Clear waves to earn new machines.", true)


func _on_board_refused(reason: String) -> void:
	show_message(reason, true)


func _on_start_pressed() -> void:
	start_wave_requested.emit()

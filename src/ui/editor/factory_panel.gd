class_name FactoryPanel
extends Panel
## The left half of the screen (docs/DESIGN.md E.1, E.8, E.9): title, Start button, board, status line,
## palette and shot readout. Absolute positions and no containers, so tests can compute every rect.

signal start_wave_requested

const BOARD_POS: Vector2 = Vector2(20, 64)
const PALETTE_POS: Vector2 = Vector2(20, 582)
const SLOT_STEP: float = 78.0
const READOUT_POS: Vector2 = Vector2(20, 678)
const PANEL_SIZE: Vector2 = Vector2(600, 900)
const MESSAGE_TIME: float = 2.5
const HINT: String = "Drag machines onto the floor. Drag from an output port to wire. Right-click removes."

var board: FactoryBoard
var start_button: Button
var status_label: Label
var slots: Array[PaletteSlot] = []        # PALETTE_ORDER
var readout: ShotReadout
var _inventory: Inventory = Inventory.new()
var _plan: ShotPlan = ShotPlan.empty()
var _locked: bool = false
var _start_enabled: bool = false
var _start_reason: String = ""
var _message: String = ""
var _message_is_error: bool = false
var _message_left: float = 0.0
var _status_color: Color = Color.TRANSPARENT


func _init() -> void:
	size = PANEL_SIZE
	var title: Label = Label.new()
	title.text = "FACTORY"
	title.position = Vector2(20, 12)
	title.size = Vector2(300, 44)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UiColors.ACCENT)
	add_child(title)
	start_button = Button.new()
	start_button.position = Vector2(360, 18)
	start_button.size = Vector2(220, 32)
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.pressed.connect(_on_start_pressed)
	add_child(start_button)
	board = FactoryBoard.new()
	board.position = BOARD_POS
	board.refused.connect(_on_board_refused)
	add_child(board)
	status_label = Label.new()
	status_label.position = Vector2(20, 552)
	status_label.size = Vector2(560, 22)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.clip_text = true     # without it the label grows to its text width, under the arena
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override("font_size", 12)
	add_child(status_label)
	for i: int in MachineCatalog.PALETTE_ORDER.size():
		var slot: PaletteSlot = PaletteSlot.new()
		slot.setup(MachineCatalog.PALETTE_ORDER[i])
		slot.position = PALETTE_POS + Vector2(SLOT_STEP * i, 0)
		slots.append(slot)
		add_child(slot)
	readout = ShotReadout.new()
	readout.position = READOUT_POS
	add_child(readout)
	set_start_state(1, false, "")


## Rebuilt every frame from the message timer, the hover, the plan and the start state, so never stale.
func _process(delta: float) -> void:
	_message_left = maxf(_message_left - delta, 0.0)
	var hover: BoardHit = board.interaction.hover
	var text: String = HINT
	var color: Color = UiColors.TEXT_DIM
	if _message_left > 0.0:
		text = _message
		color = UiColors.ERROR if _message_is_error else UiColors.TEXT
	elif hover.type == BoardHit.Type.MACHINE or (hover.type == BoardHit.Type.PORT and not hover.port.is_output):
		text = _machine_text(hover.machine_id)
		color = UiColors.TEXT
	elif hover.type == BoardHit.Type.PORT:
		text = "Output port: drag to an input port to connect."
		color = UiColors.TEXT
	elif hover.type == BoardHit.Type.BELT:
		text = "Belt: right-click or X to cut."
		color = UiColors.TEXT
	elif not _locked and not _start_enabled and _start_reason != "":
		text = _start_reason
		color = UiColors.WARN
	status_label.text = text
	if color != _status_color:
		_status_color = color
		status_label.add_theme_color_override("font_color", color)


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
	start_button.text = "START WAVE %d  [Space]" % wave
	_start_enabled = enabled
	_start_reason = reason
	_refresh_start_button()


## Shown on the status line for MESSAGE_TIME seconds.
func show_message(text: String, is_error: bool) -> void:
	_message = text
	_message_is_error = is_error
	_message_left = MESSAGE_TIME


func _refresh_palette() -> void:
	for slot: PaletteSlot in slots:
		slot.set_state(_inventory.count(slot.kind), _inventory.ever_owned(slot.kind), _locked)


func _refresh_start_button() -> void:
	start_button.disabled = _locked or not _start_enabled


## The status tag goes before the description: the label trims the end, and the Splitter's text alone overruns it.
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


func _on_board_refused(reason: String) -> void:
	show_message(reason, true)


func _on_start_pressed() -> void:
	start_wave_requested.emit()

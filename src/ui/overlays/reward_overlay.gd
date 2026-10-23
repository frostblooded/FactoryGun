class_name RewardOverlay
extends Control
## The reward pick after a cleared wave (docs/DESIGN.md G.4): three machine cards over the arena. Draws
## itself. A left click on a card, or Main's 1/2/3 keys, choose one.

signal offer_chosen(index: int)

const DIM: Color = Color(0, 0, 0, 0.55)
const TEXT_WIDTH: float = 230.0           # card text is centred in this width
const ICON_SIZE: float = 26.0

var offers: Array[RewardOffer] = []
var _wave_cleared: int = 0
var _time: float = 0.0                    # the icons' own animation clock


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	visible = false


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			choose(_card_at(click.position))


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	draw_string(font, Vector2(0, 220), "WAVE %d CLEARED" % _wave_cleared, HORIZONTAL_ALIGNMENT_CENTER, size.x, 32,
			UiColors.ACCENT)
	draw_string(font, Vector2(0, 255), "Choose one machine · +%d HP" % roundi(Tuning.HEAL_ON_REWARD),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, UiColors.TEXT)
	var hover: int = _card_at(get_local_mouse_position())
	for i: int in offers.size():
		var def: MachineDef = MachineCatalog.get_def(offers[i].kind)
		var card: Rect2 = card_rect(i)
		var x: float = card.position.x + (card.size.x - TEXT_WIDTH) / 2.0
		var y: float = card.position.y
		draw_rect(card, UiColors.STEEL_DARK)
		draw_rect(card.grow(-1.0), UiColors.ACCENT if i == hover else UiColors.PANEL_EDGE, false, 2.0)
		MachinePainter.draw_icon(self, def.kind, Vector2(card.get_center().x, y + 80), ICON_SIZE, 1.0, _time)
		draw_string(font, Vector2(x, y + 150), def.display_name, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, 22,
				UiColors.TEXT)
		draw_string(font, Vector2(x, y + 190), "×%d" % offers[i].amount, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, 28,
				UiColors.ACCENT)
		draw_multiline_string(font, Vector2(x, y + 220), def.description, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, 13,
				-1, UiColors.TEXT)
		draw_string(font, Vector2(x, y + 300), "[%d]" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, 14,
				UiColors.TEXT_DIM)


func show_offers(p_offers: Array[RewardOffer], wave_cleared: int) -> void:
	offers.assign(p_offers)
	_wave_cleared = wave_cleared
	show()
	queue_redraw()


## Only while visible and for a valid index. Hides before it emits, so a second key press does nothing.
func choose(index: int) -> void:
	if not visible or index < 0 or index >= offers.size():
		return
	hide()
	offer_chosen.emit(index)


## Overlay-local.
func card_rect(index: int) -> Rect2:
	return Rect2(90 + 280 * index, 290, 260, 320)


## The card under p, or -1.
func _card_at(p: Vector2) -> int:
	for i: int in offers.size():
		if card_rect(i).has_point(p):
			return i
	return -1

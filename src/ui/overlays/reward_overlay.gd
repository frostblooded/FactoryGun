class_name RewardOverlay
extends Control
## The reward pick after a cleared wave (docs/DESIGN.md G.4): three big machine cards over the arena, centred on
## the screen. Draws itself. A tap on a card, or Main's 1/2/3 keys, choose one.

signal offer_chosen(index: int)

const DIM: Color = Color(0, 0, 0, 0.55)
const CARD_SIZE: Vector2 = Vector2(420, 600)
const CARD_GAP: float = 40.0
const TEXT_WIDTH: float = 360.0           # card text is centred in this width
const ICON_SIZE: float = 48.0

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
	var top: float = card_rect(0).position.y
	draw_string(font, Vector2(0, top - 70), "WAVE %d CLEARED!" % _wave_cleared, HORIZONTAL_ALIGNMENT_CENTER, size.x,
			64, UiColors.ACCENT)
	draw_string(font, Vector2(0, top - 22), "Pick one machine · +%d HP" % roundi(Tuning.HEAL_ON_REWARD),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, UiColors.TEXT)
	var hover: int = _card_at(get_local_mouse_position())
	for i: int in offers.size():
		var def: MachineDef = MachineCatalog.get_def(offers[i].kind)
		var card: Rect2 = card_rect(i)
		var x: float = card.position.x + (card.size.x - TEXT_WIDTH) / 2.0
		var y: float = card.position.y
		draw_style_box(FactoryTheme.box(UiColors.TILE_BG, UiColors.HAZARD if i == hover else UiColors.TILE_LIP,
				FactoryTheme.LIP + 4), card)
		MachinePainter.draw_icon(self, def.kind, Vector2(card.get_center().x, y + 120), ICON_SIZE, 1.0, _time)
		draw_string(font, Vector2(x, y + 245), def.display_name, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, 40,
				UiColors.TEXT)
		draw_string(font, Vector2(x, y + 310), "×%d" % offers[i].amount, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, 52,
				UiColors.ACCENT)
		draw_multiline_string(font, Vector2(x, y + 355), def.description, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, 22,
				4, UiColors.TEXT)
		var take: Rect2 = Rect2(card.position.x + 30, card.end.y - 90, card.size.x - 60, 64)
		draw_style_box(FactoryTheme.box(UiColors.HAZARD, UiColors.BUTTON_LIP, FactoryTheme.LIP), take)
		draw_string(font, take.position + Vector2(0, 42), "TAKE IT", HORIZONTAL_ALIGNMENT_CENTER, take.size.x, 30,
				UiColors.INK)


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


## Overlay-local: the cards side by side, the row centred on the overlay.
func card_rect(index: int) -> Rect2:
	var n: int = maxi(offers.size(), 1)
	var row: float = n * CARD_SIZE.x + (n - 1) * CARD_GAP
	var origin: Vector2 = Vector2((size.x - row) / 2.0, (size.y - CARD_SIZE.y) / 2.0 + 50.0).round()
	return Rect2(origin + Vector2((CARD_SIZE.x + CARD_GAP) * index, 0), CARD_SIZE)


## The card under p, or -1.
func _card_at(p: Vector2) -> int:
	for i: int in offers.size():
		if card_rect(i).has_point(p):
			return i
	return -1

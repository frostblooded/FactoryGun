class_name BeltPainter
extends RefCounted
## Draws one belt along its route (docs/DESIGN.md E.2 layer 2): bed, rails, chevrons and, on live belts, items.

const BED_WIDTH: float = 14.0
const RAIL_WIDTH: float = 2.0             # centred on +-6 px
const CHEVRON_STEP: float = 12.0
const ITEM_STEP: float = 28.0
const ITEM_SIZE: Vector2 = Vector2(8, 8)
const HOVER_TINT: float = 1.25


## scroll: how far chevrons and items have travelled (px); pass 0 for a still belt.
## item_colors: one per stream on the belt; items are drawn only on live belts.
static func draw_belt(ci: CanvasItem, points: PackedVector2Array, live: bool, scroll: float, item_colors: Array[Color],
		hovered: bool) -> void:
	var k: float = HOVER_TINT if hovered else 1.0
	# A rail-coloured band under a bed 4 px narrower leaves the two 2 px rails at +-6 px.
	_band(ci, points, BED_WIDTH, _tint(UiColors.RAIL, k))
	_band(ci, points, BED_WIDTH - 2.0 * RAIL_WIDTH, _tint(UiColors.BELT_BED, k))
	var length: float = BeltRouter.length(points)
	var chevron: Color = _tint(UiColors.CHEVRON if live else UiColors.CHEVRON_DIM, k)
	var d: float = fposmod(scroll, CHEVRON_STEP)
	while d < length:
		var at: Array[Vector2] = BeltRouter.sample(points, d)
		var side: Vector2 = at[1].orthogonal() * 3.5
		ci.draw_polyline(PackedVector2Array([at[0] - at[1] * 2.5 + side, at[0] + at[1] * 1.5, at[0] - at[1] * 2.5 - side]),
				chevron, 1.5)
		d += CHEVRON_STEP
	if not live or item_colors.is_empty():
		return
	var first: int = floori(scroll / ITEM_STEP)   # counts items already gone, so each item keeps its colour
	d = fposmod(scroll, ITEM_STEP)
	var i: int = 0
	while d < length:
		var box: Rect2 = Rect2(BeltRouter.sample(points, d)[0] - ITEM_SIZE / 2, ITEM_SIZE)
		ci.draw_rect(box, _tint(item_colors[posmod(i - first, item_colors.size())], k))
		ci.draw_rect(box, UiColors.OUTLINE, false, 1.0)
		d += ITEM_STEP
		i += 1


## Square-cornered thick polyline: one line per segment plus a square on every bend.
static func _band(ci: CanvasItem, points: PackedVector2Array, width: float, color: Color) -> void:
	for i: int in range(points.size() - 1):
		ci.draw_line(points[i], points[i + 1], color, width)
	for i: int in range(1, points.size() - 1):
		ci.draw_rect(Rect2(points[i] - Vector2(width, width) / 2, Vector2(width, width)), color)


static func _tint(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)

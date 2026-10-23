class_name BeltPainter
extends RefCounted
## Draws belts along their routes (docs/DESIGN.md E.2 layer 2) in parts, so the board can cache the still
## bed and redraw only the moving chevrons and items every frame. Each moving part is one batched draw call.

const BED_WIDTH: float = 14.0
const RAIL_WIDTH: float = 2.0             # centred on +-6 px
const CHEVRON_STEP: float = 12.0
const ITEM_STEP: float = 28.0
const ITEM_SIZE: float = 8.0
const HOVER_TINT: float = 1.25
const COUPLER_SIZE: Vector2 = Vector2(10, 6)


## The bed and its two rails.
static func draw_bed(ci: CanvasItem, points: PackedVector2Array, hovered: bool) -> void:
	# A rail-coloured band under a bed 4 px narrower leaves the two 2 px rails at +-6 px.
	_band(ci, points, BED_WIDTH, tint(UiColors.RAIL, hovered))
	_band(ci, points, BED_WIDTH - 2.0 * RAIL_WIDTH, tint(UiColors.BELT_BED, hovered))


## Chevrons every CHEVRON_STEP px; scroll (px) is how far they have moved (0 for a still belt).
static func draw_chevrons(ci: CanvasItem, points: PackedVector2Array, scroll: float, color: Color) -> void:
	var marks: PackedVector2Array = BeltRouter.sample_every(points, fposmod(scroll, CHEVRON_STEP), CHEVRON_STEP)
	if marks.is_empty():
		return
	var lines: PackedVector2Array = []
	for i: int in range(0, marks.size(), 2):
		var dir: Vector2 = marks[i + 1]
		var back: Vector2 = marks[i] - dir * 2.5
		var tip: Vector2 = marks[i] + dir * 1.5
		var side: Vector2 = dir.orthogonal() * 3.5
		lines.append(back + side)
		lines.append(tip)
		lines.append(tip)
		lines.append(back - side)
	ci.draw_multiline(lines, color, 1.5)


## Items every ITEM_STEP px, cycling through item_colors (one per stream on the belt); nothing if it is empty.
static func draw_items(ci: CanvasItem, points: PackedVector2Array, scroll: float, item_colors: PackedColorArray,
		hovered: bool) -> void:
	if item_colors.is_empty():
		return
	var marks: PackedVector2Array = BeltRouter.sample_every(points, fposmod(scroll, ITEM_STEP), ITEM_STEP)
	if marks.is_empty():
		return
	var first: int = floori(scroll / ITEM_STEP)   # counts items already gone, so each item keeps its colour
	var half: Vector2 = Vector2(ITEM_SIZE / 2.0, 0)
	var rims: PackedVector2Array = []
	var fills: PackedVector2Array = []
	var colors: PackedColorArray = []
	for i: int in range(0, marks.size(), 2):
		# A horizontal segment as thick as it is long is an axis-aligned square: one batched call per layer.
		rims.append(marks[i] - half - Vector2(1, 0))
		rims.append(marks[i] + half + Vector2(1, 0))
		fills.append(marks[i] - half)
		fills.append(marks[i] + half)
		colors.append(tint(item_colors[posmod(i / 2 - first, item_colors.size())], hovered))
	ci.draw_multiline(rims, UiColors.OUTLINE, ITEM_SIZE + 2.0)
	ci.draw_multiline_colors(fills, colors, ITEM_SIZE)


## The clamp where a belt meets a port: a machine edge with one is wired, a bare port is free.
static func draw_coupler(ci: CanvasItem, anchor: Vector2, live: bool) -> void:
	var r: Rect2 = Rect2(anchor - COUPLER_SIZE / 2.0, COUPLER_SIZE)
	ci.draw_rect(r.grow(1.0), UiColors.OUTLINE)
	ci.draw_rect(r, UiColors.CHEVRON if live else UiColors.CHEVRON_DIM)


static func tint(c: Color, hovered: bool) -> Color:
	var k: float = HOVER_TINT if hovered else 1.0
	return Color(c.r * k, c.g * k, c.b * k, c.a)


## Square-cornered thick polyline: one line per segment plus a square on every bend.
static func _band(ci: CanvasItem, points: PackedVector2Array, width: float, color: Color) -> void:
	for i: int in range(points.size() - 1):
		ci.draw_line(points[i], points[i + 1], color, width)
	for i: int in range(1, points.size() - 1):
		ci.draw_rect(Rect2(points[i] - Vector2(width, width) / 2, Vector2(width, width)), color)

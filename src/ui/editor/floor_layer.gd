class_name FloorLayer
extends Control
## The board's floor plates (docs/DESIGN.md E.2 layer 1). A separate canvas item behind the board, so the
## static floor is drawn once (and again on resize) instead of every frame.

const JITTER_STEP: float = 0.012          # posmod(..., 7) - 3 gives -3..3 steps: +-0.036 brightness
const BOLT_INSET: float = 4.0


func _init() -> void:
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiColors.SEAM)
	for y: int in Tuning.GRID_ROWS:
		for x: int in Tuning.GRID_COLS:
			var base: Color = UiColors.FLOOR_A if (x + y) % 2 == 0 else UiColors.FLOOR_B
			var j: float = (posmod(hash(Vector2i(x, y)), 7) - 3) * JITTER_STEP
			var c: Color = Color(base.r + j, base.g + j, base.b + j)
			var plate: Rect2 = Rect2(Vector2(x, y) * BoardLayout.TILE, Vector2.ONE * BoardLayout.TILE).grow(-1.0)
			draw_rect(plate, c)
			draw_rect(Rect2(plate.position, Vector2(plate.size.x, 1)), c.lightened(0.12))   # top-edge highlight
			if (x + y) % 2 == 0:
				var inset: Rect2 = plate.grow(-BOLT_INSET)
				for bolt: Vector2 in [inset.position, Vector2(inset.end.x, inset.position.y),
						Vector2(inset.position.x, inset.end.y), inset.end]:
					# a square, not a circle: rects batch, while each circle is a draw call of its own (336 bolts, every frame)
					draw_rect(Rect2(bolt - Vector2(1.4, 1.4), Vector2(2.8, 2.8)), UiColors.STEEL)

class_name MachinePainter
extends RefCounted
## Draws machines and their procedural icons on any CanvasItem during its _draw() (docs/DESIGN.md E.2).

const COPPER: Color = Color("b87333")
const FLAME_CORE: Color = Color("ffd34d")
const ICON_SIZE: float = 12.0             # the s of draw_icon on a machine


## rect is the 80x80 machine rect; id <= 0 (a ghost) draws no id plate. still = true leaves out an icon that
## animates, for a cached drawing that draws it every frame with draw_machine_icon.
static func draw_machine(ci: CanvasItem, kind: StringName, rect: Rect2, id: int, status: ShotPlan.MachineStatus,
		alpha: float, t: float, still: bool = false) -> void:
	var def: MachineDef = MachineCatalog.get_def(kind)
	var font: Font = ThemeDB.fallback_font
	var body: Rect2 = rect.grow(-3.0)
	ci.draw_rect(body, _a(UiColors.STEEL_DARK, alpha))                                    # bottom and right bevel
	ci.draw_rect(Rect2(body.position, body.size - Vector2(3, 3)), _a(UiColors.STEEL_LIGHT, alpha))   # top and left bevel
	ci.draw_rect(body.grow(-3.0), _a(UiColors.STEEL, alpha))
	ci.draw_rect(body, _a(UiColors.OUTLINE, alpha), false, 2.0)
	ci.draw_rect(Rect2(body.position + Vector2(10, 6), Vector2(body.size.x - 20, 5)), _a(def.color, alpha))
	for corner: Vector2 in [Vector2(6, 6), Vector2(body.size.x - 6, 6), Vector2(6, body.size.y - 6), body.size - Vector2(6, 6)]:
		# squares batch with the body rects; a circle costs a draw call of its own
		ci.draw_rect(Rect2(body.position + corner - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), _a(UiColors.RIVET, alpha))
	if not (still and animates(kind)):
		draw_machine_icon(ci, kind, rect, alpha, t)
	ci.draw_string(font, Vector2(rect.position.x, rect.end.y - 10), def.short_name, HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x, 11, _a(UiColors.TEXT, alpha))
	ci.draw_circle(Vector2(body.end.x - 14, body.position.y + 17), 4.0, _a(lamp_color(status), alpha))
	if def.removable and id > 0:
		var plate: String = "#%d" % id
		var plate_rect: Rect2 = Rect2(body.position + Vector2(4, 12), Vector2(font.get_string_size(plate, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 6, 12))
		ci.draw_rect(plate_rect, _a(UiColors.OUTLINE, alpha))
		ci.draw_string(font, plate_rect.position + Vector2(3, 10), plate, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, _a(UiColors.TEXT_DIM, alpha))
	if def.input_ports > 0:
		var a: Vector2 = rect.position + BoardLayout.input_anchor_at(Vector2i.ZERO)
		ci.draw_rect(Rect2(a.x, a.y - 7, 7, 14), _a(UiColors.OUTLINE, alpha))
		ci.draw_colored_polygon(PackedVector2Array([a + Vector2(1, -4), a + Vector2(6, 0), a + Vector2(1, 4)]),
				_a(UiColors.ACCENT, alpha))
	for port: int in def.output_ports:
		var o: Vector2 = rect.position + BoardLayout.output_anchor_at(Vector2i.ZERO, port, def.output_ports) - Vector2(5, 0)
		ci.draw_circle(o, 4.0, _a(UiColors.ACCENT, alpha))
		ci.draw_arc(o, 5.0, 0.0, TAU, 16, _a(UiColors.OUTLINE, alpha), 1.5)


## The icon of a machine at rect, where draw_machine puts it.
static func draw_machine_icon(ci: CanvasItem, kind: StringName, rect: Rect2, alpha: float, t: float) -> void:
	draw_icon(ci, kind, rect.get_center() + Vector2(0, 1), ICON_SIZE, alpha, t)


## Whether the kind's icon changes with t (the Fire flame flickers).
static func animates(kind: StringName) -> bool:
	return kind == MachineCatalog.FIRE


## The procedural icon of a kind, about 2*s wide, centred on centre. t (seconds) animates the flame.
static func draw_icon(ci: CanvasItem, kind: StringName, centre: Vector2, s: float, alpha: float, t: float) -> void:
	var def: MachineDef = MachineCatalog.get_def(kind)
	if def == null:
		return
	var c: Color = _a(def.color, alpha)
	var w: float = maxf(s * 0.16, 1.0)   # stroke width
	match kind:
		MachineCatalog.SOURCE:            # a cartridge: brass case, copper tip
			ci.draw_rect(Rect2(centre + Vector2(-s, -0.42 * s), Vector2(1.25 * s, 0.84 * s)), c)
			ci.draw_rect(Rect2(centre + Vector2(-s, -0.5 * s), Vector2(0.2 * s, s)), _a(def.color.darkened(0.3), alpha))
			ci.draw_colored_polygon(_pts(centre, s, [Vector2(0.25, -0.42), Vector2(1, 0), Vector2(0.25, 0.42)]), _a(COPPER, alpha))
		MachineCatalog.OUTPUT:            # a barrel with three spray lines
			ci.draw_rect(Rect2(centre + Vector2(-s, -0.3 * s), Vector2(1.15 * s, 0.6 * s)), c)
			ci.draw_rect(Rect2(centre + Vector2(0.05 * s, -0.42 * s), Vector2(0.2 * s, 0.84 * s)), _a(UiColors.STEEL_LIGHT, alpha))
			for dy: float in [-0.55, 0.0, 0.55]:
				ci.draw_line(centre + Vector2(0.4 * s, 0), centre + Vector2(s, dy * s), _a(UiColors.ACCENT, alpha), w)
		MachineCatalog.FIRE:              # a two-layer flame that flickers
			var f: float = 1.0 + 0.1 * sin(t * 11.0)
			ci.draw_colored_polygon(_pts(centre, s, [Vector2(0, -f), Vector2(0.35, -0.4), Vector2(0.62, 0.2),
					Vector2(0.42, 0.72), Vector2(0, 0.9), Vector2(-0.42, 0.72), Vector2(-0.62, 0.2), Vector2(-0.3, -0.45)]), c)
			ci.draw_colored_polygon(_pts(centre, s, [Vector2(0, 1.2 - 1.05 * f), Vector2(0.28, 0.35), Vector2(0.2, 0.75),
					Vector2(0, 0.85), Vector2(-0.2, 0.75), Vector2(-0.28, 0.35)]), _a(FLAME_CORE, alpha))
		MachineCatalog.ICE:               # a three-axis snowflake with side ticks
			for k: int in 6:
				var dir: Vector2 = Vector2.RIGHT.rotated(k * PI / 3.0)
				ci.draw_line(centre, centre + dir * 0.95 * s, c, w)
				var knot: Vector2 = centre + dir * 0.55 * s
				ci.draw_line(knot, knot + dir.rotated(PI / 4.0) * 0.3 * s, c, w)
				ci.draw_line(knot, knot + dir.rotated(-PI / 4.0) * 0.3 * s, c, w)
		MachineCatalog.POISON:            # a drop and two bubbles
			ci.draw_circle(centre + Vector2(-0.15, 0.3) * s, 0.48 * s, c)
			ci.draw_colored_polygon(_pts(centre, s, [Vector2(-0.6, 0.18), Vector2(-0.15, -0.85), Vector2(0.3, 0.18)]), c)
			ci.draw_circle(centre + Vector2(0.62, -0.4) * s, 0.17 * s, c)
			ci.draw_circle(centre + Vector2(0.8, 0.2) * s, 0.12 * s, c)
		MachineCatalog.SPEED_UP:          # a double chevron
			for dx: float in [-0.6, 0.15]:
				ci.draw_polyline(_pts(centre, s, [Vector2(dx, -0.6), Vector2(dx + 0.5, 0), Vector2(dx, 0.6)]), c, w * 1.4)
		MachineCatalog.SIZE_UP:           # a dot, a ring and four diagonal ticks
			ci.draw_circle(centre, 0.2 * s, c)
			ci.draw_arc(centre, 0.55 * s, 0.0, TAU, 24, c, w)
			for k: int in 4:
				var diag: Vector2 = Vector2.RIGHT.rotated(PI / 4.0 + k * PI / 2.0)
				ci.draw_line(centre + diag * 0.72 * s, centre + diag * s, c, w)
		MachineCatalog.PIERCE:            # a plate with an arrow through it
			ci.draw_rect(Rect2(centre + Vector2(-0.12 * s, -0.75 * s), Vector2(0.24 * s, 1.5 * s)), _a(UiColors.RIVET, alpha))
			ci.draw_line(centre + Vector2(-s, 0), centre + Vector2(0.5 * s, 0), c, w * 1.2)
			ci.draw_colored_polygon(_pts(centre, s, [Vector2(0.4, -0.35), Vector2(1, 0), Vector2(0.4, 0.35)]), c)
		MachineCatalog.SPLITTER:          # a Y-fork with a hub dot
			var hub: Vector2 = centre + Vector2(-0.1 * s, 0)
			ci.draw_line(centre + Vector2(-s, 0), hub, c, w * 1.2)
			ci.draw_line(hub, centre + Vector2(s, -0.6 * s), c, w * 1.2)
			ci.draw_line(hub, centre + Vector2(s, 0.6 * s), c, w * 1.2)
			ci.draw_circle(hub, 0.22 * s, c)


## C.7 lamp colours: red dead end, grey idle, amber one-sided or capped, green active.
static func lamp_color(status: ShotPlan.MachineStatus) -> Color:
	match status:
		ShotPlan.MachineStatus.DEAD_END:
			return UiColors.ERROR
		ShotPlan.MachineStatus.IDLE:
			return UiColors.LAMP_IDLE
		ShotPlan.MachineStatus.ONE_SIDED, ShotPlan.MachineStatus.CAPPED:
			return UiColors.WARN
	return UiColors.OK


static func _a(c: Color, alpha: float) -> Color:
	return Color(c, c.a * alpha)


## Icon-space points (units of s) to canvas points.
static func _pts(centre: Vector2, s: float, unit: Array[Vector2]) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for u: Vector2 in unit:
		out.append(centre + u * s)
	return out

class_name ArenaView
extends Control
## Draws the ArenaWorld every frame, plus transient effects made from SimEvents (docs/DESIGN.md D.5, F.7).
## The effects are purely visual and not part of the sim state.

const GRID_STEP: int = 50
const RING_TIME: float = 0.25
const BURST_TIME: float = 0.35
const MUZZLE_TIME: float = 0.06
const HIT_FLASH_TIME: float = 0.08
const EDGE_FLASH_TIME: float = 0.3
const EDGE_BAND: float = 12.0
const BLINK: float = 0.1
const STATUS_TINT: float = 0.35

var world: ArenaWorld
var _fx: Array[SimEvent] = []             # HIT rings, KILL bursts and SHOT muzzle flashes
var _fx_age: PackedFloat32Array = []
var _hit_flash: Dictionary[int, float] = {}   # enemy id -> seconds of white flash left
var _edge_flash: float = 0.0
var _time: float = 0.0                    # animation clock for flames and orbiting poison dots
var _fire_color: Color = MachineCatalog.get_def(MachineCatalog.FIRE).color
var _ice_color: Color = MachineCatalog.get_def(MachineCatalog.ICE).color
var _poison_color: Color = MachineCatalog.get_def(MachineCatalog.POISON).color


func _process(delta: float) -> void:
	_time += delta
	_edge_flash = maxf(_edge_flash - delta, 0.0)
	for id: int in _hit_flash.keys():
		_hit_flash[id] -= delta
		if _hit_flash[id] <= 0.0:
			_hit_flash.erase(id)
	var fx: Array[SimEvent] = []
	var ages: PackedFloat32Array = []
	for i: int in _fx.size():
		var age: float = _fx_age[i] + delta
		if age < _lifetime(_fx[i].type):
			fx.append(_fx[i])
			ages.append(age)
	_fx = fx
	_fx_age = ages
	queue_redraw()


func _draw() -> void:
	_draw_floor()
	if world == null:
		return
	_draw_player(world.player)
	for e: EnemyState in world.enemies:
		_draw_enemy_body(e)
	for b: BulletState in world.bullets:
		_draw_bullet(b)
	for i: int in _fx.size():
		_draw_fx(_fx[i], _fx_age[i])
	for e: EnemyState in world.enemies:
		_draw_enemy_overlays(e)
	_draw_edge_flash()


func add_events(events: Array[SimEvent]) -> void:
	for e: SimEvent in events:
		match e.type:
			SimEvent.Type.HIT:
				_hit_flash[e.entity_id] = HIT_FLASH_TIME
				_fx.append(e)
				_fx_age.append(0.0)
			SimEvent.Type.KILL, SimEvent.Type.SHOT:
				_fx.append(e)
				_fx_age.append(0.0)
			SimEvent.Type.PLAYER_HIT:
				_edge_flash = EDGE_FLASH_TIME


func clear_fx() -> void:
	_fx.clear()
	_fx_age.clear()
	_hit_flash.clear()
	_edge_flash = 0.0


func _draw_floor() -> void:
	var s: Vector2 = SimTuning.ARENA_SIZE
	draw_rect(Rect2(Vector2.ZERO, s), UiColors.ARENA_FLOOR)
	for x: int in range(GRID_STEP, int(s.x), GRID_STEP):
		draw_line(Vector2(x, 0), Vector2(x, s.y), UiColors.ARENA_GRID)
	for y: int in range(GRID_STEP, int(s.y), GRID_STEP):
		draw_line(Vector2(0, y), Vector2(s.x, y), UiColors.ARENA_GRID)
	draw_rect(Rect2(Vector2.ONE, s - Vector2(2, 2)), UiColors.PANEL_EDGE, false, 2.0)


func _draw_player(p: PlayerState) -> void:
	var alpha: float = 0.4 if p.invuln > 0.0 and int(p.invuln / BLINK) % 2 == 0 else 1.0
	draw_circle(p.pos, SimTuning.PLAYER_RADIUS, Color(UiColors.PLAYER, alpha))
	draw_line(p.pos, p.pos + p.aim_dir * SimTuning.MUZZLE_OFFSET, Color(UiColors.STEEL_LIGHT, alpha), 5.0)


## A regular polygon; the body tint shows the highest priority status: burning > poisoned > chilled.
func _draw_enemy_body(e: EnemyState) -> void:
	var color: Color = e.type.color
	if e.status.is_burning():
		color = color.lerp(_fire_color, STATUS_TINT)
	elif e.status.is_poisoned():
		color = color.lerp(_poison_color, STATUS_TINT)
	elif e.status.is_chilled():
		color = color.lerp(_ice_color, STATUS_TINT)
	if _hit_flash.has(e.id):
		color = Color.WHITE
	var facing: float = -PI / 2.0
	if e.type.kind == EnemyType.Kind.RUNNER:
		facing = (world.player.pos - e.pos).angle()
	var points: PackedVector2Array = []
	for i: int in e.type.sides:
		points.append(e.pos + Vector2.from_angle(facing + TAU * i / e.type.sides) * e.radius())
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, UiColors.OUTLINE, 2.0)


func _draw_bullet(b: BulletState) -> void:
	var r: float = b.spec.radius
	var color: Color = b.spec.primary_color()
	draw_line(b.pos, b.pos - b.vel.normalized() * 2.5 * r, Color(color, 0.5), r)
	draw_circle(b.pos, r, color)
	draw_arc(b.pos, r, 0.0, TAU, 16, color.lightened(0.6), 1.0)


func _draw_fx(e: SimEvent, age: float) -> void:
	match e.type:
		SimEvent.Type.HIT:
			var k: float = age / RING_TIME
			draw_arc(e.pos, lerpf(4.0, 18.0, k), 0.0, TAU, 24, Color(e.color, 1.0 - k), 2.0)
		SimEvent.Type.KILL:
			var fade: Color = Color(e.color, 1.0 - age / BURST_TIME)
			for i: int in 8:
				draw_circle(e.pos + Vector2.from_angle(TAU * i / 8.0) * 120.0 * age, 3.0, fade)
		SimEvent.Type.SHOT:
			draw_circle(e.pos, 8.0, Color(e.color.lightened(0.5), 0.9))


## Flames, chill ring, poison dots and the HP bar. Every overlay is drawn, whatever the body tint.
func _draw_enemy_overlays(e: EnemyState) -> void:
	var r: float = e.radius()
	if e.status.is_burning():
		var base: float = e.pos.y - r * 0.6
		for i: int in 3:
			var x: float = e.pos.x + (i - 1) * r * 0.55
			var h: float = r * 0.5 + 4.0 + 2.0 * sin(_time * 11.0 + i * 2.1 + e.id)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 3.5, base), Vector2(x + 3.5, base),
					Vector2(x, base - h)]), _fire_color)
	if e.status.is_chilled():
		draw_arc(e.pos, r + 3.0, 0.0, TAU, 32, _ice_color, 2.0)
	if e.status.is_poisoned():
		var dots: int = mini(e.status.poison_stacks, 5)
		for i: int in dots:
			draw_circle(e.pos + Vector2.from_angle(_time * 3.0 + TAU * i / dots) * (r + 5.0), 2.5, _poison_color)
	if e.hp < e.max_hp:
		var bar: Rect2 = Rect2(e.pos.x - r, e.pos.y - r - 12.0, 2.0 * r, 3.0)
		draw_rect(bar, UiColors.OUTLINE)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(e.hp / e.max_hp, 0.0, 1.0), bar.size.y)),
				UiColors.ERROR)


func _draw_edge_flash() -> void:
	if _edge_flash <= 0.0:
		return
	var c: Color = Color(UiColors.ERROR, 0.6 * _edge_flash / EDGE_FLASH_TIME)
	var s: Vector2 = SimTuning.ARENA_SIZE
	draw_rect(Rect2(0, 0, s.x, EDGE_BAND), c)
	draw_rect(Rect2(0, s.y - EDGE_BAND, s.x, EDGE_BAND), c)
	draw_rect(Rect2(0, EDGE_BAND, EDGE_BAND, s.y - 2.0 * EDGE_BAND), c)
	draw_rect(Rect2(s.x - EDGE_BAND, EDGE_BAND, EDGE_BAND, s.y - 2.0 * EDGE_BAND), c)


static func _lifetime(type: SimEvent.Type) -> float:
	match type:
		SimEvent.Type.HIT:
			return RING_TIME
		SimEvent.Type.KILL:
			return BURST_TIME
	return MUZZLE_TIME

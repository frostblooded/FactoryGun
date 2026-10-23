class_name ArenaWorld
extends RefCounted
## The pure arena simulation (docs/DESIGN.md F.4). The same (wave, plan, seed, hp) and the same intents
## give the same events and the same state_hash().

var wave: int = 0
var time: float = 0.0
var player: PlayerState
var enemies: Array[EnemyState] = []       # sorted by id: new ids only grow, removal keeps the order
var bullets: Array[BulletState] = []      # sorted by id
var kills: int = 0                        # this wave only
var plan: ShotPlan = ShotPlan.empty()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _schedule: Array[EnemyType.Kind] = []
var _next_spawn: int = 0                  # index into _schedule
var _cooldown: float = 0.0
var _clear_timer: float = 0.0
var _next_enemy_id: int = 1
var _next_bullet_id: int = 1
var _running: bool = false
var _finished: bool = false


func _init() -> void:
	reset_idle(Tuning.PLAYER_MAX_HP)


## Resets everything a wave depends on, so nothing carries over from the previous wave.
func begin_wave(p_wave: int, p_plan: ShotPlan, wave_seed: int, player_hp: float) -> void:
	reset_idle(player_hp)
	wave = p_wave
	plan = p_plan
	_rng.seed = wave_seed
	_schedule = WavePlan.order(wave, _rng)
	_running = true


## begin_wave's resets except wave, plan and rng; an empty schedule; not running.
func reset_idle(player_hp: float) -> void:
	time = 0.0
	kills = 0
	_cooldown = 0.0
	_clear_timer = 0.0
	_next_spawn = 0
	_next_enemy_id = 1
	_next_bullet_id = 1
	enemies.clear()
	bullets.clear()
	_schedule.clear()
	player = PlayerState.new()
	player.pos = SimTuning.ARENA_SIZE / 2.0
	player.hp = player_hp
	_running = false
	_finished = false


func is_running() -> bool:
	return _running


func is_finished() -> bool:
	return _finished


## Alive plus not yet spawned.
func enemies_remaining() -> int:
	return enemies.size() + _schedule.size() - _next_spawn


func step(delta: float, intent: PlayerIntent) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	if not _running:
		return events
	time += delta
	_spawn_due()
	_move_player(delta, intent)
	# Exact cooldown: it keeps falling while fire is released, and a shot sets it rather than adding to it.
	_cooldown = maxf(_cooldown - delta, 0.0)
	if intent.fire and plan.is_valid() and _cooldown <= 1e-6:
		_fire(events)
		_cooldown = Tuning.GUN_INTERVAL
	_move_bullets(delta, events)
	_move_enemies(delta, events)
	_remove_dead(events)
	if player.hp <= 0.0:                  # death wins over clear
		player.hp = 0.0
		_finish(SimEvent.Type.PLAYER_DIED, events)
	elif _next_spawn >= _schedule.size() and enemies.is_empty():
		_clear_timer += delta
		if _clear_timer >= SimTuning.CLEAR_GRACE:
			_finish(SimEvent.Type.WAVE_CLEARED, events)
	return events


func state_hash() -> int:
	var parts: Array = [time, player.pos, player.hp, player.invuln, kills, _next_spawn, _cooldown, _rng.state]
	for e: EnemyState in enemies:
		parts.append_array([e.id, e.pos, e.hp])
	for b: BulletState in bullets:
		parts.append_array([b.id, b.pos, b.pierce_left])
	return hash(parts)


## The auto-aim target: the live enemy nearest the player, or null. A tie keeps the lower id.
func nearest_enemy() -> EnemyState:
	var best: EnemyState = null
	for e: EnemyState in enemies:
		if e.hp > 0.0 and (best == null
				or player.pos.distance_squared_to(e.pos) < player.pos.distance_squared_to(best.pos)):
			best = e
	return best


## Used by step(); public for tests. Applies this wave's HP and speed scaling.
func spawn_enemy(kind: EnemyType.Kind, pos: Vector2) -> int:
	var t: EnemyType = EnemyType.get_type(kind)
	var e: EnemyState = EnemyState.new()
	e.id = _next_enemy_id
	_next_enemy_id += 1
	e.type = t
	e.pos = pos
	e.max_hp = t.max_hp * SimTuning.hp_mult(wave)
	e.hp = e.max_hp
	e.speed = t.speed * SimTuning.speed_mult(wave)
	enemies.append(e)
	return e.id


## Tests only: drop the remaining schedule.
func cancel_spawns() -> void:
	_schedule.resize(_next_spawn)


func _spawn_due() -> void:
	while _next_spawn < _schedule.size() and enemies.size() < SimTuning.MAX_LIVE_ENEMIES \
			and time >= WavePlan.spawn_time(wave, _next_spawn):
		spawn_enemy(_schedule[_next_spawn], _spawn_point())
		_next_spawn += 1


## The first of up to 4 random points outside the edges that is far enough from the player, else the farthest.
func _spawn_point() -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var best_dist: float = -1.0
	for i: int in SimTuning.SPAWN_CANDIDATES:
		var p: Vector2 = _edge_point()
		var dist: float = p.distance_to(player.pos)
		if dist >= SimTuning.SPAWN_MIN_PLAYER_DIST:
			return p
		if dist > best_dist:
			best = p
			best_dist = dist
	return best


## A uniform point along a random side of the rectangle SPAWN_OUTSIDE px outside the arena.
func _edge_point() -> Vector2:
	var lo: Vector2 = -Vector2.ONE * SimTuning.SPAWN_OUTSIDE
	var hi: Vector2 = SimTuning.ARENA_SIZE + Vector2.ONE * SimTuning.SPAWN_OUTSIDE
	var side: int = _rng.randi_range(0, 3)
	var along: float = _rng.randf()
	match side:
		0:
			return Vector2(lerpf(lo.x, hi.x, along), lo.y)
		1:
			return Vector2(hi.x, lerpf(lo.y, hi.y, along))
		2:
			return Vector2(lerpf(lo.x, hi.x, along), hi.y)
	return Vector2(lo.x, lerpf(lo.y, hi.y, along))


func _move_player(delta: float, intent: PlayerIntent) -> void:
	var r: Vector2 = Vector2.ONE * SimTuning.PLAYER_RADIUS
	player.pos = (player.pos + intent.move * SimTuning.PLAYER_SPEED * delta).clamp(r, SimTuning.ARENA_SIZE - r)
	player.invuln = maxf(player.invuln - delta, 0.0)
	var to_aim: Vector2 = intent.aim - player.pos
	if to_aim.length() >= 1.0:
		player.aim_dir = to_aim.normalized()


func _fire(events: Array[SimEvent]) -> void:
	var muzzle: Vector2 = player.pos + player.aim_dir * SimTuning.MUZZLE_OFFSET
	for spec: BulletSpec in plan.bullets:
		var b: BulletState = BulletState.new()
		b.id = _next_bullet_id
		_next_bullet_id += 1
		b.spec = spec
		b.pos = muzzle
		b.vel = player.aim_dir.rotated(spec.angle_offset) * spec.speed
		b.pierce_left = spec.pierce
		b.life = spec.lifetime
		bullets.append(b)
	events.append(SimEvent.make(SimEvent.Type.SHOT, muzzle, plan.bullets[0].primary_color()))


## D.4: sweep each bullet, apply its hits in (t, enemy index) order, then move or remove it.
func _move_bullets(delta: float, events: Array[SimEvent]) -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, SimTuning.ARENA_SIZE).grow(SimTuning.DESPAWN_MARGIN)
	var kept: Array[BulletState] = []
	for b: BulletState in bullets:
		var a: Vector2 = b.pos
		var to: Vector2 = b.pos + b.vel * delta
		var hits: Array[Vector2] = []     # (t, enemy index): Array[Vector2].sort() orders by x, then y
		for i: int in enemies.size():
			var e: EnemyState = enemies[i]
			if e.hp <= 0.0 or b.hit_ids.has(e.id):
				continue                  # a dead enemy is skipped by later bullets: no overkill
			var t: float = CollisionMath.first_contact(a, to, e.pos, e.radius() + b.spec.radius)
			if t >= 0.0:
				hits.append(Vector2(t, i))
		hits.sort()
		var alive: bool = true
		for h: Vector2 in hits:
			var e: EnemyState = enemies[int(h.y)]
			e.hp -= b.spec.damage
			e.status.apply_hit(b.spec)
			b.hit_ids[e.id] = true
			events.append(SimEvent.make(SimEvent.Type.HIT, a.lerp(to, h.x), b.spec.primary_color(), e.id))
			if b.pierce_left == 0:
				alive = false
				break
			b.pierce_left -= 1
		if not alive:
			continue
		b.pos = to
		b.life -= delta
		if b.life > 0.0 and bounds.has_point(b.pos):
			kept.append(b)
	bullets = kept


func _move_enemies(delta: float, events: Array[SimEvent]) -> void:
	for e: EnemyState in enemies:
		if e.hp <= 0.0:
			continue
		e.hp -= e.status.tick(delta)
		e.pos = e.pos.move_toward(player.pos, e.speed * e.status.speed_multiplier() * delta)
	_separate()
	for e: EnemyState in enemies:
		if e.hp <= 0.0:
			continue
		var away: Vector2 = e.pos - player.pos
		if away.length() > e.radius() + SimTuning.PLAYER_RADIUS:
			continue
		if player.invuln <= 0.0:
			player.hp -= e.type.contact_damage
			player.invuln = SimTuning.PLAYER_INVULN
			events.append(SimEvent.make(SimEvent.Type.PLAYER_HIT, player.pos, e.type.color, e.id))
		e.pos += _direction(away) * SimTuning.CONTACT_PUSHBACK


## Each overlapping pair loses SEPARATION of its overlap, split equally. O(n^2) with n <= 40.
func _separate() -> void:
	for i: int in enemies.size():
		var a: EnemyState = enemies[i]
		if a.hp <= 0.0:
			continue
		for j: int in range(i + 1, enemies.size()):
			var b: EnemyState = enemies[j]
			if b.hp <= 0.0:
				continue
			var d: Vector2 = b.pos - a.pos
			var overlap: float = a.radius() + b.radius() - d.length()
			if overlap <= 0.0:
				continue
			var push: Vector2 = _direction(d) * overlap * SimTuning.SEPARATION / 2.0
			a.pos -= push
			b.pos += push


func _remove_dead(events: Array[SimEvent]) -> void:
	var alive: Array[EnemyState] = []
	for e: EnemyState in enemies:
		if e.hp > 0.0:
			alive.append(e)
		else:
			kills += 1
			events.append(SimEvent.make(SimEvent.Type.KILL, e.pos, e.type.color, e.id))
	enemies = alive


func _finish(type: SimEvent.Type, events: Array[SimEvent]) -> void:
	_running = false
	_finished = true
	events.append(SimEvent.make(type, player.pos))


## Unit direction of v; coincident centres get a fixed direction so the result stays deterministic.
static func _direction(v: Vector2) -> Vector2:
	return v.normalized() if v != Vector2.ZERO else Vector2.RIGHT

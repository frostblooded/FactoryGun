extends RefCounted
## Scripted player for arena tests (docs/DESIGN.md I.5). If a balance test fails, tune only these four
## constants: Tuning and SimTuning numbers are frozen.

const KITE_DISTANCE: float = 260.0
const WALL_MARGIN: float = 140.0
const SIDESTEP: float = 0.6
const WALL_PUSH: float = 1.2


## Aims at the nearest enemy. Closer than KITE_DISTANCE: moves away plus SIDESTEP sideways. Within
## WALL_MARGIN of a wall: adds WALL_PUSH toward the centre. No enemies: no fire, no move.
static func intent(world: ArenaWorld, fire: bool = true) -> PlayerIntent:
	var p: Vector2 = world.player.pos
	var target: EnemyState = null
	for e: EnemyState in world.enemies:
		if target == null or p.distance_squared_to(e.pos) < p.distance_squared_to(target.pos):
			target = e
	if target == null:
		return PlayerIntent.make(Vector2.ZERO, p + world.player.aim_dir, false)
	var move: Vector2 = Vector2.ZERO
	if p.distance_to(target.pos) < KITE_DISTANCE:
		var away: Vector2 = (p - target.pos).normalized()
		move = away + away.orthogonal() * SIDESTEP
	var arena: Vector2 = SimTuning.ARENA_SIZE
	if p.x < WALL_MARGIN or p.y < WALL_MARGIN or p.x > arena.x - WALL_MARGIN or p.y > arena.y - WALL_MARGIN:
		move += (arena / 2.0 - p).normalized() * WALL_PUSH
	return PlayerIntent.make(move, target.pos, fire)


## Steps until the world stops or max_seconds of sim time pass. ArenaWorld-only: never call it on an
## ArenaController's world, whose signals come only from the controller's own step().
static func play(world: ArenaWorld, max_seconds: float, fire: bool = true) -> void:
	for i: int in roundi(max_seconds / SimTuning.STEP):
		if not world.is_running():
			return
		world.step(SimTuning.STEP, intent(world, fire))

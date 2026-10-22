class_name SimTuning
extends RefCounted
## Arena-only numbers (docs/DESIGN.md F.1). World coordinates are the arena control's local pixels.

const STEP: float = 1.0 / 60.0            # physics ticks are 60/s; tests step with this
const ARENA_SIZE: Vector2 = Vector2(1000, 900)
const PLAYER_SPEED: float = 240.0
const PLAYER_RADIUS: float = 13.0
const PLAYER_INVULN: float = 0.6
const MUZZLE_OFFSET: float = 22.0
const MAX_LIVE_ENEMIES: int = 40          # spawns wait while 40 are alive
const DESPAWN_MARGIN: float = 60.0
const SPAWN_OUTSIDE: float = 30.0         # enemies appear 30 px outside the edge and walk in
const SPAWN_MIN_PLAYER_DIST: float = 260.0
const SPAWN_CANDIDATES: int = 4
const FIRST_SPAWN_DELAY: float = 1.0
const CLEAR_GRACE: float = 1.0
const CONTACT_PUSHBACK: float = 30.0
const SEPARATION: float = 0.5             # fraction of a pair's overlap removed per step, split equally:
                                          # each enemy of the pair moves SEPARATION / 2 · overlap


static func hp_mult(wave: int) -> float:
	return 1.0 + 0.15 * (wave - 1)


static func speed_mult(wave: int) -> float:
	return minf(1.0 + 0.03 * (wave - 1), 1.4)


static func spawn_interval(wave: int) -> float:
	return maxf(0.3, 1.0 - 0.05 * (wave - 1))

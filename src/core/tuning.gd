class_name Tuning
extends RefCounted
## Every rules number shared by the factory, the readout and the run (docs/DESIGN.md B.1).

const GRID_COLS: int = 14
const GRID_ROWS: int = 12
const MAX_BULLETS_PER_SHOT: int = 8
const GUN_INTERVAL: float = 0.25          # 4 shots/s
const FAN_STEP_DEG: float = 10.0
const FAN_MAX_DEG: float = 50.0

const BASE_DAMAGE: float = 10.0
const BASE_SPEED: float = 600.0           # px/s
const BASE_RADIUS: float = 5.0            # px
const BASE_LIFETIME: float = 1.4          # s

const SPEED_MULT: float = 1.35            # per Speed Up level
const SPEED_DAMAGE_MULT: float = 1.10
const SIZE_RADIUS_MULT: float = 1.5       # per Size Up level
const SIZE_DAMAGE_MULT: float = 1.25
const SIZE_SPEED_MULT: float = 0.9
const PIERCE_PER_LEVEL: int = 1
const SPLIT_DAMAGE_MULT: float = 0.7      # per real split on the path

const FIRE_DPS_PER_LEVEL: float = 6.0
const FIRE_DURATION: float = 3.0
const ICE_SLOW_PER_LEVEL: float = 0.2
const ICE_DURATION: float = 2.0
const POISON_STACKS_PER_LEVEL: int = 1
const POISON_DPS_PER_STACK: float = 1.5
const POISON_DURATION: float = 4.0
const POISON_MAX_STACKS: int = 15

const PLAYER_MAX_HP: float = 100.0
const HEAL_ON_REWARD: float = 25.0
const OFFER_COUNT: int = 3
# Literals, not MachineCatalog constants: a cross-script const expression risks a cyclic resolution.
const START_INVENTORY: Dictionary[StringName, int] = {&"fire": 1, &"speed_up": 1}

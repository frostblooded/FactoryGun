class_name StatusEffects
extends RefCounted
## Burn, chill and poison on one enemy (docs/DESIGN.md D.3).

var burn_dps: float = 0.0
var burn_time: float = 0.0
var slow: float = 0.0
var slow_time: float = 0.0
var poison_stacks: int = 0
var poison_time: float = 0.0


## Only effects with level > 0 apply. Burn and chill keep the strongest; poison stacks and refreshes all stacks.
func apply_hit(spec: BulletSpec) -> void:
	if spec.fire_level > 0:
		burn_dps = maxf(burn_dps if is_burning() else 0.0, spec.burn_dps())
		burn_time = Tuning.FIRE_DURATION
	if spec.ice_level > 0:
		slow = maxf(slow if is_chilled() else 0.0, spec.slow_fraction())
		slow_time = Tuning.ICE_DURATION
	if spec.poison_level > 0:
		poison_stacks = mini((poison_stacks if is_poisoned() else 0) + spec.poison_stacks_per_hit(),
				Tuning.POISON_MAX_STACKS)
		poison_time = Tuning.POISON_DURATION


## Returns the DoT damage for this step. Integrates exactly, so totals do not depend on the frame rate.
func tick(delta: float) -> float:
	var dmg: float = burn_dps * minf(delta, burn_time) \
			+ poison_stacks * Tuning.POISON_DPS_PER_STACK * minf(delta, poison_time)
	burn_time = maxf(burn_time - delta, 0.0)
	slow_time = maxf(slow_time - delta, 0.0)
	poison_time = maxf(poison_time - delta, 0.0)
	if burn_time <= 0.0:
		burn_dps = 0.0
	if slow_time <= 0.0:
		slow = 0.0
	if poison_time <= 0.0:
		poison_stacks = 0
	return dmg


func is_burning() -> bool:
	return burn_time > 0.0


func is_chilled() -> bool:
	return slow_time > 0.0


func is_poisoned() -> bool:
	return poison_time > 0.0


func speed_multiplier() -> float:
	return 1.0 - slow if is_chilled() else 1.0

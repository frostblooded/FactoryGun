class_name WavePlan
extends RefCounted
## Which enemies a wave sends, in what order and when (docs/DESIGN.md F.3).


static func counts(wave: int) -> Dictionary[EnemyType.Kind, int]:
	return {
		EnemyType.Kind.GRUNT: 4 + 2 * wave,
		EnemyType.Kind.RUNNER: maxi(2 * (wave - 1), 0),
		EnemyType.Kind.BRUTE: (wave - 2) / 2 if wave >= 4 else 0,
	}


## The counts in Kind order, shuffled with Fisher-Yates: i from n-1 down to 1, j = randi_range(0, i).
static func order(wave: int, rng: RandomNumberGenerator) -> Array[EnemyType.Kind]:
	var out: Array[EnemyType.Kind] = []
	var c: Dictionary[EnemyType.Kind, int] = counts(wave)
	for kind: EnemyType.Kind in c:
		for i: int in c[kind]:
			out.append(kind)
	for i: int in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: EnemyType.Kind = out[i]
		out[i] = out[j]
		out[j] = swap
	return out


## Spawn index is due at 1.0 + index · spawn_interval(wave) seconds into the wave.
static func spawn_time(wave: int, index: int) -> float:
	return SimTuning.FIRST_SPAWN_DELAY + index * SimTuning.spawn_interval(wave)

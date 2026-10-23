class_name Seeds
extends RefCounted
## Per-purpose RNG seeds. String.hash() is djb2-like: "wave|1|1" and "wave|1|2" give adjacent
## integers, and similar seeds give similar RandomNumberGenerator streams. SHA-256 mixes every bit.

const WAVE: StringName = &"wave"
const REWARD: StringName = &"reward"


## A non-negative 60-bit integer: 15 hex digits never overflow int.
static func derive(run_seed: int, wave: int, purpose: StringName) -> int:
	return ("%s|%d|%d" % [purpose, run_seed, wave]).sha256_text().substr(0, 15).hex_to_int()

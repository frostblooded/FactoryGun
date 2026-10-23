class_name RewardGenerator
extends RefCounted
## The machine offers after a cleared wave (docs/DESIGN.md H.2). Seeded, so the same run and wave
## always offer the same cards.


## Tuning.OFFER_COUNT distinct placeable kinds, in palette order.
static func generate(run_seed: int, wave_cleared: int, ever_owned: Array[StringName]) -> Array[RewardOffer]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Seeds.derive(run_seed, wave_cleared, Seeds.REWARD)
	var picked: Array[StringName] = []
	if wave_cleared == 1 and not ever_owned.has(MachineCatalog.SPLITTER):
		picked.append(MachineCatalog.SPLITTER)                 # every run can try branching early
	while picked.size() < Tuning.OFFER_COUNT:
		var candidates: Array[StringName] = []
		var weights: PackedFloat32Array = []
		for kind: StringName in MachineCatalog.PALETTE_ORDER:
			if not picked.has(kind):
				candidates.append(kind)
				weights.append(weight_of(kind, wave_cleared))
		picked.append(candidates[rng.rand_weighted(weights)])
	var offers: Array[RewardOffer] = []
	for kind: StringName in MachineCatalog.PALETTE_ORDER:
		if picked.has(kind):
			offers.append(RewardOffer.make(kind, amount_of(kind, wave_cleared)))
	return offers


## 0 for a kind that is never offered.
static func weight_of(kind: StringName, wave_cleared: int) -> float:
	if kind == MachineCatalog.SPLITTER:
		return minf(2.0 + wave_cleared, 8.0)
	if kind == MachineCatalog.PIERCE:
		return 6.0
	return 10.0 if MachineCatalog.palette_index(kind) != -1 else 0.0


## 0 for a kind that is never offered.
static func amount_of(kind: StringName, wave_cleared: int) -> int:
	if kind == MachineCatalog.SPLITTER:
		return 1
	if kind == MachineCatalog.PIERCE:
		return 2 if wave_cleared >= 5 else 1
	return 2 if MachineCatalog.palette_index(kind) != -1 else 0

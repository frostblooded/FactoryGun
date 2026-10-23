extends GutTest

const MODIFIERS_10: Array[StringName] = [MachineCatalog.FIRE, MachineCatalog.ICE, MachineCatalog.POISON,
		MachineCatalog.SPEED_UP, MachineCatalog.SIZE_UP]    # weight 10, amount 2


func test_three_distinct_offers_in_palette_order() -> void:
	for wave: int in range(1, 11):
		for run_seed: int in 20:
			var offers: Array[RewardOffer] = RewardGenerator.generate(run_seed, wave, [MachineCatalog.FIRE])
			var label: String = "seed %d, wave %d" % [run_seed, wave]
			assert_eq(offers.size(), Tuning.OFFER_COUNT, label)
			var last: int = -1
			for o: RewardOffer in offers:
				var index: int = MachineCatalog.palette_index(o.kind)
				assert_gt(index, last, label)                    # placeable, distinct and in palette order
				last = index
				assert_eq(o.amount, RewardGenerator.amount_of(o.kind, wave), label)
	assert_eq(RewardOffer.make(MachineCatalog.FIRE, 2).label(), "Fire ×2")
	assert_eq(RewardOffer.make(MachineCatalog.SPEED_UP, 1).label(), "Speed Up ×1")
	assert_eq(RewardOffer.new().amount, 1)


func test_same_inputs_same_offers() -> void:
	var distinct: Dictionary[String, bool] = {}
	var wave_changes: int = 0
	for run_seed: int in 20:
		var offers: String = _labels(RewardGenerator.generate(run_seed, 3, []))
		assert_eq(_labels(RewardGenerator.generate(run_seed, 3, [])), offers, str(run_seed))
		distinct[offers] = true
		if _labels(RewardGenerator.generate(run_seed, 4, [])) != offers:
			wave_changes += 1
	assert_gt(distinct.size(), 1, "the run seed changes the offers")
	assert_gt(wave_changes, 0, "the wave changes the offers")


func test_first_reward_includes_splitter_unless_owned() -> void:
	var start: Array[StringName] = [MachineCatalog.FIRE, MachineCatalog.SPEED_UP]
	var with_splitter: Array[StringName] = [MachineCatalog.FIRE, MachineCatalog.SPLITTER]
	var free_when_owned: int = 0
	var free_later: int = 0
	for run_seed: int in 50:
		var first: Array[RewardOffer] = RewardGenerator.generate(run_seed, 1, start)
		assert_eq(first.size(), Tuning.OFFER_COUNT)
		assert_eq(first[-1].kind, MachineCatalog.SPLITTER, str(run_seed))   # the Splitter sorts last
		assert_eq(first[-1].amount, 1)
		if not _kinds(RewardGenerator.generate(run_seed, 1, with_splitter)).has(MachineCatalog.SPLITTER):
			free_when_owned += 1
		if not _kinds(RewardGenerator.generate(run_seed, 2, start)).has(MachineCatalog.SPLITTER):
			free_later += 1
	assert_gt(free_when_owned, 0, "a run that already owns a Splitter is not forced to get another")
	assert_gt(free_later, 0, "only the first reward forces the Splitter")


func test_amounts() -> void:
	for kind: StringName in MODIFIERS_10:
		for wave: int in [1, 4, 5, 20]:
			assert_eq(RewardGenerator.amount_of(kind, wave), 2, "%s wave %d" % [kind, wave])
	assert_eq(RewardGenerator.amount_of(MachineCatalog.PIERCE, 1), 1)
	assert_eq(RewardGenerator.amount_of(MachineCatalog.PIERCE, 4), 1)
	assert_eq(RewardGenerator.amount_of(MachineCatalog.PIERCE, 5), 2)
	assert_eq(RewardGenerator.amount_of(MachineCatalog.PIERCE, 12), 2)
	assert_eq(RewardGenerator.amount_of(MachineCatalog.SPLITTER, 1), 1)
	assert_eq(RewardGenerator.amount_of(MachineCatalog.SPLITTER, 9), 1)
	assert_eq(RewardGenerator.amount_of(MachineCatalog.SOURCE, 1), 0)
	assert_eq(RewardGenerator.amount_of(&"laser", 1), 0)


func test_weights() -> void:
	for kind: StringName in MODIFIERS_10:
		assert_almost_eq(RewardGenerator.weight_of(kind, 1), 10.0, 1e-4, String(kind))
		assert_almost_eq(RewardGenerator.weight_of(kind, 9), 10.0, 1e-4, String(kind))
	assert_almost_eq(RewardGenerator.weight_of(MachineCatalog.PIERCE, 1), 6.0, 1e-4)
	assert_almost_eq(RewardGenerator.weight_of(MachineCatalog.PIERCE, 30), 6.0, 1e-4)
	assert_almost_eq(RewardGenerator.weight_of(MachineCatalog.SPLITTER, 1), 3.0, 1e-4)
	assert_almost_eq(RewardGenerator.weight_of(MachineCatalog.SPLITTER, 5), 7.0, 1e-4)
	assert_almost_eq(RewardGenerator.weight_of(MachineCatalog.SPLITTER, 6), 8.0, 1e-4)
	assert_almost_eq(RewardGenerator.weight_of(MachineCatalog.SPLITTER, 40), 8.0, 1e-4)
	assert_almost_eq(RewardGenerator.weight_of(MachineCatalog.OUTPUT, 1), 0.0, 1e-4)
	assert_almost_eq(RewardGenerator.weight_of(&"laser", 1), 0.0, 1e-4)


func test_distribution_sanity() -> void:
	var seen: Dictionary[StringName, int] = {}
	for run_seed: int in 2000:
		for o: RewardOffer in RewardGenerator.generate(run_seed, 3, [MachineCatalog.FIRE, MachineCatalog.SPEED_UP]):
			seen[o.kind] = seen.get(o.kind, 0) + 1
	assert_gt(seen.get(MachineCatalog.FIRE, 0), seen.get(MachineCatalog.PIERCE, 0))   # weight 10 against 6
	for kind: StringName in MachineCatalog.PALETTE_ORDER:
		assert_gt(seen.get(kind, 0), 0, String(kind))


func _kinds(offers: Array[RewardOffer]) -> Array[StringName]:
	var out: Array[StringName] = []
	for o: RewardOffer in offers:
		out.append(o.kind)
	return out


func _labels(offers: Array[RewardOffer]) -> String:
	var out: PackedStringArray = []
	for o: RewardOffer in offers:
		out.append(o.label())
	return ", ".join(out)

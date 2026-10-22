extends GutTest


func test_deterministic_and_non_negative() -> void:
	for run_seed: int in [0, 1, -1, 42, 2147483647, -9223372036854775807]:
		for wave: int in [1, 2, 50]:
			for purpose: StringName in [Seeds.WAVE, Seeds.REWARD]:
				var s: int = Seeds.derive(run_seed, wave, purpose)
				assert_eq(s, Seeds.derive(run_seed, wave, purpose))
				assert_between(s, 0, (1 << 60) - 1)
	# the first 15 hex digits of sha256("wave|0|1") and sha256("reward|0|1")
	assert_eq(Seeds.derive(0, 1, Seeds.WAVE), 378196640141433066)
	assert_eq(Seeds.derive(0, 1, Seeds.REWARD), 884713540714916435)


func test_each_input_changes_the_seed() -> void:
	var base: int = Seeds.derive(7, 3, Seeds.WAVE)
	assert_ne(base, Seeds.derive(8, 3, Seeds.WAVE))
	assert_ne(base, Seeds.derive(7, 4, Seeds.WAVE))
	assert_ne(base, Seeds.derive(7, 3, Seeds.REWARD))
	# adjacent inputs give far-apart seeds (String.hash() would give adjacent ones)
	assert_gt(absi(Seeds.derive(1, 1, Seeds.WAVE) - Seeds.derive(1, 2, Seeds.WAVE)), 1 << 32)

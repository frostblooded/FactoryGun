extends GutTest

const Fixtures = preload("res://test/helpers/fixtures.gd")


func test_from_counts_and_count() -> void:
	var inv: Inventory = Inventory.from_counts(Tuning.START_INVENTORY)
	assert_eq(inv.count(MachineCatalog.FIRE), 1)
	assert_eq(inv.count(MachineCatalog.SPEED_UP), 1)
	assert_eq(inv.count(MachineCatalog.ICE), 0)
	assert_true(inv.ever_owned(MachineCatalog.FIRE))
	assert_true(inv.ever_owned(MachineCatalog.SPEED_UP))
	assert_false(inv.ever_owned(MachineCatalog.ICE))
	assert_true(inv.take(MachineCatalog.FIRE))   # the const was copied, so the counts are writable
	assert_eq(inv.count(MachineCatalog.FIRE), 0)
	assert_eq(Tuning.START_INVENTORY[MachineCatalog.FIRE], 1)
	var mixed: Inventory = Inventory.from_counts({MachineCatalog.SOURCE: 2, &"laser": 1, MachineCatalog.ICE: 0,
			MachineCatalog.POISON: 3, MachineCatalog.PIERCE: -1})
	assert_eq(mixed.to_dict(), {"poison": 3})
	assert_eq(mixed.kinds_ever_owned(), [MachineCatalog.POISON])
	assert_false(mixed.ever_owned(MachineCatalog.SOURCE))
	assert_false(mixed.ever_owned(MachineCatalog.ICE))


func test_take_until_empty() -> void:
	var inv: Inventory = Inventory.from_counts({MachineCatalog.FIRE: 2})
	assert_true(inv.take(MachineCatalog.FIRE))
	assert_true(inv.take(MachineCatalog.FIRE))
	assert_false(inv.take(MachineCatalog.FIRE))
	assert_eq(inv.count(MachineCatalog.FIRE), 0)
	assert_false(inv.take(MachineCatalog.ICE))
	assert_false(inv.take(&"laser"))
	assert_eq(inv.to_dict(), {})


func test_add_rejects_unplaceable_unknown_and_non_positive() -> void:
	var inv: Inventory = Inventory.new()
	watch_signals(inv)
	assert_false(inv.add(MachineCatalog.SOURCE))
	assert_false(inv.add(MachineCatalog.OUTPUT, 2))
	assert_false(inv.add(&"laser"))
	assert_false(inv.add(MachineCatalog.FIRE, 0))
	assert_false(inv.add(MachineCatalog.FIRE, -1))
	assert_eq(inv.to_dict(), {})
	assert_true(inv.kinds_ever_owned().is_empty())
	assert_signal_emit_count(inv, "changed", 0)
	assert_true(inv.add(MachineCatalog.FIRE))
	assert_true(inv.add(MachineCatalog.FIRE, 3))
	assert_eq(inv.count(MachineCatalog.FIRE), 4)
	assert_eq(Fixtures.inventory_all(2).to_dict(),
			{"fire": 2, "ice": 2, "poison": 2, "speed_up": 2, "size_up": 2, "pierce": 2, "splitter": 2})


func test_ever_owned_survives_taking_all() -> void:
	var inv: Inventory = Inventory.new()
	assert_true(inv.add(MachineCatalog.SPLITTER))
	assert_true(inv.take(MachineCatalog.SPLITTER))
	assert_eq(inv.count(MachineCatalog.SPLITTER), 0)
	assert_true(inv.ever_owned(MachineCatalog.SPLITTER))
	assert_eq(inv.kinds_ever_owned(), [MachineCatalog.SPLITTER])
	assert_eq(inv.to_dict(), {})


func test_kinds_ever_owned_in_palette_order() -> void:
	var inv: Inventory = Inventory.new()
	for kind: StringName in [MachineCatalog.SPLITTER, MachineCatalog.FIRE, MachineCatalog.PIERCE]:
		inv.add(kind)
	var kinds: Array[StringName] = inv.kinds_ever_owned()
	assert_eq(kinds, [MachineCatalog.FIRE, MachineCatalog.PIERCE, MachineCatalog.SPLITTER])
	assert_eq(inv.to_dict().keys(), ["fire", "pierce", "splitter"])
	assert_eq(Fixtures.inventory_all(1).kinds_ever_owned(), MachineCatalog.PALETTE_ORDER)


func test_changed_counts() -> void:
	var inv: Inventory = Inventory.from_counts(Tuning.START_INVENTORY)
	watch_signals(inv)
	inv.add(MachineCatalog.ICE, 2)
	inv.add(MachineCatalog.SOURCE)       # refused
	inv.take(MachineCatalog.ICE)
	inv.take(MachineCatalog.POISON)      # refused
	assert_signal_emit_count(inv, "changed", 2)
	var other: Inventory = Inventory.from_counts({MachineCatalog.SPLITTER: 1})
	inv.assign_from(other)
	assert_signal_emit_count(inv, "changed", 3)
	assert_eq(inv.to_dict(), {"splitter": 1})
	assert_eq(inv.kinds_ever_owned(), [MachineCatalog.SPLITTER])   # ever-owned is copied too
	assert_true(inv.take(MachineCatalog.SPLITTER))
	assert_eq(other.count(MachineCatalog.SPLITTER), 1)            # copied, not shared

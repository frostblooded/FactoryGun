extends GutTest


func test_nine_kinds_with_ports() -> void:
	# kind -> [display_name, short_name, input ports, output ports]
	var table: Dictionary[StringName, Array] = {
		MachineCatalog.SOURCE: ["Basic Bullet", "BULLET", 0, 1],
		MachineCatalog.OUTPUT: ["Output", "OUTPUT", 1, 0],
		MachineCatalog.FIRE: ["Fire", "FIRE", 1, 1],
		MachineCatalog.ICE: ["Ice", "ICE", 1, 1],
		MachineCatalog.POISON: ["Poison", "POISON", 1, 1],
		MachineCatalog.SPEED_UP: ["Speed Up", "SPEED", 1, 1],
		MachineCatalog.SIZE_UP: ["Size Up", "SIZE", 1, 1],
		MachineCatalog.PIERCE: ["Pierce", "PIERCE", 1, 1],
		MachineCatalog.SPLITTER: ["Splitter", "SPLIT", 1, 2],
	}
	assert_eq(table.size(), 9)
	for kind: StringName in table:
		var def: MachineDef = MachineCatalog.get_def(kind)
		assert_true(MachineCatalog.has_kind(kind), String(kind))
		assert_eq(def.kind, kind)
		assert_eq([def.display_name, def.short_name, def.input_ports, def.output_ports], table[kind], String(kind))
		assert_false(def.description.is_empty(), String(kind))
		assert_eq(def.is_splitter(), kind == MachineCatalog.SPLITTER, String(kind))
		assert_eq(def.is_modifier(), def.placeable and kind != MachineCatalog.SPLITTER, String(kind))
	assert_eq(MachineCatalog.get_def(MachineCatalog.SOURCE).color, Color("d9b45a"))
	assert_eq(MachineCatalog.get_def(MachineCatalog.SPLITTER).description,
			"Forks the stream: each output fires its own bullets. ×0.7 damage when both outputs are used.")
	assert_same(MachineCatalog.get_def(MachineCatalog.FIRE), MachineCatalog.get_def(MachineCatalog.FIRE))


func test_caps() -> void:
	for kind: StringName in [MachineCatalog.FIRE, MachineCatalog.ICE, MachineCatalog.POISON,
			MachineCatalog.SPEED_UP, MachineCatalog.SIZE_UP]:
		assert_eq(MachineCatalog.get_def(kind).max_stacks, 3, String(kind))
	assert_eq(MachineCatalog.get_def(MachineCatalog.PIERCE).max_stacks, 4)
	for kind: StringName in [MachineCatalog.SOURCE, MachineCatalog.OUTPUT, MachineCatalog.SPLITTER]:
		assert_eq(MachineCatalog.get_def(kind).max_stacks, 0, String(kind))


func test_source_and_output_fixed() -> void:
	for kind: StringName in [MachineCatalog.SOURCE, MachineCatalog.OUTPUT]:
		var def: MachineDef = MachineCatalog.get_def(kind)
		assert_false(def.removable, String(kind))
		assert_false(def.placeable, String(kind))
		assert_false(def.is_modifier(), String(kind))
		assert_eq(MachineCatalog.palette_index(kind), -1, String(kind))
	var kinds: Array[StringName] = MachineCatalog.placeable_kinds()
	assert_eq(kinds, MachineCatalog.PALETTE_ORDER)
	for i: int in kinds.size():
		assert_true(MachineCatalog.get_def(kinds[i]).removable, String(kinds[i]))
		assert_true(MachineCatalog.get_def(kinds[i]).placeable, String(kinds[i]))
		assert_eq(MachineCatalog.palette_index(kinds[i]), i)
	kinds.clear()                             # a copy: the palette order is untouched
	assert_eq(MachineCatalog.PALETTE_ORDER.size(), 7)


func test_unknown_kind_is_null() -> void:
	assert_null(MachineCatalog.get_def(&"laser"))
	assert_false(MachineCatalog.has_kind(&"laser"))
	assert_eq(MachineCatalog.palette_index(&"laser"), -1)
	assert_null(MachineCatalog.get_def(&""))

extends RefCounted
## Builds graphs, plans and inventories for tests through the public API only.
## Machine ids are assigned in order from 3.


## Source -> kinds[0] -> ... -> Output (default belt replaced); machine i at chain_cell(i).
static func chain(kinds: Array[StringName]) -> FactoryGraph:
	var g: FactoryGraph = FactoryGraph.create_default()
	var prev: int = FactoryGraph.SOURCE_ID
	for i: int in kinds.size():
		var id: int = g.add_machine(kinds[i], chain_cell(i))
		g.connect_ports(prev, 0, id, 0)
		prev = id
	g.connect_ports(prev, 0, FactoryGraph.OUTPUT_ID, 0)
	return g


## Rows 1, 4, 7 and 10, four machines each: up to 16 machines.
static func chain_cell(i: int) -> Vector2i:
	return Vector2i(3 + 2 * (i % 4), 1 + 3 * (i / 4))


## Source -> Splitter (id 3, cell (3,5)); port 0 -> upper[i] at (5 + 2i, 2) -> Output;
## port 1 -> lower[i] at (5 + 2i, 8) -> Output; an empty branch goes straight to the Output (max 3 per branch).
static func split(upper: Array[StringName], lower: Array[StringName]) -> FactoryGraph:
	var g: FactoryGraph = FactoryGraph.create_default()
	var splitter: int = g.add_machine(MachineCatalog.SPLITTER, Vector2i(3, 5))
	g.connect_ports(FactoryGraph.SOURCE_ID, 0, splitter, 0)
	_branch(g, splitter, 0, upper, 2)
	_branch(g, splitter, 1, lower, 8)
	return g


## ShotPlan.new() with these bullets (no compiler needed).
static func plan_of(specs: Array[BulletSpec]) -> ShotPlan:
	var plan: ShotPlan = ShotPlan.new()
	plan.bullets.assign(specs)
	return plan


## n of every placeable kind.
static func inventory_all(n: int) -> Inventory:
	var inv: Inventory = Inventory.new()
	for kind: StringName in MachineCatalog.placeable_kinds():
		inv.add(kind, n)
	return inv


static func _branch(g: FactoryGraph, splitter: int, port: int, kinds: Array[StringName], row: int) -> void:
	var prev: int = splitter
	var prev_port: int = port
	for i: int in kinds.size():
		var id: int = g.add_machine(kinds[i], Vector2i(5 + 2 * i, row))
		g.connect_ports(prev, prev_port, id, 0)
		prev = id
		prev_port = 0
	g.connect_ports(prev, prev_port, FactoryGraph.OUTPUT_ID, 0)

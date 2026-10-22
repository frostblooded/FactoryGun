class_name RunState
extends RefCounted
## Aggregate root of one run. graph, inventory and flow are the same instances for the whole
## session (restart() copies into them), so views bind once.
## Every try_* returns LOCKED outside BUILD, and a refused try_* changes nothing at all.

signal plan_changed(plan: ShotPlan)

const NO_PATH_REASON: String = "Connect the Basic Bullet to the Output first."

var graph: FactoryGraph = FactoryGraph.create_default()
var inventory: Inventory = Inventory.from_counts(Tuning.START_INVENTORY)
var flow: GameFlow = GameFlow.new()
var plan: ShotPlan                        # compiled in _init and after every graph change
var active_plan: ShotPlan = ShotPlan.empty()   # frozen by start_wave(); the arena fires this
var run_seed: int = 0
var player_hp: float = Tuning.PLAYER_MAX_HP
var total_kills: int = 0
var offers: Array[RewardOffer] = []       # set by complete_wave(); cleared by choose_offer/fail_wave/restart


func _init(p_run_seed: int = 0) -> void:
	run_seed = p_run_seed
	plan = FactoryCompiler.compile(graph)
	graph.changed.connect(_on_graph_changed)   # a method, not a lambda: no reference cycle (A.4.4)


## LOCKED -> OUT_OF_STOCK (a known, placeable kind with none left) -> the graph's own checks (C.3).
## A splice drops the machine onto that belt. Takes 1 from the inventory.
func try_place_machine(kind: StringName, cell: Vector2i, splice: Wire = null) -> GraphError.Code:
	if not flow.is_editing_allowed():
		return GraphError.Code.LOCKED
	if MachineCatalog.palette_index(kind) != -1 and inventory.count(kind) == 0:
		return GraphError.Code.OUT_OF_STOCK
	var code: GraphError.Code = graph.can_add_machine(kind, cell) if splice == null \
			else graph.can_splice(kind, cell, splice)
	if code == GraphError.Code.OK:
		inventory.take(kind)             # before the graph, so plan_changed listeners see the final inventory
		if splice == null:
			graph.add_machine(kind, cell)
		else:
			graph.splice_machine(kind, cell, splice)
	return code


func try_move_machine(id: int, cell: Vector2i) -> GraphError.Code:
	if not flow.is_editing_allowed():
		return GraphError.Code.LOCKED
	return graph.move_machine(id, cell)


## Refunds 1 to the inventory.
func try_remove_machine(id: int) -> GraphError.Code:
	if not flow.is_editing_allowed():
		return GraphError.Code.LOCKED
	var code: GraphError.Code = graph.can_remove_machine(id)
	if code == GraphError.Code.OK:
		inventory.add(graph.kind_of(id))  # before the graph, as in try_place_machine
		graph.remove_machine(id)
	return code


func try_connect(from_id: int, from_port: int, to_id: int, to_port: int) -> GraphError.Code:
	if not flow.is_editing_allowed():
		return GraphError.Code.LOCKED
	return graph.connect_ports(from_id, from_port, to_id, to_port)


func try_disconnect(w: Wire) -> GraphError.Code:
	if not flow.is_editing_allowed():
		return GraphError.Code.LOCKED
	return graph.disconnect_wire(w)


## In the inventory plus on the floor. Only rewards change it.
func owned(kind: StringName) -> int:
	return inventory.count(kind) + graph.count_kind(kind)


func can_start_wave() -> bool:
	return flow.state == GameFlow.State.BUILD and plan.is_valid()


## Why Start is disabled, or "".
func start_reason() -> String:
	return "" if plan.is_valid() else NO_PATH_REASON


## Freezes the current plan as the one the arena fires this wave.
func start_wave() -> bool:
	if not can_start_wave():
		return false
	active_plan = plan
	return flow.start_wave()


func wave_seed() -> int:
	return Seeds.derive(run_seed, flow.wave, Seeds.WAVE)


## PLAY only. The offers are set before flow.clear_wave(), so state_changed listeners already see them.
func complete_wave(hp_left: float, kills: int) -> bool:
	if flow.state != GameFlow.State.PLAY:
		return false
	player_hp = hp_left
	total_kills += kills
	offers = RewardGenerator.generate(run_seed, flow.wave, inventory.kinds_ever_owned())
	return flow.clear_wave()


## PLAY only.
func fail_wave(kills: int) -> bool:
	if flow.state != GameFlow.State.PLAY:
		return false
	player_hp = 0.0
	total_kills += kills
	offers = []
	return flow.lose()


## REWARD only, with a valid index: adds the offer, heals (capped at full HP), then builds the next wave.
func choose_offer(index: int) -> bool:
	if flow.state != GameFlow.State.REWARD or index < 0 or index >= offers.size():
		return false
	inventory.add(offers[index].kind, offers[index].amount)
	player_hp = minf(player_hp + Tuning.HEAL_ON_REWARD, Tuning.PLAYER_MAX_HP)
	offers = []
	return flow.finish_reward()


## A fresh run in the same instances. flow.restart() goes last, so its listeners see the reset run.
func restart(p_run_seed: int) -> void:
	run_seed = p_run_seed
	player_hp = Tuning.PLAYER_MAX_HP
	total_kills = 0
	offers = []
	active_plan = ShotPlan.empty()
	inventory.assign_from(Inventory.from_counts(Tuning.START_INVENTORY))
	graph.assign_from(FactoryGraph.create_default())   # recompiles the plan through graph.changed
	flow.restart()


func _on_graph_changed() -> void:
	plan = FactoryCompiler.compile(graph)
	plan_changed.emit(plan)

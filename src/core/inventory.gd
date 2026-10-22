class_name Inventory
extends RefCounted
## Machines held but not placed. Only placeable kinds are ever stored.

signal changed

var _counts: Dictionary[StringName, int] = {}
var _ever: Dictionary[StringName, bool] = {}


## Copies key by key (never stores counts: a const dictionary is read-only); emits nothing.
## Keeps only placeable kinds with a count above 0, and marks each kept kind ever-owned.
static func from_counts(counts: Dictionary[StringName, int]) -> Inventory:
	var inv: Inventory = Inventory.new()
	for kind: StringName in counts:
		if MachineCatalog.palette_index(kind) != -1 and counts[kind] > 0:
			inv._counts[kind] = counts[kind]
			inv._ever[kind] = true
	return inv


func count(kind: StringName) -> int:
	return _counts.get(kind, 0)


## false, no change: unknown or unplaceable kind, or amount <= 0.
func add(kind: StringName, amount: int = 1) -> bool:
	if MachineCatalog.palette_index(kind) == -1 or amount <= 0:
		return false
	_counts[kind] = count(kind) + amount
	_ever[kind] = true
	changed.emit()
	return true


## false, no change: none left.
func take(kind: StringName) -> bool:
	if count(kind) <= 0:
		return false
	_counts[kind] -= 1
	changed.emit()
	return true


## true once added, even after taking all.
func ever_owned(kind: StringName) -> bool:
	return _ever.has(kind)


func kinds_ever_owned() -> Array[StringName]:
	return MachineCatalog.PALETTE_ORDER.filter(func(k: StringName) -> bool: return _ever.has(k))


## Copies counts and ever-owned; emits once.
func assign_from(other: Inventory) -> void:
	_counts.assign(other._counts)
	_ever.assign(other._ever)
	changed.emit()


## {"fire": 2, ...} for counts > 0, in palette order.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for kind: StringName in MachineCatalog.PALETTE_ORDER:
		if count(kind) > 0:
			out[String(kind)] = count(kind)
	return out

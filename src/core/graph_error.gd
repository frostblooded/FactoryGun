class_name GraphError
extends RefCounted
## Why a factory edit was refused, and the text the player sees for it.

enum Code {
	OK,
	LOCKED,
	UNKNOWN_KIND,
	NOT_PLACEABLE,
	OUT_OF_BOUNDS,
	CELL_OCCUPIED,
	NO_SUCH_MACHINE,
	NOT_REMOVABLE,
	NO_SUCH_PORT,
	NO_SUCH_WIRE,
	SELF_LOOP,
	DUPLICATE_WIRE,
	WOULD_CYCLE,
	TOO_MANY_BULLETS,
	OUT_OF_STOCK,
}


static func describe(code: Code) -> String:
	match code:
		Code.LOCKED:
			return "The factory is locked until the next build phase."
		Code.UNKNOWN_KIND:
			return "Unknown machine."
		Code.NOT_PLACEABLE:
			return "That machine can't be placed."
		Code.OUT_OF_BOUNDS:
			return "That doesn't fit on the factory floor."
		Code.CELL_OCCUPIED:
			return "Something is already there."
		Code.NO_SUCH_MACHINE:
			return "That machine no longer exists."
		Code.NOT_REMOVABLE:
			return "The Basic Bullet and the Output can't be removed."
		Code.NO_SUCH_PORT:
			return "There is no such port."
		Code.NO_SUCH_WIRE:
			return "That belt no longer exists."
		Code.SELF_LOOP:
			return "A machine can't feed itself."
		Code.DUPLICATE_WIRE:
			return "Those ports are already connected."
		Code.WOULD_CYCLE:
			return "That would make a loop: bullets can't go backwards."
		Code.TOO_MANY_BULLETS:
			return "The gun fires at most %d bullets per shot." % Tuning.MAX_BULLETS_PER_SHOT
		Code.OUT_OF_STOCK:
			return "None left. Earn more by clearing waves."
	return ""

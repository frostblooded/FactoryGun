class_name BulletSpec
extends RefCounted
## Stats of one bullet of a shot, or of the partial stream on one belt.

const ROMAN: PackedStringArray = ["", "I", "II", "III"]

var damage: float = Tuning.BASE_DAMAGE
var speed: float = Tuning.BASE_SPEED
var radius: float = Tuning.BASE_RADIUS
var lifetime: float = Tuning.BASE_LIFETIME
var pierce: int = 0
var fire_level: int = 0
var ice_level: int = 0
var poison_level: int = 0
var speed_level: int = 0
var size_level: int = 0
var real_splits: int = 0
## Radians added to the aim angle. y points down, so negative is counter-clockwise on screen.
var angle_offset: float = 0.0


## counts: occurrences of each modifier kind on the path. Levels are clamped to MachineDef.max_stacks here.
static func from_counts(counts: Dictionary[StringName, int], p_real_splits: int) -> BulletSpec:
	var s: BulletSpec = BulletSpec.new()
	s.fire_level = _level(counts, MachineCatalog.FIRE)
	s.ice_level = _level(counts, MachineCatalog.ICE)
	s.poison_level = _level(counts, MachineCatalog.POISON)
	s.speed_level = _level(counts, MachineCatalog.SPEED_UP)
	s.size_level = _level(counts, MachineCatalog.SIZE_UP)
	s.pierce = _level(counts, MachineCatalog.PIERCE) * Tuning.PIERCE_PER_LEVEL
	s.real_splits = p_real_splits
	s.damage = Tuning.BASE_DAMAGE * pow(Tuning.SPEED_DAMAGE_MULT, s.speed_level) \
			* pow(Tuning.SIZE_DAMAGE_MULT, s.size_level) * pow(Tuning.SPLIT_DAMAGE_MULT, p_real_splits)
	s.speed = Tuning.BASE_SPEED * pow(Tuning.SPEED_MULT, s.speed_level) * pow(Tuning.SIZE_SPEED_MULT, s.size_level)
	s.radius = Tuning.BASE_RADIUS * pow(Tuning.SIZE_RADIUS_MULT, s.size_level)
	return s


func burn_dps() -> float:
	return Tuning.FIRE_DPS_PER_LEVEL * fire_level


func slow_fraction() -> float:
	return Tuning.ICE_SLOW_PER_LEVEL * ice_level


func poison_stacks_per_hit() -> int:
	return Tuning.POISON_STACKS_PER_LEVEL * poison_level


## Tints bullets and belt items: fire > poison > ice > pierce > speed > size, else the Source colour.
func primary_color() -> Color:
	var levels: Dictionary[StringName, int] = {
		MachineCatalog.FIRE: fire_level,
		MachineCatalog.POISON: poison_level,
		MachineCatalog.ICE: ice_level,
		MachineCatalog.PIERCE: pierce,
		MachineCatalog.SPEED_UP: speed_level,
		MachineCatalog.SIZE_UP: size_level,
	}
	for kind: StringName in levels:
		if levels[kind] > 0:
			return MachineCatalog.get_def(kind).color
	return MachineCatalog.get_def(MachineCatalog.SOURCE).color


## "DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE I · PIERCE 1" (D.1).
func describe() -> String:
	var parts: PackedStringArray = ["DMG %.1f" % damage, "SPD %d" % roundi(speed), "SIZE %.1f" % radius]
	if fire_level > 0:
		parts.append("FIRE " + ROMAN[fire_level])
	if ice_level > 0:
		parts.append("ICE " + ROMAN[ice_level])
	if poison_level > 0:
		parts.append("POISON " + ROMAN[poison_level])
	if pierce > 0:
		parts.append("PIERCE %d" % pierce)
	return " · ".join(parts)


static func _level(counts: Dictionary[StringName, int], kind: StringName) -> int:
	return mini(counts.get(kind, 0), MachineCatalog.get_def(kind).max_stacks)

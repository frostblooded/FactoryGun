class_name ShotPlan
extends RefCounted
## What one trigger pull fires. Never mutated after compile; RunState replaces it on every edit.

enum MachineStatus { ACTIVE, CAPPED, ONE_SIDED, DEAD_END, IDLE }

const MAX_ISSUE_LINES: int = 2

var bullets: Array[BulletSpec] = []
var statuses: Dictionary[int, MachineStatus] = {}
var live_wire_keys: Dictionary[String, bool] = {}
var wire_streams: Dictionary[String, Array] = {}   # Wire.key() -> up to 4 distinct partial BulletSpecs
var issues: Array[PlanIssue] = []


## No bullets + the NO_PATH issue.
static func empty() -> ShotPlan:
	var plan: ShotPlan = ShotPlan.new()
	plan.issues.append(PlanIssue.make(PlanIssue.Code.NO_PATH, -1, "Connect the Basic Bullet to the Output."))
	return plan


func is_valid() -> bool:
	return not bullets.is_empty()


func status_of(id: int) -> MachineStatus:
	return statuses.get(id, MachineStatus.IDLE)


func is_live_wire(w: Wire) -> bool:
	return live_wire_keys.has(w.key())


func streams_on(w: Wire) -> Array[BulletSpec]:
	var out: Array[BulletSpec] = []
	out.assign(wire_streams.get(w.key(), []))
	return out


func damage_per_shot() -> float:
	var total: float = 0.0
	for b: BulletSpec in bullets:
		total += b.damage
	return total


func has_issue(code: PlanIssue.Code) -> bool:
	return issues.any(func(i: PlanIssue) -> bool: return i.code == code)


## The readout text (E.7): headline, one row per bullet, up to 2 non-ERROR issues, then "… N more".
func summary_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if bullets.is_empty():
		lines.append("NO PATH: connect the Basic Bullet to the Output")
	else:
		lines.append("%d bullet%s/shot · %d shots/s · %.1f dmg/shot" % [bullets.size(),
				"" if bullets.size() == 1 else "s", roundi(1.0 / Tuning.GUN_INTERVAL), damage_per_shot()])
	for i: int in bullets.size():
		lines.append("#%d %s" % [i + 1, bullets[i].describe()])
	var shown: Array[PlanIssue] = issues.filter(func(i: PlanIssue) -> bool:
			return i.severity() != PlanIssue.Severity.ERROR)
	shown.sort_custom(PlanIssue.before)
	for i: int in mini(shown.size(), MAX_ISSUE_LINES):
		lines.append("! " + shown[i].text)
	if shown.size() > MAX_ISSUE_LINES:
		lines.append("… %d more" % (shown.size() - MAX_ISSUE_LINES))
	return lines

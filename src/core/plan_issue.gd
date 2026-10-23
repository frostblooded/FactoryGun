class_name PlanIssue
extends RefCounted
## One problem with the factory, shown in the shot readout.

enum Code { NO_PATH, DEAD_END, IDLE, CAPPED, ONE_SIDED }
enum Severity { INFO, WARNING, ERROR }

var code: Code
var machine_id: int = -1
var text: String = ""


static func make(p_code: Code, p_machine_id: int, p_text: String) -> PlanIssue:
	var i: PlanIssue = PlanIssue.new()
	i.code = p_code
	i.machine_id = p_machine_id
	i.text = p_text
	return i


## Severity descending, then machine_id ascending, then code ascending.
static func before(a: PlanIssue, b: PlanIssue) -> bool:
	if a.severity() != b.severity():
		return a.severity() > b.severity()
	if a.machine_id != b.machine_id:
		return a.machine_id < b.machine_id
	return a.code < b.code


func severity() -> Severity:
	match code:
		Code.NO_PATH:
			return Severity.ERROR
		Code.ONE_SIDED:
			return Severity.INFO
	return Severity.WARNING

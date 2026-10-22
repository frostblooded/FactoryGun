extends GutHookScript
## Fails the run for two things GUT 9.5.0 lets pass with exit code 0:
## - errors raised outside a test body (before_each, after_each, deferred calls, frees);
## - test files GUT skipped (parse error, or not extending GutTest).
## Only ever call set_exit_code(1): any exit code set here overrides GUT's own.


func run() -> void:
	var problems: PackedStringArray = []
	var stray: Array = gut.error_tracker.errors.items.get(GutUtils.NO_TEST, []).duplicate()
	for e: GutTrackedError in stray:
		problems.append("error outside a test body: %s %s:%d" % [e.code, e.file, e.line])
	var collected: Dictionary[String, bool] = {}
	for s: Object in gut.get_test_collector().scripts:
		collected[s.get("path")] = true
	for path: String in _test_files("res://test"):
		if not collected.has(path):
			problems.append("test file was not run (parse error, or it does not extend GutTest): " + path)
	for p: String in problems:
		print("POST-RUN CHECK FAILED: " + p)
	if not problems.is_empty():
		set_exit_code(1)


func _test_files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f: String in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_test_files(dir.path_join(d)))
	return out

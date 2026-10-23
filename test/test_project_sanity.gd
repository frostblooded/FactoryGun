extends GutTest
## Plugs GUT 9.5.0 blind spots. GUT loads test scripts, and any src script first pulled in while it
## collects tests, with GDScript warnings disabled, so untyped code would pass. Each script is compiled
## again in a fresh `godot --check-only` process, which applies the project's warnings-as-errors to the
## real file, class_name included. In-process recompiles are unsafe or wrong (L.1 #1b). OS.execute is
## fine here: export_presets.cfg excludes test/ from the web export.

const FORBIDDEN_IN_PURE: String = "\\b(Input|InputMap|Time|OS|Engine|DisplayServer|FileAccess|DirAccess|ResourceLoader)\\.|\\b(Node|Node2D|Control|CanvasItem|SceneTree)\\b|\\bget_tree\\(|\\bawait\\b|\\b(print\\w*|push_warning|push_error)\\(|(?<![.\\w])(randi|randf|randi_range|randf_range|randfn|randomize|seed)\\("


func test_every_script_compiles_with_project_warnings() -> void:
	var project: String = ProjectSettings.globalize_path("res://")
	var paths: PackedStringArray = _scripts("res://src") + _scripts("res://test")
	assert_gt(paths.size(), 0)
	for path: String in paths:
		var out: Array = []
		var code: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", project, "--check-only", "-s", path], out, true)
		assert_eq(code, 0, "%s\n%s" % [path, "\n".join(out)])


func test_core_and_sim_are_pure() -> void:
	var forbidden: RegEx = RegEx.create_from_string(FORBIDDEN_IN_PURE)
	var comment: RegEx = RegEx.create_from_string("#.*")
	for path: String in _scripts("res://src/core") + _scripts("res://src/sim"):
		var code: String = comment.sub(FileAccess.get_file_as_string(path), "", true)
		assert_true(code.contains("extends RefCounted"), path + " must extend RefCounted")
		var hit: RegExMatch = forbidden.search(code)
		assert_null(hit, "%s uses %s" % [path, hit.get_string() if hit != null else ""])


func test_input_actions_are_registered() -> void:
	InputSetup.ensure_actions()
	var events_before: int = InputMap.action_get_events(InputSetup.START_WAVE).size()
	InputSetup.ensure_actions()               # idempotent
	assert_eq(InputMap.action_get_events(InputSetup.START_WAVE).size(), events_before)
	for a: StringName in [InputSetup.MOVE_LEFT, InputSetup.MOVE_RIGHT, InputSetup.MOVE_UP, InputSetup.MOVE_DOWN,
			InputSetup.START_WAVE, InputSetup.DELETE_HOVERED, InputSetup.CANCEL,
			InputSetup.RESTART] + InputSetup.PICK:
		assert_true(InputMap.has_action(a) and not InputMap.action_get_events(a).is_empty(), String(a))


func _scripts(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(dir):  # src/sim does not exist until WP2
		return out
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out

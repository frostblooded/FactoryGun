class_name GameOverOverlay
extends Control
## The end of a run (docs/DESIGN.md G.4): the result and a Restart button over the frozen arena.

signal restart_requested

const DIM: Color = Color(0, 0, 0, 0.55)

var restart_button: Button
var result_text: String = ""              # set by show_result(), e.g. "Survived 2 waves · 17 kills"


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	restart_button = Button.new()
	restart_button.text = "RESTART  [R]"
	restart_button.position = Vector2(400, 440)
	restart_button.size = Vector2(200, 44)
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.pressed.connect(_on_restart_pressed)
	add_child(restart_button)


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	draw_string(font, Vector2(0, 330), "GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, size.x, 48, UiColors.ERROR)
	draw_string(font, Vector2(0, 390), result_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, UiColors.TEXT)


func show_result(waves_cleared: int, kills: int) -> void:
	result_text = "Survived %d wave%s · %d kill%s" % [waves_cleared, "" if waves_cleared == 1 else "s", kills,
			"" if kills == 1 else "s"]
	show()
	queue_redraw()


func _on_restart_pressed() -> void:
	restart_requested.emit()

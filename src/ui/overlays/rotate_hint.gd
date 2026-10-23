class_name RotateHint
extends Control
## Covers the whole game on a touch screen held upright (docs/DESIGN.md G.5): the game is landscape only. While it
## shows, the tree is paused, so a wave waits for the player to turn the phone back. Draws itself.

const DIM: Color = Color(0, 0, 0, 0.9)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	process_mode = PROCESS_MODE_ALWAYS    # it must notice the turn back while the tree is paused
	visible = false


func _process(_delta: float) -> void:
	var show_it: bool = should_show(DisplayServer.window_get_size(), DisplayServer.is_touchscreen_available())
	if show_it != visible:
		visible = show_it
		get_tree().paused = show_it


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	draw_string(font, Vector2(0, size.y / 2 - 10), "ROTATE YOUR PHONE", HORIZONTAL_ALIGNMENT_CENTER, size.x, 64,
			UiColors.ACCENT)
	draw_string(font, Vector2(0, size.y / 2 + 60), "FactoryGun plays in landscape", HORIZONTAL_ALIGNMENT_CENTER,
			size.x, 32, UiColors.TEXT)


## Only touch screens: a narrow desktop window just gets letterboxed.
static func should_show(window_size: Vector2i, touchscreen: bool) -> bool:
	return touchscreen and window_size.y > window_size.x

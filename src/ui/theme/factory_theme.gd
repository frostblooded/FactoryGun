class_name FactoryTheme
extends RefCounted
## The game's Theme, built in code (docs/DESIGN.md E.9). Main assigns it to its root control.

const FONT_SIZE: int = 14


static func build() -> Theme:
	var t: Theme = Theme.new()
	t.default_font_size = FONT_SIZE
	t.set_stylebox("normal", "Button", _box(UiColors.STEEL, UiColors.OUTLINE))
	t.set_stylebox("hover", "Button", _box(UiColors.STEEL_LIGHT, UiColors.OUTLINE))
	t.set_stylebox("pressed", "Button", _box(UiColors.STEEL_DARK, UiColors.ACCENT))
	t.set_stylebox("disabled", "Button", _box(UiColors.STEEL_DARK, UiColors.STEEL))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(state, "Button", UiColors.TEXT)
	t.set_color("font_pressed_color", "Button", UiColors.ACCENT)
	t.set_color("font_hover_pressed_color", "Button", UiColors.ACCENT)
	t.set_color("font_disabled_color", "Button", UiColors.TEXT_DIM)
	t.set_color("font_color", "Label", UiColors.TEXT)
	t.set_stylebox("panel", "Panel", _box(UiColors.PANEL_BG, UiColors.PANEL_EDGE))
	t.set_stylebox("panel", "PanelContainer", _box(UiColors.PANEL_BG, UiColors.PANEL_EDGE))
	# Godot's default tooltip panel is 50% black: the palette's names and counts showed through its text.
	t.set_stylebox("panel", "TooltipPanel", _box(UiColors.PANEL_BG, UiColors.PANEL_EDGE))
	t.set_color("font_color", "TooltipLabel", UiColors.TEXT)
	return t


## Border 2, corner radius 2, content margins 8 (left, right) and 4 (top, bottom).
static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(2)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box

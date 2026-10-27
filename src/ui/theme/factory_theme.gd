class_name FactoryTheme
extends RefCounted
## The game's Theme, built in code (docs/DESIGN.md E.9). Main assigns it to its root control.
## Chunky arcade look for thumbs on a phone: a bold font, big type, rounded buttons with a thick bottom lip.

const FONT_SIZE: int = 28
const BIG_FONT_SIZE: int = 44             # the Start button
const RADIUS: int = 16
const BORDER: int = 4
const LIP: int = 10                       # the bottom border: the button's "depth"
const BIG_BUTTON: StringName = &"BigButton"   # theme type variation of Button for the main call to action


static func build() -> Theme:
	var t: Theme = Theme.new()
	t.default_font = bold_font()
	t.default_font_size = FONT_SIZE
	t.set_stylebox("normal", "Button", box(UiColors.STEEL, UiColors.OUTLINE, LIP))
	t.set_stylebox("hover", "Button", box(UiColors.STEEL_LIGHT, UiColors.OUTLINE, LIP))
	t.set_stylebox("pressed", "Button", box(UiColors.STEEL_DARK, UiColors.ACCENT, BORDER, LIP - BORDER))
	t.set_stylebox("disabled", "Button", box(UiColors.STEEL_DARK, UiColors.STEEL, LIP))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(state, "Button", UiColors.TEXT)
	t.set_color("font_pressed_color", "Button", UiColors.ACCENT)
	t.set_color("font_hover_pressed_color", "Button", UiColors.ACCENT)
	t.set_color("font_disabled_color", "Button", UiColors.TEXT_DIM)
	t.set_type_variation(BIG_BUTTON, "Button")
	t.set_font_size("font_size", BIG_BUTTON, BIG_FONT_SIZE)
	t.set_stylebox("normal", BIG_BUTTON, box(UiColors.HAZARD, UiColors.BUTTON_LIP, LIP + 4))
	t.set_stylebox("hover", BIG_BUTTON, box(UiColors.HAZARD.lightened(0.15), UiColors.BUTTON_LIP, LIP + 4))
	t.set_stylebox("pressed", BIG_BUTTON, box(UiColors.ACCENT, UiColors.BUTTON_LIP, BORDER, LIP))
	t.set_stylebox("disabled", BIG_BUTTON, box(UiColors.STEEL_DARK, UiColors.STEEL, LIP + 4))
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color",
			"font_hover_pressed_color"]:
		t.set_color(state, BIG_BUTTON, UiColors.INK)
	t.set_color("font_disabled_color", BIG_BUTTON, UiColors.TEXT_DIM)
	t.set_color("font_color", "Label", UiColors.TEXT)
	t.set_stylebox("panel", "Panel", box(UiColors.PANEL_BG, UiColors.PANEL_EDGE, BORDER))
	t.set_stylebox("panel", "PanelContainer", box(UiColors.PANEL_BG, UiColors.PANEL_EDGE, BORDER))
	# Godot's default tooltip panel is 50% black: the palette's names and counts showed through its text.
	t.set_stylebox("panel", "TooltipPanel", box(UiColors.PANEL_BG, UiColors.PANEL_EDGE, BORDER))
	t.set_color("font_color", "TooltipLabel", UiColors.TEXT)
	return t


## The engine's default font, emboldened. Web exports have no system fonts, so it is the one font there is.
static func bold_font() -> FontVariation:
	var f: FontVariation = FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = 0.6
	return f


## Rounded, with a BORDER outline and a thicker bottom edge (lip); top_pad pushes a pressed button's text down.
static func box(bg: Color, border: Color, lip: int, top_pad: int = 0) -> StyleBoxFlat:
	var b: StyleBoxFlat = StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(BORDER)
	b.border_width_bottom = lip
	b.border_width_top = BORDER + top_pad
	b.set_corner_radius_all(RADIUS)
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b

class_name Hud
extends Control
## The fight screen's HUD (docs/DESIGN.md F.7): wave and HP on the left wing, enemies left on the right wing, and
## the wave banner over the arena. Draws itself, in screen (controller-local) coordinates.

const LOW_HP: float = 30.0
const BANNER_TIME: float = 1.5
const BANNER_FADE: float = 0.5
const BANNER_SIZE: int = 96
const NUMBER_SIZE: int = 110
const CAPTION_SIZE: int = 30
const WING_PAD: float = 28.0

var wave: int = 1
var running: bool = false
var hp: float = Tuning.PLAYER_MAX_HP
var enemies_left: int = 0
var banner_text: String = ""
var banner_left: float = 0.0              # seconds the banner still shows
var arena: Rect2 = Rect2(Vector2(300, 0), SimTuning.ARENA_SIZE)   # where the arena is drawn; set by the controller


func _process(delta: float) -> void:
	if banner_left > 0.0:
		banner_left = maxf(banner_left - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var left: Rect2 = Rect2(WING_PAD, 0, arena.position.x - 2 * WING_PAD, size.y)
	var right: Rect2 = Rect2(arena.end.x + WING_PAD, 0, size.x - arena.end.x - 2 * WING_PAD, size.y)
	_caption(font, left, 80, "WAVE")
	draw_string(font, Vector2(left.position.x, 80 + NUMBER_SIZE), str(wave), HORIZONTAL_ALIGNMENT_CENTER, left.size.x,
			NUMBER_SIZE, UiColors.ACCENT)
	_caption(font, left, 300, "HP")
	var bar: Rect2 = hp_bar_rect()
	draw_style_box(FactoryTheme.box(UiColors.STEEL_DARK, UiColors.OUTLINE, FactoryTheme.BORDER), bar)
	var inner: Rect2 = bar.grow(-FactoryTheme.BORDER)
	inner.size.x *= clampf(hp / Tuning.PLAYER_MAX_HP, 0.0, 1.0)
	draw_rect(inner, UiColors.ERROR if hp < LOW_HP else UiColors.OK)
	draw_string(font, bar.position + Vector2(0, 46), str(ceili(hp)), HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 38,
			UiColors.INK)
	_caption(font, right, 80, "ENEMIES" if running else "READY")
	draw_string(font, Vector2(right.position.x, 80 + NUMBER_SIZE), str(enemies_left) if running else "-",
			HORIZONTAL_ALIGNMENT_CENTER, right.size.x, NUMBER_SIZE, UiColors.TEXT)
	if running:
		_caption(font, right, size.y - 120, "DRAG ANYWHERE")
		_caption(font, right, size.y - 80, "TO MOVE")
	if banner_left > 0.0:
		var baseline: float = arena.get_center().y - font.get_height(BANNER_SIZE) / 2.0 + font.get_ascent(BANNER_SIZE)
		draw_string(font, Vector2(arena.position.x, baseline), banner_text, HORIZONTAL_ALIGNMENT_CENTER, arena.size.x,
				BANNER_SIZE, Color(UiColors.ACCENT, minf(banner_left / BANNER_FADE, 1.0)))


## Hud-local: the HP bar on the left wing.
func hp_bar_rect() -> Rect2:
	return Rect2(WING_PAD, 320, maxf(arena.position.x - 2 * WING_PAD, 40.0), 64)


func set_wave(p_wave: int, p_running: bool) -> void:
	wave = p_wave
	running = p_running
	queue_redraw()


func set_stats(p_hp: float, p_enemies_left: int) -> void:
	hp = p_hp
	enemies_left = p_enemies_left
	queue_redraw()


## BANNER_SIZE ACCENT text centred on the arena for 1.5 s, fading over the last 0.5 s.
func show_banner(text: String) -> void:
	banner_text = text
	banner_left = BANNER_TIME
	queue_redraw()


func _caption(font: Font, wing: Rect2, baseline: float, text: String) -> void:
	draw_string(font, Vector2(wing.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, wing.size.x, CAPTION_SIZE,
			UiColors.TEXT_DIM)

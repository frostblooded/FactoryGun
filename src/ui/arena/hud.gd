class_name Hud
extends Control
## Top bar, wave banner and idle hint over the arena (docs/DESIGN.md F.7). Draws itself.

const BAR_SIZE: Vector2 = Vector2(1000, 36)
const HP_BAR: Rect2 = Rect2(380, 11, 240, 14)
const LOW_HP: float = 30.0
const BANNER_TIME: float = 1.5
const BANNER_FADE: float = 0.5
const BANNER_Y: float = 300.0
const HINT_Y: float = 860.0
const IDLE_HINT: String = "Build your gun on the left · press START WAVE to begin"

var wave: int = 1
var running: bool = false
var hp: float = Tuning.PLAYER_MAX_HP
var enemies_left: int = 0
var banner_text: String = ""
var banner_left: float = 0.0              # seconds the banner still shows


func _process(delta: float) -> void:
	if banner_left > 0.0:
		banner_left = maxf(banner_left - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, BAR_SIZE), Color(UiColors.PANEL_BG, 0.85))
	draw_string(font, Vector2(16, 25), "WAVE %d" % wave, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiColors.TEXT)
	draw_rect(HP_BAR, UiColors.STEEL_DARK)
	var fill: float = HP_BAR.size.x * clampf(hp / Tuning.PLAYER_MAX_HP, 0.0, 1.0)
	draw_rect(Rect2(HP_BAR.position, Vector2(fill, HP_BAR.size.y)), UiColors.ERROR if hp < LOW_HP else UiColors.OK)
	draw_rect(HP_BAR, UiColors.OUTLINE, false, 1.0)
	draw_string(font, Vector2(HP_BAR.end.x + 10, 24), "HP %d" % ceili(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			UiColors.TEXT)
	var right: String = "ENEMIES %d" % enemies_left if running else "BUILD PHASE"
	draw_string(font, Vector2(BAR_SIZE.x - 216, 24), right, HORIZONTAL_ALIGNMENT_RIGHT, 200, 16, UiColors.TEXT)
	if banner_left > 0.0:
		var baseline: float = BANNER_Y - font.get_height(40) / 2.0 + font.get_ascent(40)
		draw_string(font, Vector2(0, baseline), banner_text, HORIZONTAL_ALIGNMENT_CENTER, BAR_SIZE.x, 40,
				Color(UiColors.ACCENT, minf(banner_left / BANNER_FADE, 1.0)))
	if not running:
		draw_string(font, Vector2(0, HINT_Y), IDLE_HINT, HORIZONTAL_ALIGNMENT_CENTER, BAR_SIZE.x, 16,
				UiColors.TEXT_DIM)


func set_wave(p_wave: int, p_running: bool) -> void:
	wave = p_wave
	running = p_running
	queue_redraw()


func set_stats(p_hp: float, p_enemies_left: int) -> void:
	hp = p_hp
	enemies_left = p_enemies_left
	queue_redraw()


## Size-40 ACCENT text centred at y 300 for 1.5 s, fading over the last 0.5 s.
func show_banner(text: String) -> void:
	banner_text = text
	banner_left = BANNER_TIME
	queue_redraw()

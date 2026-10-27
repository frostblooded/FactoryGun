extends GutTest


func test_reward_overlay_shows_and_chooses() -> void:
	var overlay: RewardOverlay = _reward_overlay()
	assert_false(overlay.visible)
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP)
	watch_signals(overlay)
	overlay.choose(0)                         # hidden: nothing to choose
	assert_signal_not_emitted(overlay, "offer_chosen")
	var offers: Array[RewardOffer] = _offers([MachineCatalog.FIRE, MachineCatalog.PIERCE, MachineCatalog.SPLITTER])
	overlay.show_offers(offers, 1)
	assert_true(overlay.visible)
	assert_eq(overlay.offers, offers)
	for i: int in 3:                          # big cards, the row centred on the screen
		assert_eq(overlay.card_rect(i), Rect2(130 + 460 * i, 200, 420, 600))
	await wait_process_frames(2)              # draws the cards and animates the icons
	overlay.choose(3)
	overlay.choose(-1)
	assert_true(overlay.visible)
	assert_signal_not_emitted(overlay, "offer_chosen")
	overlay.choose(2)
	assert_false(overlay.visible)
	assert_signal_emit_count(overlay, "offer_chosen", 1)
	assert_signal_emitted_with_parameters(overlay, "offer_chosen", [2])
	overlay.choose(1)                         # a second key press after the pick does nothing
	assert_signal_emit_count(overlay, "offer_chosen", 1)
	# every other kind draws too, and the overlay keeps its own copy of the offers
	offers = _offers([MachineCatalog.ICE, MachineCatalog.POISON, MachineCatalog.SPEED_UP])
	overlay.show_offers(offers, 2)
	offers.clear()
	assert_eq(overlay.offers.size(), 3)
	await wait_process_frames(2)
	overlay.show_offers(_offers([MachineCatalog.SIZE_UP]), 9)
	assert_eq(overlay.card_rect(0), Rect2(590, 200, 420, 600), "one card sits in the middle")
	await wait_process_frames(2)
	overlay.choose(1)                         # only one card
	assert_true(overlay.visible)
	assert_signal_emit_count(overlay, "offer_chosen", 1)


func test_reward_card_click() -> void:
	var overlay: RewardOverlay = _reward_overlay()
	overlay.show_offers(_offers([MachineCatalog.FIRE, MachineCatalog.ICE, MachineCatalog.SPLITTER]), 3)
	watch_signals(overlay)
	var centre: Vector2 = overlay.card_rect(1).get_center()
	for miss: InputEventMouseButton in [_click(Vector2(100, 400)), _click(Vector2(570, 400)),   # beside, between
			_click(Vector2(700, 850)), _click(centre, MOUSE_BUTTON_RIGHT), _click(centre, MOUSE_BUTTON_LEFT, false)]:
		overlay._gui_input(miss)
	assert_signal_not_emitted(overlay, "offer_chosen")
	assert_true(overlay.visible)
	overlay._gui_input(_click(Vector2(1465, 795)))  # near the corner of card 2 (1050..1470, 200..800)
	assert_signal_emit_count(overlay, "offer_chosen", 1)
	assert_signal_emitted_with_parameters(overlay, "offer_chosen", [2])
	assert_false(overlay.visible)
	overlay._gui_input(_click(centre))            # hidden now
	assert_signal_emit_count(overlay, "offer_chosen", 1)


func test_game_over_text_and_restart_signal() -> void:
	var overlay: GameOverOverlay = GameOverOverlay.new()
	add_child_autofree(overlay)
	overlay.size = Vector2(1600, 900)
	assert_false(overlay.visible)
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP)
	var button: Button = overlay.restart_button
	assert_eq(button.text, "PLAY AGAIN")
	assert_eq(button.theme_type_variation, FactoryTheme.BIG_BUTTON)
	assert_eq(Rect2(button.position, button.size), Rect2(570, 495, 460, 150), "big and centred")
	assert_eq(button.focus_mode, Control.FOCUS_NONE)
	overlay.show_result(0, 0)
	assert_true(overlay.visible)
	assert_eq(overlay.result_text, "Survived 0 waves · 0 kills")
	overlay.show_result(1, 1)
	assert_eq(overlay.result_text, "Survived 1 wave · 1 kill")
	overlay.show_result(7, 213)
	assert_eq(overlay.result_text, "Survived 7 waves · 213 kills")
	await wait_process_frames(2)
	watch_signals(overlay)
	button.pressed.emit()
	assert_signal_emit_count(overlay, "restart_requested", 1)


func test_rotate_hint_only_on_upright_touch_screens() -> void:
	assert_true(RotateHint.should_show(Vector2i(390, 844), true))
	assert_false(RotateHint.should_show(Vector2i(844, 390), true))
	assert_false(RotateHint.should_show(Vector2i(390, 844), false), "a narrow desktop window is letterboxed")
	var hint: RotateHint = RotateHint.new()
	add_child_autofree(hint)
	hint.size = Vector2(1600, 900)
	await wait_process_frames(2)
	assert_false(hint.visible, "headless has no touch screen")
	assert_false(get_tree().paused)
	assert_eq(hint.process_mode, Node.PROCESS_MODE_ALWAYS)


func _reward_overlay() -> RewardOverlay:
	var overlay: RewardOverlay = RewardOverlay.new()
	add_child_autofree(overlay)
	overlay.size = Vector2(1600, 900)
	return overlay


func _offers(kinds: Array[StringName]) -> Array[RewardOffer]:
	var out: Array[RewardOffer] = []
	for kind: StringName in kinds:
		out.append(RewardOffer.make(kind, RewardGenerator.amount_of(kind, 1)))
	return out


func _click(at: Vector2, index: MouseButton = MOUSE_BUTTON_LEFT, pressed: bool = true) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = at
	return e

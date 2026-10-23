extends GutTest


func test_reward_overlay_shows_and_chooses() -> void:
	var overlay: RewardOverlay = _reward_overlay()
	assert_false(overlay.visible)
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP)
	for i: int in 3:
		assert_eq(overlay.card_rect(i), Rect2(90 + 280 * i, 290, 260, 320))
	watch_signals(overlay)
	overlay.choose(0)                         # hidden: nothing to choose
	assert_signal_not_emitted(overlay, "offer_chosen")
	var offers: Array[RewardOffer] = _offers([MachineCatalog.FIRE, MachineCatalog.PIERCE, MachineCatalog.SPLITTER])
	overlay.show_offers(offers, 1)
	assert_true(overlay.visible)
	assert_eq(overlay.offers, offers)
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
	await wait_process_frames(2)
	overlay.choose(1)                         # only one card
	assert_true(overlay.visible)
	assert_signal_emit_count(overlay, "offer_chosen", 1)


func test_reward_card_click() -> void:
	var overlay: RewardOverlay = _reward_overlay()
	overlay.show_offers(_offers([MachineCatalog.FIRE, MachineCatalog.ICE, MachineCatalog.SPLITTER]), 3)
	watch_signals(overlay)
	var centre: Vector2 = overlay.card_rect(1).get_center()
	for miss: InputEventMouseButton in [_click(Vector2(60, 400)), _click(Vector2(360, 400)),   # beside, between
			_click(Vector2(500, 620)), _click(centre, MOUSE_BUTTON_RIGHT), _click(centre, MOUSE_BUTTON_LEFT, false)]:
		overlay._gui_input(miss)
	assert_signal_not_emitted(overlay, "offer_chosen")
	assert_true(overlay.visible)
	overlay._gui_input(_click(Vector2(905, 605)))   # near the corner of card 2 (650..910, 290..610)
	assert_signal_emit_count(overlay, "offer_chosen", 1)
	assert_signal_emitted_with_parameters(overlay, "offer_chosen", [2])
	assert_false(overlay.visible)
	overlay._gui_input(_click(centre))            # hidden now
	assert_signal_emit_count(overlay, "offer_chosen", 1)


func test_game_over_text_and_restart_signal() -> void:
	var overlay: GameOverOverlay = GameOverOverlay.new()
	add_child_autofree(overlay)
	overlay.size = Vector2(1000, 900)
	assert_false(overlay.visible)
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP)
	var button: Button = overlay.restart_button
	assert_eq(button.text, "RESTART  [R]")
	assert_eq(Rect2(button.position, button.size), Rect2(400, 440, 200, 44))
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


func _reward_overlay() -> RewardOverlay:
	var overlay: RewardOverlay = RewardOverlay.new()
	add_child_autofree(overlay)
	overlay.size = Vector2(1000, 900)
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

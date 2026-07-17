extends SceneTree

# View-layer smoke: VendorPromptPanel (2026-07-17 general store design §3.6) — a WoW-style
# Talk/Shop/Leave prompt, mirrors AdventuringBoardPanel's open_for()/is_open()/close() shape.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vendor_prompt_panel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var line: DialogueLine = DialogueLine.new()
	line.speaker_name = "Shopkeeper"
	line.text = "Welcome! Take a look at my wares."
	var ds: DialogueSet = DialogueSet.new()
	ds.lines = [line]

	var panel: VendorPromptPanel = VendorPromptPanel.new()
	panel.open_for(ds)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visibility")
	_check(panel.greeting_text_for_test() == "Welcome! Take a look at my wares.", "shows the DialogueSet's first line as the greeting")

	var talk_count: Array[int] = [0]
	var shop_count: Array[int] = [0]
	var leave_count: Array[int] = [0]
	panel.talk_pressed.connect(func() -> void: talk_count[0] += 1)
	panel.shop_pressed.connect(func() -> void: shop_count[0] += 1)
	panel.leave_pressed.connect(func() -> void: leave_count[0] += 1)

	panel.press_talk_for_test()
	_check(talk_count[0] == 1, "pressing Talk emits talk_pressed")
	_check(not panel.visible, "pressing Talk closes the prompt")

	panel.open_for(ds)
	panel.press_shop_for_test()
	_check(shop_count[0] == 1, "pressing Shop emits shop_pressed")
	_check(not panel.visible, "pressing Shop closes the prompt")

	panel.open_for(ds)
	panel.press_leave_for_test()
	_check(leave_count[0] == 1, "pressing Leave emits leave_pressed")
	_check(not panel.visible, "pressing Leave closes the prompt")

	panel.free()
	quit()

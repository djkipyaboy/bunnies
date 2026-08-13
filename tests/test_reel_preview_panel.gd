extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	var panel: ReelPreviewPanel = ReelPreviewPanel.new()
	var draft: CharacterCreationDraft = CharacterCreationDraft.new()

	panel.refresh(draft)
	_check(panel.text_for_test() == "Make a selection to preview your reels.", "an empty draft shows the placeholder prompt")

	draft.class_id = &"warrior"
	panel.refresh(draft)
	_check(panel.text_for_test().find("Martin (Mouse)") != -1, "picking a class shows its display name in the preview")
	_check(panel.text_for_test().find("3 reels") != -1, "picking a class shows its reel_count in the preview")

	draft.heritage_id = &"hare"
	panel.refresh(draft)
	_check(panel.text_for_test().find("Hare") != -1, "picking a heritage adds its species name to the preview")
	_check(panel.text_for_test().find("Finesse") != -1, "picking a heritage adds its passive description to the preview")

	draft.background_id = &"reformed_vermin"
	panel.refresh(draft)
	_check(panel.text_for_test().find("Reformed Vermin") != -1, "picking a background adds its name to the preview")
	_check(panel.text_for_test().find("CRIT_SUCCESS") != -1, "picking a background adds its signature face's tier to the preview")

	print(("REEL PREVIEW PANEL TEST PASSED" if _failures == 0 else "REEL PREVIEW PANEL TEST FAILED: %d" % _failures))
	quit(_failures)

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
	_check(BackgroundLibrary.IDS.size() == 2, "BackgroundLibrary registers exactly 2 placeholder entries (got %d)" % BackgroundLibrary.IDS.size())

	var seen_names: Dictionary = {}
	for id: StringName in BackgroundLibrary.IDS:
		var b: Background = BackgroundLibrary.make(id)
		_check(b != null, "BackgroundLibrary.make(&\"%s\") returns a Background" % id)
		_check(not b.background_name.is_empty(), "%s has a non-empty background_name" % id)
		_check(not (b.background_name in seen_names), "%s's background_name '%s' is distinct from every other background" % [id, b.background_name])
		seen_names[b.background_name] = true
		_check(b.signature_face != null, "%s carries exactly one signature_face" % id)

	_check(BackgroundLibrary.make(&"not_a_real_background") == null, "an unknown id returns null")

	var rv: Background = BackgroundLibrary.make(&"reformed_vermin")
	_check(rv.signature_face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS, "Reformed Vermin's signature face is a CRIT_SUCCESS tier")

	print(("BACKGROUND LIBRARY TEST PASSED" if _failures == 0 else "BACKGROUND LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)

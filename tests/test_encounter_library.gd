extends SceneTree

## EncounterLibrary: code registry of authored RandomEncounters (player direction 2026-07-12) —
## mirrors ClassLibrary/EnemyLibrary's own smoke-test shape.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_check(EncounterLibrary.IDS.has(&"bandit_ambush"), "IDS includes bandit_ambush")

	var e: RandomEncounter = EncounterLibrary.make(&"bandit_ambush")
	_check(e != null, "make(&bandit_ambush) returns a RandomEncounter")
	_check(e.id == &"bandit_ambush", "the built encounter carries its own id")
	_check(not e.description.is_empty(), "the built encounter has a non-empty description")
	_check(e.options.size() == 3, "bandit_ambush has 3 options (duel/flee/negotiate)")
	for option: EncounterOption in e.options:
		_check(not option.label.is_empty(), "option %s has a non-empty label" % option.label)
		_check(option.reel != null and option.reel.faces.size() > 0, "option %s has a non-empty reel" % option.label)

	var e2: RandomEncounter = EncounterLibrary.make(&"bandit_ambush")
	_check(e2 != e, "make() returns a FRESH instance each call (mirrors ClassLibrary/EnemyLibrary), not a shared singleton")
	_check(e2.options[0] != e.options[0], "fresh instances don't share option Resources either")

	_check(EncounterLibrary.make(&"not_a_real_id") == null, "an unknown id returns null")

	quit()

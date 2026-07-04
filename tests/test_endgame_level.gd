extends SceneTree

## Regression check for the ENDGAME playtest toggle (Task 32): spawning a Combatant at level 9
## must unlock every one of its class's extra_abilities (L5/L7/L9 kit, Tasks 11-31). Pure logic —
## exercises Combatant.level + unlocked_extra_abilities() (Task 2), not the UI toggle itself.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	for id in ClassLibrary.IDS:
		var cc: CharacterClass = ClassLibrary.make(id)
		var c: Combatant = cc.build_combatant(true)
		c.level = 9
		_check(c.unlocked_extra_abilities().size() == cc.extra_abilities.size(), "%s: level 9 unlocks all extra_abilities" % id)
	quit()

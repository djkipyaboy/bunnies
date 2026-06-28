extends SceneTree

# Headless test: RosterSelection.toggle — the ordered party/enemy selection model (spec
# 2026-06-29-nvm-party-combat §5.2): select appends in order, deselect removes + shifts the rest up,
# max cap blocks over-selection.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_roster_selection.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var sel: Array[StringName] = []

	# Select appends in selection order.
	RosterSelection.toggle(sel, &"a", 3)
	RosterSelection.toggle(sel, &"b", 3)
	RosterSelection.toggle(sel, &"c", 3)
	_check(sel == [&"a", &"b", &"c"], "select appends in order -> [a,b,c]")

	# Re-selecting an already-selected id deselects it (toggle).
	RosterSelection.toggle(sel, &"b", 3)
	_check(sel == [&"a", &"c"], "deselect middle (b) -> [a,c]")

	# Deselecting the FIRST shifts the rest up (locked rule: 1st gone -> 2nd promotes to 1st).
	RosterSelection.toggle(sel, &"b", 3)        # back to [a,c,b]
	_check(sel == [&"a", &"c", &"b"], "re-select b appends at tail -> [a,c,b]")
	RosterSelection.toggle(sel, &"a", 3)        # deselect first
	_check(sel == [&"c", &"b"], "deselect first shifts rest up -> [c,b]")

	# Max cap: selecting past max_n is a no-op (no 4th member, original order kept).
	var cap: Array[StringName] = [&"x", &"y", &"z"]
	RosterSelection.toggle(cap, &"w", 3)
	_check(cap == [&"x", &"y", &"z"], "select past max (3) is a no-op")
	# ...but deselect still works at the cap, and a new one then fits.
	RosterSelection.toggle(cap, &"y", 3)
	RosterSelection.toggle(cap, &"w", 3)
	_check(cap == [&"x", &"z", &"w"], "deselect at cap frees a slot; new id appends -> [x,z,w]")

	# Min handling is the caller's concern (BEGIN gating) — toggle allows emptying.
	var one: Array[StringName] = [&"only"]
	RosterSelection.toggle(one, &"only", 3)
	_check(one == [], "toggle can empty the list (min enforced by caller)")

	print(("ROSTER SELECTION TEST PASSED" if _failures == 0 else "ROSTER SELECTION TEST FAILED: %d" % _failures))
	quit(_failures)

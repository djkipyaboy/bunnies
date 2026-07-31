extends SceneTree

## Headless test: CombatantPanel.bind() must show an ALREADY-ACTIVE effect immediately, with no
## manual refresh_status() call needed — playtest 2026-07-31 found a combatant carrying an effect
## into a freshly-built panel (CombatHandoff reuses the same real Combatant across encounters)
## showed BLANK status until that combatant's own first turn.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combatant_panel_bind_shows_existing_effects.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	c.display_name = "TestCombatant"
	c.base_stats = Stats.new()
	c.base_max_hp = 100
	c.apply_stats()
	c.start_combat()
	c.attach_effect(EffectLibrary.make(&"guarded"))  # attached BEFORE the panel exists

	var panel: CombatantPanel = CombatantPanel.new()
	root.add_child(panel)  # _ready() must run before bind() for the labels to exist
	await process_frame
	await process_frame
	panel.bind(c)

	_check(panel._status_label.text.contains("GUARDED"), "bind() shows an already-active effect immediately (got '%s')" % panel._status_label.text)

	print(("COMBATANTPANEL BIND SHOWS EXISTING EFFECTS TEST PASSED" if _failures == 0 else "COMBATANTPANEL BIND SHOWS EXISTING EFFECTS TEST FAILED: %d" % _failures))
	quit(_failures)

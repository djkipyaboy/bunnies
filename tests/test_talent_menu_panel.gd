extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_warrior_at(level: int) -> Combatant:
	var c: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c.level = level
	return c

func _init() -> void:
	var panel: TalentMenuPanel = TalentMenuPanel.new()

	# All 6 Ability Talent rows render for the viewed character's class, even locked ones.
	var c: Combatant = _mk_warrior_at(5)  # only base_ability row unlocked
	panel.open_for(c, true)
	_check(panel.row_button_count(&"base_ability") == 3, "base_ability row (unlocked at L5) shows 3 option buttons")
	_check(panel.row_button_count(&"ultimate") == 3, "ultimate row (locked until L10) STILL shows 3 option buttons — locked rows are shown, not hidden")
	_check(not panel.is_row_interactive(&"ultimate"), "a locked row's buttons are disabled")
	_check(panel.is_row_interactive(&"base_ability"), "an unlocked row's buttons are enabled")
	_check(panel.locked_row_label(&"ultimate") == "Unlocks at Level 10", "a locked row shows its unlock level (got '%s')" % panel.locked_row_label(&"ultimate"))
	panel.close()

	# Picking via the panel calls through to the real Combatant methods (no separate pick state).
	var c2: Combatant = _mk_warrior_at(10)
	panel.open_for(c2, true)
	_check(panel.press_option_for_test(&"base_ability", &"rend_efficient"), "pressing an option button picks it")
	_check(c2.has_ability_talent(&"rend_efficient"), "the real Combatant now has the talent picked")
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "the panel shows the picked option as selected")
	panel.close()

	# Respec gating: town (respec_available=true) allows swapping an already-spent row; overworld/
	# dungeon (false) shows the pick but disables the swap action — mirrors InventoryMenuPanel's
	# existing vault_available convention exactly.
	var c3: Combatant = _mk_warrior_at(10)
	c3.pick_ability_talent(&"base_ability", &"rend_efficient")
	panel.open_for(c3, false)
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "an already-spent pick is still shown outside a safe zone")
	_check(not panel.is_row_interactive(&"base_ability"), "an already-spent row's buttons are disabled outside a safe zone (view-only)")
	panel.close()

	panel.open_for(c3, true)
	_check(panel.is_row_interactive(&"base_ability"), "the same already-spent row IS interactive in town (respec_available=true)")
	_check(panel.press_option_for_test(&"base_ability", &"rend_deeper_cut"), "town respec: picking a different option in an already-spent row succeeds (unpick + repick)")
	_check(c3.has_ability_talent(&"rend_deeper_cut"), "the swap actually changed the Combatant's pick")
	_check(not c3.has_ability_talent(&"rend_efficient"), "the old pick is cleared")
	panel.close()

	# Universal Perk section: 5 milestone slots, shown-when-reached (unlike the Ability Talent grid's
	# always-shown rows), one-time-pick enforcement carried straight through to TalentPerkLibrary.
	var c4: Combatant = _mk_warrior_at(3)
	panel.open_for(c4, true)
	_check(panel.universal_slot_count() == 1, "L3: only the L2 milestone has been reached (1 slot shown, got %d)" % panel.universal_slot_count())
	panel.close()

	var c5: Combatant = _mk_warrior_at(10)
	panel.open_for(c5, true)
	_check(panel.universal_slot_count() == 5, "L10: all 5 milestones reached (got %d)" % panel.universal_slot_count())
	_check(panel.press_universal_perk_for_test(&"vigor_boost"), "picking a universal perk succeeds")
	_check(c5.has_ability_talent(&"") == false, "sanity: has_ability_talent is unrelated to talent_perks")
	_check(&"vigor_boost" in c5.talent_perks, "the real Combatant now carries the picked universal perk")
	panel.close()

	print(("TALENT MENU PANEL TEST PASSED" if _failures == 0 else "TALENT MENU PANEL TEST FAILED: %d" % _failures))
	quit(_failures)

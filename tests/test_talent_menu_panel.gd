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
	panel.open_for(c, [], true)
	_check(panel.row_button_count(&"base_ability") == 3, "base_ability row (unlocked at L5) shows 3 option buttons")
	_check(panel.row_button_count(&"ultimate") == 3, "ultimate row (locked until L10) STILL shows 3 option buttons — locked rows are shown, not hidden")
	_check(not panel.is_row_interactive(&"ultimate"), "a locked row's buttons are disabled")
	_check(panel.is_row_interactive(&"base_ability"), "an unlocked row's buttons are enabled")
	_check(panel.locked_row_label(&"ultimate") == "Unlocks at Level 10", "a locked row shows its unlock level (got '%s')" % panel.locked_row_label(&"ultimate"))
	panel.close()

	# Picking via the panel calls through to the real Combatant methods (no separate pick state).
	var c2: Combatant = _mk_warrior_at(10)
	panel.open_for(c2, [], true)
	_check(panel.press_option_for_test(&"base_ability", &"rend_efficient"), "pressing an option button picks it")
	_check(c2.has_ability_talent(&"rend_efficient"), "the real Combatant now has the talent picked")
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "the panel shows the picked option as selected")
	panel.close()

	# Respec gating: town (respec_available=true) allows swapping an already-spent row; overworld/
	# dungeon (false) shows the pick but disables the swap action — mirrors InventoryMenuPanel's
	# existing vault_available convention exactly.
	var c3: Combatant = _mk_warrior_at(10)
	c3.pick_ability_talent(&"base_ability", &"rend_efficient")
	panel.open_for(c3, [], false)
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "an already-spent pick is still shown outside a safe zone")
	_check(not panel.is_row_interactive(&"base_ability"), "an already-spent row's buttons are disabled outside a safe zone (view-only)")
	panel.close()

	panel.open_for(c3, [], true)
	_check(panel.is_row_interactive(&"base_ability"), "the same already-spent row IS interactive in town (respec_available=true)")
	_check(panel.press_option_for_test(&"base_ability", &"rend_deeper_cut"), "town respec: picking a different option in an already-spent row succeeds (unpick + repick)")
	_check(c3.has_ability_talent(&"rend_deeper_cut"), "the swap actually changed the Combatant's pick")
	_check(not c3.has_ability_talent(&"rend_efficient"), "the old pick is cleared")
	panel.close()

	# Universal Perk section: 5 milestone slots, shown-when-reached (unlike the Ability Talent grid's
	# always-shown rows), one-time-pick enforcement carried straight through to TalentPerkLibrary.
	var c4: Combatant = _mk_warrior_at(3)
	panel.open_for(c4, [], true)
	_check(panel.universal_slot_count() == 1, "L3: only the L2 milestone has been reached (1 slot shown, got %d)" % panel.universal_slot_count())
	panel.close()

	var c5: Combatant = _mk_warrior_at(10)
	panel.open_for(c5, [], true)
	_check(panel.universal_slot_count() == 5, "L10: all 5 milestones reached (got %d)" % panel.universal_slot_count())
	_check(panel.press_universal_perk_for_test(&"vigor_boost"), "picking a universal perk succeeds")
	_check(c5.has_ability_talent(&"") == false, "sanity: has_ability_talent is unrelated to talent_perks")
	_check(&"vigor_boost" in c5.talent_perks, "the real Combatant now carries the picked universal perk")
	panel.close()

	# Playtest-found bug (2026-07-24): pressing an EMPTY universal-perk slot's button did nothing —
	# no handler existed for that case at all. Drive the REAL button press (not the
	# press_universal_perk_for_test() bypass, which calls pick_talent_perk() directly and would
	# never have caught this) through to a real picker option press.
	var c6: Combatant = _mk_warrior_at(10)
	panel.open_for(c6, [], true)
	_check(not panel.perk_picker_open_for_test(), "sanity: the perk picker starts closed")
	_check(panel.press_universal_slot_for_test(0), "pressing an empty universal-perk slot succeeds")
	_check(panel.perk_picker_open_for_test(), "pressing an empty slot opens the perk picker")
	_check(panel.perk_picker_option_count_for_test() == 10, "the picker offers all 10 perks when none are picked yet (got %d)" % panel.perk_picker_option_count_for_test())
	_check(panel.press_perk_picker_option_for_test(&"vigor_boost"), "pressing a picker option succeeds")
	_check(&"vigor_boost" in c6.talent_perks, "the real Combatant now carries the perk chosen through the actual picker UI")
	_check(not panel.perk_picker_open_for_test(), "the picker closes after a pick (panel rebuilds)")
	panel.close()

	# Playtest-found bug (2026-07-24): Button.toggle_mode auto-flips the CLICKED button's own
	# visual state on every click. Re-pressing an already-selected option must NOT change the real
	# pick, and the rebuild must restore that button's toggle-ON state (not leave it looking
	# deselected while the pick silently survives underneath, which read as "my de-select didn't
	# stick" and then "reverted" the next time anything else rebuilt the panel).
	var c7: Combatant = _mk_warrior_at(10)
	c7.pick_ability_talent(&"base_ability", &"rend_efficient")
	panel.open_for(c7, [], true)
	_check(panel.press_option_for_test(&"base_ability", &"rend_efficient"), "re-pressing the already-selected option is accepted (no-op on data, rebuilds the view)")
	_check(c7.has_ability_talent(&"rend_efficient"), "the pick is UNCHANGED by re-pressing its own button")
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "the button still shows as selected after the rebuild (not left looking deselected)")
	panel.close()

	# Same guard outside a safe zone: re-pressing an already-spent row's own option (or attempting
	# a different one) while respec is unavailable must also rebuild, not leave a stale/mismatched
	# toggle state on the buttons.
	var c8: Combatant = _mk_warrior_at(10)
	c8.pick_ability_talent(&"base_ability", &"rend_efficient")
	panel.open_for(c8, [], false)
	_check(not panel.press_option_for_test(&"base_ability", &"rend_deeper_cut"), "outside a safe zone, pressing a DIFFERENT option in an already-spent row is refused (button is disabled)")
	_check(c8.has_ability_talent(&"rend_efficient"), "the original pick survives untouched")
	panel.close()

	# Companion switcher (2026-07-25 companion-talent-panel spec): open_for() takes PC + companions,
	# defaults to viewing the PC (index 0), and switching tabs shows/edits a DIFFERENT Combatant's
	# own picks without touching anyone else's.
	var pc9: Combatant = _mk_warrior_at(10)
	var companion9: Combatant = ClassLibrary.make(&"skirmisher").build_combatant(true)
	companion9.level = 10
	panel.open_for(pc9, [companion9], true)
	_check(panel.party_tab_count() == 2, "2 tabs shown: PC + 1 companion (got %d)" % panel.party_tab_count())
	_check(panel.viewed_combatant_for_test() == pc9, "open_for() defaults to viewing the PC (index 0)")

	_check(panel.press_option_for_test(&"base_ability", &"rend_efficient"), "picking while viewing the PC picks it on the PC")
	_check(pc9.has_ability_talent(&"rend_efficient"), "the PC's own pick landed on the PC")
	_check(not companion9.has_ability_talent(&"rend_efficient"), "the companion is untouched by a pick made while viewing the PC")

	_check(panel.press_party_tab_for_test(1), "switching to the companion's tab succeeds")
	_check(panel.viewed_combatant_for_test() == companion9, "the panel now views the companion")
	_check(not panel.is_option_selected(&"base_ability", &"rend_efficient"), "the companion's OWN base_ability row shows no pick yet (Skirmisher options differ from Warrior's)")
	_check(panel.press_option_for_test(&"base_ability", &"flurry_efficient"), "picking a Skirmisher option while viewing the companion succeeds")
	_check(companion9.has_ability_talent(&"flurry_efficient"), "the pick landed on the COMPANION")
	_check(not pc9.has_ability_talent(&"flurry_efficient"), "the PC is untouched by a pick made while viewing the companion")

	_check(panel.press_party_tab_for_test(0), "switching back to the PC's tab succeeds")
	_check(panel.viewed_combatant_for_test() == pc9, "the panel now views the PC again")
	_check(pc9.has_ability_talent(&"rend_efficient"), "the PC's earlier pick is still there after switching away and back")
	panel.close()

	var pc10: Combatant = _mk_warrior_at(10)
	panel.open_for(pc10, [], true)
	_check(panel.party_tab_count() == 1, "with no companions, exactly 1 tab (the PC) is shown")
	panel.close()

	print(("TALENT MENU PANEL TEST PASSED" if _failures == 0 else "TALENT MENU PANEL TEST FAILED: %d" % _failures))
	quit(_failures)

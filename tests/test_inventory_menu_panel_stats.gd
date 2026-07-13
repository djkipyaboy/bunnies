extends SceneTree

## View-layer smoke: InventoryMenuPanel's Stats tab (2026-07-12, player-requested WoW-style
## character pane) — 3 columns mirroring the paperdoll (Companion1 | PC | Companion2), each
## showing the live 6-stat spread (gear bonuses included) with hover tooltips, plus weapon base
## damage. Opened directly via open_for()'s initial_tab param (the 'C' keybinding's entry point).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.base_stats = Stats.new()
	pc.base_stats.might = 3
	pc.base_stats.finesse = 2
	pc.base_stats.vigor = 1
	pc.base_stats.focus = 4
	pc.base_stats.grit = 0
	pc.base_stats.luck = 5
	var ring: Gear = Gear.new()
	ring.slot = Gear.Slot.CHARM
	ring.display_name = "Lucky Ring"
	ring.stat_bonuses = Stats.new()
	ring.stat_bonuses.might = 2
	pc.gear = [ring]
	var sword: Weapon = Weapon.new()
	sword.display_name = "Shortsword"
	sword.base_damage = 6.0
	pc.weapon = sword
	pc.level = 1
	pc.xp = 20

	var comp1: Combatant = Combatant.new()
	comp1.base_stats = Stats.new()

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()

	_check(InventoryMenuPanel.stat_value_at(pc.effective_stats(), 0) == 5, "stat_value_at(0) reads Might (base 3 + gear +2 = 5)")
	_check(InventoryMenuPanel.stat_value_at(pc.effective_stats(), 5) == 5, "stat_value_at(5) reads Luck")

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [comp1], inv, vault, true, &"stats")

	_check(panel.visible, "open_for shows the panel")
	_check(panel.active_tab_for_test() == &"stats", "initial_tab opens directly to the Stats tab")

	# PC is always the center column (paperdoll_columns convention) -> column 1.
	_check(panel.stat_row_text_for_test(1, 0) == "Might: 5", "PC column shows the live (gear-inclusive) Might total")
	_check(panel.stat_row_text_for_test(1, 1) == "Finesse: 2", "PC column shows Finesse")
	_check(panel.stat_row_text_for_test(1, 5) == "Luck: 5", "PC column shows Luck")
	_check(not panel.stat_row_tooltip_for_test(1, 0).is_empty(), "each stat row has a non-empty hover description")
	_check(panel.stat_damage_text_for_test(1) == "Weapon Base Damage: 6.0", "PC column shows weapon base damage")
	_check(panel.stat_xp_text_for_test(1) == "XP: 20", "PC column shows the live XP total (player direction 2026-07-12)")

	# Companion1 (col 0) is assigned -> real values, not the placeholder.
	_check(panel.stat_row_text_for_test(0, 0) == "Might: 0", "assigned companion column shows its own (zero) stats, not a placeholder")
	_check(panel.stat_xp_text_for_test(0) == "XP: 0", "assigned companion column shows its own (zero) xp")

	# Companion2 (col 2) is unassigned -> dim placeholder, no crash reading a null Combatant.
	_check(panel.stat_row_text_for_test(2, 0) == "Might: —", "unassigned companion column shows the em-dash placeholder")
	_check(panel.stat_damage_text_for_test(2) == "Weapon Base Damage: —", "unassigned companion column's damage row also shows the placeholder")
	_check(panel.stat_xp_text_for_test(2) == "XP: —", "unassigned companion column's xp row also shows the placeholder")

	# Switching back to Bag still works — the Stats tab doesn't wedge the panel.
	panel.switch_tab_for_test(&"bag")
	_check(panel.active_tab_for_test() == &"bag", "switching tabs away from Stats works normally")

	panel.free()
	quit()

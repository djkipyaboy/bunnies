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
	pc.max_hp = 50
	pc.hp = 45
	var pool: ResourcePool = ResourcePool.new()
	pool.stamina = 8
	pool.max_stamina = 10
	pc.resource_pool = pool
	var meter: BonusMeter = BonusMeter.new()
	meter.value = 3
	meter.cap = 15
	pc.bonus_meter = meter

	var comp1: Combatant = Combatant.new()
	comp1.base_stats = Stats.new()

	var inv: PartyInventory = PartyInventory.new()
	inv.amber = 42
	var vault: Vault = Vault.new()

	_check(InventoryMenuPanel.stat_value_at(pc.effective_stats(), 0) == 5, "stat_value_at(0) reads Might (base 3 + gear +2 = 5)")
	_check(InventoryMenuPanel.stat_value_at(pc.effective_stats(), 5) == 5, "stat_value_at(5) reads Luck")

	# resource_line_text() static helper — the 3 branches not otherwise reachable via the pc fixture
	# above (which only exercises the Stamina branch through a real panel).
	var mana_combatant: Combatant = Combatant.new()
	var mana_pool: ResourcePool = ResourcePool.new()
	mana_pool.mana = 6
	mana_pool.max_mana = 12
	mana_combatant.resource_pool = mana_pool
	_check(InventoryMenuPanel.resource_line_text(mana_combatant) == "Mana: 6 / 12", "resource_line_text() shows the Mana rail when max_stamina is 0")

	var empty_pool_combatant: Combatant = Combatant.new()
	empty_pool_combatant.resource_pool = ResourcePool.new()
	_check(InventoryMenuPanel.resource_line_text(empty_pool_combatant) == "Resource: —", "resource_line_text() falls back when both rails are 0")

	var null_pool_combatant: Combatant = Combatant.new()
	_check(InventoryMenuPanel.resource_line_text(null_pool_combatant) == "Resource: —", "resource_line_text() falls back when resource_pool is null")

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [comp1], inv, vault, true, &"stats")

	_check(panel.visible, "open_for shows the panel")
	_check(panel.active_tab_for_test() == &"stats", "initial_tab opens directly to the Stats tab")
	_check(panel.amber_text_for_test() == "Amber: 42", "the Stats tab shows the party's current Amber balance")

	# PC is always the center column (paperdoll_columns convention) -> column 1.
	_check(panel.stat_hp_text_for_test(1) == "HP: 45 / 50", "PC column shows HP current/max")
	_check(panel.stat_resource_text_for_test(1) == "Stamina: 8 / 10", "PC column shows its Stamina rail")
	_check(panel.stat_meter_text_for_test(1) == "Bonus Meter: 3 / 15", "PC column shows Bonus Meter current/cap")
	_check(panel.stat_row_text_for_test(1, 0) == "Might: 5", "PC column shows the live (gear-inclusive) Might total")
	_check(panel.stat_row_text_for_test(1, 1) == "Finesse: 2", "PC column shows Finesse")
	_check(panel.stat_row_text_for_test(1, 5) == "Luck: 5", "PC column shows Luck")
	_check(not panel.stat_row_tooltip_for_test(1, 0).is_empty(), "each stat row has a non-empty hover description")
	_check(panel.stat_damage_text_for_test(1) == "Weapon Base Damage: 6.0", "PC column shows weapon base damage")
	_check(panel.stat_xp_text_for_test(1) == "XP: 20", "PC column shows the live XP total (player direction 2026-07-12)")

	# Companion1 (col 0) is assigned -> real values, not the placeholder. A bare Combatant.new() has
	# no resource_pool/bonus_meter, so its rows fall back to the "Resource: —"/"Bonus Meter: —" text
	# (the placeholder is reused for BOTH "no rail data" and "no companion assigned" — the null-check
	# below covers the latter).
	_check(panel.stat_hp_text_for_test(0) == "HP: 0 / 1", "assigned companion column shows its own (default) HP")
	_check(panel.stat_resource_text_for_test(0) == "Resource: —", "an assigned companion with no resource_pool shows the fallback text")
	_check(panel.stat_meter_text_for_test(0) == "Bonus Meter: —", "an assigned companion with no bonus_meter shows the fallback text")
	_check(panel.stat_row_text_for_test(0, 0) == "Might: 0", "assigned companion column shows its own (zero) stats, not a placeholder")
	_check(panel.stat_xp_text_for_test(0) == "XP: 0", "assigned companion column shows its own (zero) xp")

	# Companion2 (col 2) is unassigned -> dim placeholder, no crash reading a null Combatant.
	_check(panel.stat_hp_text_for_test(2) == "HP: —", "unassigned companion column's HP row shows the em-dash placeholder")
	_check(panel.stat_resource_text_for_test(2) == "Resource: —", "unassigned companion column's resource row shows the em-dash placeholder")
	_check(panel.stat_meter_text_for_test(2) == "Bonus Meter: —", "unassigned companion column's bonus-meter row shows the em-dash placeholder")
	_check(panel.stat_row_text_for_test(2, 0) == "Might: —", "unassigned companion column shows the em-dash placeholder")
	_check(panel.stat_damage_text_for_test(2) == "Weapon Base Damage: —", "unassigned companion column's damage row also shows the placeholder")
	_check(panel.stat_xp_text_for_test(2) == "XP: —", "unassigned companion column's xp row also shows the placeholder")

	# Switching back to Bag still works — the Stats tab doesn't wedge the panel.
	panel.switch_tab_for_test(&"bag")
	_check(panel.active_tab_for_test() == &"bag", "switching tabs away from Stats works normally")

	panel.free()
	quit()

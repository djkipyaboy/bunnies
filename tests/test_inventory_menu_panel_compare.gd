extends SceneTree

## View-layer test: hover-tooltip text + the Compare toggle (spec §3.3) — a comparison line per
## paperdoll column that has an item equipped in the SAME slot, skipping empty-slot/no-companion columns.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.base_stats = Stats.new()
	var pc_hat: Gear = Gear.new()
	pc_hat.slot = Gear.Slot.HEADWEAR
	pc_hat.display_name = "PC's Cap"
	var pc_stats: Stats = Stats.new()
	pc_stats.vigor = 3
	pc_hat.stat_bonuses = pc_stats
	pc.gear = [pc_hat]

	var comp1: Combatant = Combatant.new()
	comp1.base_stats = Stats.new()
	# Companion 1 has nothing equipped in Headwear — must be SKIPPED (nothing to compare against).

	var candidate: Gear = Gear.new()
	candidate.slot = Gear.Slot.HEADWEAR
	candidate.display_name = "Candidate Cap"
	var cand_stats: Stats = Stats.new()
	cand_stats.might = 2
	cand_stats.vigor = -1
	candidate.stat_bonuses = cand_stats

	var columns: Array = [comp1, pc, null]   # Companion1 (empty slot) | PC (equipped) | no Companion2

	var with_compare: String = InventoryMenuPanel.item_tooltip_text(candidate, true, columns)
	_check(with_compare.contains("Candidate Cap"), "tooltip includes the item's name")
	_check(with_compare.contains("vs PC"), "tooltip compares against the PC (same slot occupied)")
	_check(with_compare.contains("Might +2"), "tooltip shows the candidate's Might bonus")
	_check(with_compare.contains("Vigor -1 (was +3)"), "tooltip shows the Vigor delta against the PC's equipped item")
	_check(not with_compare.contains("Companion 1"), "no compare line for a column with that slot empty")

	var without_compare: String = InventoryMenuPanel.item_tooltip_text(candidate, false, columns)
	_check(not without_compare.contains("vs PC"), "Compare disabled -> no comparison lines at all")
	_check(without_compare.contains("Candidate Cap"), "name/slot/stat summary still shown with Compare disabled")

	# Spec §3.3: Compare is scoped to Bag/Vault items only. A paperdoll slot's own hover tooltip
	# must NEVER show compare lines, even with the Compare checkbox ON — otherwise the PC's own
	# equipped item would show a nonsensical "vs PC: No change" line against itself.
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [comp1, null], inv, vault)
	panel.set_compare_enabled_for_test(true)
	var pc_hat_tooltip: String = panel.slot_button_tooltip_for_test(1, 1)
	_check(pc_hat_tooltip.contains("PC's Cap"), "paperdoll tooltip shows the equipped item's name")
	_check(pc_hat_tooltip.contains("Vigor +3"), "paperdoll tooltip shows the equipped item's own stat summary")
	_check(not pc_hat_tooltip.contains("vs "), "paperdoll tooltip never shows a compare line, even with Compare ON")
	panel.free()

	quit()

class_name AbilityMenuPanel
extends Panel

## Non-modal floating ability menu (spec 2026-07-02): one row per UNLOCKED ability (base L1 first,
## then L5/L7/L9), each a stage/un-stage toggle. Locked abilities are HIDDEN (player-locked rule).
## Opened by the combat scene's Abilities button; TypeChartPanel float-over-the-reels precedent.
## This file also owns the PURE row logic (row_state/cost_text/cooldown_text) so it's unit-testable
## headless without building a scene.

signal ability_pressed(id: StringName)

## Everything the old single base-ability button could render, as one enum (spec §2 table).
enum RowState { NORMAL, STAGED, UNAFFORDABLE, ON_COOLDOWN, LOCKED_BY_ULTIMATE, INCLUDED_FREE }

## The menu-row state for ability [param id] under the current plan. Base and extra abilities have
## different model gates (single ability_staged bool vs staged_extra_ability_id) — this is the one
## place that difference is flattened for the UI.
static func row_state(plan: MainPhasePlan, c: Combatant, id: StringName) -> RowState:
	if c != null and id == c.ability_id:
		if plan.ability_is_free():
			return RowState.INCLUDED_FREE
		if plan.ability_locked_by_ultimate():
			return RowState.LOCKED_BY_ULTIMATE
		if plan.ability_staged:
			return RowState.STAGED
		if plan.can_stage_ability():
			return RowState.NORMAL
		return RowState.UNAFFORDABLE
	if plan.staged_extra_ability_id == id:
		return RowState.STAGED
	if c != null and c.is_on_cooldown(id):
		return RowState.ON_COOLDOWN
	if plan.can_stage_extra_ability(id):
		return RowState.NORMAL
	return RowState.UNAFFORDABLE

## "2 STA" / "4 MANA", read LIVE from the plan (base) or AbilityDef (extra) — never from the catalog.
static func cost_text(plan: MainPhasePlan, c: Combatant, id: StringName) -> String:
	if id == &"double_or_nothing":
		return "all-in: ALL remaining Stamina"
	if c != null and id == c.ability_id:
		return "%d %s" % [plan.ability_cost, _rail_label(c.ability_resource)]
	var def: AbilityDef = c.find_extra_ability(id) if c != null else null
	if def == null:
		return ""
	return "%d %s" % [def.cost, _rail_label(def.resource)]

## "Ready" / "On cooldown: N turns" / "Ready — N-turn cooldown after use" (spec §2).
static func cooldown_text(c: Combatant, id: StringName) -> String:
	if c == null or id == c.ability_id:
		return "Ready"  # base abilities have no cooldowns
	if c.is_on_cooldown(id):
		return "On cooldown: %d turns" % int(c.cooldowns.get(id, 0))
	var def: AbilityDef = c.find_extra_ability(id)
	if def != null and def.cooldown_turns > 0:
		return "Ready — %d-turn cooldown after use" % def.cooldown_turns
	return "Ready"

static func _rail_label(resource: StringName) -> String:
	return "MANA" if resource == &"mana" else "STA"

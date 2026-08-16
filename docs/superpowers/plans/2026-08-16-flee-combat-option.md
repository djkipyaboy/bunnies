# Flee Combat Option Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add "Flee" as a real Main-Phase turn option: a PC stages it instead of an attack, it
resolves as a single whole-party reel spin, and success ends the encounter (no loot/XP) while
failure just wastes the turn.

**Architecture:** Flee is modeled as a new mutually-exclusive staged choice on `MainPhasePlan`
(same family as `staged_item_type`/`ability_staged`/`fire_ultimate_staged`), which on commit
REPLACES the attacker's `turn_reels` entirely with a single new no-damage utility reel
(`ActionReel.make_flee()`, `is_weapon_attack = false` so it never joins paylines). The reel
goes through the existing spin/strip pipeline unchanged; `combat.gd` reads its landed tier
right after the spin (same pattern already used for `rallying_cry_reel`/`item_use_reel`) and
branches in `_finish_spin()`: SUCCESS/CRIT_SUCCESS ends the encounter via a new "fled" result
path that skips `mark_defeated`/XP/loot, everything else (FAILURE/CRIT_FAILURE) just proceeds
to End Turn like any non-damaging action.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree`-based test scripts under `tests/`.

**Spec:** `docs/superpowers/specs/2026-08-16-combat-encounter-revamp-design.md` §1 (Flee).

## Global Constraints

- Engine: Godot 4.6+, GDScript only (no C#) — `CLAUDE.md` §2.
- Static typing for all new vars/signatures — `CLAUDE.md` §2.
- Reel tier weights are `[ASSUMPTION]` placeholders (tune later by playtest) — `CLAUDE.md` §4.
  Use `ABILITY_COMPOSITION`'s existing weights (5 crit-fail / 10 fail / 30 success / 5
  crit-success, out of 50) for the Flee reel — reuse an already-approved shape rather than
  inventing new numbers.
- Flee costs the chooser's whole turn (replaces `turn_reels` entirely), no extra resource cost.
- Whole-party single spin — not per-combatant.
- Success forfeits ALL loot/XP/Amber from the encounter, even from enemies already defeated
  earlier in the same fight — not just XP from unkilled enemies.
- Failure has zero punishment beyond the wasted turn.
- Disabled entirely when any enemy in the encounter has `is_boss == true`.
- Retry allowed on a later round after a failed attempt.

---

## Task 1: `ActionReel.make_flee()`

**Files:**
- Modify: `combat/resources/action_reel.gd`
- Test: `tests/test_action_reel.gd`

**Interfaces:**
- Produces: `static func make_flee() -> ActionReel` — a 50-face reel using
  `ABILITY_COMPOSITION`'s tier counts, every face `multiplier = 0.0`, `is_weapon_attack = false`,
  `charges_meter = false`, `damage_type = null`, no rider on any face.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_action_reel.gd` (follow its existing `_check()`/tier-counting style — open
the file first to match the exact helper it already uses to count faces by tier; the pattern
below assumes a `_count_tier(reel, tier)` style helper exists or is added inline):

```gdscript
	# --- make_flee(): no-damage utility reel, ABILITY_COMPOSITION tier counts, out of paylines ---
	var flee_reel: ActionReel = ActionReel.make_flee()
	_check(flee_reel.faces.size() == 50, "make_flee: 50 faces (got %d)" % flee_reel.faces.size())
	_check(not flee_reel.is_weapon_attack, "make_flee: is_weapon_attack = false (out of paylines)")
	_check(not flee_reel.charges_meter, "make_flee: charges_meter = false")
	var flee_crit_fail: int = 0
	var flee_fail: int = 0
	var flee_success: int = 0
	var flee_crit_success: int = 0
	for f: ReelFace in flee_reel.faces:
		_check(f.multiplier == 0.0, "make_flee: every face has multiplier 0.0")
		_check(f.rider_effect_id == &"", "make_flee: no face carries a rider")
		match f.result_tier:
			ReelFace.ResultTier.CRIT_FAILURE: flee_crit_fail += 1
			ReelFace.ResultTier.FAILURE: flee_fail += 1
			ReelFace.ResultTier.SUCCESS: flee_success += 1
			ReelFace.ResultTier.CRIT_SUCCESS: flee_crit_success += 1
	_check(flee_crit_fail == 5, "make_flee: 5 crit-failure faces (got %d)" % flee_crit_fail)
	_check(flee_fail == 10, "make_flee: 10 failure faces (got %d)" % flee_fail)
	_check(flee_success == 30, "make_flee: 30 success faces (got %d)" % flee_success)
	_check(flee_crit_success == 5, "make_flee: 5 crit-success faces (got %d)" % flee_crit_success)
```

- [ ] **Step 2: Run test to verify it fails**

Run (from the repo root, adjust the Godot path per `CLAUDE.md`'s note that the executable lives
one directory above the repo):
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_action_reel.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'make_flee' in base 'RefCounted'` (or
similar "not defined" parse/runtime error), since `make_flee()` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

Add to `combat/resources/action_reel.gd`, after `make_item_use()`:

```gdscript
## Builds the Flee-attempt reel (2026-08-16 combat-encounter-revamp spec §1): a no-damage
## utility reel reusing ABILITY_COMPOSITION's tier counts/odds (5 crit-fail / 10 fail / 30
## success / 5 crit-success, out of 50) — same shape already approved for resource-costed
## abilities, no new numbers invented. Every face has multiplier 0 (Flee never deals damage)
## and no rider. is_weapon_attack = false (out of paylines, same convention as Rallying Cry/
## item-use); charges_meter = false (attempting to escape shouldn't fuel the Bonus Meter).
## The orchestrator reads the landed tier post-spin: SUCCESS/CRIT_SUCCESS ends the encounter,
## FAILURE/CRIT_FAILURE just wastes the turn. [ASSUMPTION] tune tier weights by playtest,
## same as every other reel composition.
static func make_flee() -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = null
	reel.is_weapon_attack = false
	reel.charges_meter = false
	for entry: Array in ABILITY_COMPOSITION:
		var tier: ReelFace.ResultTier = entry[0]
		var count: int = entry[2]
		for i: int in range(count):
			reel.faces.append(_make_face(tier, 0.0))
	reel.faces.shuffle()
	return reel
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: PASS — all `_check()` lines print `ok:`.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_action_reel.gd
git commit -m "feat(flee): add ActionReel.make_flee() utility reel"
```

---

## Task 2: `Combatant.flee_reel` tracking field

**Files:**
- Modify: `combat/combatant.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `var flee_reel: ActionReel = null` — set by `MainPhasePlan.commit()` (Task 3) when
  Flee is staged, read by `combat.gd` (Task 5) to find the reel's resolved tier after a spin,
  mirroring the existing `rallying_cry_reel`/`item_use_reel` fields.

- [ ] **Step 1: Find the existing sibling fields**

Open `combat/combatant.gd` and locate the declarations of `rallying_cry_reel` and
`item_use_reel` (both `ActionReel`, defaulting to `null`, cleared at the start of each turn
alongside `turn_reels`). Add `flee_reel` immediately after them, same pattern:

```gdscript
## The Flee-attempt reel staged this turn, or null if Flee wasn't chosen (2026-08-16 combat-
## encounter-revamp spec §1). Mirrors rallying_cry_reel/item_use_reel: set once on commit, read
## by the orchestrator post-spin to find this reel's landed tier, cleared at the start of the
## next turn.
var flee_reel: ActionReel = null
```

- [ ] **Step 2: Clear it wherever the sibling fields are cleared**

Find where `rallying_cry_reel`/`item_use_reel` are reset to `null` (almost certainly in
`begin_turn()`, alongside `turn_reels` being rebuilt from the weapon) and add
`flee_reel = null` next to them, same pattern.

- [ ] **Step 3: No test yet — this is inert plumbing**

This field has no independent behavior to test; it's exercised by Task 3's and Task 5's tests.
Skip straight to commit.

- [ ] **Step 4: Commit**

```bash
git add combat/combatant.gd
git commit -m "feat(flee): add Combatant.flee_reel tracking field"
```

---

## Task 3: `MainPhasePlan` Flee staging

**Files:**
- Modify: `combat/main_phase_plan.gd`
- Test: `tests/test_main_phase_plan.gd`

**Interfaces:**
- Consumes: `ActionReel.make_flee()` (Task 1), `Combatant.flee_reel` (Task 2).
- Produces:
  - `var flee_staged: bool = false`
  - `func can_stage_flee() -> bool`
  - `func toggle_flee() -> void`
  - `preview_reels()` returns `[ActionReel.make_flee()]` (replacing everything) when
    `flee_staged` is true.
  - `commit()` — when `flee_staged`, sets `combatant.turn_reels = [<the flee reel>]`,
    `combatant.flee_reel = <that same reel>`, and returns immediately (skips every other
    ability/ultimate/item commit branch — Flee replaces the whole turn).
  - Every other `toggle_*` method (`toggle_ability`, `toggle_extra_ability`, `toggle_ultimate`,
    `toggle_item`) sets `flee_staged = false` on a successful stage, same "same mutual-exclusion
    family" convention already used for `staged_item_type`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_main_phase_plan.gd`, after the existing ability/ultimate sections (reuse
its `_mk_pc()` helper already defined in that file):

```gdscript
	# --- Flee: stages as a whole-turn replacement, mutually exclusive with everything else ---
	var fleeing: Combatant = _mk_pc(3, 0)
	var plan_flee: MainPhasePlan = MainPhasePlan.new(fleeing, 2, 5, 2)
	_check(plan_flee.can_stage_flee(), "flee stageable with no boss enemy present")
	plan_flee.toggle_flee()
	_check(plan_flee.flee_staged, "flee staged after toggle")
	_check(plan_flee.preview_reels().size() == 1, "flee preview REPLACES the loadout with 1 reel (got %d)" % plan_flee.preview_reels().size())
	_check(not plan_flee.preview_reels()[0].is_weapon_attack, "previewed flee reel is out of paylines")
	_check(fleeing.turn_reels.size() == 3, "PREVIEW DID NOT MUTATE turn_reels (got %d)" % fleeing.turn_reels.size())

	# --- Staging an ability un-stages Flee ---
	plan_flee.toggle_ability()
	_check(plan_flee.ability_staged, "ability staged")
	_check(not plan_flee.flee_staged, "staging ability un-stages flee")

	# --- Staging Flee un-stages a prior ability ---
	plan_flee.toggle_ability()  # un-stage the ability first
	plan_flee.toggle_ability()  # re-stage it
	plan_flee.toggle_flee()
	_check(plan_flee.flee_staged, "flee staged")
	_check(not plan_flee.ability_staged, "staging flee un-stages a previously-staged ability")

	# --- Commit: replaces turn_reels with exactly the flee reel, sets flee_reel, no resource spent ---
	var committer: Combatant = _mk_pc(3, 0)
	var plan_commit: MainPhasePlan = MainPhasePlan.new(committer, 2, 5, 2)
	plan_commit.toggle_flee()
	plan_commit.commit()
	_check(committer.turn_reels.size() == 1, "commit: turn_reels replaced with 1 reel (got %d)" % committer.turn_reels.size())
	_check(committer.flee_reel == committer.turn_reels[0], "commit: flee_reel points at the committed reel")
	_check(committer.resource_pool.stamina == 3, "commit: flee costs no resource (got %d)" % committer.resource_pool.stamina)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_main_phase_plan.gd`
Expected: FAIL — `can_stage_flee`/`toggle_flee`/`flee_staged` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/main_phase_plan.gd`:

1. Add the field near `staged_item_type` (top of the staged-choice fields):

```gdscript
## Whether Flee is staged this turn (2026-08-16 combat-encounter-revamp spec §1). Mutually
## exclusive with every other staged choice — same "one special action per turn" slot as
## staged_item_type — because Flee REPLACES the whole turn's loadout, not just adds to it.
var flee_staged: bool = false
```

2. Add `can_stage_flee()`/`toggle_flee()` near `can_stage_item()`/`toggle_item()`:

```gdscript
## True if Flee can be newly staged. Un-staging is always allowed. Boss/Elite exclusion
## (2026-08-16 spec §1) is enforced by the caller (combat.gd), which alone knows the enemy
## roster — MainPhasePlan only ever sees its own combatant.
func can_stage_flee() -> bool:
	return combatant != null

func toggle_flee() -> void:
	if flee_staged:
		flee_staged = false
	elif can_stage_flee():
		flee_staged = true
		ability_staged = false
		staged_extra_ability_id = &""
		fire_ultimate_staged = false
		selected_fate_type = null
		staged_item_type = &""
```

3. In `toggle_ability()`, add `flee_staged = false` inside the successful-stage `else` branch
   (the `if can_stage_ability():` block), alongside the existing
   `staged_extra_ability_id = &""` / `staged_item_type = &""` lines.

4. In `toggle_extra_ability()`, add `flee_staged = false` inside the `elif can_stage_extra_ability(id):`
   branch, alongside the existing clears.

5. In `toggle_ultimate()`, add `flee_staged = false` inside the `elif can_stage_ultimate():`
   branch, alongside the existing clears.

6. In `toggle_item()`, add `flee_staged = false` inside the `elif can_stage_item(...):` branch,
   alongside `ability_staged = false` / `staged_extra_ability_id = &""` / `fire_ultimate_staged = false`.

7. In `preview_reels()`, add a guard at the very top of the function body, before the existing
   `var reels: Array[ActionReel] = combatant.turn_reels.duplicate()` line:

```gdscript
	if flee_staged:
		return [ActionReel.make_flee()]
```

8. In `commit()`, add a guard at the very top of the function body, before the existing
   `var talent_cost: int = ...` line:

```gdscript
	if flee_staged:
		var reel: ActionReel = ActionReel.make_flee()
		combatant.turn_reels = [reel]
		combatant.flee_reel = reel
		return  # Flee replaces the whole turn — no ability/ultimate/item commit runs
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/main_phase_plan.gd tests/test_main_phase_plan.gd
git commit -m "feat(flee): stage Flee as a whole-turn-replacing MainPhasePlan choice"
```

---

## Task 4: Flee button + boss-gating in `combat.gd`

**Files:**
- Modify: `combat/combat.gd`

**Interfaces:**
- Consumes: `MainPhasePlan.flee_staged`/`can_stage_flee()`/`toggle_flee()` (Task 3), the
  existing `_enemies: Array[Combatant]` member and `is_player_main1`/`_plan` locals already
  used by `_refresh_main1_preview()`.
- Produces: `var _flee_button: Button`, `func _on_flee_pressed() -> void`, a
  `_any_enemy_is_boss() -> bool` helper, and staged-state readout wired into
  `_refresh_main1_preview()` alongside the existing Abilities/Ultimate/Items buttons.

- [ ] **Step 1: Declare and build the button**

Near the other button member declarations (`var _items_button: Button` etc., around
`combat.gd:54-58`), add:

```gdscript
var _flee_button: Button
```

Near where `_items_button`/`_team_up_button` are built (`combat.gd:461-479`, the "Items
button... its own 3rd row" comment), add a third button on the same row:

```gdscript
	# Flee button (2026-08-16 combat-encounter-revamp spec §1) — same 3rd-row convention as
	# Items/Team-Up!; gating (staged-state text + boss-disable) computed in
	# _refresh_main1_preview() alongside them.
	_flee_button = Button.new()
	_flee_button.text = "Flee"
	_flee_button.position = Vector2(col_x.call(2), ROW3_Y)
	_flee_button.custom_minimum_size = Vector2(BTN_W, 44)
	_flee_button.disabled = true
	_flee_button.tooltip_text = "Attempt to escape the fight — a single reel spin decides for the whole party. Replaces your attack this turn. All loot/XP is forfeited on success."
	add_child(_flee_button)
```

- [ ] **Step 2: Wire the press handler**

Near `_items_button.pressed.connect(_on_items_pressed)` (`combat.gd:1134`), add:

```gdscript
	_flee_button.pressed.connect(_on_flee_pressed)
```

Add the handler itself near `_on_abilities_pressed()`:

```gdscript
## Toggles Flee directly (no sub-menu — there's nothing to choose, unlike Abilities/Items).
func _on_flee_pressed() -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	_plan.toggle_flee()
	_refresh_main1_preview()
```

- [ ] **Step 3: Add the boss-check helper**

Near `_weapon_attack_count()` or another small `combat.gd` helper, add:

```gdscript
## True if any enemy in this encounter is a Boss/Elite (2026-08-16 spec §1: Flee is disabled
## entirely against a scripted boss fight — reuses is_boss, the same flag that already gates
## Bonus Meter visibility per CLAUDE.md §4.9, rather than introducing a separate Elite flag).
func _any_enemy_is_boss() -> bool:
	for e: Combatant in _enemies:
		if e.is_boss:
			return true
	return false
```

- [ ] **Step 4: Wire staged-state + gating into `_refresh_main1_preview()`**

In `_refresh_main1_preview()` (`combat.gd:1591` onward), add this block alongside the existing
Items-button staged-name logic (right after the `_items_button.disabled = ...` line at
`combat.gd:1646`):

```gdscript
	# Flee button (2026-08-16 spec §1): staged-green + label convention matching Items/Abilities;
	# disabled entirely against a Boss/Elite encounter regardless of staged state.
	if _plan.flee_staged:
		_flee_button.text = "Flee ✓"
		_flee_button.modulate = Color(0.6, 1.0, 0.6)
	else:
		_flee_button.text = "Flee"
		_flee_button.modulate = Color(1, 1, 1)
	_flee_button.disabled = not (is_player_main1 and _plan.can_stage_flee() and not _any_enemy_is_boss())
```

- [ ] **Step 5: Disable the button everywhere the other Main-1 buttons get force-disabled**

Search `combat.gd` for every place `_items_button.disabled = true` is set outside
`_refresh_main1_preview()` (the spin-press handler around `combat.gd:1420`, the turn-settle
block around `combat.gd:1528`/`2567`, and `_on_combat_ended()` around `combat.gd:2638`) and add
`_flee_button.disabled = true` next to each one, same as `_team_up_button` already does.

- [ ] **Step 6: Manual verification (no automated test for pure UI wiring yet — Task 6 covers
      the end-to-end behavior)**

Run the project via the `run` skill (or however this project is normally launched — see
`CLAUDE.md`'s note that the Godot executable lives one directory above the repo), start a
non-boss fight, and confirm: the Flee button is enabled during your Main Phase, toggling it
shows "Flee ✓" in green and un-toggles any previously-staged ability, and it becomes disabled
in the Hollow Warden boss fight (use the Town board's debug boss-fight button mentioned in
memory `teamup-riposte-fixes-and-boss-debug-harness-design`-style existing debug entry points,
or whatever the current boss-fight launch path is).

- [ ] **Step 7: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(flee): add Flee button, staged-state readout, boss-gating"
```

---

## Task 5: Resolve the Flee reel and end the encounter on success

**Files:**
- Modify: `combat/combat.gd`
- Test: `tests/test_combat_flee.gd` (new)

**Interfaces:**
- Consumes: `Combatant.flee_reel` (Task 2), the existing `_do_spin()`/`_finish_spin()` pipeline,
  `reels`/`attacks` locals already computed in `_do_spin()`, `_resolve_handoff_continue()`,
  `_on_combat_ended()`, `_fight_xp_gained`/`_fight_amber_gained`/`_fight_loot_names`/
  `_fight_overflow_items` members (all already exist).
- Produces: `var _flee_tier: int = -1` (member, mirrors `_rallying_cry_tier`/`_item_use_tier`),
  `var _fled_this_encounter: bool = false` (member), `func _on_combat_fled() -> void`.
  `_resolve_handoff_continue()` is modified to skip `mark_defeated`/recovery/defeat-reset when
  `_fled_this_encounter` is true.

- [ ] **Step 1: Track the Flee reel's landed tier in `_do_spin()`**

Near the existing `_rallying_cry_tier`/`_item_use_tier` tracking block in `_do_spin()`
(`combat.gd:1934-1952`), add a member declaration alongside `_rallying_cry_tier`/`_item_use_tier`
(wherever those are declared, near the top of the file):

```gdscript
var _flee_tier: int = -1         # this spin's Flee reel landed tier (-1 = none staged)
var _fled_this_encounter: bool = false  # true once a Flee attempt has succeeded this fight
```

Then in `_do_spin()`, immediately after the existing `_item_use_tier` block
(`combat.gd:1948-1952`), add:

```gdscript
	# Flee reel (2026-08-16 spec §1): read the utility reel's resolved tier the same way, so
	# _finish_spin can decide whether the whole party escapes. flee_reel is null unless Flee was
	# staged this turn.
	_flee_tier = -1
	if _attacker.flee_reel != null:
		var flee_idx: int = reels.find(_attacker.flee_reel)
		if flee_idx >= 0 and flee_idx < attacks.size():
			_flee_tier = attacks[flee_idx].face.result_tier
```

- [ ] **Step 2: Branch on the tier in `_finish_spin()`**

In `_finish_spin()`, add a branch immediately after the existing Item-use block
(`combat.gd:2541-2549`, right before `_attacker.consume_aoe_spin()`):

```gdscript
	# Flee attempt (2026-08-16 spec §1): SUCCESS/CRIT_SUCCESS ends the encounter for the whole
	# party immediately (no further turns, no XP/loot); FAILURE/CRIT_FAILURE just wastes this
	# turn — fall through to the normal end-of-spin flow below exactly like any non-damaging
	# action, and the party may attempt Flee again on a later round.
	if _attacker.flee_reel != null and _flee_tier != -1:
		if _flee_tier == ReelFace.ResultTier.SUCCESS or _flee_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			var tier_text: String = "CRITICAL SUCCESS" if _flee_tier == ReelFace.ResultTier.CRIT_SUCCESS else "SUCCESS"
			_log("  🏃 %s attempts to Flee — %s! The party escapes." % [_attacker.display_name, tier_text])
			_on_combat_fled()
			return
		else:
			_log("  🏃 %s attempts to Flee — fails! The turn is wasted." % _attacker.display_name)
```

- [ ] **Step 3: Add `_on_combat_fled()`**

Add this method right after `_on_combat_ended()`:

```gdscript
## A Flee attempt succeeded (2026-08-16 spec §1): ends the encounter for the whole party without
## going through the normal win/loss attrition check. Mirrors _on_combat_ended()'s overlay/label
## bookkeeping but shows "FLED!" and deliberately shows NO XP/Amber/Loot — those are forfeited
## entirely, even for enemies already defeated earlier in this same fight (unlike a real win,
## which always keeps whatever was earned).
func _on_combat_fled() -> void:
	_fled_this_encounter = true
	for c: Combatant in _pcs:
		c.clear_combat_effects()
		if _panels.has(c):
			(_panels[c] as CombatantPanel).refresh_riposte()
	_last_result_won = true  # routes _resolve_handoff_continue() to return_scene_path (overworld), same as a win
	_spin_button.disabled = true
	_end_turn_button.disabled = true
	_team_up_button.disabled = true
	_flee_button.disabled = true
	_awaiting_player_spin = false
	_awaiting_end_turn = false
	var label: Label = _overlay.get_node("ResultLabel")
	label.text = "FLED!"
	var continue_button: Button = _overlay.get_node_or_null("ContinueButton")
	if continue_button != null:
		continue_button.tooltip_text = "Return to the overworld. All loot and XP from this encounter were forfeited."
	if _arrived_via_handoff:
		var enemy_names: Array[String] = []
		for e: Combatant in _enemies:
			enemy_names.append(e.display_name)
		_handoff().log_event("Fled from: %s" % ", ".join(enemy_names), &"combat")
	_log("Combat over — the party fled.")
	move_child(_overlay, get_child_count() - 1)
	_overlay.visible = true
```

- [ ] **Step 4: Skip mark_defeated/recovery in `_resolve_handoff_continue()`**

In `_resolve_handoff_continue()` (`combat.gd:2744` onward), change the existing:

```gdscript
	if _last_result_won:
		handoff.mark_defeated(handoff.pending_encounter_id)
		_apply_post_combat_recovery()
	else:
		_apply_defeat_reset()
```

to:

```gdscript
	if _fled_this_encounter:
		pass  # no mark_defeated, no recovery, no defeat reset — the encounter is simply left behind
	elif _last_result_won:
		handoff.mark_defeated(handoff.pending_encounter_id)
		_apply_post_combat_recovery()
	else:
		_apply_defeat_reset()
```

- [ ] **Step 5: Write the failing test — routing/forfeit behavior via the `press_continue_for_test()` harness**

`test_combat_win_recovery.gd` proves this harness doesn't need to drive a real spin to test
post-`_finish_spin()` routing: it builds a real `combat.tscn` instance via `CombatHandoff.
begin_encounter(...)`, sets `inst._last_result_won` DIRECTLY, then calls
`inst.press_continue_for_test()` and asserts on the result. Task 5's routing/forfeit logic
(Step 4's `_resolve_handoff_continue()` change) is testable the exact same way — set
`inst._fled_this_encounter` directly instead of driving a real spin through the flee reel.
Create `tests/test_combat_flee.gd`:

```gdscript
extends SceneTree

# Headless test for the Flee combat option's post-spin routing (2026-08-16 spec §1). Mirrors
# tests/test_combat_win_recovery.gd's exact handoff-harness pattern — sets the routing flag
# directly rather than driving a real spin, since _resolve_handoff_continue()'s branching is
# what this task actually changes. Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_flee.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	# --- Fled encounter: no mark_defeated, no recovery/defeat-reset, routes like a win, label reads FLED! ---
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	pc.hp = pc.max_hp - 50  # damaged; a WIN would normally partially recover this — Flee must NOT
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	var return_path: String = "res://world/overworld_demo.tscn"
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"OverworldRat", return_path, Vector2(1.0, 2.0))

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var hp_before: int = pc.hp
	inst._on_combat_fled()  # simulates a successful Flee's post-spin call, same call site _finish_spin() uses
	var label: Label = inst._overlay.get_node("ResultLabel")
	_check(label.text == "FLED!", "result label reads FLED! (got: %s)" % label.text)

	var path: String = inst.press_continue_for_test()
	_check(path == return_path, "fled encounter routes to return_scene_path, same as a win (got: %s)" % path)
	_check(pc.hp == hp_before, "fled PC gets NO post-combat recovery (before %d, after %d)" % [hp_before, pc.hp])
	_check(not CombatHandoff.is_defeated(&"OverworldRat"), "fled encounter is NOT marked defeated (can be re-fought)")

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	# --- Sanity: a REAL win still marks defeated + recovers, proving the new _fled_this_encounter
	# branch didn't regress the existing win path (test_combat_win_recovery.gd covers this in more
	# depth; this is a lighter smoke check specific to the branch this task edited). ---
	var win_pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	win_pc.hp = win_pc.max_hp - 50
	CombatHandoff.begin_encounter(win_pc, [], inv, vault, enemy_ids, &"OverworldRat2", return_path, Vector2(1.0, 2.0))
	var win_scene: PackedScene = load("res://combat/combat.tscn")
	var win_inst: Combat = win_scene.instantiate()
	get_root().add_child(win_inst)
	await process_frame
	await process_frame
	var win_hp_before: int = win_pc.hp
	win_inst._last_result_won = true
	win_inst.press_continue_for_test()
	_check(win_pc.hp > win_hp_before, "sanity: a real win still recovers HP (before %d, after %d)" % [win_hp_before, win_pc.hp])
	_check(CombatHandoff.is_defeated(&"OverworldRat2"), "sanity: a real win still marks the encounter defeated")
	win_inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("COMBAT FLEE TEST PASSED" if _failures == 0 else "COMBAT FLEE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 6: Run test to verify it fails**

Run:
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_flee.gd`
Expected: FAIL — `_on_combat_fled`/`_fled_this_encounter` don't exist yet (write this test
BEFORE Steps 1-4's production code to get a genuine red step, then implement Steps 1-4, then
come back and run it green).

- [ ] **Step 7: Run test to verify it passes**

Same command as Step 6, after Steps 1-4's production code is in place. Expected: PASS, 0
failures, exit code 0.

- [ ] **Step 7b: Manually verify the spin-triggered branch (Steps 1-2's tier-reading + the
      FAILURE/retry path) — not covered by the headless test above**

The test above exercises `_on_combat_fled()`'s routing directly, which is what Task 5 actually
changes in `_resolve_handoff_continue()`. The reel-tier-detection code from Steps 1-2 (reading
`_flee_tier` off a real spin and calling `_on_combat_fled()` from `_finish_spin()`) is simpler
to verify by hand than to headlessly force a specific reel face through the full paylines
pipeline: launch a non-boss fight, stage Flee, spin repeatedly (its ~70% base success rate per
the `ABILITY_COMPOSITION` weights means a success shows up within a few tries) and confirm (a)
a FAILURE/CRIT_FAILURE spin just logs the miss and lets the turn/round proceed normally with
Flee stageable again next round, and (b) a SUCCESS/CRIT_SUCCESS spin immediately shows the
"FLED!" overlay. Note in your task report which outcome you actually observed.

- [ ] **Step 8: Also re-run the full existing suite for regressions**

Run every test file already touched by this plan (`test_action_reel.gd`,
`test_main_phase_plan.gd`) plus `test_combat_win_recovery.gd`, `test_combat_defeat_reset.gd`,
and `test_turn_manager.gd`/`test_phase_manager.gd` to confirm nothing about the shared
`_finish_spin()`/`_resolve_handoff_continue()` control flow broke for the normal win/loss
paths. Expected: PASS on all.

- [ ] **Step 9: Commit**

```bash
git add combat/combat.gd tests/test_combat_flee.gd
git commit -m "feat(flee): resolve the Flee reel, end encounter on success, forfeit loot/XP"
```

---

## Self-review notes (for whoever executes this plan)

- Task 5's headless test (`test_combat_flee.gd`) exercises `_on_combat_fled()` and
  `_resolve_handoff_continue()`'s new branch directly, the same way
  `test_combat_win_recovery.gd` sets `_last_result_won` directly rather than driving a full
  spin. The actual spin→tier→`_on_combat_fled()` call wiring from Steps 1-2 is verified
  manually in Step 7b — flagged explicitly there rather than silently skipped.
- This plan does not touch `TurnManager`, `PhaseManager`, or the type-chart/damage system —
  Flee is entirely a `MainPhasePlan` + `combat.gd` orchestration feature, per the spec's
  cross-cutting note that all three bundled features are additive.
- The other two bundled spec sections (visible initiative reels; the minion-summoning class)
  are separate plans, not part of this one.

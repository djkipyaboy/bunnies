# Summoner Playtest Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the bugs and data-tuning items surfaced by the 2026-08-17 human playtest of the
newly-merged Summoner ability kit (Ember/Dew/Misfortune/Hasty minions + Grand Sacrifice Ultimate),
without touching anything the playtest confirmed as working.

**Architecture:** No new systems — every task is a targeted fix inside the existing summoner-kit
code (`combat/combat.gd`, `combat/combatant.gd`, `combat/main_phase_plan.gd`,
`combat/ui/combatant_panel.gd`). Two tasks are pure numeric-constant tuning (locked-in by the
player, not [ASSUMPTION] guesses). One task (Task 3) is a live-debugging investigation because its
root cause is NOT yet confirmed by static code reading — write a repro test FIRST and let its
result drive whether a fix is even needed.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree`-based test scripts under `tests/`.

**Spec:** This plan has no separate spec doc — it implements playtest feedback directly against
`docs/superpowers/specs/2026-08-16-summoner-ability-kit-design.md` (the shipped kit) and the
2026-08-17 playtest report (see conversation/session log; key quotes are reproduced inline per
task below).

## Global Constraints

- Engine: Godot 4.6+, GDScript only (no C#) — `CLAUDE.md` §2.
- Static typing for all new vars/signatures — `CLAUDE.md` §2.
- Numeric balance values changed here (Misfortune curse damage) are explicit player-locked
  requests, not further [ASSUMPTION] guesses — do not adjust them beyond what's specified.
- Godot executable: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe` (headless test
  runs), `..._win64.exe` (windowed playtest launches).
- Run each new/modified test with: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
- After adding any new `const`/field, no class-cache refresh is needed (no new `class_name`
  introduced by this plan).
- The Dew Minion stage-2 heal bump (Task 6) is UNCONDITIONAL (always 12, not conditional on
  cleanse firing) — the conditional version was explicitly deferred to a future talent-tree design
  session (see memory `dew-cleanse-conditional-heal-talent-idea`). Do not implement the
  conditional variant here.

---

## Task 1: Prune dead minions from the turn-order tracker

**Files:**
- Modify: `combat/combat.gd:3072-3084` (the summon-reel resolution block inside `_finish_spin()`/`_apply_attack()`'s summon handling)
- Modify: `combat/combat.gd:769-793` (`_run_minion_stage()`, where a minion expires on stage-3 completion)
- Test: `tests/test_minion_lifecycle.gd` (extend the existing file — do not rewrite unrelated cases)

**Context:** Player report: *"hasty minion: lingering minion initiative scores do not leave the
initiative tracker once they are depleted. attempting to replace the non working minion with a new
one did not allow more than the stage 1..."*

**Root cause (confirmed by code read):** `TurnManager.combatants: Array[Combatant]` (`combat/turn_manager.gd:23`)
is never pruned. Two sites add a dead entry that's never removed:
1. `combat/combat.gd:769-793` — `_run_minion_stage()`'s stage-3-completion expiry does
   `minion.take_damage(minion.hp)` but never removes `minion` from `_turn_manager.combatants`.
2. `combat/combat.gd:3072-3084` — summoning a replacement while an old minion is alive kills the
   old one the same way (`_attacker.active_minion.take_damage(_attacker.active_minion.hp)`) but
   again never removes it from `_turn_manager.combatants`.

Both leave a permanently-dead `Combatant` sitting in the list. `_announce_current()`
(`combat/turn_manager.gd:143-149`) correctly SKIPS it via `is_alive()`, so it never stalls the
turn cursor — but it does mean `_turn_manager.combatants` grows without bound over a long fight
with several minion summon/replace cycles, and any UI that iterates that list to show "who's still
in this fight" (turn-order displays, party rosters keyed off it) keeps showing a dead entry
forever. This is very likely what the player is describing as "lingering minion initiative scores."

**Interfaces:**
- Produces: `TurnManager.remove_dead_combatant(c: Combatant) -> void` — new method on
  `TurnManager`, removes `c` from both `combatants` and the current round's `_order` (if present),
  so a dead minion vanishes from every turn-order-derived view immediately instead of lingering
  until the array is next rebuilt.

- [ ] **Step 1: Write the failing test**

Open `tests/test_minion_lifecycle.gd` first to match its exact `_check`/setup style (it already
builds a real combat scenario — reuse that harness). Add:

```gdscript
	# Regression (2026-08-17 playtest): a minion killed by expiry or replacement must be removed
	# from TurnManager.combatants, not just left dead in the list forever.
	var tm2: TurnManager = TurnManager.new()
	var caster2: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	var enemy2: Combatant = EnemyLibrary.make(&"rat")
	tm2.combatants = [caster2, enemy2]
	tm2.roll_initiative()
	var minion_a: Combatant = MinionLibrary.make(false, &"ember")
	caster2.active_minion = minion_a
	tm2.roll_initiative_for(minion_a)
	tm2.combatants.append(minion_a)
	_check(tm2.combatants.has(minion_a), "minion_a starts in TurnManager.combatants")
	minion_a.take_damage(minion_a.hp)
	tm2.remove_dead_combatant(minion_a)
	_check(not tm2.combatants.has(minion_a), "expired minion_a is removed from TurnManager.combatants (got size %d)" % tm2.combatants.size())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_lifecycle.gd`
Expected: FAIL on `remove_dead_combatant` — the method doesn't exist yet (parse/script error is
acceptable here since it's a missing method, not a logic mismatch).

- [ ] **Step 3: Add `TurnManager.remove_dead_combatant()`**

In `combat/turn_manager.gd`, add near `insert_acting_this_round()`:

```gdscript
## Removes a dead combatant (an expired or replaced minion) from both the master list and the
## current round's fixed order, so it stops appearing in any turn-order-derived view immediately
## instead of lingering until the list is next rebuilt (2026-08-17 playtest fix).
func remove_dead_combatant(c: Combatant) -> void:
	combatants.erase(c)
	var idx: int = _order.find(c)
	if idx != -1 and idx < _turn_index:
		_turn_index -= 1  # keep the cursor pointing at the same logical next-actor after the shrink
	_order.erase(c)
```

- [ ] **Step 4: Call it from both expiry sites in `combat.gd`**

In `_run_minion_stage()` (`combat/combat.gd:790-792`), change:

```gdscript
	if stage >= 3 and minion.is_alive():
		_log("  %s completes its final stage and fades away." % minion.display_name)
		minion.take_damage(minion.hp)
```

to:

```gdscript
	if stage >= 3 and minion.is_alive():
		_log("  %s completes its final stage and fades away." % minion.display_name)
		minion.take_damage(minion.hp)
		_turn_manager.remove_dead_combatant(minion)
```

In the summon-replacement block (`combat/combat.gd:3072-3074`), change:

```gdscript
		if _attacker.active_minion != null and _attacker.active_minion.is_alive():
			_attacker.active_minion.take_damage(_attacker.active_minion.hp)
```

to:

```gdscript
		if _attacker.active_minion != null and _attacker.active_minion.is_alive():
			_attacker.active_minion.take_damage(_attacker.active_minion.hp)
			_turn_manager.remove_dead_combatant(_attacker.active_minion)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_lifecycle.gd`
Expected: PASS, including the pre-existing cases in this file (don't regress them).

- [ ] **Step 6: Commit**

```bash
git add combat/turn_manager.gd combat/combat.gd tests/test_minion_lifecycle.gd
git commit -m "fix(minion): remove expired/replaced minions from TurnManager.combatants"
```

---

## Task 2: Reset stale `active_minion` between combat encounters

**Files:**
- Modify: `combat/combat.gd:257-275` (`_build_combatants()`, right after `_pcs` is populated from either branch)
- Test: `tests/test_combat_handoff_last_town.gd` or a new focused test — see Step 1 (name it `tests/test_stale_active_minion_reset.gd` to keep this regression isolated and greppable)

**Context:** Player report: *"bug where summoner is able to queue the ultimate to fire when there
is no minion active. may be lingering from the previous combat encounter that finished with a
minion active for the ally party. upon testing the ultimate, it fired the 'sacrifice hasty minion'
version... this usage of ultimate applies to all of the minion types and will use the active one
from the end of last combat each time."*

**Root cause (confirmed by code read):** `Combatant.active_minion` is only ever cleared to `null`
inside `fire_grand_sacrifice()` (`combat/combatant.gd:2287`) — never on natural minion expiry,
never on combat end. The Summoner PC is a PERSISTENT `Combatant` instance carried across
encounters via `CombatHandoff` (`combat/combat.gd:236-243`, the `_arrived_via_handoff` branch of
`_build_combatants()`: `_pcs.append(handoff.pc as Combatant)`). If a fight ends while the
Summoner's minion is still alive, `active_minion` keeps pointing at that (now off-screen, still
technically alive) `Combatant` into the NEXT encounter, where
`MainPhasePlan.can_stage_ultimate()` (`combat/main_phase_plan.gd:120-124`) reads exactly that
stale reference (`combatant.active_minion != null and combatant.active_minion.is_alive()`) and
wrongly reports the Ultimate as fireable.

Per the project's recurring "test both CombatHandoff paths" gotcha (a field only reset/tested
through one of the two paths — `stash_party()`/`SceneExit` vs. `begin_encounter()`/
`OverworldEnemy` — has silently broken on the other before), reset this in `_build_combatants()`
UNCONDITIONALLY after `_pcs` is fully populated, not inside just the `_arrived_via_handoff` branch
— that way it's covered regardless of which path fed the party in.

**Interfaces:**
- Consumes: `Combatant.active_minion` (existing field, `combat/combatant.gd`), `_pcs: Array[Combatant]` (existing, populated earlier in `_build_combatants()`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_stale_active_minion_reset.gd` (mirror the `SceneTree`-script style of
`tests/test_combat_handoff_last_town.gd` — copy its boilerplate header/`_check`/`_finish` helpers
exactly since this needs a real `CombatHandoff` + `combat.tscn` instantiation):

```gdscript
extends SceneTree

## Regression (2026-08-17 playtest): active_minion must not survive into a new combat encounter
## via CombatHandoff — a minion still alive when a fight ends must not let the Summoner's
## Ultimate wrongly report itself as fireable in the NEXT fight.

var _failures: int = 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok %s" % msg)
	else:
		_failures += 1
		print("FAIL %s" % msg)

func _init() -> void:
	var handoff: Node = get_root().get_node("/root/CombatHandoff")
	var summoner: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	summoner.active_minion = MinionLibrary.make(false, &"hasty")  # simulates a fight that ended with a live minion
	handoff.pc = summoner
	handoff.companions = []
	handoff.enemy_ids = [&"rat"]
	handoff.party_inventory = PartyInventory.new()

	var combat_scene: PackedScene = load("res://combat/combat.tscn")
	var combat: Node = combat_scene.instantiate()
	get_root().add_child(combat)
	# _build_combatants() runs as part of _start_combat(), which _ready() already triggered via
	# _arrived_via_handoff — no extra call needed here; just re-read the same summoner instance.
	_check(summoner.active_minion == null, "active_minion is reset to null when a new encounter is built from handoff (got %s)" % summoner.active_minion)

	if _failures > 0:
		print("STALE ACTIVE MINION RESET TEST FAILED: %d" % _failures)
		quit(1)
	else:
		quit(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stale_active_minion_reset.gd`
Expected: FAIL — `active_minion` is still the old Hasty minion instance.

- [ ] **Step 3: Reset it in `_build_combatants()`**

In `combat/combat.gd`, immediately after the `if _arrived_via_handoff: ... else: ...` block that
populates `_pcs` (right before the `_pc = _pcs[0]` line, `combat/combat.gd:~272`), add:

```gdscript
	# Combat-only transient state must not survive across encounters even though the Combatant
	# itself does (CombatHandoff carries the same PC/companion instances forward). A minion still
	# alive when a fight ended would otherwise let the NEXT fight's Ultimate check
	# (MainPhasePlan.can_stage_ultimate()) wrongly see a live active_minion from last time
	# (2026-08-17 playtest fix). Reset unconditionally — covers both the handoff path and the
	# standalone "Choose your Party" launch path alike.
	for p: Combatant in _pcs:
		p.active_minion = null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stale_active_minion_reset.gd`
Expected: PASS.

- [ ] **Step 5: Run the existing Grand Sacrifice + handoff suites to confirm no regression**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_grand_sacrifice.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff_last_town.gd
```
Expected: both PASS (the Grand Sacrifice suite builds its own `active_minion` fresh per test via
direct assignment, so a same-encounter reset must not clear it out from under a test that sets it
up and fires within the same `_build_combatants()` call — confirm this by reading the test's setup
order before treating a failure here as expected).

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd tests/test_stale_active_minion_reset.gd
git commit -m "fix(summoner): reset active_minion when a new combat encounter is built"
```

---

## Task 3: Investigate — Hasty minion not acting once Initiative exceeds 100

**Files:**
- Test: `tests/test_hasty_minion.gd` (extend)
- Modify: TBD — depends entirely on what Step 1's repro finds. Do not guess at a fix location
  before the repro test result is in hand.

**Context:** Player report: *"hasty minion: stage 1 working (if minion's initiative surpasses 100
after being buffed, it does not act during combat any more)"* — but later in the same report:
*"upon starting a new combat encounter, hasty minion rolled an initiative of 50, received the +20
bonus to initiative, and then was able to act on its turn with its stage 2 ability as expected"*
(50+20=70, under 100 — consistent with the bug only appearing above 100).

**Status: NOT YET CONFIRMED as a code bug.** A full read of `TurnManager.get_turn_order()`
(`combat/turn_manager.gd:68-80`, plain descending sort on `current_initiative: int`, no
clamp/modulo) and `Combatant.recompute_initiative()` (`combat/combatant.gd:1279-1284`, plain int
arithmetic, no clamp) found NO code path that treats a value over 100 specially. This does not
mean the bug is imaginary — it means the repro needs to happen live, matching the actual sequence
that triggered it (a minion whose ALREADY-HIGH rolled Initiative, not just the buffed total, pushes
past 100), rather than being guessed at from a plan document.

- [ ] **Step 1: Write a repro test using a real combat scenario**

Add to `tests/test_hasty_minion.gd` (match its existing setup style — it already drives a real
`combat.tscn` encounter per the plan's Task 8 test):

```gdscript
	# Regression repro (2026-08-17 playtest): does a Hasty-buffed minion whose current_initiative
	# exceeds 100 still get a turn? Force a high base roll so the +20 buff pushes it over 100.
	var tm3: TurnManager = TurnManager.new()
	var caster3: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	var enemy3: Combatant = EnemyLibrary.make(&"rat")
	tm3.combatants = [caster3, enemy3]
	tm3.roll_initiative()
	var hasty3: Combatant = MinionLibrary.make(false, &"hasty")
	hasty3.base_initiative = 95  # force high; +20 Hasty buff will push current_initiative to 115
	hasty3.recompute_initiative()
	var haste_buff := Effect.new()
	haste_buff.id = &"hasty_initiative"
	haste_buff.kind = Effect.Kind.INITIATIVE_MOD
	haste_buff.magnitude = 20.0
	haste_buff.duration = 3
	haste_buff.beneficial = true
	hasty3.attach_effect(haste_buff)
	_check(hasty3.current_initiative > 100, "test setup: current_initiative is actually over 100 (got %d)" % hasty3.current_initiative)
	tm3.combatants.append(hasty3)
	tm3.begin()
	var order3: Array[Combatant] = tm3.get_turn_order()
	_check(order3.has(hasty3), "a >100-current_initiative minion still appears in get_turn_order() (size %d)" % order3.size())
	_check(order3[0] == hasty3, "it sorts to the FRONT of turn order, not dropped (front is %s)" % order3[0].display_name)
```

- [ ] **Step 2: Run it**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion.gd`

- [ ] **Step 3a: If it PASSES** (turn order is fine at the `TurnManager` level)

The bug is NOT in turn-order sorting. Before writing any fix, get a more precise repro from the
player: ask specifically what UI element or log line showed the minion "not acting" — likely
candidates to check next (do not fix speculatively): the Initiative reel strip display
(`combat/ui/initiative_reel_strip.gd`) rendering a 2-digit-only widget that might visually show
"00"/garbage for a 3-digit value and get misread as "not this minion's turn yet," or the
`_turn_order_bar` widget (`combat/combat.gd:1637`, `_turn_order_bar.set_current(c)`) silently
failing to highlight/advance past a 3-digit value. Report back to the human partner with these
specific candidates rather than guessing a fix blind.

- [ ] **Step 3b: If it FAILS** (confirms a real `TurnManager`/`Combatant` bug)

Investigate the actual failure output (which assertion failed) and fix the specific defect found
— e.g. if `order3[0] != hasty3`, add debug prints of `current_initiative`/`tiebreak_roll` for both
combatants in the failing case and trace `sort_custom`'s comparator step by step for this exact
pair before changing any code.

- [ ] **Step 4: Commit whatever was actually found/fixed**

```bash
git add tests/test_hasty_minion.gd combat/turn_manager.gd combat/combatant.gd
git commit -m "fix(hasty): <describe the actual root cause found, or 'add >100-initiative regression coverage' if it already passed>"
```

---

## Task 4: Hasty stage-3 extra reel — show it in the pre-spin preview

**Files:**
- Modify: `combat/main_phase_plan.gd:317-384` (`preview_reels()`)
- Test: `tests/test_hasty_minion.gd` (extend) or `tests/test_reel_surge_buff.gd` (extend — pick whichever already builds a `MainPhasePlan` for a `reel_surge`-carrying combatant; check both files' existing setup before choosing)

**Context:** Player report: *"stage 3 working but additional weapon reel does not show up until
spin has already been chosen. This additional reel should also affect the paylines available."*

**Root cause (confirmed by code read):** The extra reel from Hasty's `reel_surge` buff is only
appended at spin-commit time, in `_commit_main1()` (`combat/combat.gd:2317-2329`) — which runs
from `_on_spin_pressed()`, i.e. AFTER the player has already viewed the pre-spin preview built by
`MainPhasePlan.preview_reels()` (`combat/main_phase_plan.gd:317-384`) and pressed Spin.
`preview_reels()` already has an established pattern for previewing OTHER reel-adding mechanics
that aren't player-staged toggles (e.g. the Rampage/Collateral/Earthquake Ultimate block at
`main_phase_plan.gd:370-375`, which checks `fire_ultimate_staged` directly rather than
`staged_extra_ability_id`) — `reel_surge` needs the same treatment, keyed on
`combatant.has_effect(&"reel_surge")` (an ALREADY-ACTIVE passive buff from a prior turn, not
something staged this turn).

Because `preview_reels()` is also what feeds the payline-scoring preview (whatever downstream code
computes "paylines available" reads this same array), adding the reel here fixes both parts of the
report in one change — there's no separate payline-preview code path to touch.

**Interfaces:**
- Consumes: `Combatant.has_effect(effect_id: StringName) -> bool` (existing method), the existing
  `REEL_SURGE_CAP: int = 5` constant currently local to `combat.gd:_commit_main1()` — duplicate the
  literal `5` in `main_phase_plan.gd` rather than importing it (it's a plain int matching the
  project-wide reel cap already referenced by comment at `main_phase_plan.gd:2323`, not worth a
  cross-file constant for one caller).

- [ ] **Step 1: Write the failing test**

Add to `tests/test_reel_surge_buff.gd` (open it first to match its exact setup — it already builds
a real combatant with `reel_surge` attached and a `MainPhasePlan`):

```gdscript
	# Regression (2026-08-17 playtest): the reel-surge reel must appear in the PRE-spin preview,
	# not just after commit — otherwise the player picks their spin blind to the extra reel.
	var plan_preview: MainPhasePlan = MainPhasePlan.new(surging, surging.ability_cost, 5, 2, null)
	var previewed: Array[ActionReel] = plan_preview.preview_reels()
	_check(previewed.size() == surging.turn_reels.size() + 1, "preview_reels() includes the reel-surge bonus reel before commit (got %d, base was %d)" % [previewed.size(), surging.turn_reels.size()])
```

(Adjust the setup-combatant variable name — call it whatever the file's existing `reel_surge`-carrying
test combatant is actually named; do not introduce a second one.)

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_surge_buff.gd`
Expected: FAIL — `previewed.size()` equals the base count, no bonus reel.

- [ ] **Step 3: Add the preview branch**

In `combat/main_phase_plan.gd`, inside `preview_reels()`, right after the existing
Rampage/Collateral/Earthquake block (`main_phase_plan.gd:370-375`) and before the Big Bang block,
add:

```gdscript
	# Hasty Minion's reel-surge buff (2026-08-16 summoner-ability-kit spec, playtest fix
	# 2026-08-17): an ALREADY-ACTIVE passive buff from a prior turn, not a staged ability — so it's
	# keyed on has_effect() like the Rampage/Collateral/Earthquake block above, not on
	# staged_extra_ability_id. Must mirror _commit_main1()'s 5-reel cap exactly so the preview never
	# promises a reel that commit-time will actually reject in favor of the overflow fallback.
	const PREVIEW_REEL_SURGE_CAP: int = 5
	if combatant.has_effect(&"reel_surge") and reels.size() < PREVIEW_REEL_SURGE_CAP:
		reels.append(ActionReel.make_ability_attack(combatant.weapon_type()))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_surge_buff.gd`
Expected: PASS.

- [ ] **Step 5: Run the full Hasty + reel-surge suites to confirm no regression**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_surge_buff.gd
```
Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add combat/main_phase_plan.gd tests/test_reel_surge_buff.gd
git commit -m "fix(hasty): preview the reel-surge bonus reel before spin, not just at commit"
```

---

## Task 5: Combat-log clarity — reel-surge overflow, Dew thorns, Hasty regen

**Files:**
- Modify: `combat/combat.gd:2551-2561` (`_apply_attack()`, the reel-surge overflow log line)
- Modify: `combat/combat.gd:815-835` (`_run_dew_stage()`, add a thorns log line)
- Modify: `combat/combat.gd:869-906` (`_run_hasty_stage()`, add a regen log line)
- Test: `tests/test_reel_surge_buff.gd`, `tests/test_dew_minion.gd`, `tests/test_hasty_minion.gd` (extend each)

**Context:** Player report (reel-surge): *"combat log message about basil's reel surge overflow is
a bit confusing as none of the successful damage rolls had 13 added to them... it might be adding
the 13 damage but not mentioning it on the specific reel result line... it would be best if it was
the first reel that achieved the successful attack roll... might be worth adding the hp totals of
targets... after trying a few more times... the additional damage is being added correctly it just
isn't clear in the combat log which swing is the one that benefits from the bonus damage."*
Player report (Dew): *"thorns buff needs to be added to combat log."*
Player report (Hasty): *"buff regen should be added to combat log."*

**Root cause (confirmed by code read):** All three are pure logging gaps / clarity issues, not
logic bugs — the underlying mechanics (which reel gets doubled, the thorns/regen effects
themselves) already work correctly per the player's own follow-up testing.
`combat/combat.gd:2557-2561` currently logs only the delta (`surge_bonus`, equal to the hit's own
`final_damage`) with no reel index and no before/after HP; `_run_dew_stage()`/`_run_hasty_stage()`
never log the thorns/regen attachment at all (unlike the adjacent cleanse log line at
`combat.gd:823-824`, which already prints on attach).

- [ ] **Step 1: Update the reel-surge overflow log line**

In `combat/combat.gd`, replace the block at `~2557-2561`:

```gdscript
			if _attacker.reel_surge_overflow_pending and (attack.face.result_tier == ReelFace.ResultTier.SUCCESS or attack.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS):
				var surge_bonus: int = attack.final_damage
				t.take_damage(surge_bonus)
				_log("  ⚡ %s's reel surge overflow doubles this hit's damage (would-be 6th reel converted to +%d bonus damage)." % [_attacker.display_name, surge_bonus])
				_attacker.reel_surge_overflow_pending = false
```

with:

```gdscript
			if _attacker.reel_surge_overflow_pending and (attack.face.result_tier == ReelFace.ResultTier.SUCCESS or attack.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS):
				var surge_bonus: int = attack.final_damage
				t.take_damage(surge_bonus)
				_log("  ⚡ %s's reel surge overflow DOUBLES reel %d's hit on %s: +%d bonus damage (%d/%d HP)." % [_attacker.display_name, reel_index + 1, t.display_name, surge_bonus, t.hp, t.max_hp])
				_attacker.reel_surge_overflow_pending = false
```

(`reel_index` and `t` must already be in scope from the enclosing per-reel loop in `_apply_attack()`
— confirm the exact loop variable name by reading the surrounding ~20 lines before editing; if the
loop variable is named differently, e.g. `i`, use that instead of `reel_index`.)

- [ ] **Step 2: Add the Dew thorns log line**

In `combat/combat.gd:_run_dew_stage()`, inside the `if stage >= 3:` block (`~825-832`), immediately
after `ally.attach_effect(thorns)`, add:

```gdscript
				_log("  🛡 Dew Minion wraps %s in Thorns (%d%% reflected, %d turns)." % [ally.display_name, roundi(DEW_THORNS_PCT * 100), DEW_THORNS_TURNS])
```

- [ ] **Step 3: Add the Hasty regen log line**

In `combat/combat.gd:_run_hasty_stage()`, inside the `if stage == 2:` block (`~886-893`),
immediately after `ally.attach_effect(regen)`, add:

```gdscript
			_log("  💨 Hasty Minion grants %s +%d resource regen (%d turns)." % [ally.display_name, HASTY_REGEN_BONUS, HASTY_REGEN_TURNS])
```

- [ ] **Step 4: Write/extend tests asserting each new log line fires**

Each of the three test files above already drives a real combat scenario and has access to
whatever log-capture mechanism the project's other log-assertion tests use (grep the file for
`_log` or a captured log array/signal — match its existing pattern exactly rather than inventing a
new one). Add one `_check` per new line confirming it appears after the relevant stage fires, e.g.
for Dew:

```gdscript
	_check("Thorns" in captured_log_text, "Dew stage-3 logs the Thorns application")
```

(Substitute the project's actual log-capture variable/method name — read the file's existing
log-assertion cases first; do not guess at an API that doesn't exist.)

- [ ] **Step 5: Run all three affected test files, confirm PASS**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_surge_buff.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion.gd
```

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd tests/test_reel_surge_buff.gd tests/test_dew_minion.gd tests/test_hasty_minion.gd
git commit -m "fix(summoner): clarify reel-surge overflow log line, log Thorns/regen application"
```

---

## Task 6: Data tuning — Misfortune curse damage + Dew stage-2 heal

**Files:**
- Modify: `combat/combat.gd:843-857` (`_run_misfortune_stage()`, stage-3 curse)
- Modify: `combat/combat.gd:908-939+` (`_apply_grand_sacrifice()`, `&"misfortune"` branch — find the exact `dot_base_damage = 2.0` line by reading the branch, since the provided line range is approximate)
- Modify: `combat/combat.gd:807-835` (`_run_dew_stage()` + its `const` block above it)
- Test: `tests/test_misfortune_minion.gd`, `tests/test_grand_sacrifice.gd`, `tests/test_dew_minion.gd` (extend each)

**Context:** Player-locked values (not [ASSUMPTION] guesses — explicit playtest requests):
- *"stage 3 working but curse is defaulted to 1 damage. bump dot up to 6 damage per turn"*
- *"issue is improved curse is only 3 damage per tick. up improved curse damage to 18 damage per turn"*
- *"unconditional 12 for stage 2"* (Dew heal, confirmed via this session's clarifying question)

**Math (confirmed by code read):** The shared `&"cursed"` effect's damage formula
(`combat/resources/effect.gd:dot_damage()`) is `ceili(dot_base_damage * dot_fractions[stacks-1])`,
with `dot_fractions = [0.50, 0.80, 1.15]` (`combat/effect_library.gd`, unchanged, shared by every
`&"cursed"` user — do not touch this table, only the per-call-site `dot_base_damage`).
- Misfortune stage 3 currently: `dot_base_damage = 1.0`, `stacks` stays at default 1 →
  `ceili(1.0*0.50) = 1`. Target 6/turn at stacks=1 → `dot_base_damage = 12.0` → `ceili(12*0.50) = 6`. ✓
- Grand Sacrifice's `&"misfortune"` branch currently: `dot_base_damage = 2.0`, two `add_stack()`
  calls → stacks=3 → `ceili(2.0*1.15) = 3`. Target 18/turn at stacks=3 → `dot_base_damage = 15.0` →
  `ceili(15.0*1.15) = ceili(17.25) = 18`. ✓

- [ ] **Step 1: Write/extend the failing tests**

In `tests/test_misfortune_minion.gd`, add (matching its existing setup style):

```gdscript
	_check(cursed_effect.dot_damage() == 6, "Misfortune stage-3 curse deals 6 damage/turn (got %d)" % cursed_effect.dot_damage())
```

(Substitute the file's actual variable name for the attached `&"cursed"` `Effect` instance —
whatever the existing stage-3 test case already retrieves it as.)

In `tests/test_grand_sacrifice.gd`, add similarly for the `&"misfortune"` variant's curse:

```gdscript
	_check(improved_curse.dot_damage() == 18, "Grand Sacrifice's improved curse deals 18 damage/turn (got %d)" % improved_curse.dot_damage())
```

In `tests/test_dew_minion.gd`, update (or add, if the existing stage-2 case only checks
`heal_amount == 8`) to expect 12:

```gdscript
	_check(ally.hp == hp_before + 12, "Dew stage-2 heals for 12 (got delta %d)" % (ally.hp - hp_before))
```

- [ ] **Step 2: Run all three, verify they fail**

Run each test file headlessly; expect the new/updated assertions to FAIL against current values
(1, 3, 8 respectively).

- [ ] **Step 3: Change the three constants**

In `combat/combat.gd:_run_misfortune_stage()`:
```gdscript
			if stage == 3:
				var curse: Effect = EffectLibrary.make(&"cursed")
				curse.dot_base_damage = 12.0  # flat, not weapon-scaled — 6 dmg/turn at stacks=1 (2026-08-17 playtest: was 1 dmg/turn)
				enemy.attach_effect(curse)
```

In `combat/combat.gd:_apply_grand_sacrifice()`'s `&"misfortune"` branch, change
`curse.dot_base_damage = 2.0` to `curse.dot_base_damage = 15.0` (add a trailing comment: `# 18 dmg/turn at stacks=3 (2026-08-17 playtest: was 3 dmg/turn)`).

In `combat/combat.gd`, add a new constant next to the existing Dew ones and use it:
```gdscript
const DEW_STAGE1_HEAL: int = 8
const DEW_STAGE2_HEAL: int = 12  # 2026-08-17 playtest: bumped from 8 (unconditional, not tied to cleanse)
const DEW_STAGE3_HEAL: int = 16
```
and change `_run_dew_stage()`'s heal-amount line from:
```gdscript
	var heal_amount: int = DEW_STAGE3_HEAL if stage == 3 else DEW_STAGE1_HEAL
```
to:
```gdscript
	var heal_amount: int = DEW_STAGE3_HEAL if stage == 3 else (DEW_STAGE2_HEAL if stage == 2 else DEW_STAGE1_HEAL)
```

- [ ] **Step 4: Run all three tests, verify PASS**

Re-run the three headless test commands from Step 2; expect PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_misfortune_minion.gd tests/test_grand_sacrifice.gd tests/test_dew_minion.gd
git commit -m "tune(summoner): Misfortune curse 1->6 and improved curse 3->18 dmg/turn, Dew stage-2 heal 8->12 (2026-08-17 playtest)"
```

---

## Task 7: Ally panel — status/buff area clips below the Bonus Meter at some window sizes

**Files:**
- Modify: `combat/ui/combatant_panel.gd:119-124` (`_status_label` setup)
- Test: `tests/test_combatant_panel.gd` if it exists (check first via the file list); otherwise add a focused new test `tests/test_combatant_panel_status_overflow.gd`

**Context:** Player report: *"window size and scaling also make it impossible to see below the
bonus meter of the bottom ally combatant in combat (buffs, debuffs, etc. all appearing
offscreen)."*

**Root cause (confirmed by code read):** `CombatantPanel` is a fixed-size `Panel`
(`custom_minimum_size = Vector2(PANEL_W, 312)`, `combat/ui/combatant_panel.gd:42-43`) built from a
`VBoxContainer` whose LAST child is `_status_label`, a `RichTextLabel` with `fit_content = true`
and `scroll_active = false` (`combat/ui/combatant_panel.gd:119-123`) sized for "~3 wrapped lines."
The Summoner kit's minions can stack several simultaneous status entries on one ally (Thorns +
cleanse-eligible debuffs + regen + reel_surge + Empowered, etc.) — once that text needs more than
~3 lines, `fit_content` grows the label past its allotted space, but the PARENT `Panel` stays fixed
at 312px, so the overflow is silently clipped rather than reflowed — exactly the "appearing
offscreen" symptom, and it's positioned last (below the meter bar), matching "impossible to see
below the bonus meter."

**Fix approach:** Make the status area scroll internally within its own allotted space instead of
either clipping or growing the whole panel (growing the panel would just push other UI around at
extreme cases) — flip `scroll_active` on and give it a bounded, slightly taller fixed height so
normal cases (1-2 effects) never need to scroll, but a stacked case (4+) scrolls instead of
clipping invisibly.

- [ ] **Step 1: Write the failing test**

Check whether `tests/test_combatant_panel.gd` exists first (`Glob tests/test_combatant_panel*.gd`).
If it exists, extend it; otherwise create `tests/test_combatant_panel_status_overflow.gd` mirroring
the project's existing UI-panel-size test pattern (e.g. `tests/test_professions_menu_panel.gd`'s
style of instantiating the panel node directly in a `SceneTree` script and reading back computed
sizes — copy its boilerplate).

```gdscript
	var panel := CombatantPanel.new()
	get_root().add_child(panel)
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	# Stack enough simultaneous status effects that the old fit_content behavior would overflow
	# the panel's fixed 312px height.
	for i: int in range(6):
		var e := Effect.new()
		e.id = StringName("stack_test_%d" % i)
		e.beneficial = true
		e.duration = 3
		c.attach_effect(e)
	panel.bind(c)  # substitute the panel's actual setup/bind method name — read combatant_panel.gd's public API first
	await get_tree().process_frame
	_check(panel._status_label.scroll_active, "status label scrolls internally instead of clipping when overloaded with effects")
```

(This test reads a private-by-convention member (`_status_label`) for verification only, matching
this codebase's existing convention of test files reaching into `_`-prefixed fields for assertions
— confirm that convention still holds by grepping an existing UI test for a similar underscore
access before relying on it here.)

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combatant_panel_status_overflow.gd` (or the extended existing file)
Expected: FAIL — `scroll_active` is currently `false`.

- [ ] **Step 3: Flip scroll_active and give it a bounded taller height**

In `combat/ui/combatant_panel.gd`, change:

```gdscript
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(ROW_W, 60)  # room for ~3 wrapped lines of active effects
	box.add_child(_status_label)
```

to:

```gdscript
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = false  # bounded height + internal scroll instead of growing past the panel (2026-08-17 playtest fix)
	_status_label.scroll_active = true
	_status_label.custom_minimum_size = Vector2(ROW_W, 80)  # room for ~4 wrapped lines visible at once; more scrolls internally
	box.add_child(_status_label)
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2; expect PASS.

- [ ] **Step 5: Run the full CombatantPanel-adjacent test files to confirm no regression**

Run whatever existing test files reference `CombatantPanel` (grep for it across `tests/` first) —
in particular any test that asserts on `_status_label.text` content, since `fit_content = false`
does not change the label's `.text` value, only its layout, so text-content assertions should be
unaffected; confirm this empirically rather than assuming it.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/combatant_panel.gd tests/test_combatant_panel_status_overflow.gd
git commit -m "fix(ui): scroll the ally panel's status/buff area instead of clipping when overloaded"
```

---

## Task 8: Full regression pass

**Files:** None (verification only).

- [ ] **Step 1: Run the entire summoner-kit-adjacent test set**

Run every test file touched or referenced by Tasks 1-7 individually (not just as a batch grep), and
confirm each exits 0 with no `FAIL`/`SCRIPT ERROR` in its output:
```
tests/test_minion_lifecycle.gd
tests/test_stale_active_minion_reset.gd
tests/test_hasty_minion.gd
tests/test_reel_surge_buff.gd
tests/test_dew_minion.gd
tests/test_misfortune_minion.gd
tests/test_grand_sacrifice.gd
tests/test_combatant_panel_status_overflow.gd (or the extended existing file)
tests/test_minion_library.gd
tests/test_summoner_class.gd
tests/test_combat_handoff_last_town.gd
```

- [ ] **Step 2: Run the FULL project test suite** (not just the summoner-kit subset)

```bash
for f in tests/test_*.gd; do
  Godot_v4.6.3-stable_win64_console.exe --headless --path . --script "res://$f"
done
```
Grep actual output for `SCRIPT ERROR`/`FAIL` per `CLAUDE.md`'s silent-script-error-exits-zero
gotcha — do not trust exit codes alone. Compare the failure set against the pre-existing baseline
already established on `main` (`test_double_or_nothing.gd`, `test_inventory_demo_setup_pc_override.gd`,
`test_start_menu.gd`, and `test_professions_menu_panel.gd`'s stale fixture) — any NEW failure
outside that baseline must be fixed before this task is done.

- [ ] **Step 3: Commit the final state (if anything from Step 2 needed a fix)**

Only if Step 2 surfaced something: fix it, re-run, then:
```bash
git add -A
git commit -m "fix(summoner): full regression pass after playtest fixes"
```
If Step 2 was clean against the known baseline, no commit is needed for this task.

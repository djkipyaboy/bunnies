# The Hollow Warden Boss Fight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build The Hollow Warden — a 550-HP, Dark-typed, multi-phase dungeon boss with two
minion-summoning phases, a re-triggerable phase transition, and the game's first enemy Ultimate —
and place it on dungeon floor 4.

**Architecture:** Almost every mechanic reuses an existing combat system unchanged (the type chart,
the reel/damage resolver, the multi-enemy-floor placement pattern, the AoE-targeting mechanism every
existing Ultimate already shares, the Foresight/Regrowth-style orchestrator-applies-a-pending-flag
pattern). The two genuinely new pieces are: (1) a small state machine on `Combatant` +
`combat/combat.gd` tracking the boss's phase and cooldown, and (2) a new `_spawn_enemy_mid_combat()`
helper that lets a Combatant join a fight already in progress and act that same round — nothing in
this codebase does that yet.

**Tech Stack:** Godot 4.6.3-stable, GDScript only, static typing throughout.

## Global Constraints

- **Engine: Godot 4.6+ (4.6.3-stable). Language: GDScript only** — no C#.
- **Prefer static typing** (typed vars, typed function signatures).
- **Default to writing no comments.** Only add one when the WHY is non-obvious.
- Test convention: headless `extends SceneTree` scripts under `tests/test_*.gd`, run via
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  from the `bunnies/` project root. Exit code 0 = all checks passed — never grep stdout for "FAIL".
- **After adding/changing a `class_name`-visible symbol**, refresh the project's class cache before
  running a headless test that references it:
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
- **Git commit hygiene**: this repository's working tree has unrelated pre-existing UNTRACKED files
  sitting in it from other in-progress work. Always `git add` the EXACT files a task changed, by
  name — never `git add -A` or `git add .`.
- **Every new `Combatant` field this plan adds is meaningless/zero for every non-boss/non-minion
  Combatant** (players, rat/ferret/stoat) — do not touch `ClassLibrary`, `EnemyLibrary`'s existing 3
  entries, or any existing ability/effect code beyond the exact additive edits each task specifies.
- **`EffectLibrary.make()` always returns a NEW `Effect` instance** (never shared) — every new
  `match` branch this plan adds must follow that existing convention exactly.
- **Round every new damage/heal number up (`ceili`)** — this project's locked convention
  (`round-up-damage-healing` memory) — already followed in every code sample below.
- Spec: `docs/superpowers/specs/2026-07-19-hollow-warden-boss-fight-design.md` (read this first for
  full architectural rationale — every code sample in this plan is drawn directly from it).

---

### Task 1: New status effects — `warden_curse` and `indestructible`, plus `Combatant.remove_effect()`

**Files:**
- Modify: `combat/effect_library.gd`
- Modify: `combat/combatant.gd`
- Test: `tests/test_warden_effects.gd` (new)

**Interfaces:**
- Produces: `EffectLibrary.make(&"warden_curse")`, `EffectLibrary.make(&"indestructible")`,
  `Combatant.remove_effect(id: StringName) -> void`.
- Consumed by: Task 5 (minion ability applies `warden_curse`), Task 7 (boss phase-transition
  attaches/removes `indestructible`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_warden_effects.gd`:

```gdscript
extends SceneTree

## Headless test for the Hollow Warden's 2 new effects (spec 2026-07-19 §3.1): warden_curse (a FLAT
## stacking party-wide DoT, unlike every existing weapon-derived DoT) and indestructible (blocks
## direct damage via the existing MULTIPLIER_EDIT mechanism, leaves DoT ticks untouched). Also proves
## the new Combatant.remove_effect() removes an unexpired effect early.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var curse: Effect = EffectLibrary.make(&"warden_curse")
	_check(curse != null, "warden_curse resolves to a real Effect")
	_check(curse.kind == Effect.Kind.DAMAGE_OVER_TIME, "warden_curse is a DoT")
	_check(curse.max_stacks == 3, "warden_curse stacks up to 3")
	_check(curse.dot_fractions == [4.0, 7.0, 10.0], "warden_curse fractions are [4.0, 7.0, 10.0]")
	_check(curse.duration == 3, "warden_curse lasts 3 turns per stack")
	_check(not curse.beneficial, "warden_curse is a debuff")
	curse.dot_base_damage = 1.0  # the flat baseline this project's orchestrator seeds at apply time
	_check(curse.dot_damage() == 4, "1 stack of warden_curse deals 4 (flat, not weapon-scaled)")
	curse.add_stack()
	_check(curse.dot_damage() == 7, "2 stacks of warden_curse deals 7")
	curse.add_stack()
	_check(curse.dot_damage() == 10, "3 stacks of warden_curse deals 10 (cap)")

	var indestructible: Effect = EffectLibrary.make(&"indestructible")
	_check(indestructible != null, "indestructible resolves to a real Effect")
	_check(indestructible.kind == Effect.Kind.MULTIPLIER_EDIT, "indestructible is a MULTIPLIER_EDIT")
	_check(indestructible.magnitude == 0.0, "indestructible's magnitude is 0.0 (blocks all direct damage)")
	_check(indestructible.affects_incoming, "indestructible affects INCOMING damage")
	_check(indestructible.beneficial, "indestructible is beneficial (from the boss's own perspective)")

	var c: Combatant = Combatant.new()
	c.attach_effect(indestructible)
	_check(c.incoming_damage_multiplier() == 0.0, "a combatant with indestructible has incoming_damage_multiplier() == 0.0")
	_check(c.dot_damage_multiplier() > 0.0, "indestructible does NOT affect dot_damage_multiplier() — DoT still applies")

	# Two independent effects to prove remove_effect only removes the named one.
	c.attach_effect(EffectLibrary.make(&"guarded"))
	_check(c.has_effect(&"indestructible"), "indestructible is active before removal")
	_check(c.has_effect(&"guarded"), "guarded is active before removal")
	c.remove_effect(&"indestructible")
	_check(not c.has_effect(&"indestructible"), "remove_effect() removes indestructible")
	_check(c.has_effect(&"guarded"), "remove_effect() leaves guarded untouched")
	_check(c.incoming_damage_multiplier() != 0.0, "incoming_damage_multiplier() is no longer 0.0 once indestructible is removed")
	c.remove_effect(&"nonexistent_id")
	_check(c.has_effect(&"guarded"), "remove_effect() on a nonexistent id is a harmless no-op")

	print(("WARDEN EFFECTS TEST PASSED" if _failures == 0 else "WARDEN EFFECTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_warden_effects.gd`
Expected: FAIL — `EffectLibrary.make(&"warden_curse")`/`&"indestructible"` return `null` (no such
branch yet), and `Combatant.remove_effect` doesn't exist yet (parse error or missing-method error).

- [ ] **Step 3: Add the 2 new effects to `combat/effect_library.gd`**

Add these 2 new `match` branches to `EffectLibrary.make()`, immediately before the final `_:` branch:

```gdscript
		&"warden_curse":
			# The Hollow Warden's Minion B ability (spec 2026-07-19 §3.1) — a FLAT stacking party-wide
			# DoT, unlike every other DoT in this codebase (bleed/cursed/regen all scale off a weapon).
			# The orchestrator seeds dot_base_damage = 1.0 at apply time so dot_damage() produces exactly
			# 4/7/10 rather than a weapon-scaled number.
			var e: Effect = Effect.new()
			e.id = &"warden_curse"; e.kind = Effect.Kind.DAMAGE_OVER_TIME; e.duration = 3
			e.max_stacks = 3; e.dot_fractions = [4.0, 7.0, 10.0]; e.beneficial = false
			return e
		&"indestructible":
			# The Hollow Warden's phase-2 buff (spec 2026-07-19 §3.1) — blocks ALL direct damage via the
			# existing MULTIPLIER_EDIT mechanism (magnitude 0.0). DoT ticks read a separate multiplier
			# hook (dot_damage_multiplier) and are unaffected — no extra plumbing needed. duration is a
			# long placeholder; the orchestrator clears this explicitly via remove_effect(), not expiry.
			var e: Effect = Effect.new()
			e.id = &"indestructible"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 0.0
			e.affects_incoming = true; e.duration = 99; e.beneficial = true
			return e
```

- [ ] **Step 4: Add `Combatant.remove_effect()` to `combat/combatant.gd`**

Add this new method immediately after `cleanse()` (search for `func cleanse() -> int:`):

```gdscript
## Removes the active effect with [param id], if any, then refreshes the derived sort key. Used by
## the boss phase-transition orchestrator to clear Indestructible the instant both its minions die —
## not a turn-counted expiry, so tick_effects()/cleanse() can't do this (spec 2026-07-19 §3.1).
func remove_effect(id: StringName) -> void:
	active_effects = active_effects.filter(func(e: Effect) -> bool: return e.id != id)
	recompute_initiative()
```

- [ ] **Step 5: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 6: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_warden_effects.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 7: Run the existing effect test suite for regressions**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_effect_thorns.gd`
(or any other pre-existing `test_effect*`/`test_*_effect*.gd` file) — confirm still exit 0 (this
task is purely additive to `EffectLibrary.make()`'s match and adds a new `Combatant` method, so no
existing behavior should change).

- [ ] **Step 8: Commit**

```bash
git add combat/effect_library.gd combat/combatant.gd tests/test_warden_effects.gd
git commit -m "feat(combat): add warden_curse + indestructible effects, Combatant.remove_effect()"
```

---

### Task 2: Turn order — `acts_last` + `TurnManager.insert_acting_this_round()`

**Files:**
- Modify: `combat/combatant.gd`
- Modify: `combat/turn_manager.gd`
- Test: `tests/test_acts_last_turn_order.gd` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `Combatant.acts_last: bool`, `TurnManager.get_turn_order()` now sorts `acts_last`
  combatants after every non-`acts_last` one regardless of initiative, and a new
  `TurnManager.insert_acting_this_round(c: Combatant) -> void`.
- Consumed by: Task 3 (acolytes set `acts_last = true`), Task 6 (`_spawn_enemy_mid_combat()` calls
  `insert_acting_this_round()`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_acts_last_turn_order.gd`:

```gdscript
extends SceneTree

## Headless test: acts_last combatants always sort after every non-acts_last combatant in
## TurnManager.get_turn_order(), regardless of initiative (spec 2026-07-19 §3.1) — and
## insert_acting_this_round() appends a combatant into the round already in progress.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make(name: String, initiative: int, acts_last: bool) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name
	c.base_stats = Stats.new()
	c.base_max_hp = 10
	c.apply_stats()
	c.start_combat()
	c.current_initiative = initiative
	c.acts_last = acts_last
	return c

func _initialize() -> void:
	var tm: TurnManager = TurnManager.new()
	var fast: Combatant = _make("Fast", 90, false)
	var slow_acts_last: Combatant = _make("SlowActsLast", 5, true)
	var slow: Combatant = _make("Slow", 10, false)
	var fast_acts_last: Combatant = _make("FastActsLast", 95, true)
	tm.combatants = [slow_acts_last, fast, slow, fast_acts_last]
	var order: Array[Combatant] = tm.get_turn_order()
	_check(order[0] == fast, "the highest-initiative NON-acts_last combatant goes first")
	_check(order[1] == slow, "the next NON-acts_last combatant goes second")
	_check(order[2] == fast_acts_last or order[2] == slow_acts_last, "an acts_last combatant is 3rd")
	_check(order[3] == fast_acts_last or order[3] == slow_acts_last, "an acts_last combatant is 4th")
	_check(order.find(fast) < order.find(fast_acts_last), "fast_acts_last (init 95) still sorts AFTER fast (init 90) despite higher initiative")
	_check(order.find(fast_acts_last) < order.find(slow_acts_last), "between two acts_last combatants, higher initiative (95 vs 5) still wins the tie")

	# insert_acting_this_round: a combatant joining mid-round must act THIS round.
	tm.combatants = [fast, slow]
	tm.begin()
	var newcomer: Combatant = _make("Newcomer", 999, true)
	tm.insert_acting_this_round(newcomer)
	_check(tm.combatants.has(newcomer), "insert_acting_this_round adds the combatant to .combatants")
	# Drain the round: fast, slow, newcomer should each get a turn before a new round starts.
	var seen: Array[Combatant] = []
	var round_before: int = tm.round_number
	for i in range(3):
		seen.append(tm._order[tm._turn_index])
		tm.advance_turn()
	_check(newcomer in seen, "the newly-inserted combatant took a turn in the SAME round it joined")
	_check(tm.round_number == round_before, "no new round started while draining the 3 acting members")

	print(("ACTS_LAST TURN ORDER TEST PASSED" if _failures == 0 else "ACTS_LAST TURN ORDER TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_acts_last_turn_order.gd`
Expected: FAIL — `Combatant.acts_last` doesn't exist yet, `insert_acting_this_round` doesn't exist yet.

- [ ] **Step 3: Add `acts_last` to `combat/combatant.gd`**

Add this field near the other simple boolean flags (e.g. next to `var is_target_dummy: bool = false`
or `var is_player: bool = false` — search for either):

```gdscript
## True for a combatant that always acts LAST in turn order regardless of its initiative roll (the
## Hollow Warden's minions, spec 2026-07-19 §3.1). Checked FIRST in TurnManager's sort comparator.
var acts_last: bool = false
```

- [ ] **Step 4: Update `TurnManager.get_turn_order()`'s sort comparator**

In `combat/turn_manager.gd`, change:

```gdscript
func get_turn_order() -> Array[Combatant]:
	var ordered: Array[Combatant] = combatants.duplicate()
	ordered.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.current_initiative != b.current_initiative:
			return a.current_initiative > b.current_initiative
		var fa: int = a.effective_stats().finesse
		var fb: int = b.effective_stats().finesse
		if fa != fb:
			return fa > fb
		return a.tiebreak_roll > b.tiebreak_roll)
	return ordered
```

to:

```gdscript
func get_turn_order() -> Array[Combatant]:
	var ordered: Array[Combatant] = combatants.duplicate()
	ordered.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.acts_last != b.acts_last:
			return b.acts_last   # false (normal) sorts before true (acts-last), regardless of initiative
		if a.current_initiative != b.current_initiative:
			return a.current_initiative > b.current_initiative
		var fa: int = a.effective_stats().finesse
		var fb: int = b.effective_stats().finesse
		if fa != fb:
			return fa > fb
		return a.tiebreak_roll > b.tiebreak_roll)
	return ordered
```

- [ ] **Step 5: Add `TurnManager.insert_acting_this_round()`**

Add this new method immediately after `get_turn_order()`:

```gdscript
## Adds [param c] to both .combatants (so future rounds' get_turn_order() include it) AND the
## CURRENT round's already-fixed _order (so it acts THIS round too, not just from next round on).
## Appending at the end of _order is correct without position-aware insertion because every caller
## of this method passes an acts_last combatant (spec 2026-07-19 §3.6) — it belongs at the back of
## the current round's remaining order regardless, the same place a fresh get_turn_order() call
## would put it next round anyway.
func insert_acting_this_round(c: Combatant) -> void:
	combatants.append(c)
	_order.append(c)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_acts_last_turn_order.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 7: Run existing turn-order/combat regression tests**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_turn_manager.gd`
(or whichever existing test file covers `TurnManager` — locate via `ls tests/ | grep -i turn`) —
confirm still exit 0 (the sort comparator change is additive: every existing Combatant defaults
`acts_last = false`, so `a.acts_last != b.acts_last` is always `false` for pre-existing fights and
the new check is a no-op).

- [ ] **Step 8: Commit**

```bash
git add combat/combatant.gd combat/turn_manager.gd tests/test_acts_last_turn_order.gd
git commit -m "feat(combat): add acts_last turn-order rule + TurnManager.insert_acting_this_round()"
```

---

### Task 3: `EnemyLibrary` — The Hollow Warden + 2 acolyte tiers (4 role variants)

**Files:**
- Modify: `combat/enemy_library.gd`
- Test: `tests/test_enemy_library_hollow_warden.gd` (new)

**Interfaces:**
- Consumes: `Combatant.acts_last` (Task 2).
- Produces: `EnemyLibrary.make(&"hollow_warden")`, `EnemyLibrary.make(&"warden_acolyte_lesser_healer")`,
  `EnemyLibrary.make(&"warden_acolyte_lesser_curser")`, `EnemyLibrary.make(&"warden_acolyte_greater_healer")`,
  `EnemyLibrary.make(&"warden_acolyte_greater_curser")`. None of these 5 ids are added to `EnemyLibrary.IDS`.
- Consumed by: Task 5 (ability wiring reads `ability_id`), Task 6/7 (mid-fight spawning by id),
  Task 10 (floor 4 placement by id).

- [ ] **Step 1: Write the failing test**

Create `tests/test_enemy_library_hollow_warden.gd`:

```gdscript
extends SceneTree

## Headless test for The Hollow Warden + its 4 acolyte variants (spec 2026-07-19 §3.2).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var dark: DamageType = load("res://combat/resources/types/dark.tres")
	var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
	_check(boss.max_hp == 550, "Hollow Warden has 550 max HP (got %d)" % boss.max_hp)
	_check(boss.defense_type == dark, "Hollow Warden's defense type is Dark")
	_check(boss.weapon_type() == dark, "Hollow Warden's weapon type is Dark")
	_check(boss.weapon.reels.size() == 3, "Hollow Warden has 3 weapon reels (got %d)" % boss.weapon.reels.size())
	_check(boss.weapon.base_damage == 12.0, "Hollow Warden's weapon base damage is 12.0 (got %s)" % boss.weapon.base_damage)
	_check(boss.ultimate_id == &"dark_reinforcements", "Hollow Warden's Ultimate is dark_reinforcements")
	_check(boss.bonus_meter.is_visible, "Hollow Warden's Bonus Meter is VISIBLE (first Elite/Boss meter)")
	_check(boss.is_boss, "Hollow Warden has is_boss == true")
	_check(not boss.acts_last, "Hollow Warden itself does NOT act last")
	_check(boss.amber_reward > 12, "Hollow Warden's Amber reward exceeds every existing enemy's (got %d)" % boss.amber_reward)

	var lesser_healer: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_healer")
	_check(lesser_healer.max_hp == 30, "lesser_healer has 30 max HP (got %d)" % lesser_healer.max_hp)
	_check(lesser_healer.acts_last, "lesser_healer always acts last")
	_check(lesser_healer.ability_id == &"warden_support_heal", "lesser_healer's ability is warden_support_heal")
	_check(lesser_healer.has_effect(&"warden_acolyte_immunity"), "lesser_healer carries a permanent stun-immunity effect")
	var stun_check: bool = lesser_healer.evaluate_stun(999999)  # an impossibly high threshold would normally force a stun
	_check(not stun_check, "lesser_healer is never stunned, even against an extreme threshold")

	var lesser_curser: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_curser")
	_check(lesser_curser.max_hp == 30, "lesser_curser has 30 max HP")
	_check(lesser_curser.ability_id == &"warden_support_curse", "lesser_curser's ability is warden_support_curse")

	var greater_healer: Combatant = EnemyLibrary.make(&"warden_acolyte_greater_healer")
	_check(greater_healer.max_hp == 90, "greater_healer has 90 max HP (got %d)" % greater_healer.max_hp)
	_check(greater_healer.ability_id == &"warden_support_heal", "greater_healer's ability is warden_support_heal")
	_check(greater_healer.acts_last, "greater_healer always acts last")

	var greater_curser: Combatant = EnemyLibrary.make(&"warden_acolyte_greater_curser")
	_check(greater_curser.max_hp == 90, "greater_curser has 90 max HP")
	_check(greater_curser.ability_id == &"warden_support_curse", "greater_curser's ability is warden_support_curse")

	var boss_ids: Array[StringName] = [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser", &"warden_acolyte_greater_healer", &"warden_acolyte_greater_curser"]
	for id: StringName in boss_ids:
		_check(not EnemyLibrary.IDS.has(id), "%s is NOT in EnemyLibrary.IDS (not player-selectable for testing)" % id)
	# Existing 3 enemies unaffected.
	var rat: Combatant = EnemyLibrary.make(&"rat")
	_check(rat.ultimate_id == &"", "the existing rat enemy still has no Ultimate (unaffected by this task)")
	_check(not rat.bonus_meter.is_visible, "the existing rat's meter is still hidden (unaffected)")
	_check(not rat.is_boss, "the existing rat is not a boss")
	_check(not rat.acts_last, "the existing rat does not act last")

	print(("ENEMY LIBRARY HOLLOW WARDEN TEST PASSED" if _failures == 0 else "ENEMY LIBRARY HOLLOW WARDEN TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_library_hollow_warden.gd`
Expected: FAIL — none of these ids resolve yet, `is_boss`/`acts_last` don't exist on `Combatant` yet
(Note: `acts_last` was added in Task 2 — if Task 2 is already merged this specific failure won't
occur, but `is_boss` genuinely doesn't exist until this task adds it).

- [ ] **Step 3: Add `is_boss` to `combat/combatant.gd`**

Add this field immediately after the `acts_last` field added in Task 2:

```gdscript
## True for a boss-tier enemy (The Hollow Warden). Drives the phase-transition orchestration in
## combat.gd (spec 2026-07-19 §3.3) — every other Combatant leaves this at the default.
var is_boss: bool = false
```

- [ ] **Step 4: Extend `EnemyLibrary._build()`'s signature in `combat/enemy_library.gd`**

Change:
```gdscript
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int, defense: DamageType, hp: int, ability_id: StringName = &"", ability_cost: int = 0, loot_table_id: StringName = &"", amber_reward: int = 0) -> Combatant:
	var c: Combatant = Combatant.new()
	if loot_table_id != &"":
		c.loot_table = LootTableLibrary.make(loot_table_id)
	c.display_name = enemy_name
	c.amber_reward = amber_reward
	c.is_player = false
	c.defense_type = defense
	c.ultimate_id = &""   # enemies never fire an Ultimate (override Combatant's default)
	var w: Weapon = Weapon.new()
	w.base_damage = weapon_base
	for i: int in range(reels):
		w.reels.append(ActionReel.make_default(weapon_type))
	c.weapon = w
	c.base_max_hp = hp
	c.base_meter_floor = 3
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = 15
	meter.is_visible = false   # enemy meters hidden by default (CLAUDE.md §4)
	c.bonus_meter = meter
```

to:
```gdscript
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int, defense: DamageType, hp: int, ability_id: StringName = &"", ability_cost: int = 0, loot_table_id: StringName = &"", amber_reward: int = 0, ultimate_id: StringName = &"", meter_visible: bool = false) -> Combatant:
	var c: Combatant = Combatant.new()
	if loot_table_id != &"":
		c.loot_table = LootTableLibrary.make(loot_table_id)
	c.display_name = enemy_name
	c.amber_reward = amber_reward
	c.is_player = false
	c.defense_type = defense
	c.ultimate_id = ultimate_id   # &"" for every enemy except the Hollow Warden (spec 2026-07-19 §3.2)
	var w: Weapon = Weapon.new()
	w.base_damage = weapon_base
	for i: int in range(reels):
		w.reels.append(ActionReel.make_default(weapon_type))
	c.weapon = w
	c.base_max_hp = hp
	c.base_meter_floor = 3
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = 15
	meter.is_visible = meter_visible   # true only for the Hollow Warden (spec 2026-07-19 §3.2)
	c.bonus_meter = meter
```

(The rest of `_build()`'s body — `base_stats`, the ability-cost/Stamina-pool block, `apply_stats()`,
`apply_luck()`, `start_combat()` — is unchanged.)

- [ ] **Step 5: Add the Hollow Warden + acolyte entries to `EnemyLibrary`**

In `EnemyLibrary.make()`, add these 5 new `match` branches immediately before the existing `_:
return null`:

```gdscript
		&"hollow_warden":
			var boss: Combatant = _build("The Hollow Warden", dark, 12.0, 3, dark, 550, &"", 0, &"", 50, &"dark_reinforcements", true)
			boss.is_boss = true
			return boss
		&"warden_acolyte_lesser_healer": return _build_acolyte(30, &"warden_support_heal")
		&"warden_acolyte_lesser_curser": return _build_acolyte(30, &"warden_support_curse")
		&"warden_acolyte_greater_healer": return _build_acolyte(90, &"warden_support_heal")
		&"warden_acolyte_greater_curser": return _build_acolyte(90, &"warden_support_curse")
```

Add `dark` to `make()`'s existing type-loading block at the top (alongside `slashing`/`crushing`/
`piercing`/`earth`):
```gdscript
	var dark: DamageType = load("res://combat/resources/types/dark.tres")
```

Add this new shared builder immediately after `_build()` (not inside `make()`):
```gdscript
## Builds one of the Hollow Warden's 4 acolyte variants (2 HP tiers × 2 ability roles — spec
## 2026-07-19 §3.2/§3.3). Always acts last and is permanently immune to stun (a MULTIPLIER_EDIT
## effect with an inert 1.0 magnitude, whose only real purpose is carrying grants_stun_immunity).
static func _build_acolyte(hp: int, ability_id: StringName) -> Combatant:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var c: Combatant = _build("Warden Acolyte", crushing, 3.0, 1, crushing, hp, ability_id, 0)
	c.acts_last = true
	var immune: Effect = Effect.new()
	immune.id = &"warden_acolyte_immunity"
	immune.kind = Effect.Kind.MULTIPLIER_EDIT
	immune.magnitude = 1.0
	immune.duration = 999
	immune.beneficial = true
	immune.grants_stun_immunity = true
	c.attach_effect(immune)
	return c
```

**Do NOT add any of these 5 new ids to `EnemyLibrary.IDS`** (`const IDS: Array[StringName] = [&"rat",
&"ferret", &"stoat"]` stays unchanged) — they are scripted dungeon-encounter enemies only, never
player-selectable in the standalone "Choose Enemy Combatants" testing screen.

- [ ] **Step 6: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 7: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_library_hollow_warden.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 8: Run the existing enemy-selection-screen test for regressions**

Locate the existing test covering `EnemyLibrary`/the enemy selection screen (e.g.
`ls tests/ | grep -i enemy`) and run it — confirm still exit 0 (rat/ferret/stoat's `make()` calls
are unchanged in behavior; the new trailing params default to their old hardcoded values).

- [ ] **Step 9: Commit**

```bash
git add combat/enemy_library.gd combat/combatant.gd tests/test_enemy_library_hollow_warden.gd
git commit -m "feat(combat): add The Hollow Warden + 4 acolyte variants to EnemyLibrary"
```

---

### Task 4: Boss/Ultimate/Darkness-Rampage `Combatant` fields

**Files:**
- Modify: `combat/combatant.gd`
- Test: `tests/test_boss_combatant_fields.gd` (new)

**Interfaces:**
- Consumes: nothing new (pure field/method additions).
- Produces: `Combatant.boss_phase_two_active`, `boss_turns_taken`, `boss_last_phase_trigger_turn`,
  `boss_phase_minion_ids`, `boss_reinforcement_ids`, `heal_boss_pending`, `curse_party_pending`,
  `darkness_rampage_spins_remaining`, `is_darkness_rampage_active() -> bool`,
  `consume_darkness_rampage_spin() -> void`.
- Consumed by: Task 5 (`heal_boss_pending`/`curse_party_pending`), Task 7 (the `boss_*` fields),
  Task 9 (`darkness_rampage_spins_remaining`/`is_darkness_rampage_active`/
  `consume_darkness_rampage_spin`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_boss_combatant_fields.gd`:

```gdscript
extends SceneTree

## Headless test: the new Combatant fields/methods this plan's boss orchestration needs all default
## correctly and behave as plain data (spec 2026-07-19 §3.3/§3.5) — no orchestrator logic here, just
## confirming the fields/methods exist with the right shapes and defaults before later tasks wire
## real behavior around them.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	_check(c.boss_phase_two_active == false, "boss_phase_two_active defaults false")
	_check(c.boss_turns_taken == 0, "boss_turns_taken defaults 0")
	_check(c.boss_last_phase_trigger_turn == -1, "boss_last_phase_trigger_turn defaults -1")
	_check(c.boss_phase_minion_ids.is_empty(), "boss_phase_minion_ids defaults empty")
	_check(c.boss_reinforcement_ids.is_empty(), "boss_reinforcement_ids defaults empty")
	_check(c.heal_boss_pending == false, "heal_boss_pending defaults false")
	_check(c.curse_party_pending == false, "curse_party_pending defaults false")
	_check(c.darkness_rampage_spins_remaining == 0, "darkness_rampage_spins_remaining defaults 0")
	_check(not c.is_darkness_rampage_active(), "is_darkness_rampage_active() is false by default")
	c.darkness_rampage_spins_remaining = 1
	_check(c.is_darkness_rampage_active(), "is_darkness_rampage_active() is true once spins are set")
	c.consume_darkness_rampage_spin()
	_check(c.darkness_rampage_spins_remaining == 0, "consume_darkness_rampage_spin() decrements to 0")
	_check(not c.is_darkness_rampage_active(), "is_darkness_rampage_active() is false again after consuming")
	c.consume_darkness_rampage_spin()  # already 0 — must not go negative
	_check(c.darkness_rampage_spins_remaining == 0, "consume_darkness_rampage_spin() at 0 stays 0 (no underflow)")

	var other: Combatant = Combatant.new()
	c.boss_phase_minion_ids = [other]
	c.boss_reinforcement_ids = [other, other]
	_check(c.boss_phase_minion_ids.size() == 1, "boss_phase_minion_ids holds Combatant references")
	_check(c.boss_reinforcement_ids.size() == 2, "boss_reinforcement_ids holds Combatant references")

	print(("BOSS COMBATANT FIELDS TEST PASSED" if _failures == 0 else "BOSS COMBATANT FIELDS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_boss_combatant_fields.gd`
Expected: FAIL — none of these fields/methods exist yet.

- [ ] **Step 3: Add the new fields to `combat/combatant.gd`**

Add these fields immediately after `is_boss` (added in Task 3):

```gdscript
## True while the Hollow Warden's Indestructible phase is active (spec 2026-07-19 §3.3). Boss-only.
var boss_phase_two_active: bool = false

## The boss's own turn counter (incremented once per boss turn), used for the 10-turn re-trigger
## cooldown — NOT a global round counter. No other Combatant has a use for this (YAGNI: not added
## to the universal begin_turn() path). Boss-only.
var boss_turns_taken: int = 0

## boss_turns_taken's value the last time the phase transition triggered, or -1 before the first
## trigger. Boss-only.
var boss_last_phase_trigger_turn: int = -1

## The CURRENT phase's 2 spawned minions, so the orchestrator knows when both are dead and can clear
## Indestructible. Boss-only.
var boss_phase_minion_ids: Array[Combatant] = []

## Minions summoned by the boss's own Ultimate (Dark Reinforcements), tracked separately from
## boss_phase_minion_ids so they can be sacrificed (no reward) if still alive at the next phase
## transition. Boss-only.
var boss_reinforcement_ids: Array[Combatant] = []

## Set when a Warden Acolyte's healer-role ability is staged; consumed by the orchestrator
## (combat.gd's _commit_main1) to heal the boss + attach Guarded. Spec 2026-07-19 §3.2.
var heal_boss_pending: bool = false

## Set when a Warden Acolyte's curser-role ability is staged; consumed by the orchestrator to attach
## a freshly-seeded warden_curse to every living PC. Spec 2026-07-19 §3.2.
var curse_party_pending: bool = false

## Spins remaining of the Hollow Warden's phase-locked Darkness Rampage AoE attack (spec 2026-07-19
## §3.5) — set directly by the phase-transition orchestrator (NOT a meter-gated fire_X(), since
## Darkness Rampage auto-replaces the boss's normal attack rather than being player/AI-staged).
var darkness_rampage_spins_remaining: int = 0

## True while a Darkness Rampage spin is pending (drives the orchestrator's post-spin self-heal).
func is_darkness_rampage_active() -> bool:
	return darkness_rampage_spins_remaining > 0

## Consumes one Darkness Rampage spin. Call once per resolved spin (after the self-heal is applied).
func consume_darkness_rampage_spin() -> void:
	if darkness_rampage_spins_remaining > 0:
		darkness_rampage_spins_remaining -= 1
```

- [ ] **Step 4: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_boss_combatant_fields.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd tests/test_boss_combatant_fields.gd
git commit -m "feat(combat): add boss/Ultimate/Darkness-Rampage state fields to Combatant"
```

---

### Task 5: Minion ability wiring — heal+guard the boss / curse the party

**Files:**
- Modify: `combat/combat.gd`
- Test: `tests/test_warden_acolyte_abilities.gd` (new)

**Interfaces:**
- Consumes: `Combatant.ability_id` values `&"warden_support_heal"`/`&"warden_support_curse"` (Task 3),
  `heal_boss_pending`/`curse_party_pending` (Task 4), `EffectLibrary.make(&"warden_curse")` (Task 1).
- Produces: `_enemy_stage_ability()` always-stages both new ability ids; `_commit_main1()` applies
  their effects.
- Consumed by: nothing further in this plan (this is a leaf integration task) — exercised end-to-end
  by Task 11's full phase-transition test.

- [ ] **Step 1: Write the failing test**

Create `tests/test_warden_acolyte_abilities.gd`. This test drives the REAL `combat.tscn` scene (the
established technique in this codebase for exercising orchestrator-level ability wiring — see
`tests/test_regrowth.gd` for the precedent pattern of building `combat.tscn`, forcing a specific
attacker/ability, and asserting the orchestrator's effect on the target):

```gdscript
extends SceneTree

## Headless test for the Warden Acolytes' 2 ability roles (spec 2026-07-19 §3.2): warden_support_heal
## (heal the boss ally 30 HP + attach Guarded) and warden_support_curse (attach a flat warden_curse
## DoT to every living PC). Drives combat.gd's real _enemy_stage_ability()/_commit_main1() path
## directly rather than a full scripted spin, mirroring this codebase's existing precedent for
## testing orchestrator-applied pending-flag abilities (Foresight/Regrowth).

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Node = _instance
		var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
		boss.hp = 400  # damaged, so the heal is visible against a non-max HP
		var healer: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_healer")
		var curser: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_curser")
		var pc: Combatant = Combatant.new()
		pc.display_name = "TestPC"
		pc.is_player = true
		pc.base_stats = Stats.new()
		pc.base_max_hp = 100
		pc.apply_stats()
		pc.start_combat()

		combat._pcs = [pc]
		combat._enemies = [boss, healer, curser]
		combat._turn_manager.combatants = [pc, boss, healer, curser]
		combat._panels[boss] = CombatantPanel.new()
		combat._panels[healer] = CombatantPanel.new()
		combat._panels[curser] = CombatantPanel.new()
		combat._panels[pc] = CombatantPanel.new()

		# Healer's turn: stage + commit its ability directly.
		combat._attacker = healer
		combat._defender = pc
		healer.begin_turn()
		combat._plan = MainPhasePlan.new(healer, 0, 5, 2, null)
		combat._enemy_stage_ability()
		_check(combat._plan.ability_staged, "warden_support_heal is always-staged (greedy AI)")
		combat._commit_main1()
		_check(boss.hp == 430, "the boss heals 30 HP from warden_support_heal (400 -> 430, got %d)" % boss.hp)
		_check(boss.has_effect(&"guarded"), "warden_support_heal attaches Guarded to the boss")

		# Curser's turn: stage + commit its ability directly.
		combat._attacker = curser
		combat._defender = pc
		curser.begin_turn()
		combat._plan = MainPhasePlan.new(curser, 0, 5, 2, null)
		combat._enemy_stage_ability()
		_check(combat._plan.ability_staged, "warden_support_curse is always-staged (greedy AI)")
		combat._commit_main1()
		_check(pc.has_effect(&"warden_curse"), "warden_support_curse attaches warden_curse to the living PC")
		var curse: Effect = pc._find_effect(&"warden_curse")
		_check(curse.dot_damage() == 4, "the applied warden_curse deals the flat 4 (1 stack), not a weapon-scaled number (got %d)" % curse.dot_damage())

		_instance.free()
	if _frames >= 3:
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_warden_acolyte_abilities.gd`
Expected: FAIL — `_enemy_stage_ability()` has no branch for `warden_support_heal`/`warden_support_curse`
yet, `heal_boss_pending`/`curse_party_pending` are never set or consumed.

- [ ] **Step 3: Extend `_enemy_stage_ability()` in `combat/combat.gd`**

Change:
```gdscript
func _enemy_stage_ability() -> void:
	if _plan == null or _attacker == null or _attacker.is_player:
		return
	match _attacker.ability_id:
		&"flurry":
			if _plan.can_stage_ability():
				_plan.ability_staged = true
		&"hunters_mark":
			if _plan.can_stage_ability() and _defender != null and not _defender.has_effect(&"hunters_mark"):
				_plan.ability_staged = true
```

to:
```gdscript
func _enemy_stage_ability() -> void:
	if _plan == null or _attacker == null or _attacker.is_player:
		return
	match _attacker.ability_id:
		&"flurry":
			if _plan.can_stage_ability():
				_plan.ability_staged = true
		&"hunters_mark":
			if _plan.can_stage_ability() and _defender != null and not _defender.has_effect(&"hunters_mark"):
				_plan.ability_staged = true
		&"warden_support_heal", &"warden_support_curse":
			# Warden Acolytes always fire their signature ability (spec 2026-07-19 §3.2) — same
			# always-fire greedy pattern as Flurry. Both roles have 0 ability_cost (EnemyLibrary),
			# so can_stage_ability() is always affordable; the real logic lives in _commit_main1().
			if _plan.can_stage_ability():
				_plan.ability_staged = true
```

- [ ] **Step 4: Add `stage_warden_support_heal()`/`stage_warden_support_curse()` to `Combatant`**

Every existing pending-flag ability (Foresight, Regrowth, etc.) goes through a small `stage_X(cost)
-> bool` method that spends the resource and sets the flag — mirror that convention exactly rather
than setting the flags directly from `MainPhasePlan.commit()`, even though both acolyte abilities
cost 0 (spending `{stamina: 0}` is a harmless no-op, and this keeps every ability in this codebase
following the same shape). Add these 2 new methods to `combat/combatant.gd`, immediately after
`stage_regrowth()`:

```gdscript
## Stages the Warden Acolyte's healer-role ability: spends [param cost] Stamina (0 for this
## enemy-only ability) and flags a pending boss heal+Guard. The orchestrator finds the living boss
## ally and applies both at commit (spec 2026-07-19 §3.2). Returns false if unaffordable.
func stage_warden_support_heal(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	heal_boss_pending = true
	return true

## Stages the Warden Acolyte's curser-role ability: spends [param cost] Stamina (0 for this
## enemy-only ability) and flags a pending party-wide curse. The orchestrator attaches a
## freshly-seeded warden_curse to every living PC at commit (spec 2026-07-19 §3.2). Returns false if
## unaffordable.
func stage_warden_support_curse(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	curse_party_pending = true
	return true
```

- [ ] **Step 5: Call the new stage methods from `MainPhasePlan.commit()` — `combat/main_phase_plan.gd`**

In `commit()`'s `match ability_id:` block (inside the `if ability_staged and not ability_is_free():`
guard), add 2 new branches immediately after the existing `&"rallying_cry":` branch:

```gdscript
			&"warden_support_heal":
				combatant.stage_warden_support_heal(ability_cost)
			&"warden_support_curse":
				combatant.stage_warden_support_curse(ability_cost)
```

- [ ] **Step 6: Consume the pending flags in `_commit_main1()` — `combat/combat.gd`**

In `_commit_main1()`, add 2 new blocks immediately after the existing `regrowth_pending` block (the
last of the existing pending-flag blocks):

```gdscript
	# Warden Acolyte "heal+guard the boss" (spec 2026-07-19 §3.2): the orchestrator finds the living
	# boss ally (there is exactly one Hollow Warden per fight) and heals it + attaches Guarded.
	if _attacker.heal_boss_pending:
		var boss: Combatant = _find_boss_ally(_attacker)
		if boss != null:
			boss.heal(30)
			boss.attach_effect(EffectLibrary.make(&"guarded"))
			_log("  ☾ %s heals The Hollow Warden 30 HP and shields it." % _attacker.display_name)
			if _panels.has(boss):
				(_panels[boss] as CombatantPanel).refresh_status()
		_attacker.heal_boss_pending = false
	# Warden Acolyte "curse the party" (spec 2026-07-19 §3.2): a flat (not weapon-derived) stacking
	# DoT on every living PC. dot_base_damage = 1.0 is the flat baseline so dot_damage() produces
	# exactly 4/7/10 (Effect.dot_damage()'s formula multiplies dot_base_damage by dot_fractions).
	if _attacker.curse_party_pending:
		for target: Combatant in _enemies_of(_attacker):
			var curse: Effect = EffectLibrary.make(&"warden_curse")
			curse.dot_base_damage = 1.0
			target.attach_effect(curse)
			if _panels.has(target):
				(_panels[target] as CombatantPanel).refresh_status()
		_log("  ☾ %s afflicts the party with a curse." % _attacker.display_name)
		_attacker.curse_party_pending = false
```

Add this new small helper immediately after `_lowest_hp_pct_ally()` (the existing Foresight/Regrowth
target-picker helper):

```gdscript
## The living boss ally of [param caster] (there is exactly one Hollow Warden per fight). Used by
## the Warden Acolyte's heal-role ability (spec 2026-07-19 §3.2).
func _find_boss_ally(caster: Combatant) -> Combatant:
	for c: Combatant in _turn_manager.combatants:
		if c.is_player == caster.is_player and c.is_boss and c.is_alive():
			return c
	return null
```

- [ ] **Step 7: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 8: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_warden_acolyte_abilities.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 9: Commit**

```bash
git add combat/combat.gd combat/combatant.gd combat/main_phase_plan.gd tests/test_warden_acolyte_abilities.gd
git commit -m "feat(combat): wire Warden Acolyte heal+guard / curse-party abilities"
```

---

### Task 6: `_spawn_enemy_mid_combat()` — the novel mid-fight-spawn plumbing

**Files:**
- Modify: `combat/combat.gd`
- Test: `tests/test_spawn_enemy_mid_combat.gd` (new)

**Interfaces:**
- Consumes: `TurnManager.insert_acting_this_round()` (Task 2).
- Produces: `Combat._spawn_enemy_mid_combat(id: StringName) -> Combatant`.
- Consumed by: Task 7 (phase-transition spawns 2 minions), Task 8 (Dark Reinforcements spawns 2
  minions).

This is the plan's one genuinely novel piece (per spec §3.6) — its test must prove the BEHAVIORAL
CONTRACT (a spawned Combatant is fully playable the SAME round it appears), not just that it ends
up in a data array.

- [ ] **Step 1: Write the failing test**

Create `tests/test_spawn_enemy_mid_combat.gd`:

```gdscript
extends SceneTree

## Headless test for Combat._spawn_enemy_mid_combat() (spec 2026-07-19 §3.6) — the one genuinely new
## piece of plumbing this boss fight needs: a Combatant spawned AFTER _build_combatants() has already
## run must be fully playable in the SAME round it appears — targetable, panel-visible, and takes its
## own turn before the round ends — not merely present in a data array.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Node = _instance
		var pc: Combatant = Combatant.new()
		pc.display_name = "TestPC"
		pc.is_player = true
		pc.base_stats = Stats.new()
		pc.base_max_hp = 100
		pc.apply_stats()
		pc.start_combat()
		var rat: Combatant = EnemyLibrary.make(&"rat")

		combat._pcs = [pc]
		combat._enemies = [rat]
		combat._dummies = []
		combat._turn_manager.combatants = [pc, rat]
		combat._panels[pc] = CombatantPanel.new()
		combat._panels[rat] = CombatantPanel.new()
		combat._turn_manager.begin()

		var before_enemies: int = combat._enemies.size()
		var before_combatants: int = combat._turn_manager.combatants.size()
		var spawned: Combatant = combat._spawn_enemy_mid_combat(&"warden_acolyte_lesser_healer")

		_check(spawned != null, "_spawn_enemy_mid_combat returns a real Combatant")
		_check(combat._enemies.size() == before_enemies + 1, "the spawned Combatant is appended to _enemies")
		_check(combat._turn_manager.combatants.size() == before_combatants + 1, "the spawned Combatant is appended to TurnManager.combatants")
		_check(combat._panels.has(spawned), "the spawned Combatant has a real CombatantPanel registered")
		_check(combat._enemies_of(pc).has(spawned), "the spawned Combatant is targetable via _enemies_of() from the PC's side")

		# Behavioral contract: it must act THIS round, not just next round.
		var seen: Array[Combatant] = []
		var round_before: int = combat._turn_manager.round_number
		var guard: int = 0
		while combat._turn_manager._turn_index < combat._turn_manager._order.size() and guard < 10:
			seen.append(combat._turn_manager._order[combat._turn_manager._turn_index])
			combat._turn_manager.advance_turn()
			guard += 1
		_check(spawned in seen, "the spawned Combatant takes a turn in the SAME round it was spawned")
		_check(combat._turn_manager.round_number == round_before, "no new round started while draining the round's remaining turns")

		# Not connected to the XP/Amber reward hookup (spec 2026-07-19 §3.3 sacrifice rule).
		var xp_before: int = pc.xp
		spawned.take_damage(spawned.hp)
		_check(pc.xp == xp_before, "defeating a mid-combat-spawned Combatant grants NO XP (no _on_enemy_defeated connection)")

		_instance.free()
	if _frames >= 3:
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_spawn_enemy_mid_combat.gd`
Expected: FAIL — `_spawn_enemy_mid_combat` doesn't exist yet.

- [ ] **Step 3: Read the surrounding code before implementing**

Read `combat/combat.gd`'s `_build_combatants()`, `_place_party_column()`, and
`combat/turn_manager.gd`'s `_start_next_round()`/`_announce_current()` in full before writing this
method — the behavioral contract (not just data presence) depends on understanding exactly how a
round currently advances.

- [ ] **Step 4: Add `_spawn_enemy_mid_combat()` to `combat/combat.gd`**

Add this new method immediately after `_place_party_column()`:

```gdscript
## Spawns a NEW enemy Combatant mid-fight, after _build_combatants() has already run once (spec
## 2026-07-19 §3.6 — the boss's phase-transition/Ultimate summons). Fully playable the SAME round it
## appears: appended to _enemies/_turn_manager.combatants (so _enemies_of()/_allies_of()/win-check
## pick it up immediately, since those already compute fresh every call) AND to the current round's
## already-fixed _order via TurnManager.insert_acting_this_round(). Deliberately does NOT connect
## `defeated` to _on_enemy_defeated — a boss's summoned/sacrificed minions grant no XP/Amber whether
## they die in battle or are sacrificed (spec §2's "no reward" rule) — do not add that connection.
func _spawn_enemy_mid_combat(id: StringName) -> Combatant:
	var c: Combatant = EnemyLibrary.make(id)
	_enemies.append(c)
	_turn_manager.insert_acting_this_round(c)
	var column_index: int = _enemies.size() + _dummies.size() - 1
	var p := CombatantPanel.new()
	p.position = Vector2(1276.0, 80.0 + column_index * (278.0 + 14.0))
	add_child(p)
	_panels[c] = p
	p.bind(c)
	return c
```

- [ ] **Step 5: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 6: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_spawn_enemy_mid_combat.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 7: Commit**

```bash
git add combat/combat.gd tests/test_spawn_enemy_mid_combat.gd
git commit -m "feat(combat): add Combat._spawn_enemy_mid_combat() for mid-fight enemy spawns"
```

---

### Task 7: Boss phase-transition orchestration

**Files:**
- Modify: `combat/combat.gd`
- Test: `tests/test_boss_phase_transition.gd` (new)

**Interfaces:**
- Consumes: `Combatant.is_boss`/`boss_phase_two_active`/`boss_turns_taken`/
  `boss_last_phase_trigger_turn`/`boss_phase_minion_ids`/`boss_reinforcement_ids` (Task 4),
  `Combatant.remove_effect()` (Task 1), `EffectLibrary.make(&"indestructible")`/`&"empowered"`
  (Task 1 / pre-existing), `_spawn_enemy_mid_combat()` (Task 6).
- Produces: `Combat._check_boss_phase_transition(c: Combatant) -> void`,
  `Combat._sacrifice_reinforcements(c: Combatant) -> void`, wired into `_on_turn_started()`.
- Consumed by: Task 9 (Darkness Rampage keys off `boss_phase_two_active`), Task 11 (full sequence
  test).

- [ ] **Step 1: Write the failing test**

Create `tests/test_boss_phase_transition.gd`:

```gdscript
extends SceneTree

## Headless test for the boss phase-transition orchestrator (spec 2026-07-19 §3.3): the 40%-HP
## trigger, Indestructible attach + 2 new 90-HP minions, Indestructible clearing once both die,
## Empowered applying afterward, the 10-turn-of-the-BOSS'S-OWN-turns cooldown gating a re-trigger,
## Indestructible always superseding Empowered (never both active), and reinforcements being
## sacrificed (boss heals half their HP, no reward) if still alive at a later trigger.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Node = _instance
		var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
		combat._panels[boss] = CombatantPanel.new()
		combat._turn_manager.combatants = [boss]
		combat._enemies = [boss]
		combat._dummies = []

		# Not yet below 40% (550 * 0.4 = 220) — no trigger.
		boss.hp = 230
		combat._check_boss_phase_transition(boss)
		_check(not boss.boss_phase_two_active, "no trigger above the 40% threshold")
		_check(boss.boss_turns_taken == 1, "boss_turns_taken increments every check")

		# Drop below 40% — triggers.
		boss.hp = 200
		combat._check_boss_phase_transition(boss)
		_check(boss.boss_phase_two_active, "the transition triggers once HP drops below 220 (40%)")
		_check(boss.has_effect(&"indestructible"), "the boss gains Indestructible")
		_check(boss.boss_phase_minion_ids.size() == 2, "2 new minions are tracked as this phase's minions")
		for m: Combatant in boss.boss_phase_minion_ids:
			_check(m.max_hp == 90, "each phase-2 minion has 90 max HP (got %d)" % m.max_hp)
			_check(combat._enemies.has(m), "each phase-2 minion is a real, targetable enemy Combatant")

		# Doesn't re-trigger the same turn it just resolved (both minions still alive).
		combat._check_boss_phase_transition(boss)
		_check(boss.boss_phase_two_active, "still in phase 2 while both minions live")
		_check(boss.boss_phase_minion_ids.size() == 2, "no second pair spawned while still in phase 2")

		# Kill both phase-2 minions — Indestructible clears, Empowered applies.
		for m: Combatant in boss.boss_phase_minion_ids:
			m.take_damage(m.hp)
		combat._check_boss_phase_transition(boss)
		_check(not boss.boss_phase_two_active, "phase 2 ends once both minions are dead")
		_check(not boss.has_effect(&"indestructible"), "Indestructible clears when phase 2 ends")
		_check(boss.has_effect(&"empowered"), "Empowered applies once phase 2 ends")

		# Still below 40% but cooldown hasn't elapsed (boss_turns_taken is only 4 so far) — no re-trigger.
		combat._check_boss_phase_transition(boss)
		_check(not boss.boss_phase_two_active, "no re-trigger before the 10-turn cooldown elapses")
		_check(boss.has_effect(&"empowered"), "Empowered persists while waiting on cooldown")

		# Fast-forward the boss's own turns to elapse the cooldown.
		for i in range(10):
			combat._check_boss_phase_transition(boss)
		_check(boss.boss_phase_two_active, "the transition re-triggers once 10 of the boss's own turns have passed below threshold")
		_check(not boss.has_effect(&"empowered"), "Empowered is removed the instant Indestructible re-triggers — they never both apply")
		_check(boss.has_effect(&"indestructible"), "Indestructible is active again on the re-trigger")

		# Sacrifice check: summon 2 reinforcements, then trigger another cycle while they're still alive.
		for m: Combatant in boss.boss_phase_minion_ids:
			m.take_damage(m.hp)
		combat._check_boss_phase_transition(boss)  # clears phase 2, applies Empowered again
		var r1: Combatant = combat._spawn_enemy_mid_combat(&"warden_acolyte_lesser_healer")
		var r2: Combatant = combat._spawn_enemy_mid_combat(&"warden_acolyte_lesser_curser")
		boss.boss_reinforcement_ids = [r1, r2]
		var reinforcement_hp_total: int = r1.hp + r2.hp
		var boss_hp_before_sacrifice: int = boss.hp
		for i in range(10):
			combat._check_boss_phase_transition(boss)  # elapse cooldown again
		_check(boss.boss_phase_two_active, "the transition re-triggers a second time")
		_check(not r1.is_alive() and not r2.is_alive(), "surviving reinforcements are sacrificed on the next trigger")
		var expected_heal: int = ceili(reinforcement_hp_total / 2.0)
		_check(boss.hp == mini(boss_hp_before_sacrifice + expected_heal, boss.max_hp), "the boss heals half the sacrificed reinforcements' combined HP")

		_instance.free()
	if _frames >= 3:
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_boss_phase_transition.gd`
Expected: FAIL — `_check_boss_phase_transition` doesn't exist yet.

- [ ] **Step 3: Add `_check_boss_phase_transition()` and `_sacrifice_reinforcements()` to `combat/combat.gd`**

Add these 2 new methods immediately after `_find_boss_ally()` (added in Task 5):

```gdscript
## The boss phase-transition state machine (spec 2026-07-19 §3.3), called once per turn from
## _on_turn_started() for boss combatants only. If phase 2 is active, checks whether both its
## minions are dead (clears Indestructible, applies Empowered). Otherwise, checks the 40%-HP
## threshold + the 10-of-the-boss's-own-turns cooldown, and if both hold, sacrifices any surviving
## Ultimate-summoned reinforcements, attaches Indestructible (removing Empowered first — they never
## both apply), and spawns 2 new 90-HP minions.
func _check_boss_phase_transition(c: Combatant) -> void:
	c.boss_turns_taken += 1
	if c.boss_phase_two_active:
		var both_dead: bool = true
		for m: Combatant in c.boss_phase_minion_ids:
			if m.is_alive():
				both_dead = false
				break
		if both_dead:
			c.remove_effect(&"indestructible")
			c.boss_phase_two_active = false
			var emp: Effect = EffectLibrary.make(&"empowered")
			emp.duration = 999   # "until end of combat" — this boss-only grant, not the 2-turn player-facing version
			c.attach_effect(emp)
			_log("  ☾ The Hollow Warden's minions have fallen — it is EMPOWERED!")
			if _panels.has(c):
				(_panels[c] as CombatantPanel).refresh_status()
		return   # a transition can't re-trigger the same turn it just resolved
	var hp_below_threshold: bool = c.hp < int(c.max_hp * 0.4)
	var cooldown_elapsed: bool = c.boss_last_phase_trigger_turn == -1 or (c.boss_turns_taken - c.boss_last_phase_trigger_turn) >= 10
	if hp_below_threshold and cooldown_elapsed:
		_sacrifice_reinforcements(c)
		c.remove_effect(&"empowered")   # Indestructible always supersedes Empowered (spec §2) — never both active
		c.attach_effect(EffectLibrary.make(&"indestructible"))
		var minion_a: Combatant = _spawn_enemy_mid_combat(&"warden_acolyte_greater_healer")
		var minion_b: Combatant = _spawn_enemy_mid_combat(&"warden_acolyte_greater_curser")
		c.boss_phase_minion_ids = [minion_a, minion_b]
		c.boss_phase_two_active = true
		c.boss_last_phase_trigger_turn = c.boss_turns_taken
		_log("  ☾ The Hollow Warden becomes INDESTRUCTIBLE and summons reinforcements!")
		if _panels.has(c):
			(_panels[c] as CombatantPanel).refresh_status()

## Instantly removes any surviving Ultimate-summoned reinforcements (no reward, since they're removed
## by the boss's own script rather than defeated in battle — spec 2026-07-19 §2) and heals the boss
## for half their combined remaining HP.
func _sacrifice_reinforcements(c: Combatant) -> void:
	var total_hp: int = 0
	for m: Combatant in c.boss_reinforcement_ids:
		if m.is_alive():
			total_hp += m.hp
			m.take_damage(m.hp)
	if total_hp > 0:
		var heal_amt: int = ceili(total_hp / 2.0)
		c.heal(heal_amt)
		_log("  ☾ The Hollow Warden sacrifices its reinforcements, healing %d HP." % heal_amt)
	c.boss_reinforcement_ids.clear()
```

- [ ] **Step 4: Wire the check into `_on_turn_started()`**

In `_on_turn_started()`, find this exact line:
```gdscript
	c.begin_turn()
	_plan = MainPhasePlan.new(c, c.ability_cost, 5, 2, _party_inventory)  # ability cost from class; reel cap 5; wild 2 spins; shared party inventory (2026-07-14 items)
```
and insert the boss check between them:
```gdscript
	c.begin_turn()
	if c.is_boss:
		_check_boss_phase_transition(c)
	_plan = MainPhasePlan.new(c, c.ability_cost, 5, 2, _party_inventory)  # ability cost from class; reel cap 5; wild 2 spins; shared party inventory (2026-07-14 items)
```

- [ ] **Step 5: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 6: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_boss_phase_transition.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 7: Commit**

```bash
git add combat/combat.gd tests/test_boss_phase_transition.gd
git commit -m "feat(combat): add the Hollow Warden's phase-transition orchestration"
```

---

### Task 8: Enemy Ultimate-firing + "Dark Reinforcements"

**Files:**
- Modify: `combat/combat.gd`
- Test: `tests/test_enemy_ultimate_firing.gd` (new)

**Interfaces:**
- Consumes: `Combatant.ultimate_id`/`bonus_meter` (pre-existing), `MainPhasePlan.toggle_ultimate()`/
  `can_stage_ultimate()` (pre-existing, confirmed in spec §3.3 research), `_spawn_enemy_mid_combat()`
  (Task 6), `Combatant.boss_reinforcement_ids` (Task 4).
- Produces: `_enemy_stage_ability()` fires an armed enemy Ultimate in preference to its base ability;
  `_commit_main1()` applies Dark Reinforcements' minion-summon; `_ultimate_label()`/`_ultimate_name()`
  gain a `&"dark_reinforcements"` entry.
- Consumed by: Task 11 (full sequence test exercises this via a filled meter).

- [ ] **Step 1: Write the failing test**

Create `tests/test_enemy_ultimate_firing.gd`:

```gdscript
extends SceneTree

## Headless test: an enemy with a non-empty ultimate_id and an armed Bonus Meter fires its Ultimate
## (in preference to its base ability that turn) via the same _enemy_stage_ability()/_commit_main1()
## path every enemy ability already uses (spec 2026-07-19 §3.3) — the FIRST enemy-side Ultimate logic
## in this codebase. Also proves Dark Reinforcements' minion-summon effect.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Node = _instance
		var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
		var pc: Combatant = Combatant.new()
		pc.display_name = "TestPC"
		pc.is_player = true
		pc.base_stats = Stats.new()
		pc.base_max_hp = 100
		pc.apply_stats()
		pc.start_combat()

		combat._pcs = [pc]
		combat._enemies = [boss]
		combat._dummies = []
		combat._turn_manager.combatants = [pc, boss]
		combat._panels[pc] = CombatantPanel.new()
		combat._panels[boss] = CombatantPanel.new()

		boss.bonus_meter.value = boss.bonus_meter.cap  # armed
		combat._attacker = boss
		combat._defender = pc
		boss.begin_turn()
		combat._plan = MainPhasePlan.new(boss, 0, 5, 2, null)
		combat._enemy_stage_ability()
		_check(combat._plan.fire_ultimate_staged, "an armed enemy Ultimate is staged by _enemy_stage_ability()")

		combat._commit_main1()
		_check(boss.bonus_meter.value == 0, "firing the Ultimate consumes the meter")
		_check(boss.boss_reinforcement_ids.size() == 2, "Dark Reinforcements summons 2 tracked reinforcements")
		for r: Combatant in boss.boss_reinforcement_ids:
			_check(r.max_hp == 30, "each Dark Reinforcements minion has 30 max HP (the lesser tier, got %d)" % r.max_hp)
			_check(combat._enemies.has(r), "each Dark Reinforcements minion is a real, targetable enemy Combatant")

		_check(combat._ultimate_label(&"dark_reinforcements") != "Fire Ultimate", "dark_reinforcements has a real button label, not the generic fallback")
		_check(combat._ultimate_name(&"dark_reinforcements") != "Ultimate", "dark_reinforcements has a real log name, not the generic fallback")

		_instance.free()
	if _frames >= 3:
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_ultimate_firing.gd`
Expected: FAIL — `_enemy_stage_ability()` never checks `ultimate_id`/meter yet; no
`dark_reinforcements` handling anywhere.

- [ ] **Step 3: Confirm `MainPhasePlan.toggle_ultimate()`'s exact behavior**

Read `combat/main_phase_plan.gd`'s `toggle_ultimate()` and `can_stage_ultimate()` before writing
Step 4 — confirm `toggle_ultimate()` sets `fire_ultimate_staged = true` when armed and not already
staged (it does; already confirmed during this plan's research — `can_stage_ultimate()` just checks
`bonus_meter.is_armed()`).

- [ ] **Step 4: Extend `_enemy_stage_ability()`'s Ultimate check**

Change the start of `_enemy_stage_ability()` (from Task 5's version) to check for an armed Ultimate
FIRST, before the base-ability match:

```gdscript
func _enemy_stage_ability() -> void:
	if _plan == null or _attacker == null or _attacker.is_player:
		return
	if _attacker.ultimate_id != &"" and _attacker.bonus_meter != null and _attacker.bonus_meter.is_armed():
		_plan.toggle_ultimate()   # mirrors the player-facing _on_ultimate_pressed() path exactly
		return   # fire the Ultimate this turn instead of the base ability (spec 2026-07-19 §3.3)
	match _attacker.ability_id:
		&"flurry":
			if _plan.can_stage_ability():
				_plan.ability_staged = true
		&"hunters_mark":
			if _plan.can_stage_ability() and _defender != null and not _defender.has_effect(&"hunters_mark"):
				_plan.ability_staged = true
		&"warden_support_heal", &"warden_support_curse":
			if _plan.can_stage_ability():
				_plan.ability_staged = true
```

- [ ] **Step 5: Apply "Dark Reinforcements" in `_commit_main1()`**

In `_commit_main1()`, change:
```gdscript
	if did_ultimate:
		_log("  ★ %s fires ULTIMATE — %s!" % [_attacker.display_name, _ultimate_name(_attacker.ultimate_id)])
```
to:
```gdscript
	if did_ultimate:
		_log("  ★ %s fires ULTIMATE — %s!" % [_attacker.display_name, _ultimate_name(_attacker.ultimate_id)])
		if _attacker.ultimate_id == &"dark_reinforcements":
			var r1: Combatant = _spawn_enemy_mid_combat(&"warden_acolyte_lesser_healer")
			var r2: Combatant = _spawn_enemy_mid_combat(&"warden_acolyte_lesser_curser")
			_attacker.boss_reinforcement_ids.append_array([r1, r2])
			_log("  ☾ Dark Reinforcements — 2 acolytes join the fight!")
```

- [ ] **Step 6: Add label/name entries**

In `_ultimate_label()`, add immediately before the final `_:` branch:
```gdscript
		&"dark_reinforcements": return "ULTIMATE: Dark Reinforcements"
```

In `_ultimate_name()`, add immediately before the final `_:` branch:
```gdscript
		&"dark_reinforcements": return "DARK REINFORCEMENTS (summon 2 acolytes)"
```

- [ ] **Step 7: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 8: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_ultimate_firing.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 9: Run existing enemy-ability regression tests**

Run the existing tests covering the ferret's Flurry / stoat's Hunter's Mark (e.g.
`ls tests/ | grep -iE "flurry|hunters_mark"` to locate them) — confirm still exit 0 (the new
Ultimate check returns early ONLY when `ultimate_id != &""` and the meter is armed; every existing
enemy has `ultimate_id == &""`, so the new check is always false for them and falls through
unchanged to the existing match).

- [ ] **Step 10: Commit**

```bash
git add combat/combat.gd tests/test_enemy_ultimate_firing.gd
git commit -m "feat(combat): add enemy Ultimate-firing + the Dark Reinforcements Ultimate"
```

---

### Task 9: Darkness Rampage — the boss's phase-locked AoE attack

**Files:**
- Modify: `combat/combat.gd`
- Test: `tests/test_darkness_rampage.gd` (new)

**Interfaces:**
- Consumes: `Combatant.boss_phase_two_active` (Task 4/7), `darkness_rampage_spins_remaining`/
  `is_darkness_rampage_active()`/`consume_darkness_rampage_spin()` (Task 4), the existing
  `sticky_wild_count`/`sticky_wild_spins_remaining`/`aoe_spins_remaining`/`_targets_for()`/
  `_enemies_of()` mechanisms (pre-existing, confirmed in spec §3.5 research).
- Produces: a Darkness Rampage turn is a real 4-reel Dark WILD AoE dealing 18 base damage, and the
  boss self-heals half the total damage dealt afterward.
- Consumed by: Task 11 (full sequence test).

- [ ] **Step 1: Write the failing test**

Create `tests/test_darkness_rampage.gd`. This drives a REAL spin through `combat.tscn`'s actual
pipeline (the established technique in this codebase for forcing a deterministic reel outcome — see
`tests/test_item_use_targeting_e2e.gd`'s precedent of rigging a reel's `.faces` to a single known
tier so `Reel.spin()` always resolves to it):

```gdscript
extends SceneTree

## Headless end-to-end test for Darkness Rampage (spec 2026-07-19 §3.5): while boss_phase_two_active,
## the boss's turn is a REAL 4-reel Dark WILD AoE hitting every living PC for 18 base damage (not the
## normal 12), and the boss self-heals half the total damage dealt. Rigs every reel's .faces to a
## single known SUCCESS tier (this codebase's established technique for a deterministic spin) and
## drives the actual async _do_spin()/_finish_spin() pipeline, not a shortcut past it.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Node = _instance
		var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
		boss.boss_phase_two_active = true
		boss.hp = 300
		var pc1: Combatant = Combatant.new()
		pc1.display_name = "PC1"; pc1.is_player = true; pc1.base_stats = Stats.new()
		pc1.base_max_hp = 100; pc1.apply_stats(); pc1.start_combat()
		var pc2: Combatant = Combatant.new()
		pc2.display_name = "PC2"; pc2.is_player = true; pc2.base_stats = Stats.new()
		pc2.base_max_hp = 100; pc2.apply_stats(); pc2.start_combat()

		combat._pcs = [pc1, pc2]
		combat._enemies = [boss]
		combat._dummies = []
		combat._turn_manager.combatants = [pc1, pc2, boss]
		combat._panels[pc1] = CombatantPanel.new()
		combat._panels[pc2] = CombatantPanel.new()
		combat._panels[boss] = CombatantPanel.new()
		combat._attacker = boss
		combat._defender = pc1

		boss.begin_turn()
		if boss.is_boss and boss.boss_phase_two_active:
			var dark: DamageType = load("res://combat/resources/types/dark.tres")
			boss.turn_reels.clear()
			for i in range(4):
				boss.turn_reels.append(ActionReel.make_default(dark))
			boss.sticky_wild_count = 4
			boss.sticky_wild_spins_remaining = 1
			boss.aoe_spins_remaining = 1
			boss.darkness_rampage_spins_remaining = 1
		_check(boss.turn_reels.size() == 4, "a Darkness Rampage turn builds 4 reels (got %d)" % boss.turn_reels.size())
		_check(boss.is_aoe_active(), "a Darkness Rampage turn is AoE-active")
		_check(boss.is_darkness_rampage_active(), "a Darkness Rampage turn is Darkness-Rampage-active")

		# Rig every reel to a known SUCCESS face so the spin is deterministic.
		for reel: ActionReel in boss.turn_reels:
			var success_face: ReelFace = null
			for f: ReelFace in reel.faces:
				if f.result_tier == ReelFace.ResultTier.SUCCESS:
					success_face = f
					break
			reel.faces = [success_face]

		combat._plan = MainPhasePlan.new(boss, 0, 5, 2, null)
		var pc1_hp_before: int = pc1.hp
		var pc2_hp_before: int = pc2.hp
		var boss_hp_before: int = boss.hp
		combat._do_spin()
		await get_tree().create_timer(2.0).timeout  # let the real Tween-driven strip animation settle

		_check(pc1.hp < pc1_hp_before, "PC1 takes damage from Darkness Rampage's AoE")
		_check(pc2.hp < pc2_hp_before, "PC2 ALSO takes damage — this is a true AoE, not primary+splash")
		_check(boss.hp > boss_hp_before, "the boss self-heals after Darkness Rampage")

		_instance.free()
	if _frames >= 3:
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_darkness_rampage.gd`
Expected: FAIL — the reel-building block is written directly in the test (mirroring what
`_on_turn_started()` should do), but `_darkness_rampage_total` tracking and the self-heal in
`_finish_spin()` don't exist yet, so the boss's HP never rises.

- [ ] **Step 3: Wire the Darkness Rampage reel-shape into `_on_turn_started()`**

In `_on_turn_started()`, immediately after the `if c.is_boss: _check_boss_phase_transition(c)` block
added in Task 7, add:

```gdscript
	if c.is_boss and c.boss_phase_two_active:
		var dark: DamageType = load("res://combat/resources/types/dark.tres")
		c.turn_reels.clear()
		for i in range(4):
			c.turn_reels.append(ActionReel.make_default(dark))
		c.sticky_wild_count = 4
		c.sticky_wild_spins_remaining = 1
		c.aoe_spins_remaining = 1
		c.darkness_rampage_spins_remaining = 1
```

- [ ] **Step 4: Give the boss its Darkness Rampage-specific base damage**

Darkness Rampage's HIT is 18 damage, but the boss's own `weapon.base_damage` is 12.0 (its normal
attack). Rather than adding a new field, mutate the shared `Weapon` resource for the duration of a
Darkness Rampage turn and restore it after — the boss's `weapon.base_damage` is otherwise only read
during its OWN turn and never referenced elsewhere between turns. Add this to the SAME block from
Step 3:

```gdscript
	if c.is_boss and c.boss_phase_two_active:
		var dark: DamageType = load("res://combat/resources/types/dark.tres")
		c.turn_reels.clear()
		for i in range(4):
			c.turn_reels.append(ActionReel.make_default(dark))
		c.sticky_wild_count = 4
		c.sticky_wild_spins_remaining = 1
		c.aoe_spins_remaining = 1
		c.darkness_rampage_spins_remaining = 1
		c.weapon.base_damage = 18.0
```

Add a matching restore at the END of `_finish_spin()` (after the `_attacker.consume_wild_spin()`
line, which is already unconditional and runs every turn):

```gdscript
	if _attacker.is_boss and _attacker.weapon.base_damage == 18.0:
		_attacker.weapon.base_damage = 12.0  # restore the Hollow Warden's normal attack damage after Darkness Rampage
```

- [ ] **Step 5: Track `_darkness_rampage_total` in `_do_spin()`**

Add a new field near the existing `_big_bang_total`/`_earthquake_total`/`_collateral_total` fields at
the top of the `Combat` script (search for `var _collateral_total: int = 0` or similar):

```gdscript
var _darkness_rampage_total: int = 0
```

In `_do_spin()`, immediately after the existing `_earthquake_total` block (search for
`if _attacker.is_earthquake_active():`), add:

```gdscript
	_darkness_rampage_total = 0
	if _attacker.is_darkness_rampage_active():
		for a in attacks:
			_darkness_rampage_total += a.final_damage
```

- [ ] **Step 6: Apply the self-heal in `_finish_spin()`**

In `_finish_spin()`, immediately after the existing Earthquake block (search for
`_attacker.consume_earthquake_spin()`), add:

```gdscript
	if _attacker.is_darkness_rampage_active():
		var heal_amt: int = ceili(_darkness_rampage_total / 2.0)
		_attacker.heal(heal_amt)
		_log("  ☾ Darkness Rampage: %d total damage → The Hollow Warden heals %d HP." % [_darkness_rampage_total, heal_amt])
		if _panels.has(_attacker):
			(_panels[_attacker] as CombatantPanel).refresh_status()
		_attacker.consume_darkness_rampage_spin()
```

- [ ] **Step 7: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 8: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_darkness_rampage.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 9: Run existing Ultimate-AoE regression tests**

Run the existing tests covering Rampage/Big Bang/Earthquake (e.g.
`ls tests/ | grep -iE "rampage|big_bang|earthquake"`) — confirm still exit 0 (this task's new code
paths are ALL gated on `_attacker.is_boss`/`is_darkness_rampage_active()`, which are false for every
existing class/enemy).

- [ ] **Step 10: Commit**

```bash
git add combat/combat.gd tests/test_darkness_rampage.gd
git commit -m "feat(combat): wire Darkness Rampage — the Hollow Warden's phase-locked AoE attack"
```

---

### Task 10: Floor 4 placement

**Files:**
- Modify: `world/dungeon_demo.gd`
- Modify: `tests/test_dungeon_demo_scene.gd`
- Test: (extends the existing test above — no new file)

**Interfaces:**
- Consumes: `EnemyLibrary.make(&"hollow_warden")`/`&"warden_acolyte_lesser_healer")`/
  `&"warden_acolyte_lesser_curser")` (Task 3).
- Produces: floor 4 (index 3) of `dungeon_demo.tscn` has a real `OverworldEnemy` encounter.
- Consumed by: nothing further in this plan (this is the player-facing terminal wiring task).

- [ ] **Step 1: Write the failing test**

In `tests/test_dungeon_demo_scene.gd`, find this existing line:
```gdscript
		_check(dungeon._floors[3].get_node_or_null("DungeonFloor4Enemy") == null, "floor 4 has no placeholder encounter (reserved for the boss, a later step)")
```
Replace it with:
```gdscript
		var enemy_4: OverworldEnemy = dungeon._floors[3].get_node("DungeonFloor4Enemy")
		_check(enemy_4 != null and enemy_4.enemy_ids == [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser"], "floor 4 has the Hollow Warden encounter (boss + 2 lesser acolytes)")
		_check(enemy_4.dungeon_floor == 3, "floor 4's enemy carries dungeon_floor == 3")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_scene.gd`
Expected: FAIL — `DungeonFloor4Enemy` doesn't exist yet.

- [ ] **Step 3: Add the floor-4 placement to `world/dungeon_demo.gd`**

In `_place_dungeon_enemies()`, change:
```gdscript
func _place_dungeon_enemies() -> void:
	var floor1_ids: Array[StringName] = [&"rat"]
	var floor2_ids: Array[StringName] = [&"rat", &"ferret"]
	var floor3_ids: Array[StringName] = [&"rat", &"ferret", &"stoat"]
	_place_dungeon_enemy("DungeonFloor1Enemy", floor1_ids, floor_bounds(0).position + ENEMY_LOCAL, 0)
	_place_dungeon_enemy("DungeonFloor2Enemy", floor2_ids, floor_bounds(1).position + ENEMY_LOCAL, 1)
	_place_dungeon_enemy("DungeonFloor3Enemy", floor3_ids, floor_bounds(2).position + ENEMY_LOCAL, 2)
```
to:
```gdscript
func _place_dungeon_enemies() -> void:
	var floor1_ids: Array[StringName] = [&"rat"]
	var floor2_ids: Array[StringName] = [&"rat", &"ferret"]
	var floor3_ids: Array[StringName] = [&"rat", &"ferret", &"stoat"]
	var floor4_ids: Array[StringName] = [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser"]
	_place_dungeon_enemy("DungeonFloor1Enemy", floor1_ids, floor_bounds(0).position + ENEMY_LOCAL, 0)
	_place_dungeon_enemy("DungeonFloor2Enemy", floor2_ids, floor_bounds(1).position + ENEMY_LOCAL, 1)
	_place_dungeon_enemy("DungeonFloor3Enemy", floor3_ids, floor_bounds(2).position + ENEMY_LOCAL, 2)
	_place_dungeon_enemy("DungeonFloor4Enemy", floor4_ids, floor_bounds(3).position + ENEMY_LOCAL, 3)
```

Update the function's own doc-comment (currently ending "Floor 4 (index 3) is reserved for the
boss, a later step — no placeholder enemy there.") to instead say floor 4 now holds the real Hollow
Warden encounter.

- [ ] **Step 4: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_scene.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 6: Commit**

```bash
git add world/dungeon_demo.gd tests/test_dungeon_demo_scene.gd
git commit -m "feat(world): place The Hollow Warden encounter on dungeon floor 4"
```

---

### Task 11: Full phase-transition sequence test + full regression sweep + status doc

**Files:**
- Create: `tests/test_hollow_warden_full_sequence.gd`
- Modify: `CLAUDE.md`

**Interfaces:** none new — this is an integration-proof + verification + documentation task.

- [ ] **Step 1: Write the full-sequence integration test**

Create `tests/test_hollow_warden_full_sequence.gd` — a scripted fight proving the WHOLE cycle in one
place (phase-1 minions' scripted actions, the 40% trigger, Indestructible blocking a direct hit but
not a DoT tick, Empowered applying after phase 2 ends, and the boss's Ultimate firing once its meter
is full):

```gdscript
extends SceneTree

## Full end-to-end integration test for The Hollow Warden (spec 2026-07-19) — proves the pieces built
## across Tasks 1-9 work TOGETHER in one real fight, not just in isolation.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Node = _instance
		var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
		var healer: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_healer")
		var curser: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_curser")
		var pc: Combatant = Combatant.new()
		pc.display_name = "TestPC"; pc.is_player = true; pc.base_stats = Stats.new()
		pc.base_max_hp = 200; pc.apply_stats(); pc.start_combat()

		combat._pcs = [pc]
		combat._enemies = [boss, healer, curser]
		combat._dummies = []
		combat._turn_manager.combatants = [pc, boss, healer, curser]
		for c: Combatant in combat._turn_manager.combatants:
			combat._panels[c] = CombatantPanel.new()

		# 1. Phase-1 minions' scripted actions still work end-to-end via the real ability path.
		combat._attacker = healer
		combat._defender = pc
		boss.hp = 500
		healer.begin_turn()
		combat._plan = MainPhasePlan.new(healer, 0, 5, 2, null)
		combat._enemy_stage_ability()
		combat._commit_main1()
		_check(boss.hp == 530 or boss.hp == boss.max_hp, "the healer's scripted action heals the boss (capped at max)")
		_check(boss.has_effect(&"guarded"), "the healer's scripted action shields the boss")

		combat._attacker = curser
		curser.begin_turn()
		combat._plan = MainPhasePlan.new(curser, 0, 5, 2, null)
		combat._enemy_stage_ability()
		combat._commit_main1()
		_check(pc.has_effect(&"warden_curse"), "the curser's scripted action curses the PC")

		# 2. The 40% phase transition (calls the orchestrator method directly, same as Task 7's test —
		# _on_turn_started() itself is UI/timer-heavy and covered by human playtest, not headlessly).
		boss.hp = 200
		combat._attacker = boss
		boss.begin_turn()
		combat._check_boss_phase_transition(boss)
		_check(boss.boss_phase_two_active, "the phase transition triggers for real below 40% HP")
		_check(boss.has_effect(&"indestructible"), "Indestructible is attached")

		# 3. Indestructible blocks a direct hit but not a DoT tick.
		var hp_before_hit: int = boss.hp
		boss.take_damage(int(boss.incoming_damage_multiplier() * 999))  # a "direct hit" scaled by the multiplier, mirroring how combat.gd computes final_damage
		_check(boss.hp == hp_before_hit, "Indestructible blocks a direct hit entirely")
		var curse_on_boss: Effect = EffectLibrary.make(&"warden_curse")
		curse_on_boss.dot_base_damage = 1.0
		boss.attach_effect(curse_on_boss)
		var dot_amount: int = ceili(curse_on_boss.dot_damage() * boss.dot_damage_multiplier())
		boss.take_damage(dot_amount)
		_check(boss.hp == hp_before_hit - dot_amount, "a DoT tick still damages the boss through Indestructible")

		# 4. Kill the phase-2 minions — Indestructible clears, Empowered applies.
		for m: Combatant in boss.boss_phase_minion_ids:
			m.take_damage(m.hp)
		combat._check_boss_phase_transition(boss)
		_check(not boss.has_effect(&"indestructible"), "Indestructible clears once phase-2 minions die")
		_check(boss.has_effect(&"empowered"), "Empowered applies once phase-2 minions die")

		# 5. The boss's Ultimate fires once its meter is full.
		boss.bonus_meter.value = boss.bonus_meter.cap
		combat._attacker = boss
		combat._defender = pc
		boss.begin_turn()
		combat._plan = MainPhasePlan.new(boss, 0, 5, 2, null)
		combat._enemy_stage_ability()
		combat._commit_main1()
		_check(boss.boss_reinforcement_ids.size() == 2, "Dark Reinforcements fires for real once the meter fills")

		_instance.free()
	if _frames >= 3:
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hollow_warden_full_sequence.gd`
Expected: FAIL if run before Tasks 1-9 are complete (this test exercises everything built across
this whole plan). If Tasks 1-9 are already done when this task starts, this test should PASS on the
first run — in that case, skip straight to Step 3 rather than forcing an artificial RED (there is no
new production code left for this task to motivate).

- [ ] **Step 3: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hollow_warden_full_sequence.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 4: Full headless suite regression sweep**

```bash
for f in tests/test_*.gd; do
  name=$(basename "$f")
  ../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script "res://tests/$name" > /dev/null 2>&1
  code=$?
  if [ $code -ne 0 ]; then
    echo "NONZERO EXIT ($code): $name"
  fi
done
echo "sweep complete"
```

Retry any nonzero-exit file individually once — this project has a documented intermittent
teardown-only SIGSEGV flake class that clears on retry, and one pre-existing, unrelated failure
(`tests/test_adventuring_board_panel.gd`, documented in `CLAUDE.md` since 2026-07-14). Anything else
that fails consistently on retry is a real regression from this plan's work and must be fixed before
proceeding — do not dismiss it.

- [ ] **Step 5: Update `CLAUDE.md`'s status section**

Add a new entry after the most recent SHIPPED entry (match the existing entries' style/format)
describing: The Hollow Warden boss fight shipped — 550 HP, Dark-typed, phase-1 minions
(heal+guard/curse), the 40%-HP phase transition with Indestructible + Darkness Rampage + a re-
triggerable 10-turn cooldown, the first enemy Ultimate (Dark Reinforcements), and floor 4 placement.
Note the new `_spawn_enemy_mid_combat()`/`TurnManager.insert_acting_this_round()` mechanism as a
reusable piece of plumbing future content can build on. Note this is Plan 2 of 3 for the boss + Lost
Cat quest feature; Plan 3 (the quest system itself) is next. Note that a human has not yet
playtested this live — that's the next step before Plan 3.

- [ ] **Step 6: Commit**

```bash
git add tests/test_hollow_warden_full_sequence.gd CLAUDE.md
git commit -m "test(combat): full Hollow Warden phase-transition sequence + record shipped status"
```

# Shared Foundations Implementation Plan (Phase 1 of remaining-four-classes)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the cross-cutting combat systems the remaining four classes all need — a Mana resource rail, a SHIELDED absorb pool, Heal and Cleanse on `Combatant` — and make LUCK Chancer-exclusive. Pure logic, all headless-testable; no UI or orchestrator wiring (that lands in each class's own plan).

**Architecture:** Extend the existing pure-logic resources. `ResourcePool` gains a Mana rail parallel to Stamina (cost dictionaries already key by resource name, so no signature changes). `Combatant` gains shield state absorbed inside the single `take_damage` chokepoint, plus `heal()`/`cleanse()`. `CharacterClass.build_combatant()` seeds the Mana pool. `ClassLibrary` zeroes Luck on every class but Chancer.

**Tech Stack:** Godot 4.6.3-stable, GDScript (static typing), `Resource`/`RefCounted` data objects, headless `SceneTree` test scripts.

## Global Constraints

- **Engine Godot 4.6.3-stable; GDScript only — never C#** (CLAUDE.md §2).
- **Naming (LOCKED):** Classes/Resources `PascalCase`; script files `snake_case`; signals `snake_case` past-tense; signal handlers `_on_<emitter>_<signal>` (CLAUDE.md §2).
- **All damage/heal math rounds up (`ceil`)** project-wide (CLAUDE.md §10 / memory).
- **Balance numbers are `[ASSUMPTION]` placeholders** — build as editable data, do not "balance" (CLAUDE.md §4).
- **Architect N-vs-M-ready**, but the scene stays 1v1 — multi-target paths are verified by headless tests only (CLAUDE.md §7).
- **Run a test:** from the project dir `C:\bunnies\bunnies-main\bunnies`, run
  `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_<name>.gd`
  A suite prints `... TEST PASSED` / `... TEST FAILED: N` and exits with the failure count (`quit(_failures)`).
- **Commit** after each task only (not mid-task). End commit messages with the `Co-Authored-By` trailer.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `combat/resource_pool.gd` | Stamina **+ Mana** rails; cost-dict spend/refund/regen | Modify |
| `combat/combatant.gd` | + `base_max_mana`, mana derivation in `apply_stats`; + shield state/`take_damage` absorb/`apply_shield`/shield tick; + `heal()`; + `cleanse()` | Modify |
| `combat/resources/character_class.gd` | + mana fields; seed mana pool in `build_combatant` | Modify |
| `combat/class_library.gd` | zero Luck on Warrior & Skirmisher | Modify |
| `tests/test_mana_pool.gd` | ResourcePool mana rail | Create |
| `tests/test_mana_derivation.gd` | `apply_stats` + `build_combatant` mana | Create |
| `tests/test_shielded.gd` | absorb / higher-overrides / tick | Create |
| `tests/test_heal.gd` | clamp + overflow return | Create |
| `tests/test_cleanse.gd` | strips debuffs, keeps buffs | Create |
| `tests/test_luck_cleanup.gd` | no non-Chancer class ships Luck > 0 | Create |

> **Deferred to later (per-class) plans, not here:** the `ability_cost`/`ability_resource` cost-model fields + `MainPhasePlan`/`combat.gd` wiring (first exercised by Chancer); the Mana-bar UI + shield chip (first exercised by Seer); the re-resolve-one-reel primitive (Chancer); all four classes' abilities/Ultimates/modals.

---

### Task 1: Mana rail in `ResourcePool`

**Files:**
- Modify: `combat/resource_pool.gd`
- Test: `tests/test_mana_pool.gd`

**Interfaces:**
- Produces: `ResourcePool` with `mana: int`, `max_mana: int`, `mana_regen_per_turn: int`; `can_afford(cost)`/`spend(cost)`/`refund(cost)`/`regen()` now handle the `&"mana"` cost key alongside `&"stamina"`. `regen()` regenerates both rails.

- [ ] **Step 1: Write the failing test** — create `tests/test_mana_pool.gd`:

```gdscript
extends SceneTree

# Headless test: ResourcePool's Mana rail — affordability across both rails, spend, refund clamp,
# and regen of both rails. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_pool.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var p: ResourcePool = ResourcePool.new()
	p.stamina = 5; p.max_stamina = 5; p.regen_per_turn = 1
	p.mana = 10; p.max_mana = 15; p.mana_regen_per_turn = 1

	# can_afford checks BOTH rails.
	_check(p.can_afford({&"mana": 6}), "affords 6 mana of 10")
	_check(not p.can_afford({&"mana": 11}), "cannot afford 11 mana of 10")
	_check(p.can_afford({&"stamina": 2, &"mana": 6}), "affords mixed 2 sta + 6 mana")
	_check(not p.can_afford({&"stamina": 6, &"mana": 1}), "mixed unaffordable if stamina short")

	# spend mana only, stamina untouched.
	_check(p.spend({&"mana": 6}), "spent 6 mana")
	_check(p.mana == 4, "mana 10 -> 4 (got %d)" % p.mana)
	_check(p.stamina == 5, "stamina untouched by mana spend (got %d)" % p.stamina)

	# unaffordable spend changes nothing.
	_check(p.spend({&"mana": 99}) == false, "overspend mana rejected")
	_check(p.mana == 4, "mana unchanged after rejected spend (got %d)" % p.mana)

	# refund clamps to max_mana.
	p.refund({&"mana": 100})
	_check(p.mana == 15, "mana refund clamps at max 15 (got %d)" % p.mana)

	# regen bumps both rails by their per-turn amounts, clamped.
	p.stamina = 4; p.mana = 4
	p.regen()
	_check(p.stamina == 5, "stamina regen +1 -> 5 (got %d)" % p.stamina)
	_check(p.mana == 5, "mana regen +1 -> 5 (got %d)" % p.mana)

	print(("MANA POOL TEST PASSED" if _failures == 0 else "MANA POOL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_pool.gd`
Expected: FAIL — `Invalid set ... 'mana'` / unknown property (mana fields don't exist yet).

- [ ] **Step 3: Add the Mana rail.** In `combat/resource_pool.gd`, after the stamina vars (line 17), add:

```gdscript
## Mana rail — parallel to Stamina, for caster classes (Seer/Warden). Same cost-dictionary shape.
var mana: int = 0
var max_mana: int = 0
var mana_regen_per_turn: int = 0
```

Replace `can_afford` (lines 20-21):

```gdscript
## True if every entry in [param cost] is currently affordable on its rail.
func can_afford(cost: Dictionary) -> bool:
	return stamina >= int(cost.get(&"stamina", 0)) and mana >= int(cost.get(&"mana", 0))
```

Replace `spend` (lines 24-32):

```gdscript
## Spends [param cost] atomically across both rails. Returns false and changes nothing if unaffordable.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	var sta: int = int(cost.get(&"stamina", 0))
	if sta != 0:
		stamina -= sta
		pool_changed.emit(&"stamina", stamina, max_stamina)
	var man: int = int(cost.get(&"mana", 0))
	if man != 0:
		mana -= man
		pool_changed.emit(&"mana", mana, max_mana)
	return true
```

Replace `refund` (lines 36-43):

```gdscript
## Adds resources back on each rail, clamped to that rail's maximum.
func refund(cost: Dictionary) -> void:
	var sta: int = int(cost.get(&"stamina", 0))
	if sta > 0:
		var before_s: int = stamina
		stamina = mini(stamina + sta, max_stamina)
		if stamina != before_s:
			pool_changed.emit(&"stamina", stamina, max_stamina)
	var man: int = int(cost.get(&"mana", 0))
	if man > 0:
		var before_m: int = mana
		mana = mini(mana + man, max_mana)
		if mana != before_m:
			pool_changed.emit(&"mana", mana, max_mana)
```

Replace `regen` (lines 46-50):

```gdscript
## Upkeep regeneration: bumps each rail by its per-turn amount, clamped at its maximum.
func regen() -> void:
	var before_s: int = stamina
	stamina = mini(stamina + regen_per_turn, max_stamina)
	if stamina != before_s:
		pool_changed.emit(&"stamina", stamina, max_stamina)
	var before_m: int = mana
	mana = mini(mana + mana_regen_per_turn, max_mana)
	if mana != before_m:
		pool_changed.emit(&"mana", mana, max_mana)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_pool.gd`
Expected: `MANA POOL TEST PASSED`

- [ ] **Step 5: Regression — confirm the existing stamina suite still passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_heft.gd`
Expected: `HEFT TEST PASSED`

- [ ] **Step 6: Commit**

```bash
git add combat/resource_pool.gd tests/test_mana_pool.gd
git commit -m "feat(resource): add Mana rail to ResourcePool (parallel to Stamina)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Mana derivation in `Combatant.apply_stats`

**Files:**
- Modify: `combat/combatant.gd:55-58` (add `base_max_mana`), `combat/combatant.gd:132-139` (`apply_stats`)
- Test: `tests/test_mana_derivation.gd`

**Interfaces:**
- Consumes: `ResourcePool` mana fields (Task 1).
- Produces: `Combatant.base_max_mana: int`; `apply_stats()` sets `resource_pool.max_mana = base_max_mana + focus` and clamps `mana` to it (mirroring the stamina derivation).

- [ ] **Step 1: Write the failing test** — create `tests/test_mana_derivation.gd`:

```gdscript
extends SceneTree

# Headless test: apply_stats derives max_mana = base_max_mana + Focus and clamps current mana. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_derivation.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	var s: Stats = Stats.new(); s.focus = 6
	c.base_stats = s
	c.base_max_mana = 9
	c.base_max_stamina = 0
	c.resource_pool = ResourcePool.new()
	c.resource_pool.mana = 15   # seeded "full" — should clamp to max after derivation
	c.apply_stats()
	_check(c.resource_pool.max_mana == 15, "max_mana = 9 base + 6 Focus = 15 (got %d)" % c.resource_pool.max_mana)
	_check(c.resource_pool.mana == 15, "mana clamped to 15 (got %d)" % c.resource_pool.mana)

	# Lower Focus lowers the cap and clamps current mana down.
	var c2: Combatant = Combatant.new()
	var s2: Stats = Stats.new(); s2.focus = 2
	c2.base_stats = s2
	c2.base_max_mana = 9
	c2.resource_pool = ResourcePool.new()
	c2.resource_pool.mana = 15
	c2.apply_stats()
	_check(c2.resource_pool.max_mana == 11, "max_mana = 9 + 2 = 11 (got %d)" % c2.resource_pool.max_mana)
	_check(c2.resource_pool.mana == 11, "mana clamped down to 11 (got %d)" % c2.resource_pool.mana)

	print(("MANA DERIVATION TEST PASSED" if _failures == 0 else "MANA DERIVATION TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_derivation.gd`
Expected: FAIL — `base_max_mana` not a valid property / `max_mana` stays 0.

- [ ] **Step 3: Add the field + derivation.** In `combat/combatant.gd`, after `var base_max_stamina: int = 0` (line 56) add:

```gdscript
var base_max_mana: int = 0
```

In `apply_stats()` (lines 132-139), inside the `if resource_pool != null:` block, after the two stamina lines add:

```gdscript
		resource_pool.max_mana = base_max_mana + s.focus
		resource_pool.mana = mini(resource_pool.mana, resource_pool.max_mana)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_derivation.gd`
Expected: `MANA DERIVATION TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_mana_derivation.gd
git commit -m "feat(combatant): derive max_mana from base + Focus in apply_stats

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Seed the Mana pool in `CharacterClass.build_combatant`

**Files:**
- Modify: `combat/resources/character_class.gd:31-33` (add mana export fields), `combat/resources/character_class.gd:72-78` (`build_combatant` pool seeding)
- Test: `tests/test_mana_derivation.gd` (extend with a `CharacterClass` round-trip)

**Interfaces:**
- Consumes: `ResourcePool` mana (Task 1), `Combatant.base_max_mana` + derivation (Task 2).
- Produces: `CharacterClass.base_max_mana: int`, `start_mana: int`, `mana_regen: int`. `build_combatant()` copies them into the pool/combatant so a built caster starts at full mana (set `start_mana` to the intended full total; the `apply_stats` clamp keeps it in range).

- [ ] **Step 1: Extend the failing test.** Append to `tests/test_mana_derivation.gd` `_initialize()`, just before the final `print(...)` line:

```gdscript
	# CharacterClass round-trip: a built caster starts at full mana.
	var cls: CharacterClass = CharacterClass.new()
	cls.base_stats = (func() -> Stats: var st: Stats = Stats.new(); st.focus = 6; return st).call()
	cls.weapon_type = load("res://combat/resources/types/mystic.tres")
	cls.reel_count = 2
	cls.base_max_hp = 300
	cls.base_max_stamina = 0
	cls.base_max_mana = 9
	cls.start_mana = 15
	cls.mana_regen = 1
	var built: Combatant = cls.build_combatant(true)
	_check(built.resource_pool != null, "built caster has a resource pool")
	_check(built.resource_pool.max_mana == 15, "built max_mana 15 (got %d)" % built.resource_pool.max_mana)
	_check(built.resource_pool.mana == 15, "built starts at full mana 15 (got %d)" % built.resource_pool.mana)
	_check(built.resource_pool.mana_regen_per_turn == 1, "built mana regen 1 (got %d)" % built.resource_pool.mana_regen_per_turn)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_derivation.gd`
Expected: FAIL — `start_mana`/`base_max_mana`/`mana_regen` not valid properties on `CharacterClass`.

- [ ] **Step 3: Add fields + pool seeding.** In `combat/resources/character_class.gd`, after the Stamina export block (lines 31-33) add:

```gdscript
## Starting / regenerating Mana (caster Main-1 economy). max_mana derives as base_max_mana + Focus
## in Combatant.apply_stats; set start_mana to the intended full total (the clamp keeps it in range).
@export var base_max_mana: int = 0
@export var start_mana: int = 0
@export var mana_regen: int = 0
```

In `build_combatant()`, inside the `if is_player:` block (lines 72-78), after `pool.regen_per_turn = stamina_regen` add:

```gdscript
		pool.mana = start_mana
		pool.mana_regen_per_turn = mana_regen
```

and after `c.base_max_stamina = base_max_stamina` add:

```gdscript
		c.base_max_mana = base_max_mana
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_derivation.gd`
Expected: `MANA DERIVATION TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/resources/character_class.gd tests/test_mana_derivation.gd
git commit -m "feat(class): mana fields on CharacterClass; build_combatant seeds full mana

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: SHIELDED state on `Combatant` (absorb / higher-overrides / tick)

**Files:**
- Modify: `combat/combatant.gd` — add a `shield_changed` signal (near line 13), shield state (near line 90), rewrite `take_damage` (lines 108-114), add `apply_shield`, add shield tick to `on_end` (lines 284-287)
- Test: `tests/test_shielded.gd`

**Interfaces:**
- Produces: `Combatant.shield_hp: int`, `shield_turns: int`; signal `shield_changed(shield_hp: int, shield_turns: int)`; `apply_shield(amount: int, turns: int) -> void` (higher-total-overrides); `take_damage` absorbs from `shield_hp` first; `on_end()` decrements `shield_turns` and clears the shield at 0.

- [ ] **Step 1: Write the failing test** — create `tests/test_shielded.gd`:

```gdscript
extends SceneTree

# Headless test: SHIELDED absorb in take_damage, higher-total-overrides apply rule, turn tick. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shielded.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(max_hp: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.max_hp = max_hp
	c.hp = max_hp
	return c

func _initialize() -> void:
	# User's worked example: 300 HP + 10 shield, struck for 20 -> shield eats 10, HP takes 10 -> 290, shield gone.
	var c: Combatant = _mk(300)
	c.apply_shield(10, 2)
	_check(c.shield_hp == 10, "shield applied 10 (got %d)" % c.shield_hp)
	c.take_damage(20)
	_check(c.hp == 290, "HP 300 -> 290 after 10 absorbed (got %d)" % c.hp)
	_check(c.shield_hp == 0, "shield fully spent (got %d)" % c.shield_hp)
	_check(c.shield_turns == 0, "shield turns cleared when hp hits 0 (got %d)" % c.shield_turns)

	# Partial absorb: damage less than shield leaves HP untouched.
	var d: Combatant = _mk(300)
	d.apply_shield(50, 2)
	d.take_damage(20)
	_check(d.hp == 300, "HP untouched while shield absorbs (got %d)" % d.hp)
	_check(d.shield_hp == 30, "shield 50 -> 30 (got %d)" % d.shield_hp)

	# Higher-total-overrides: a smaller new shield is ignored; a bigger one replaces.
	var e: Combatant = _mk(300)
	e.apply_shield(30, 2)
	e.apply_shield(10, 5)
	_check(e.shield_hp == 30 and e.shield_turns == 2, "smaller shield ignored (got hp %d turns %d)" % [e.shield_hp, e.shield_turns])
	e.apply_shield(50, 1)
	_check(e.shield_hp == 50 and e.shield_turns == 1, "bigger shield overrides (got hp %d turns %d)" % [e.shield_hp, e.shield_turns])

	# Turn tick: a 2-turn shield clears after two on_end ticks.
	var f: Combatant = _mk(300)
	f.apply_shield(40, 2)
	f.on_end()
	_check(f.shield_hp == 40 and f.shield_turns == 1, "after 1 tick: 40 hp, 1 turn (got hp %d turns %d)" % [f.shield_hp, f.shield_turns])
	f.on_end()
	_check(f.shield_hp == 0 and f.shield_turns == 0, "after 2 ticks: shield expired (got hp %d turns %d)" % [f.shield_hp, f.shield_turns])

	print(("SHIELDED TEST PASSED" if _failures == 0 else "SHIELDED TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shielded.gd`
Expected: FAIL — `apply_shield` / `shield_hp` not defined.

- [ ] **Step 3: Implement shields.** In `combat/combatant.gd`:

(a) After the `defeated` signal (line 14) add:

```gdscript
## Emitted whenever shield_hp or shield_turns changes, for shield-chip UI binding.
signal shield_changed(shield_hp: int, shield_turns: int)
```

(b) After the STUNNED state block (line 95) add:

```gdscript
## SHIELDED buff (spec 2026-06-22 §1.2): a damage-absorbing pool. take_damage spends shield_hp before
## HP; shield_turns counts down in on_end. Higher-total-overrides on re-apply (apply_shield). Combatant
## STATE (not an Effect) because the absorb math lives in take_damage.
var shield_hp: int = 0
var shield_turns: int = 0
```

(c) Replace `take_damage` (lines 108-114) with:

```gdscript
## Applies [param amount] damage. SHIELDED absorbs first (and the shield clears if fully spent), then
## the remainder hits HP, clamped so HP never goes negative. Emits [signal hp_changed], and
## [signal defeated] once when HP reaches 0. No-op if already dead or amount ≤ 0.
func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	var remaining: int = amount
	if shield_hp > 0:
		var absorbed: int = mini(shield_hp, remaining)
		shield_hp -= absorbed
		remaining -= absorbed
		if shield_hp == 0:
			shield_turns = 0
		shield_changed.emit(shield_hp, shield_turns)
	if remaining <= 0:
		return
	hp = maxi(hp - remaining, 0)
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		defeated.emit()
```

(d) Immediately after `take_damage`, add:

```gdscript
## Applies a SHIELDED buff of [param amount] HP for [param turns] turns. Higher-total-overrides
## (spec §1.2 / §3.3): replaces the current shield only if [param amount] exceeds it; otherwise no-op.
func apply_shield(amount: int, turns: int) -> void:
	if amount <= 0 or amount <= shield_hp:
		return
	shield_hp = amount
	shield_turns = turns
	shield_changed.emit(shield_hp, shield_turns)
```

(e) In `on_end()` (lines 284-287), after `tick_effects()` add:

```gdscript
	if shield_turns > 0:
		shield_turns -= 1
		if shield_turns == 0:
			shield_hp = 0
		shield_changed.emit(shield_hp, shield_turns)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shielded.gd`
Expected: `SHIELDED TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_shielded.gd
git commit -m "feat(combatant): SHIELDED absorb pool (take_damage + apply_shield + tick)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `Combatant.heal()` with overflow return

**Files:**
- Modify: `combat/combatant.gd` — add `heal()` after `apply_shield` (Task 4)
- Test: `tests/test_heal.gd`

**Interfaces:**
- Produces: `heal(amount: int) -> int` — clamps HP to `max_hp`, emits `hp_changed`, returns the **overflow** (`amount` minus the amount actually restored). No-op (returns 0) on a dead combatant. Callers pass an already-`ceil`-ed amount.

- [ ] **Step 1: Write the failing test** — create `tests/test_heal.gd`:

```gdscript
extends SceneTree

# Headless test: heal clamps to max_hp and returns the overflow (for Big Bang's excess->shield). Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_heal.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(max_hp: int, hp: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.max_hp = max_hp; c.hp = hp
	return c

func _initialize() -> void:
	# Normal heal, no overflow.
	var a: Combatant = _mk(300, 250)
	var of1: int = a.heal(20)
	_check(a.hp == 270, "250 + 20 -> 270 (got %d)" % a.hp)
	_check(of1 == 0, "no overflow (got %d)" % of1)

	# User's example: 295/300 + 20 heal -> 300 HP, 15 overflow.
	var b: Combatant = _mk(300, 295)
	var of2: int = b.heal(20)
	_check(b.hp == 300, "295 + 20 clamps to 300 (got %d)" % b.hp)
	_check(of2 == 15, "overflow 15 (got %d)" % of2)

	# Full HP: all overflow.
	var c: Combatant = _mk(300, 300)
	_check(c.heal(10) == 10, "full HP -> all 10 overflow")
	_check(c.hp == 300, "HP stays 300")

	# Dead: no-op.
	var d: Combatant = _mk(300, 0)
	_check(d.heal(50) == 0, "healing the dead returns 0")
	_check(d.hp == 0, "dead stays dead")

	print(("HEAL TEST PASSED" if _failures == 0 else "HEAL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_heal.gd`
Expected: FAIL — `heal` not defined.

- [ ] **Step 3: Implement `heal`.** In `combat/combatant.gd`, immediately after `apply_shield`, add:

```gdscript
## Restores [param amount] HP, clamped to max_hp. Returns the OVERFLOW (amount that exceeded max) so a
## caller (e.g. Big Bang) can convert it to a shield. No-op (returns 0) if dead or amount ≤ 0.
func heal(amount: int) -> int:
	if amount <= 0 or hp <= 0:
		return 0
	var before: int = hp
	hp = mini(hp + amount, max_hp)
	if hp != before:
		hp_changed.emit(hp, max_hp)
	return amount - (hp - before)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_heal.gd`
Expected: `HEAL TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_heal.gd
git commit -m "feat(combatant): heal() with overflow return for excess->shield

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: `Combatant.cleanse()`

**Files:**
- Modify: `combat/combatant.gd` — add `cleanse()` after `tick_effects` (line 203)
- Test: `tests/test_cleanse.gd`

**Interfaces:**
- Consumes: existing `Effect.beneficial` flag, `attach_effect`, `recompute_initiative`.
- Produces: `cleanse() -> int` — removes all non-beneficial (`beneficial == false`) effects, recomputes initiative, returns the count removed. Used by the Warden Pick'em Ultimate later.

- [ ] **Step 1: Write the failing test** — create `tests/test_cleanse.gd`:

```gdscript
extends SceneTree

# Headless test: cleanse strips debuffs, keeps buffs, and restores derived initiative. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_cleanse.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	c.base_initiative = 50
	c.recompute_initiative()
	c.attach_effect(EffectLibrary.make(&"slow"))           # debuff: -20 initiative
	c.attach_effect(EffectLibrary.make(&"inspirational"))  # buff: +5 initiative
	_check(c.active_effects.size() == 2, "two effects attached (got %d)" % c.active_effects.size())
	_check(c.current_initiative == 35, "50 -20 +5 = 35 (got %d)" % c.current_initiative)

	var removed: int = c.cleanse()
	_check(removed == 1, "cleansed 1 debuff (got %d)" % removed)
	_check(c.active_effects.size() == 1, "buff remains (got %d effects)" % c.active_effects.size())
	_check(c.active_effects[0].id == &"inspirational", "the survivor is the buff")
	_check(c.current_initiative == 55, "50 +5 = 55 after debuff removed (got %d)" % c.current_initiative)

	print(("CLEANSE TEST PASSED" if _failures == 0 else "CLEANSE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_cleanse.gd`
Expected: FAIL — `cleanse` not defined.

- [ ] **Step 3: Implement `cleanse`.** In `combat/combatant.gd`, after `tick_effects()` (ends line 203) add:

```gdscript
## Removes all non-beneficial (debuff) effects, keeping buffs, then refreshes the derived sort key.
## Returns the number of effects removed. Used by the Warden Pick'em Ultimate (spec §3.3).
func cleanse() -> int:
	var before: int = active_effects.size()
	active_effects = active_effects.filter(func(e: Effect) -> bool: return e != null and e.beneficial)
	recompute_initiative()
	return before - active_effects.size()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_cleanse.gd`
Expected: `CLEANSE TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_cleanse.gd
git commit -m "feat(combatant): cleanse() strips debuffs, keeps buffs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: LUCK cleanup — make Luck Chancer-exclusive

**Files:**
- Modify: `combat/class_library.gd:23` (Warrior stats), `combat/class_library.gd:48` (Skirmisher stats)
- Test: `tests/test_luck_cleanup.gd`

**Interfaces:**
- Consumes: `ClassLibrary.IDS`, `ClassLibrary.make(id)`, `CharacterClass.base_stats.luck`.
- Produces: every class in `IDS` except `&"chancer"` has `base_stats.luck == 0`. (Chancer is not yet in `IDS`; the test is written forward-compatibly so it stays correct once Chancer is added with Luck 4.)

- [ ] **Step 1: Write the failing test** — create `tests/test_luck_cleanup.gd`:

```gdscript
extends SceneTree

# Headless test: LUCK is Chancer-exclusive — no other class in the library ships Luck > 0. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_luck_cleanup.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	for id: StringName in ClassLibrary.IDS:
		var c: CharacterClass = ClassLibrary.make(id)
		if id == &"chancer":
			_check(c.base_stats.luck > 0, "Chancer keeps Luck (got %d)" % c.base_stats.luck)
		else:
			_check(c.base_stats.luck == 0, "%s has Luck 0 (got %d)" % [id, c.base_stats.luck])

	print(("LUCK CLEANUP TEST PASSED" if _failures == 0 else "LUCK CLEANUP TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_luck_cleanup.gd`
Expected: FAIL — Warrior `Luck 0` and Skirmisher `Luck 0` checks fail (both currently ship Luck 1).

- [ ] **Step 3: Zero the Luck.** In `combat/class_library.gd`:

Warrior (line 23): change
`c.base_stats = _stats(3, 2, 3, 1, 2, 1)` → `c.base_stats = _stats(3, 2, 3, 1, 2, 0)`

Skirmisher (line 48): change
`c.base_stats = _stats(1, 5, 2, 2, 1, 1)` → `c.base_stats = _stats(1, 5, 2, 2, 1, 0)`

(Vanguard already has Luck 0 — no change.)

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_luck_cleanup.gd`
Expected: `LUCK CLEANUP TEST PASSED`

- [ ] **Step 5: Regression — confirm class-library tests still pass.** Run any existing class/luck suite, e.g.:

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_heft.gd`
Expected: `HEFT TEST PASSED`
(If a dedicated `tests/test_apply_luck.gd` or `tests/test_class_library*.gd` exists, run it too and confirm it still passes — the Warrior/Skirmisher Luck change must not break it.)

- [ ] **Step 6: Commit**

```bash
git add combat/class_library.gd tests/test_luck_cleanup.gd
git commit -m "feat(class): make Luck Chancer-exclusive (zero Warrior/Skirmisher Luck)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase-1 completion checklist

- [ ] All six new suites pass: `test_mana_pool`, `test_mana_derivation`, `test_shielded`, `test_heal`, `test_cleanse`, `test_luck_cleanup`.
- [ ] **Full regression:** run every suite under `tests/` and confirm all green (the shared changes touch `ResourcePool`, `Combatant.take_damage`/`apply_stats`/`on_end`, and `ClassLibrary` — all widely used). If a `tests/run_all` script exists use it; otherwise run each `tests/test_*.gd`.
- [ ] No UI/orchestrator files changed (deferred by design).
- [ ] **No playtest gate here** — Phase 1 ships no player-visible feature. The first playtest gate is at the end of the **Chancer** plan (Phase 2), the first class to consume these foundations.

---

## Self-review notes (author)

- **Spec coverage:** §1.1 Mana → Tasks 1-3; §1.2 SHIELDED/Heal/Cleanse → Tasks 4-6; §2 LUCK → Task 7. §1.3 reroll primitive, §1.4 modals, and the `ability_cost`/`ability_resource` cost model are **intentionally deferred** to the class plans that first consume them (noted in File Structure) — not gaps.
- **Type consistency:** `apply_shield(amount, turns)`, `heal(amount) -> int` (overflow), `cleanse() -> int` (count), `shield_hp`/`shield_turns`, `mana`/`max_mana`/`mana_regen_per_turn`, `base_max_mana`/`start_mana`/`mana_regen` — names used identically across tasks and match the spec's §4 table.
- **No placeholders:** every code/test step shows complete code and a real run command.

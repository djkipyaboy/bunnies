# Level & Stat Damage-Scaling System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the level-based automatic "rank-up" system and the stat-based diminishing-returns
power-stat scaling system, as pure/generic infrastructure ready for future per-ability content
authoring — no per-class ability numbers are authored in this plan.

**Architecture:** Two independent additive systems layered on the existing `Combatant`/
`CharacterClass` resources. Rank-up is a pure level-lookup function reusing the existing
talent-row unlock schedule. Stat scaling is a pure diminishing-returns formula
(`combat/stat_scaling.gd`) consumed two ways: folded into the existing `outgoing_damage_multiplier()`
chain for weapon-type reel damage (only for classes whose power stat isn't Might, keeping Might's
existing flat model byte-for-byte unchanged), and exposed as a standalone method for future
ability-magnitude authoring to call.

**Tech Stack:** Godot 4.6.3-stable, GDScript, headless `SceneTree`-script tests run via
`Godot_v4.6.3-stable_win64_console.exe` (lives one directory above this repo, at
`C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`).

**Spec:** `docs/superpowers/specs/2026-08-28-level-stat-scaling-design.md`

## Global Constraints

- Engine is Godot 4.6+ (built/tested on 4.6.3-stable). GDScript only — never C#.
- Round UP (ceil) for all damage/heal math — existing project convention, already used everywhere
  this plan touches.
- Every new tunable number is an `[ASSUMPTION]` placeholder (CLAUDE.md §4) — implement as a named
  constant, never a magic number, and never hand-tune it as "correct" now.
- Naming: PascalCase classes/Resources, snake_case script files, snake_case past-tense signals
  (none are added by this plan, but existing ones must not be renamed).
- Rank-up is **automatic and level-gated only** — never a player choice, never interacting with
  `pick_ability_talent()`'s existing selection state.
- Rank-up schedule (spec §1.1, flipped to match `ability_talent_row_unlock_level()`'s existing
  order): level 5/6/7/8 → base ability / L2 / L3 / L4 each rank up to 2; level 9 → passive
  amplified; level 10 → Ultimate ranks up to 2.
- `power_stat` resolution (spec §2.1): melee/ranged `combat_role` → Might; caster → Focus; Ranger
  → Finesse (override); Chancer → Luck (override).
- Might's existing weapon-damage model (`might_damage_bonus_per_reel()`) and the existing weapon
  level-empowerment layer (`weapon_effective_base_damage()`, +3%/level) are **not modified** by
  this plan.
- No per-ability rank-2 content or per-ability stat-scaling call sites are authored in this plan —
  that is explicitly separate future content-authoring work (spec "Open Questions").

---

## File Structure

- **Create:** `combat/stat_scaling.gd` — the pure diminishing-returns formula (`class_name
  StatScaling`, static functions, no state — same shape as `combat/rarity_visuals.gd`).
- **Create:** `tests/test_stat_scaling.gd`, `tests/test_power_stat_resolution.gd`,
  `tests/test_power_stat_weapon_multiplier.gd`, `tests/test_ability_magnitude_multiplier.gd`,
  `tests/test_ability_talent_row_rank.gd` — one focused headless test file per new behavior.
- **Modify:** `combat/resources/character_class.gd` — add `power_stat_override` +
  `resolve_power_stat()`.
- **Modify:** `combat/class_library.gd` — set `power_stat_override` for Ranger (Finesse) and
  Chancer (Luck); copy `power_stat` in `build_combatant()` is actually done from
  `character_class.gd`, not here (see Task 3).
- **Modify:** `combat/combatant.gd` — add `power_stat` field, `effective_power_stat_value()`,
  `power_stat_weapon_multiplier()` (folded into `outgoing_damage_multiplier()`),
  `ability_magnitude_multiplier()`, `ability_talent_row_rank()`.
- **Modify:** `tests/test_character_class.gd` — extend with `power_stat` copy-through assertions.
- **Modify:** `combat/combat.gd` — drive-by fix of the stale "L5/L7/L9" endgame-button tooltip.

---

## Task 1: `StatScaling` — the diminishing-returns formula

**Files:**
- Create: `combat/stat_scaling.gd`
- Test: `tests/test_stat_scaling.gd`

**Interfaces:**
- Produces: `StatScaling.multiplier(stat: int) -> float` — used by Tasks 4 and 5.

- [ ] **Step 1: Write the failing test**

Create `tests/test_stat_scaling.gd`:

```gdscript
extends SceneTree

# Headless test: StatScaling's diminishing-returns power-stat curve (design spec 2026-08-28 §2.3).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stat_scaling.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# stat 0 -> exactly neutral (1.0), so an un-invested class sees no change from today's baseline.
	_check(is_equal_approx(StatScaling.multiplier(0), 1.0), "stat 0 -> 1.0 (got %f)" % StatScaling.multiplier(0))

	# K = 4.0: stat 4 -> 1 + 4/(4+4) = 1.5.
	_check(is_equal_approx(StatScaling.multiplier(4), 1.5), "stat 4 -> 1.5 (got %f)" % StatScaling.multiplier(4))

	# stat 8 -> 1 + 8/(8+4) = 1.6667.
	_check(is_equal_approx(StatScaling.multiplier(8), 5.0 / 3.0), "stat 8 -> 1.6667 (got %f)" % StatScaling.multiplier(8))

	# Monotonic, decelerating: each successive +4 stat adds a SMALLER bonus than the last.
	var m0: float = StatScaling.multiplier(0)
	var m4: float = StatScaling.multiplier(4)
	var m8: float = StatScaling.multiplier(8)
	var m12: float = StatScaling.multiplier(12)
	_check(m4 > m0 and m8 > m4 and m12 > m8, "multiplier strictly increases with stat")
	_check((m4 - m0) > (m8 - m4) and (m8 - m4) > (m12 - m8), "each successive step's gain is smaller (diminishing returns)")

	# Never below 1.0, even for a defensively-clamped negative stat (shouldn't occur, but no crash/dip).
	_check(StatScaling.multiplier(-3) == 1.0, "negative stat clamps to 1.0, not undefined/negative")

	print(("STAT SCALING TEST PASSED" if _failures == 0 else "STAT SCALING TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stat_scaling.gd`
Expected: FAIL — `StatScaling` class does not exist yet (parse/identifier error).

- [ ] **Step 3: Write minimal implementation**

Create `combat/stat_scaling.gd`:

```gdscript
class_name StatScaling
extends RefCounted

## Diminishing-returns power-stat scaling curve (design spec 2026-08-28 §2.3): stat 0 -> exactly
## neutral (1.0); climbs steeply at low values, flattens toward an asymptote of 2.0 as stat grows.
## Pure + static, same convention as [RarityVisuals] — no state, trivially testable.
## [ASSUMPTION] K tuned by playtest (CLAUDE.md §4) — not a "correct" value yet.
const K: float = 4.0

## Returns the multiplier for [param stat] (an effective Stats field value, e.g. Might or Focus).
## Negative input clamps to 0 rather than producing a sub-1.0 or undefined result.
static func multiplier(stat: int) -> float:
	var s: int = maxi(stat, 0)
	if s == 0:
		return 1.0
	return 1.0 + float(s) / float(s + K)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stat_scaling.gd`
Expected: `STAT SCALING TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/stat_scaling.gd tests/test_stat_scaling.gd
git commit -m "feat(scaling): add StatScaling diminishing-returns formula"
```

---

## Task 2: `CharacterClass.resolve_power_stat()` + per-class overrides

**Files:**
- Modify: `combat/resources/character_class.gd`
- Modify: `combat/class_library.gd`
- Test: `tests/test_power_stat_resolution.gd`

**Interfaces:**
- Consumes: `CharacterClass.combat_role: StringName` (existing field, values `&"melee"`/
  `&"ranged"`/`&"caster"`).
- Produces: `CharacterClass.power_stat_override: StringName` (new exported field) and
  `CharacterClass.resolve_power_stat() -> StringName` — used by Task 3.

- [ ] **Step 1: Write the failing test**

Create `tests/test_power_stat_resolution.gd`:

```gdscript
extends SceneTree

# Headless test: CharacterClass.resolve_power_stat() (design spec 2026-08-28 §2.1).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_resolution.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# No override: melee -> Might.
	var melee: CharacterClass = CharacterClass.new()
	melee.combat_role = &"melee"
	_check(melee.resolve_power_stat() == &"might", "melee, no override -> might (got %s)" % melee.resolve_power_stat())

	# No override: ranged -> Might (the role default, before any per-class override).
	var ranged: CharacterClass = CharacterClass.new()
	ranged.combat_role = &"ranged"
	_check(ranged.resolve_power_stat() == &"might", "ranged, no override -> might (got %s)" % ranged.resolve_power_stat())

	# No override: caster -> Focus.
	var caster: CharacterClass = CharacterClass.new()
	caster.combat_role = &"caster"
	_check(caster.resolve_power_stat() == &"focus", "caster, no override -> focus (got %s)" % caster.resolve_power_stat())

	# Explicit override wins regardless of role.
	var overridden: CharacterClass = CharacterClass.new()
	overridden.combat_role = &"caster"
	overridden.power_stat_override = &"luck"
	_check(overridden.resolve_power_stat() == &"luck", "override always wins over role default (got %s)" % overridden.resolve_power_stat())

	# Real ClassLibrary classes resolve as designed: Ranger -> Finesse, Chancer -> Luck, everyone
	# else follows their role default.
	var expected: Dictionary = {
		&"warrior": &"might", &"vanguard": &"might", &"skirmisher": &"might",
		&"chancer": &"luck", &"ranger": &"finesse",
		&"seer": &"focus", &"warden": &"focus", &"summoner": &"focus",
	}
	for id: StringName in ClassLibrary.IDS:
		var cc: CharacterClass = ClassLibrary.make(id)
		var want: StringName = expected.get(id, &"")
		_check(cc.resolve_power_stat() == want, "%s resolves to %s (got %s)" % [id, want, cc.resolve_power_stat()])

	print(("POWER STAT RESOLUTION TEST PASSED" if _failures == 0 else "POWER STAT RESOLUTION TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_resolution.gd`
Expected: FAIL — `resolve_power_stat` / `power_stat_override` do not exist yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/resources/character_class.gd`, add near the existing `combat_role` field (after its
doc comment block, before `base_stats`):

```gdscript
## Explicit override of this class's power stat (design spec 2026-08-28 §2.1) — empty (default)
## means [method resolve_power_stat] derives it from [member combat_role] instead. Set this only
## when a class's identity stat differs from its role default (e.g. Ranger -> Finesse, Chancer ->
## Luck).
@export var power_stat_override: StringName = &""
```

Add the resolver method near the bottom of the file, just above `build_combatant()`:

```gdscript
## The stat that scales this class's ability magnitudes (all classes) and its weapon attacks (only
## when the result isn't Might — see [method Combatant.power_stat_weapon_multiplier]). Design spec
## 2026-08-28 §2.1: an explicit [member power_stat_override] always wins; otherwise melee/ranged
## default to Might and caster defaults to Focus.
func resolve_power_stat() -> StringName:
	if power_stat_override != &"":
		return power_stat_override
	if combat_role == &"caster":
		return &"focus"
	return &"might"
```

In `combat/class_library.gd`, add one line to the Ranger case (near its `combat_role = &"ranged"`
line) and one to the Chancer case (near its `combat_role = &"ranged"` line):

```gdscript
			c.power_stat_override = &"finesse"  # Ranger scales off Finesse, not the ranged default (Might)
```

```gdscript
			c.power_stat_override = &"luck"  # Chancer scales off Luck, not the ranged default (Might)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_resolution.gd`
Expected: `POWER STAT RESOLUTION TEST PASSED`

- [ ] **Step 5: Run the full existing class-library/character-class suites for regression**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_class.gd`
Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_roles.gd`
Expected: both still PASS (a new exported field defaulting to `&""` and one new method must not
change any existing `combat_role`/build behavior).

- [ ] **Step 6: Commit**

```bash
git add combat/resources/character_class.gd combat/class_library.gd tests/test_power_stat_resolution.gd
git commit -m "feat(scaling): add CharacterClass.resolve_power_stat() with per-class overrides"
```

---

## Task 3: Carry `power_stat` onto `Combatant`

**Files:**
- Modify: `combat/combatant.gd`
- Modify: `combat/resources/character_class.gd`
- Test: `tests/test_character_class.gd` (extend)

**Interfaces:**
- Consumes: `CharacterClass.resolve_power_stat()` (Task 2).
- Produces: `Combatant.power_stat: StringName` and `Combatant.effective_power_stat_value() -> int`
  — used by Tasks 4 and 5.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_character_class.gd`, just before the final `print(...)` line:

```gdscript
	# power_stat is copied from resolve_power_stat() at build time (design spec 2026-08-28 §2.1/§3),
	# and its live value reads correctly off effective_stats().
	var pc: CharacterClass = CharacterClass.new()
	pc.combat_role = &"caster"
	pc.weapon_type = slashing; pc.defense_type = slashing; pc.reel_count = 2
	var ps: Stats = Stats.new(); ps.focus = 4
	pc.base_stats = ps
	var built_caster: Combatant = pc.build_combatant(true)
	_check(built_caster.power_stat == &"focus", "caster combatant's power_stat is focus (got %s)" % built_caster.power_stat)
	_check(built_caster.effective_power_stat_value() == 4, "effective_power_stat_value reads Focus 4 off effective_stats (got %d)" % built_caster.effective_power_stat_value())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_class.gd`
Expected: FAIL — `power_stat` / `effective_power_stat_value` don't exist on `Combatant` yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, add the field right after the existing `class_id` declaration
(combatant.gd:179):

```gdscript
## The stat that scales this combatant's ability magnitudes and (conditionally) weapon attacks —
## copied from CharacterClass.resolve_power_stat() at build time (design spec 2026-08-28 §2.1).
## Defaults to Might so a Combatant built without going through a CharacterClass (most existing
## tests) keeps today's exact behavior.
var power_stat: StringName = &"might"
```

Add the accessor right after `effective_stats()` (combatant.gd:590 area):

```gdscript
## The live value of [member power_stat], read off effective_stats() by name (design spec
## 2026-08-28 §2.1). Resources expose exported fields to Object.get() by name, so this stays a
## one-line lookup rather than a per-stat match.
func effective_power_stat_value() -> int:
	return effective_stats().get(power_stat)
```

In `combat/resources/character_class.gd`'s `build_combatant()`, add one line alongside the other
identity copies (next to `c.class_id = class_id`):

```gdscript
	c.power_stat = resolve_power_stat()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_class.gd`
Expected: `CHARACTER CLASS TEST PASSED`

- [ ] **Step 5: Regression — full existing Combatant/Stats suites**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stats.gd`
Expected: PASS (a Combatant with no `CharacterClass` involved still defaults `power_stat` to
`&"might"`, so nothing that predates this field changes behavior).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/resources/character_class.gd tests/test_character_class.gd
git commit -m "feat(scaling): carry power_stat from CharacterClass onto Combatant"
```

---

## Task 4: `power_stat_weapon_multiplier()` — weapon-attack scaling for non-Might classes

**Files:**
- Modify: `combat/combatant.gd`
- Test: `tests/test_power_stat_weapon_multiplier.gd`

**Interfaces:**
- Consumes: `StatScaling.multiplier()` (Task 1), `Combatant.power_stat` /
  `effective_power_stat_value()` (Task 3).
- Produces: `Combatant.power_stat_weapon_multiplier() -> float`, folded into the existing
  `Combatant.outgoing_damage_multiplier()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_power_stat_weapon_multiplier.gd`:

```gdscript
extends SceneTree

# Headless test: power_stat_weapon_multiplier() and its fold into outgoing_damage_multiplier()
# (design spec 2026-08-28 §2.2). Might-power classes must stay EXACTLY neutral (regression); any
# other power stat gets the new StatScaling curve.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_weapon_multiplier.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Might-power combatant, ANY Might value -> exactly 1.0 (Might's own damage path is untouched;
	# this is a regression guard for every existing melee/ranged combatant).
	var might_c: Combatant = Combatant.new()
	might_c.power_stat = &"might"
	var ms: Stats = Stats.new(); ms.might = 6
	might_c.base_stats = ms
	_check(might_c.power_stat_weapon_multiplier() == 1.0, "Might power_stat -> weapon multiplier stays 1.0 (got %f)" % might_c.power_stat_weapon_multiplier())
	_check(might_c.outgoing_damage_multiplier() == 1.0, "outgoing_damage_multiplier unaffected for a Might-power combatant with no other effects (got %f)" % might_c.outgoing_damage_multiplier())

	# Focus-power combatant with Focus 4 -> StatScaling.multiplier(4) = 1.5, and that flows through
	# outgoing_damage_multiplier() since no other multiplier effects are active.
	var focus_c: Combatant = Combatant.new()
	focus_c.power_stat = &"focus"
	var fs: Stats = Stats.new(); fs.focus = 4
	focus_c.base_stats = fs
	_check(is_equal_approx(focus_c.power_stat_weapon_multiplier(), 1.5), "Focus 4 power_stat -> weapon multiplier 1.5 (got %f)" % focus_c.power_stat_weapon_multiplier())
	_check(is_equal_approx(focus_c.outgoing_damage_multiplier(), 1.5), "outgoing_damage_multiplier includes the Focus curve (got %f)" % focus_c.outgoing_damage_multiplier())

	# 0 Focus -> neutral, same as Might's baseline (no regression for an un-invested caster).
	var zero_focus: Combatant = Combatant.new()
	zero_focus.power_stat = &"focus"
	_check(zero_focus.power_stat_weapon_multiplier() == 1.0, "0 Focus -> 1.0 (got %f)" % zero_focus.power_stat_weapon_multiplier())

	print(("POWER STAT WEAPON MULTIPLIER TEST PASSED" if _failures == 0 else "POWER STAT WEAPON MULTIPLIER TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_weapon_multiplier.gd`
Expected: FAIL — `power_stat_weapon_multiplier` doesn't exist yet, and `outgoing_damage_multiplier()`
doesn't yet include it.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, add the new method right after `might_damage_bonus_per_reel()`
(combatant.gd:1133-1136):

```gdscript
## Diminishing-returns multiplier applied to reel-based damage (weapon swings AND any
## ability-added attack reel, since both flow through the same resolve_combat_phase() spin —
## design spec 2026-08-28 §2.2) for any combatant whose power_stat ISN'T Might. Might-power
## combatants stay exactly 1.0 here, leaving might_damage_bonus_per_reel()'s existing flat model
## completely untouched.
func power_stat_weapon_multiplier() -> float:
	if power_stat == &"might" or power_stat == &"":
		return 1.0
	return StatScaling.multiplier(effective_power_stat_value())
```

Modify `outgoing_damage_multiplier()` (combatant.gd:1143-1149) to fold it in:

```gdscript
func outgoing_damage_multiplier(defender: Combatant = null) -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and not e.affects_incoming:
			total *= e.effective_magnitude()
	total *= passive_outgoing_multiplier(defender)
	total *= power_stat_weapon_multiplier()
	return total
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_weapon_multiplier.gd`
Expected: `POWER STAT WEAPON MULTIPLIER TEST PASSED`

- [ ] **Step 5: Regression — every suite that exercises `outgoing_damage_multiplier()`**

Run each of these (all default-construct `Combatant`s with `power_stat` defaulting to `&"might"`,
so none should change):

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_loop.gd`
Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_damage_multiplier.gd`
Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_might_scaling.gd`

Expected: all three still PASS unchanged.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd tests/test_power_stat_weapon_multiplier.gd
git commit -m "feat(scaling): fold power_stat_weapon_multiplier into outgoing_damage_multiplier"
```

---

## Task 5: `ability_magnitude_multiplier()` — the ability-scaling building block

**Files:**
- Modify: `combat/combatant.gd`
- Test: `tests/test_ability_magnitude_multiplier.gd`

**Interfaces:**
- Consumes: `StatScaling.multiplier()` (Task 1), `Combatant.effective_power_stat_value()` (Task 3).
- Produces: `Combatant.ability_magnitude_multiplier() -> float` — intentionally not yet called by
  any ability's own magnitude calculation (that wiring is future per-class content work, spec
  "Open Questions"); this task only builds and tests the standalone method.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_magnitude_multiplier.gd`:

```gdscript
extends SceneTree

# Headless test: ability_magnitude_multiplier() (design spec 2026-08-28 §2.2/§1.2) — unlike
# power_stat_weapon_multiplier(), this scales for EVERY power stat including Might.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_magnitude_multiplier.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Might power_stat with Might 4 -> StatScaling.multiplier(4) = 1.5 (NOT 1.0 — this is the
	# key difference from power_stat_weapon_multiplier(), which stays neutral for Might).
	var might_c: Combatant = Combatant.new()
	might_c.power_stat = &"might"
	var ms: Stats = Stats.new(); ms.might = 4
	might_c.base_stats = ms
	_check(is_equal_approx(might_c.ability_magnitude_multiplier(), 1.5), "Might 4 ability magnitude multiplier -> 1.5 (got %f)" % might_c.ability_magnitude_multiplier())

	# Focus power_stat with Focus 4 -> also 1.5 (same curve, different source stat).
	var focus_c: Combatant = Combatant.new()
	focus_c.power_stat = &"focus"
	var fs: Stats = Stats.new(); fs.focus = 4
	focus_c.base_stats = fs
	_check(is_equal_approx(focus_c.ability_magnitude_multiplier(), 1.5), "Focus 4 ability magnitude multiplier -> 1.5 (got %f)" % focus_c.ability_magnitude_multiplier())

	# 0 power stat -> neutral 1.0 (no ability-magnitude change for an un-invested character).
	var zero_c: Combatant = Combatant.new()
	_check(zero_c.ability_magnitude_multiplier() == 1.0, "0 power stat -> 1.0 (got %f)" % zero_c.ability_magnitude_multiplier())

	print(("ABILITY MAGNITUDE MULTIPLIER TEST PASSED" if _failures == 0 else "ABILITY MAGNITUDE MULTIPLIER TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_magnitude_multiplier.gd`
Expected: FAIL — `ability_magnitude_multiplier` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, add right after `power_stat_weapon_multiplier()` (Task 4):

```gdscript
## Diminishing-returns multiplier for ability/heal magnitude values (design spec 2026-08-28
## §2.2/§1.2) — applied off this combatant's power_stat regardless of WHICH stat that is (unlike
## power_stat_weapon_multiplier(), a Might-power combatant IS scaled here). Not yet consumed by
## any ability's own magnitude calculation: per-ability wiring (rider effect magnitudes, minion
## stage values, flat heal amounts) is a separate future content-authoring pass — this is the
## building block that pass will call.
func ability_magnitude_multiplier() -> float:
	return StatScaling.multiplier(effective_power_stat_value())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_magnitude_multiplier.gd`
Expected: `ABILITY MAGNITUDE MULTIPLIER TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_ability_magnitude_multiplier.gd
git commit -m "feat(scaling): add ability_magnitude_multiplier building block"
```

---

## Task 6: `ability_talent_row_rank()` — automatic level-gated rank lookup

**Files:**
- Modify: `combat/combatant.gd`
- Test: `tests/test_ability_talent_row_rank.gd`

**Interfaces:**
- Consumes: `Combatant.level` (existing), `Combatant.ability_talent_row_unlock_level()` (existing,
  combatant.gd:760-768).
- Produces: `Combatant.ability_talent_row_rank(row_id: StringName) -> int` — returns `1` or `2`;
  the entry point future per-ability content will call to pick which authored value set to use.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talent_row_rank.gd`:

```gdscript
extends SceneTree

# Headless test: ability_talent_row_rank() (design spec 2026-08-28 §1.1) — automatic, level-gated,
# reuses ability_talent_row_unlock_level()'s existing thresholds for a second, independent purpose.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talent_row_rank.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()

	# Below every threshold: every row is rank 1.
	c.level = 4
	for row_id: StringName in [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]:
		_check(c.ability_talent_row_rank(row_id) == 1, "level 4, %s -> rank 1 (got %d)" % [row_id, c.ability_talent_row_rank(row_id)])

	# Level 5: ONLY base_ability ranks up — the others stay rank 1 until their own threshold.
	c.level = 5
	_check(c.ability_talent_row_rank(&"base_ability") == 2, "level 5, base_ability -> rank 2 (got %d)" % c.ability_talent_row_rank(&"base_ability"))
	_check(c.ability_talent_row_rank(&"ability_l2") == 1, "level 5, ability_l2 still rank 1 (got %d)" % c.ability_talent_row_rank(&"ability_l2"))

	# Level 8: base_ability/l2/l3/l4 are all rank 2; passive/ultimate still rank 1.
	c.level = 8
	for row_id: StringName in [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4"]:
		_check(c.ability_talent_row_rank(row_id) == 2, "level 8, %s -> rank 2 (got %d)" % [row_id, c.ability_talent_row_rank(row_id)])
	_check(c.ability_talent_row_rank(&"passive") == 1, "level 8, passive still rank 1 (got %d)" % c.ability_talent_row_rank(&"passive"))
	_check(c.ability_talent_row_rank(&"ultimate") == 1, "level 8, ultimate still rank 1 (got %d)" % c.ability_talent_row_rank(&"ultimate"))

	# Level 9: passive ranks up (amplified); Ultimate does not yet (flipped order, spec §1.1).
	c.level = 9
	_check(c.ability_talent_row_rank(&"passive") == 2, "level 9, passive -> rank 2 (got %d)" % c.ability_talent_row_rank(&"passive"))
	_check(c.ability_talent_row_rank(&"ultimate") == 1, "level 9, ultimate still rank 1 (got %d)" % c.ability_talent_row_rank(&"ultimate"))

	# Level 10: Ultimate ranks up too. Everything is rank 2.
	c.level = 10
	for row_id: StringName in [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]:
		_check(c.ability_talent_row_rank(row_id) == 2, "level 10, %s -> rank 2 (got %d)" % [row_id, c.ability_talent_row_rank(row_id)])

	# Rank-up is independent of talent picks: reaching level 5 doesn't touch pick_ability_talent state.
	_check(c.ability_talent_picks.is_empty(), "no talent picks were made just by leveling (got %d entries)" % c.ability_talent_picks.size())

	print(("ABILITY TALENT ROW RANK TEST PASSED" if _failures == 0 else "ABILITY TALENT ROW RANK TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talent_row_rank.gd`
Expected: FAIL — `ability_talent_row_rank` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, add right after `ability_talent_row_unlocked()` (combatant.gd:770-771):

```gdscript
## The current RANK (1 or 2) of the ability tied to [param row_id] (design spec 2026-08-28 §1.1) —
## an AUTOMATIC, level-gated bump, entirely independent of [method pick_ability_talent]'s choice on
## the same row. Reuses [method ability_talent_row_unlock_level]'s existing thresholds for a
## second, unrelated purpose: rank 2 unlocks at exactly the level that row's talent pick does.
func ability_talent_row_rank(row_id: StringName) -> int:
	return 2 if level >= ability_talent_row_unlock_level(row_id) else 1
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talent_row_rank.gd`
Expected: `ABILITY TALENT ROW RANK TEST PASSED`

- [ ] **Step 5: Regression — existing talent-row tests**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_summoner.gd`
Expected: PASS unchanged (a new read-only method alongside the existing unlock-level lookup must
not affect talent-pick behavior).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd tests/test_ability_talent_row_rank.gd
git commit -m "feat(scaling): add automatic ability_talent_row_rank lookup"
```

---

## Task 7: Drive-by fix — stale "L5/L7/L9" endgame-button tooltip

**Files:**
- Modify: `combat/combat.gd` (~line 1447)

**Interfaces:**
- None (UI string only — no new interface).

- [ ] **Step 1: Confirm the current stale text**

Run: `grep -n "L5/L7/L9" combat/combat.gd`
Expected output includes line ~1447: `endgame_btn.tooltip_text = "Spawn PCs at level 9 — unlocks every L5/L7/L9 ability + the Ultimate."`

- [ ] **Step 2: Fix the tooltip text**

In `combat/combat.gd`, change:

```gdscript
	endgame_btn.tooltip_text = "Spawn PCs at level 9 — unlocks every L5/L7/L9 ability + the Ultimate."
```

to:

```gdscript
	endgame_btn.tooltip_text = "Spawn PCs at level 10 — unlocks every ability (L2/L3/L4) + the Ultimate + every talent-track pick, all ranks maxed."
```

- [ ] **Step 3: Verify no stale references remain**

Run: `grep -n "L5/L7/L9\|Spawn PCs at level 9" combat/combat.gd`
Expected: no matches.

- [ ] **Step 4: Regression — the endgame debug-button test**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_endgame_level.gd`
Expected: PASS unchanged (no test asserts on this tooltip's exact string).

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd
git commit -m "fix(ui): correct stale L5/L7/L9 endgame-button tooltip"
```

---

## Final Verification

- [ ] **Run every new test file together**

Run each of:
```
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stat_scaling.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_resolution.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_weapon_multiplier.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_magnitude_multiplier.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talent_row_rank.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_class.gd
```
Expected: all PASS.

- [ ] **Grep-verify no stale `Godot exit-code-blind` false pass** (CLAUDE.md known gotcha): confirm
  each run's printed output literally contains `PASSED`, not just an exit code of 0 — a thrown
  script error mid-`_initialize()` can otherwise exit 0 while silently skipping later checks.

- [ ] **Spot-check in-editor:** open the project, click the "ENDGAME" debug button (spawns PCs at
  level 10) and confirm the new tooltip text reads correctly and no console errors appear on spawn
  (this exercises `build_combatant()` → `resolve_power_stat()` → `power_stat` copy for every real
  `ClassLibrary` class in one pass).

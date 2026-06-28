# Enemy AI v1 + Enemy Variation + Selection-Screen Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the N-vs-M party prototype a realistic test: enemies vary by weapon/role, two borrow a PC base ability, the AI targets by type effectiveness (then lowest HP) and uses its abilities; plus selection-screen polish (multi-line tooltips, role badges, centered columns).

**Architecture:** Two pure new helpers — `RoleVisuals` (role → label/color) and `EnemyAI` (`pick_target`) — keep logic isolated and unit-testable. `CharacterClass` gains a `combat_role` field; `EnemyLibrary` gains a role lookup + borrowed abilities + small stamina pools. `combat.gd` swaps its placeholder targeting for `EnemyAI.pick_target`, adds a greedy enemy ability-stage step, and routes the enemy commit through the same `MainPhasePlan.commit()` + Hunter's-Mark-attach path PCs use (extracted into a shared helper).

**Tech Stack:** Godot 4.6.3-stable, GDScript (no C#), Resource-based data, headless SceneTree tests.

## Global Constraints

- Engine Godot 4.6.3-stable; language GDScript only (no C#). [CLAUDE.md §2]
- Naming: classes PascalCase, files snake_case, signals snake_case past-tense, handlers `_on_<emitter>_<signal>`. [CLAUDE.md §2]
- Prefer static typing in all signatures/vars. [CLAUDE.md §2]
- All combat damage/heal math uses `ceil` (round up). [memory: round-up-damage-healing] — no new math here, but honor it if any arises.
- Balance numbers are `[ASSUMPTION]` placeholders — build them as editable data, do not "balance" them. [CLAUDE.md §4]
- Badges + role data are **selection-screen-only** this iteration; do NOT touch `CombatantPanel`. [spec §6]
- No enemy Ultimates; no new damage types or weapon-category data axis (dagger/bow/slingshot are flavor over the existing six types). [spec §6]

### Test runner (every test step)

From the repo working dir (`C:\bunnies\bunnies-main\bunnies`), the Bash tool's cwd:

```bash
GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
# After adding a NEW class_name, refresh the class cache FIRST or --script can't resolve it:
"$GODOT" --headless --path . --editor --quit
# Run one suite (bound it — a parse error idles the SceneTree forever):
timeout 60 "$GODOT" --headless --path . --script res://tests/test_<name>.gd
```

Expected on success: the suite prints `… TEST PASSED` and exits 0. On failure it prints `FAIL:` lines + `… TEST FAILED: N` and exits non-zero.

---

## Task 1: `RoleVisuals` helper

**Files:**
- Create: `combat/ui/role_visuals.gd`
- Test: `tests/test_role_visuals.gd`

**Interfaces:**
- Produces: `RoleVisuals.label(role: StringName) -> String`, `RoleVisuals.color(role: StringName) -> Color`. Roles: `&"melee"`, `&"ranged"`, `&"caster"`; unknown → `"—"` / grey.

- [ ] **Step 1: Write the failing test**

`tests/test_role_visuals.gd`:
```gdscript
extends SceneTree

# Headless test: RoleVisuals.label/color — selection-screen combat-role badge mapping
# (spec 2026-06-28 §4.2). Pure/static; no scene.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_role_visuals.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(RoleVisuals.label(&"melee") == "MELEE", "melee label")
	_check(RoleVisuals.label(&"ranged") == "RANGED", "ranged label")
	_check(RoleVisuals.label(&"caster") == "CASTER", "caster label")
	_check(RoleVisuals.label(&"nonsense") == "—", "unknown role label -> dash")

	# Each known role has a distinct, non-white identity color; unknown -> grey default.
	var m: Color = RoleVisuals.color(&"melee")
	var r: Color = RoleVisuals.color(&"ranged")
	var c: Color = RoleVisuals.color(&"caster")
	_check(m != r and r != c and m != c, "three roles have distinct colors")
	_check(RoleVisuals.color(&"nonsense") == Color(0.5, 0.5, 0.5), "unknown role color -> grey")

	print(("ROLE VISUALS TEST PASSED" if _failures == 0 else "ROLE VISUALS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Refresh cache, run test, verify it fails**

```bash
GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
"$GODOT" --headless --path . --editor --quit
timeout 60 "$GODOT" --headless --path . --script res://tests/test_role_visuals.gd
```
Expected: FAIL — `RoleVisuals` is not a known class (parse/identifier error).

- [ ] **Step 3: Write `RoleVisuals`**

`combat/ui/role_visuals.gd`:
```gdscript
class_name RoleVisuals
extends RefCounted

## Shared presentation for the three combat roles shown on the character-select screen (spec
## 2026-06-28 §4.2). The ONE place role -> label/color lives. Pure + static — no state, trivially
## testable. Selection-screen ONLY for now; eventual character-creation screens host the production
## badge. [ASSUMPTION] palette (mirrors TypeVisuals' placeholder-color approach).

## Uppercase badge label for a role. Unknown -> "—" (defensive default).
static func label(role: StringName) -> String:
	match role:
		&"melee": return "MELEE"
		&"ranged": return "RANGED"
		&"caster": return "CASTER"
		_: return "—"

## Identity color for a role's badge pill. Unknown -> neutral grey.
static func color(role: StringName) -> Color:
	match role:
		&"melee": return Color(0.78, 0.32, 0.30)   # warm red
		&"ranged": return Color(0.42, 0.66, 0.38)  # green
		&"caster": return Color(0.52, 0.44, 0.82)  # blue-violet
		_: return Color(0.5, 0.5, 0.5)             # grey
```

- [ ] **Step 4: Refresh cache, run test, verify it passes**

```bash
"$GODOT" --headless --path . --editor --quit
timeout 60 "$GODOT" --headless --path . --script res://tests/test_role_visuals.gd
```
Expected: PASS — `ROLE VISUALS TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/role_visuals.gd tests/test_role_visuals.gd
git commit -m "feat(ui): RoleVisuals helper for combat-role badges

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `combat_role` data on classes + enemies

**Files:**
- Modify: `combat/resources/character_class.gd` (add `combat_role` export)
- Modify: `combat/class_library.gd` (set `combat_role` per class)
- Modify: `combat/enemy_library.gd` (add a `role(id)` lookup)
- Test: `tests/test_combat_roles.gd`

**Interfaces:**
- Consumes: `RoleVisuals.label` (Task 1) for validity.
- Produces: `CharacterClass.combat_role: StringName`; `EnemyLibrary.role(id: StringName) -> StringName`. Player roles per spec §2; enemy roles: rat/ferret = `&"melee"`, stoat = `&"ranged"`.

- [ ] **Step 1: Write the failing test**

`tests/test_combat_roles.gd`:
```gdscript
extends SceneTree

# Headless test: every class/enemy has a valid combat role (spec 2026-06-28 §2). Pure data.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_roles.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

const VALID: Array[StringName] = [&"melee", &"ranged", &"caster"]

func _initialize() -> void:
	# Spot-check the locked assignments.
	_check(ClassLibrary.make(&"warrior").combat_role == &"melee", "warrior -> melee")
	_check(ClassLibrary.make(&"ranger").combat_role == &"ranged", "ranger -> ranged")
	_check(ClassLibrary.make(&"chancer").combat_role == &"ranged", "chancer -> ranged (slingshot)")
	_check(ClassLibrary.make(&"seer").combat_role == &"caster", "seer -> caster")
	_check(ClassLibrary.make(&"warden").combat_role == &"caster", "warden -> caster")

	# Every class has a valid role.
	for id: StringName in ClassLibrary.IDS:
		_check(ClassLibrary.make(id).combat_role in VALID, "class %s has valid role" % id)

	# Every enemy has a valid role; stoat is ranged.
	for id: StringName in EnemyLibrary.IDS:
		_check(EnemyLibrary.role(id) in VALID, "enemy %s has valid role" % id)
	_check(EnemyLibrary.role(&"stoat") == &"ranged", "stoat -> ranged (bow)")
	_check(EnemyLibrary.role(&"ferret") == &"melee", "ferret -> melee (dagger)")

	print(("COMBAT ROLES TEST PASSED" if _failures == 0 else "COMBAT ROLES TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test, verify it fails**

```bash
timeout 60 "$GODOT" --headless --path . --script res://tests/test_combat_roles.gd
```
Expected: FAIL — `combat_role` not a property / `EnemyLibrary.role` not found.

- [ ] **Step 3a: Add the field to `CharacterClass`**

In `combat/resources/character_class.gd`, after the `species` export (line ~12), add:
```gdscript
## Coarse combat role for the selection-screen badge/tooltip (spec 2026-06-28 §2): &"melee" /
## &"ranged" / &"caster". Display-only metadata — the AI reads the type chart, not this label.
@export var combat_role: StringName = &"melee"
```

- [ ] **Step 3b: Set the role per class in `ClassLibrary`**

In `combat/class_library.gd`, add `c.combat_role = …` to each `match` arm (alongside the existing `c.` assignments):
- `&"warrior"`: `c.combat_role = &"melee"`
- `&"vanguard"`: `c.combat_role = &"melee"`
- `&"skirmisher"`: `c.combat_role = &"melee"`
- `&"chancer"`: `c.combat_role = &"ranged"`
- `&"ranger"`: `c.combat_role = &"ranged"`
- `&"seer"`: `c.combat_role = &"caster"`
- `&"warden"`: `c.combat_role = &"caster"`

- [ ] **Step 3c: Add the enemy role lookup**

In `combat/enemy_library.gd`, after the `label(id)` function, add:
```gdscript
## Combat role for the selection-screen badge (spec 2026-06-28 §2). Display-only; the AI reads the
## type chart, not this label.
static func role(id: StringName) -> StringName:
	match id:
		&"stoat": return &"ranged"   # bow
		_: return &"melee"           # rat (cudgel), ferret (dagger)
```

- [ ] **Step 4: Run test, verify it passes**

```bash
timeout 60 "$GODOT" --headless --path . --script res://tests/test_combat_roles.gd
```
Expected: PASS — `COMBAT ROLES TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/character_class.gd combat/class_library.gd combat/enemy_library.gd tests/test_combat_roles.gd
git commit -m "feat(data): combat_role on classes + enemies (selection-screen metadata)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `EnemyAI.pick_target` — type-effectiveness targeting

**Files:**
- Create: `combat/enemy_ai.gd`
- Test: `tests/test_enemy_ai.gd`

**Interfaces:**
- Consumes: `Combatant.weapon_type() -> DamageType`, `Combatant.defense_type: DamageType`, `Combatant.is_alive() -> bool`, `Combatant.hp: int`; `DamageType.multiplier_against(defender: DamageType) -> float`.
- Produces: `EnemyAI.pick_target(attacker: Combatant, pcs: Array[Combatant]) -> Combatant` — super-effective (`>1.0`) preferred, then neutral (`≈1.0`), then resisted (`<1.0`); within the chosen tier the lowest-`hp` PC wins (ties resolve to first in `pcs` order). Returns `null` if no living PC.

- [ ] **Step 1: Write the failing test**

`tests/test_enemy_ai.gd`:
```gdscript
extends SceneTree

# Headless test: EnemyAI.pick_target — first-iteration enemy targeting (spec 2026-06-28 §3.1).
# Pure/static; we hand-build minimal DamageType + Combatant objects (no scene).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_ai.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

# Build a DamageType whose row gives `mult` against the single defender type we use (id 1),
# and 1.0 against everything else.
func _atk(mult_vs_def: float) -> DamageType:
	var dt := DamageType.new()
	dt.type = DamageType.Type.SLASHING
	dt.default_multiplier = 1.0
	dt.effectiveness = {DamageType.Type.PIERCING: mult_vs_def}  # PIERCING = the defenders' def type
	return dt

func _def() -> DamageType:
	var dt := DamageType.new()
	dt.type = DamageType.Type.PIERCING
	return dt

# Minimal PC: alive, given hp + defense_type. (weapon/role irrelevant — it's a target, not attacker.)
func _pc(hp: int) -> Combatant:
	var c := Combatant.new()
	c.is_player = true
	c.defense_type = _def()
	c.base_max_hp = 1000
	c.apply_stats()
	c.start_combat()
	c.hp = hp
	return c

# Minimal attacker: a Weapon of one reel typed `atk` so weapon_type() returns it.
func _enemy(atk: DamageType) -> Combatant:
	var c := Combatant.new()
	c.is_player = false
	var w := Weapon.new()
	w.base_damage = 5.0
	w.reels.append(ActionReel.make_default(atk))
	c.weapon = w
	return c

func _initialize() -> void:
	# No living PCs -> null.
	_check(EnemyAI.pick_target(_enemy(_atk(1.0)), []) == null, "empty -> null")

	# Super-effective beats neutral even when the neutral target is lower HP.
	var super_eff := _pc(900)     # attacker is super-effective vs this one
	var neutral := _pc(100)
	# super_eff has def PIERCING and attacker mult 1.25 vs PIERCING; neutral also PIERCING but we want a
	# NEUTRAL matchup, so give `neutral` a different def type the attacker is 1.0 against.
	var neutral2 := Combatant.new(); neutral2.is_player = true
	neutral2.defense_type = DamageType.new(); (neutral2.defense_type as DamageType).type = DamageType.Type.EARTH
	neutral2.base_max_hp = 1000; neutral2.apply_stats(); neutral2.start_combat(); neutral2.hp = 100
	var atk125 := _atk(1.25)  # 1.25 vs PIERCING, 1.0 vs EARTH (default)
	_check(EnemyAI.pick_target(_enemy(atk125), [neutral2, super_eff]) == super_eff,
		"super-effective chosen over lower-HP neutral")

	# Within the same tier, lowest HP wins.
	var a := _pc(500)
	var b := _pc(200)
	var c := _pc(800)
	_check(EnemyAI.pick_target(_enemy(_atk(1.0)), [a, b, c]) == b, "neutral tier -> lowest HP (b)")

	# HP tie within a tier -> first in order.
	var d := _pc(300)
	var e := _pc(300)
	_check(EnemyAI.pick_target(_enemy(_atk(1.0)), [d, e]) == d, "HP tie -> first in order")

	# All resisted -> still attacks the lowest-HP of them (no passing the turn).
	var r1 := _pc(400)
	var r2 := _pc(150)
	_check(EnemyAI.pick_target(_enemy(_atk(0.75)), [r1, r2]) == r2, "all-resisted fallback -> lowest HP")

	# Dead PCs are skipped.
	var dead := _pc(500); dead.hp = 0
	var live := _pc(600)
	_check(EnemyAI.pick_target(_enemy(_atk(1.0)), [dead, live]) == live, "dead PC skipped")

	print(("ENEMY AI TEST PASSED" if _failures == 0 else "ENEMY AI TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Refresh cache, run test, verify it fails**

```bash
"$GODOT" --headless --path . --editor --quit
timeout 60 "$GODOT" --headless --path . --script res://tests/test_enemy_ai.gd
```
Expected: FAIL — `EnemyAI` is not a known class.

- [ ] **Step 3: Write `EnemyAI`**

`combat/enemy_ai.gd`:
```gdscript
class_name EnemyAI
extends RefCounted

## First-iteration enemy targeting policy (spec 2026-06-28 §3.1). Pure + static so it's unit-testable
## without a scene and a future policy swaps only this. Prefers a super-effective matchup, then a
## neutral one, then (only resisted left) attacks anyway; within the chosen tier the lowest-HP PC wins,
## which is also the tie-break. The orchestrator (combat.gd) owns ability use + the actual attack.

## Returns the living PC this [param attacker] should hit, or null if none are alive.
static func pick_target(attacker: Combatant, pcs: Array[Combatant]) -> Combatant:
	if attacker == null or attacker.weapon_type() == null:
		return null
	var atk: DamageType = attacker.weapon_type()
	var supereff: Array[Combatant] = []
	var neutral: Array[Combatant] = []
	var resisted: Array[Combatant] = []
	for pc: Combatant in pcs:
		if pc == null or not pc.is_alive():
			continue
		var m: float = atk.multiplier_against(pc.defense_type)
		if m > 1.0 and not is_equal_approx(m, 1.0):
			supereff.append(pc)
		elif is_equal_approx(m, 1.0):
			neutral.append(pc)
		else:
			resisted.append(pc)
	var tier: Array[Combatant] = supereff if not supereff.is_empty() else (neutral if not neutral.is_empty() else resisted)
	return _lowest_hp(tier)

## Lowest current-HP combatant in [param cands] (ties -> first in order). Null if empty.
static func _lowest_hp(cands: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	for c: Combatant in cands:
		if best == null or c.hp < best.hp:
			best = c
	return best
```

- [ ] **Step 4: Refresh cache, run test, verify it passes**

```bash
"$GODOT" --headless --path . --editor --quit
timeout 60 "$GODOT" --headless --path . --script res://tests/test_enemy_ai.gd
```
Expected: PASS — `ENEMY AI TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/enemy_ai.gd tests/test_enemy_ai.gd
git commit -m "feat(ai): EnemyAI.pick_target — type-effectiveness targeting (super > neutral > resisted, lowest-HP)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Enemy variation — ferret Flurry, stoat Hunter's Mark, small pools

**Files:**
- Modify: `combat/enemy_library.gd` (`_build` gains ability/pool params; ferret + stoat get an ability)
- Test: `tests/test_enemy_variation.gd`

**Interfaces:**
- Consumes: existing `Combatant` fields `ability_id` / `ability_cost` / `ability_resource` / `ultimate_id`, `ResourcePool` (`stamina`, `regen_per_turn`), `Combatant.base_max_stamina`.
- Produces: `EnemyLibrary.make(&"ferret")` → `ability_id == &"flurry"`, has a `resource_pool` affording its cost, `ultimate_id == &""`. `EnemyLibrary.make(&"stoat")` → `ability_id == &"hunters_mark"`, pool affords its cost, `ultimate_id == &""`. `EnemyLibrary.make(&"rat")` → `ability_id == &""`, `resource_pool == null`.

- [ ] **Step 1: Write the failing test**

`tests/test_enemy_variation.gd`:
```gdscript
extends SceneTree

# Headless test: EnemyLibrary variation (spec 2026-06-28 §2) — ferret = Flurry, stoat = Hunter's Mark,
# both with a stamina pool that affords the ability and NO Ultimate; rat = plain (no ability/pool).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_variation.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var ferret: Combatant = EnemyLibrary.make(&"ferret")
	_check(ferret.ability_id == &"flurry", "ferret ability = flurry")
	_check(ferret.resource_pool != null, "ferret has a resource pool")
	_check(ferret.resource_pool != null and ferret.resource_pool.can_afford({&"stamina": ferret.ability_cost}),
		"ferret pool affords Flurry")
	_check(ferret.ultimate_id == &"", "ferret has NO Ultimate")

	var stoat: Combatant = EnemyLibrary.make(&"stoat")
	_check(stoat.ability_id == &"hunters_mark", "stoat ability = hunters_mark")
	_check(stoat.resource_pool != null and stoat.resource_pool.can_afford({&"stamina": stoat.ability_cost}),
		"stoat pool affords Hunter's Mark")
	_check(stoat.ability_resource == &"stamina", "stoat ability spends stamina")
	_check(stoat.ultimate_id == &"", "stoat has NO Ultimate")

	var rat: Combatant = EnemyLibrary.make(&"rat")
	_check(rat.ability_id == &"", "rat has no ability")
	_check(rat.resource_pool == null, "rat has no resource pool")
	_check(rat.ultimate_id == &"", "rat has NO Ultimate")

	print(("ENEMY VARIATION TEST PASSED" if _failures == 0 else "ENEMY VARIATION TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test, verify it fails**

```bash
timeout 60 "$GODOT" --headless --path . --script res://tests/test_enemy_variation.gd
```
Expected: FAIL — ferret has no `ability_id` / default `ultimate_id` is `&"sticky_wild"`, not `&""`.

- [ ] **Step 3: Update `EnemyLibrary`**

In `combat/enemy_library.gd`, replace the `make` match arms and the `_build` helper so abilities/pools are passed. New `make` (keep the `load(...)` lines above it):
```gdscript
	match id:
		&"rat":    return _build("Cluny's Rat", crushing, 8.0, 2, earth, 300)       # plain melee baseline
		&"ferret": return _build("Redtooth (Ferret)", slashing, 7.0, 3, slashing, 260, &"flurry", 2)
		&"stoat":  return _build("Killconey (Stoat)", piercing, 6.0, 4, piercing, 220, &"hunters_mark", 3)
		_:         return null
```

Replace `_build` with (adds the ability + pool; `ultimate_id` explicitly cleared so no enemy Ultimate path — Combatant defaults `ultimate_id` to `&"sticky_wild"`):
```gdscript
## Stamps a fresh enemy Combatant. Enemies have NO Ultimate (ultimate_id cleared). An enemy with a
## base ability ([param ability_id] != &"") gets a small Stamina pool sized for it so the greedy AI
## can fire it through the same MainPhasePlan.commit() path PCs use (spec 2026-06-28 §2/§3.2).
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int, defense: DamageType, hp: int, ability_id: StringName = &"", ability_cost: int = 0) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = enemy_name
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
	c.base_stats = Stats.new()
	# Borrowed base ability + a small Stamina pool to pay for it (rat: none). [ASSUMPTION] costs/pool.
	if ability_id != &"":
		c.ability_id = ability_id
		c.ability_cost = ability_cost
		c.ability_resource = &"stamina"
		c.base_max_stamina = maxi(5, ability_cost)
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = ability_cost      # enough to fire turn 1
		pool.regen_per_turn = ability_cost  # refreshes each turn so the greedy AI can re-fire
		c.resource_pool = pool
	c.apply_stats()   # derive max_hp (and max_stamina if a pool exists) BEFORE seeding hp
	c.apply_luck()    # luck 0 -> no-op, kept for parity with ClassLibrary
	c.start_combat()
	return c
```

- [ ] **Step 4: Run test, verify it passes**

```bash
timeout 60 "$GODOT" --headless --path . --script res://tests/test_enemy_variation.gd
```
Expected: PASS — `ENEMY VARIATION TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/enemy_library.gd tests/test_enemy_variation.gd
git commit -m "feat(enemy): ferret Flurry + stoat Hunter's Mark with small stamina pools; no enemy Ultimate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Wire enemy AI into combat.gd (targeting + greedy ability use + enemy commit)

**Files:**
- Modify: `combat/combat.gd` — `_enemy_pick_target` (use `EnemyAI`), extract a shared `_commit_main1()` from `_on_spin_pressed`, add `_enemy_stage_ability()`, call both on the enemy spin path in `_do_spin`.
- Test: `tests/test_enemy_combat_actions.gd`

**Interfaces:**
- Consumes: `EnemyAI.pick_target` (Task 3); enemy abilities/pools (Task 4); `MainPhasePlan` (`can_stage_ability()`, `ability_staged`, `commit()`); `Combatant.hunters_mark_pending`, `EffectLibrary.make(&"hunters_mark")`, `Combatant.attach_effect`, `has_effect`.
- Produces: enemy turns that target via `EnemyAI` and (ferret/stoat) stage + commit their ability; a stoat's target ends up `has_effect(&"hunters_mark")`; a ferret's committed `turn_reels` is one longer than its weapon reel count.

- [ ] **Step 1: Write the failing test**

This test drives the *pure* parts of the wiring without a full scene by exercising the same plan path the orchestrator uses, plus a small AI-decision mirror. It verifies the mechanical outcome the orchestrator relies on.

`tests/test_enemy_combat_actions.gd`:
```gdscript
extends SceneTree

# Headless test: enemy ability commit mechanics (spec 2026-06-28 §3.2/§3.3) — that the orchestrator's
# building blocks work for an enemy: Flurry adds a reel via MainPhasePlan.commit(); Hunter's Mark sets
# hunters_mark_pending so the orchestrator can attach the mark; and the greedy decision matches policy.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_combat_actions.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Ferret Flurry: stage on the per-turn plan, commit, expect +1 turn reel.
	var ferret: Combatant = EnemyLibrary.make(&"ferret")
	ferret.begin_turn()  # seeds turn_reels from the weapon
	var base_reels: int = ferret.turn_reels.size()
	var plan := MainPhasePlan.new(ferret, ferret.ability_cost, 5, 2)
	_check(plan.can_stage_ability(), "ferret CAN stage Flurry (affordable, under cap)")
	plan.ability_staged = true
	plan.commit()
	_check(ferret.turn_reels.size() == base_reels + 1, "Flurry committed -> +1 turn reel")

	# Stoat Hunter's Mark: commit sets the pending flag (the orchestrator then attaches to the target).
	var stoat: Combatant = EnemyLibrary.make(&"stoat")
	stoat.begin_turn()
	var plan2 := MainPhasePlan.new(stoat, stoat.ability_cost, 5, 2)
	_check(plan2.can_stage_ability(), "stoat CAN stage Hunter's Mark")
	plan2.ability_staged = true
	plan2.commit()
	_check(stoat.hunters_mark_pending, "Hunter's Mark committed -> hunters_mark_pending set")

	# Orchestrator attach step (mirrors combat.gd): attach mark to a target PC.
	var target := Combatant.new(); target.is_player = true
	target.defense_type = load("res://combat/resources/types/slashing.tres")
	target.base_max_hp = 100; target.apply_stats(); target.start_combat()
	target.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(target.has_effect(&"hunters_mark"), "target PC ends up marked")

	# Rat: no ability -> plan cannot stage.
	var rat: Combatant = EnemyLibrary.make(&"rat")
	rat.begin_turn()
	var plan3 := MainPhasePlan.new(rat, rat.ability_cost, 5, 2)
	_check(not plan3.can_stage_ability(), "rat cannot stage (no ability/pool)")

	print(("ENEMY COMBAT ACTIONS TEST PASSED" if _failures == 0 else "ENEMY COMBAT ACTIONS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test, verify it fails (or passes partially)**

```bash
timeout 60 "$GODOT" --headless --path . --script res://tests/test_enemy_combat_actions.gd
```
Expected: FAIL — until Task 4 is in, `can_stage_ability()` is false for the ferret/stoat. (If Task 4 already landed, this test may pass at the model level; the orchestrator wiring in Step 3 is still required for the *scene* to use it — verified by the smoke test in Step 4.)

- [ ] **Step 3a: Replace `_enemy_pick_target` to use `EnemyAI`**

In `combat/combat.gd`, replace the body of `_enemy_pick_target` (currently `return Combat.first_living(_enemies_of(c))`):
```gdscript
## Picks which living PC an enemy attacks this turn (spec 2026-06-28 §3.1): EnemyAI prefers a
## super-effective matchup, then neutral, then lowest-HP. Isolated so a future policy swaps only this.
func _enemy_pick_target(c: Combatant) -> Combatant:
	return EnemyAI.pick_target(c, _pcs)
```

- [ ] **Step 3b: Extract the shared Main-1 commit into `_commit_main1()`**

In `_on_spin_pressed`, the block that commits the plan + logs + attaches Hunter's Mark (currently lines ~869–886, from `if _plan != null:` through the `hunters_mark_pending` attach) becomes a call. Replace that block with:
```gdscript
	_commit_main1()
```
And add this new method (near `_do_spin`):
```gdscript
## Commits the active combatant's staged Main-1 plan: spends resources, appends ability reels, arms
## the Ultimate, logs the intent, and attaches Hunter's Mark to the current defender if pending. The
## ONE apply point — shared by the PC path (_on_spin_pressed) and the enemy path (_do_spin). Safe to
## call with nothing staged (commit() is a no-op then). [ARCHITECTURE §2 authority rule.]
func _commit_main1() -> void:
	if _plan == null:
		return
	var did_ability: bool = _plan.ability_staged
	var did_ultimate: bool = _plan.fire_ultimate_staged
	_plan.commit()  # spends resources / appends reel / arms wild — the ONLY apply point
	if did_ability:
		_log("  ⮞ %s uses %s." % [_attacker.display_name, _ability_name(_attacker.ability_id)])
	if did_ultimate:
		_log("  ★ %s fires ULTIMATE — %s!" % [_attacker.display_name, _ultimate_name(_attacker.ultimate_id)])
	# Hunter's Mark: the orchestrator owns the target, so it does the attach (ARCHITECTURE §2). The
	# downstream crit-fail->hit swap in _do_spin is side-agnostic, so an enemy's mark helps every enemy.
	if _attacker.hunters_mark_pending:
		var mark: Effect = EffectLibrary.make(&"hunters_mark")
		_defender.attach_effect(mark)
		_attacker.hunters_mark_pending = false
		_log("  ⊕ %s MARKS %s — crit-fails become hits vs it (%d turns)." % [_attacker.display_name, _defender.display_name, mark.duration])
		(_panels[_defender] as CombatantPanel).refresh_status()
```
> Note: preserve the comment context already in `_on_spin_pressed` about the spin benefiting this turn; the logic now lives in `_commit_main1`. Verify the surrounding `_on_spin_pressed` lines (clearing payline preview, disabling buttons, re-preparing strips, `proceed_to_combat()`, `_do_spin()`) are unchanged — only the commit/log/attach block moves.

- [ ] **Step 3c: Add `_enemy_stage_ability()` (the greedy policy)**

Add near `_enemy_pick_target`:
```gdscript
## Greedy first-iteration enemy ability use (spec 2026-06-28 §3.2): stage the enemy's base ability
## into _plan when affordable. Flurry: always (pure upside). Hunter's Mark: only if the chosen target
## isn't already marked (don't waste a re-mark). No-op for abilityless enemies (rat). The staged plan
## is committed by _commit_main1 on the enemy's spin.
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

- [ ] **Step 3d: Run the enemy stage+commit on the enemy spin path**

At the TOP of `_do_spin` (before the existing `if _phase_manager.current_phase != PhaseManager.Phase.COMBAT:` line), add the enemy commit. PCs already committed in `_on_spin_pressed`, so gate on enemy:
```gdscript
	# Enemy turns commit Main 1 here (PCs committed in _on_spin_pressed). Decide ability use, then
	# commit through the shared apply point so Flurry's reel + Hunter's Mark land before resolution.
	if _attacker != null and not _attacker.is_player:
		_enemy_stage_ability()
		_commit_main1()
		_prepare_strips(_attacker.turn_reels)  # rebuild strips so an added Flurry reel animates
```
> This runs before the existing `proceed_to_combat()` call (which stays). `_commit_main1` is idempotent-safe to call once per enemy turn; an enemy reaches `_do_spin` exactly once per turn (normal timer OR stun-recovery timer, never both).

- [ ] **Step 4: Run the new test + the scene smoke tests, verify all pass**

```bash
timeout 60 "$GODOT" --headless --path . --script res://tests/test_enemy_combat_actions.gd
timeout 90 "$GODOT" --headless --path . --script res://tests/test_scene_party_smoke.gd
timeout 90 "$GODOT" --headless --path . --script res://tests/test_party_combat.gd
```
Expected: all three print `… TEST PASSED`, exit 0. (The smoke test exercises the scene build + a few turns; it must still load and run with the rewired enemy path.)

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_enemy_combat_actions.gd
git commit -m "feat(ai): wire enemy AI into combat — targeting + greedy ability use + shared Main-1 commit

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Selection-screen polish — multi-line tooltips, role badges, centered columns

**Files:**
- Modify: `combat/combat.gd` — `_build_roster_list` (optional tooltip + role providers; vertical centering), `_build_start_overlay` (pass providers; multi-line tooltip builders), add `_class_select_tooltip` / `_enemy_select_tooltip` helpers.
- Test: manual (scene-level); regression via existing smoke tests.

**Interfaces:**
- Consumes: `RoleVisuals.label`/`color` (Task 1), `CharacterClass.combat_role` + `EnemyLibrary.role` (Task 2), `TypeVisuals.type_name` (existing).
- Produces: roster buttons with multi-line `tooltip_text` and a role-color pill beside each; both columns vertically centered.

- [ ] **Step 1: Add multi-line tooltip builders**

In `combat/combat.gd`, add two helpers (reuse the existing `_class_tooltip` one-liners' content but reflow into rows):
```gdscript
## Multi-row hover text for a party-pick button (spec 2026-06-28 §4.1): name / type · reels · role /
## ability / ultimate, one per line.
func _class_select_tooltip(id: StringName) -> String:
	var cc: CharacterClass = ClassLibrary.make(id)
	var lines: PackedStringArray = []
	lines.append(cc.display_name)
	lines.append("%s · %d reels · %s" % [TypeVisuals.type_name(cc.weapon_type), cc.reel_count, RoleVisuals.label(cc.combat_role).capitalize()])
	lines.append("Ability: %s" % _ability_name(cc.ability_id))
	lines.append("Ultimate: %s" % _ultimate_name(cc.ultimate_id))
	return "\n".join(lines)

## Multi-row hover text for an enemy-pick button: name / type · reels · role / borrowed ability (if any).
func _enemy_select_tooltip(id: StringName) -> String:
	var e: Combatant = EnemyLibrary.make(id)
	var lines: PackedStringArray = []
	lines.append(e.display_name)
	var reels: int = e.weapon.reels.size() if e.weapon != null else 0
	lines.append("%s · %d reels · %s" % [TypeVisuals.type_name(e.weapon_type()), reels, RoleVisuals.label(EnemyLibrary.role(id)).capitalize()])
	if e.ability_id != &"":
		lines.append("Ability: %s" % _ability_name(e.ability_id))
	return "\n".join(lines)
```
> `cc.weapon_type` is the `CharacterClass` export (a `DamageType`); the enemy uses `e.weapon_type()` (the `Combatant` method). Both feed `TypeVisuals.type_name`.

- [ ] **Step 2: Extend `_build_roster_list` with tooltip + role providers and vertical centering**

Change the signature and body of `_build_roster_list`. New signature (adds two optional `Callable`s; pass `Callable()` to skip):
```gdscript
func _build_roster_list(parent: Control, heading: String, x: float, top_y: float, ids: Array[StringName], selected: Array, max_n: int, labeler: Callable, on_change: Callable, tooltip: Callable = Callable(), role: Callable = Callable()) -> float:
```
Inside the per-button loop (after `b.custom_minimum_size = BTN` and before connecting `pressed`), add the tooltip + badge:
```gdscript
		if tooltip.is_valid():
			b.tooltip_text = String(tooltip.call(id))
		if role.is_valid():
			var badge := Label.new()
			badge.text = " %s " % RoleVisuals.label(role.call(id))
			badge.add_theme_font_size_override("font_size", 12)
			var sb := StyleBoxFlat.new()
			var col: Color = RoleVisuals.color(role.call(id))
			sb.bg_color = Color(col.r, col.g, col.b, 0.35)
			sb.set_corner_radius_all(8)
			sb.set_content_margin_all(4)
			badge.add_theme_stylebox_override("normal", sb)
			badge.position = Vector2(x + BTN.x + 8.0, list_top + i * STEP + 8.0)
			parent.add_child(badge)
```
> `Label` has a `normal` stylebox in Godot 4; the `StyleBoxFlat` gives the pill its rounded colored background.

- [ ] **Step 3: Center the columns + pass the providers from `_build_start_overlay`**

In `_build_start_overlay`, compute a centered `top_y` and pass the providers. Replace the two `_build_roster_list(...)` calls (currently at fixed `120.0`) with:
```gdscript
	# Vertically center the list block in the mid-region between the subtitle (~92) and the
	# dummy/BEGIN buttons (~view.y-110). Block height = heading (34) + N rows.
	var rows: int = maxi(ClassLibrary.IDS.size(), EnemyLibrary.IDS.size())
	var block_h: float = 34.0 + rows * 46.0   # STEP = 46 (matches _build_roster_list)
	var region_top: float = 100.0
	var region_bot: float = view.y - 120.0
	var list_top_y: float = maxf(region_top, region_top + ((region_bot - region_top) - block_h) * 0.5)

	# LEFT — Choose your Party (7 classes); label = "<display_name> — <Class>".
	var class_label: Callable = func(id: StringName) -> String:
		return "%s — %s" % [ClassLibrary.make(id).display_name, String(id).capitalize()]
	_build_roster_list(_start_overlay, "Choose your Party  (1–3)", 80.0, list_top_y,
		ClassLibrary.IDS, _pc_class_ids, 3, class_label, update_begin,
		_class_select_tooltip, func(id: StringName) -> StringName: return ClassLibrary.make(id).combat_role)

	# RIGHT — Enemy Combatants (3 enemies); label = the enemy's display name.
	var enemy_label: Callable = func(id: StringName) -> String:
		return EnemyLibrary.label(id)
	_build_roster_list(_start_overlay, "Enemy Combatants  (1–3)", view.x - 400.0, list_top_y,
		EnemyLibrary.IDS, _enemy_ids, 3, enemy_label, update_begin,
		_enemy_select_tooltip, func(id: StringName) -> StringName: return EnemyLibrary.role(id))
```
> Keep the existing `update_begin` Callable defined above these calls (unchanged). Keep the X positions `80.0` and `view.x - 400.0`.

- [ ] **Step 4: Verify the scene builds + smoke tests pass**

```bash
"$GODOT" --headless --path . --editor --quit   # refresh cache (RoleVisuals/EnemyAI are referenced from the scene)
timeout 90 "$GODOT" --headless --path . --script res://tests/test_scene_party_smoke.gd
timeout 90 "$GODOT" --headless --path . --script res://tests/test_scene_load_seer.gd
```
Expected: both print `… TEST PASSED`, exit 0 (the overlay builds with the new providers; no parse/runtime error).

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(ui): selection-screen polish — multi-line tooltips, role badges, centered columns

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Full suite green + handoff/docs update

**Files:**
- Modify: `CLAUDE.md` §8, `HANDOFF.md` §6 (record the iteration), `docs/superpowers/DECISIONS-LOG.md` (the `[ASSUMPTION]` calls: enemy pool sizing, greedy policy).

- [ ] **Step 1: Run the WHOLE headless suite, confirm all green**

```bash
GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
"$GODOT" --headless --path . --editor --quit
fail=0
for t in tests/test_*.gd; do
  name="res://$t"
  out=$(timeout 90 "$GODOT" --headless --path . --script "$name" 2>&1)
  if echo "$out" | grep -q "TEST PASSED"; then echo "PASS: $t";
  else echo "FAIL: $t"; echo "$out" | tail -5; fail=1; fi
done
echo "SUITE: $([ $fail -eq 0 ] && echo ALL GREEN || echo HAS FAILURES)"
```
Expected: `SUITE: ALL GREEN`. Fix any regression before continuing.

- [ ] **Step 2: Update docs**

Add to `CLAUDE.md` §8 and `HANDOFF.md` §6 a short note: "SHIPPED 2026-06-28 — enemy variation + first-iteration enemy AI (type-effectiveness targeting + greedy ability use; ferret Flurry, stoat Hunter's Mark) + selection-screen polish (multi-line tooltips, role badges, centered columns). N suites green." Record in `DECISIONS-LOG.md` the `[ASSUMPTION]` calls (enemy pool = ability_cost with full regen; greedy ability policy; role→color palette).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md HANDOFF.md docs/superpowers/DECISIONS-LOG.md
git commit -m "docs: enemy AI v1 + selection polish shipped; assumptions logged

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff nvm-party-combat -m "Merge: N-vs-M party combat + enemy AI v1 + selection polish"
git checkout nvm-party-combat   # leave the branch checked out for any follow-up
```
> Per CLAUDE.md, only merge when the suite is green (Step 1). The branch already carried the N-vs-M prototype (2 commits ahead) plus this iteration's commits.

---

## Self-Review

**Spec coverage:**
- §2 enemy variation → Task 4 (abilities/pools), Task 2 (roles). Chancer=Ranged → Task 2. ✓
- §3.1 targeting → Task 3. ✓
- §3.2 greedy ability use → Task 5 (`_enemy_stage_ability`). ✓
- §3.3 enemy commit + Hunter's Mark attach → Task 5 (`_commit_main1` + `_do_spin` enemy branch). ✓
- §4.1 multi-line tooltips → Task 6. §4.2 badges/`RoleVisuals` → Task 1 + Task 6. §4.3 centering → Task 6. ✓
- §5 testing → tests in Tasks 1–5 + full suite in Task 7. ✓
- §6 out-of-scope honored (no CombatantPanel changes, no enemy Ultimate, no new type axis). ✓

**Type consistency:** `combat_role: StringName`, `EnemyLibrary.role(id) -> StringName`, `EnemyAI.pick_target(Combatant, Array[Combatant]) -> Combatant`, `RoleVisuals.label/color`, `_commit_main1()`, `_enemy_stage_ability()` — names match across tasks. `cc.weapon_type` (class export) vs `e.weapon_type()` (Combatant method) distinction noted in Task 6.

**Placeholder scan:** no TBD/TODO; every code step shows full code; commands have expected output.

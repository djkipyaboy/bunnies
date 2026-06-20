# Stacking Control Debuffs (merge-by-id) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-applying an effect merges into the existing one by id (never a second instance); control debuffs like SLOW stack with diminishing returns (−20/−10/−5, cap 3) and refresh duration.

**Architecture:** Add a small per-stack data model to `Effect` (`max_stacks`, `stack_magnitudes`, `stacks` + `effective_magnitude()`/`add_stack()`), have `EffectLibrary` author SLOW's schedule, and rewrite `Combatant.attach_effect` to merge by id. `recompute_initiative` sums `effective_magnitude()`. No change to combat resolution, the type chart, the Ultimate, or staging.

**Tech Stack:** Godot 4.6.3-stable, GDScript (static-typed). Headless `SceneTree` test scripts under `tests/`.

## Global Constraints

- **Engine: Godot 4.6.3-stable. Language: GDScript only — never C#/.NET.** (CLAUDE.md §2)
- **Data = `Resource`; logic = `RefCounted`/`Node`; prefer static typing.** `Effect` stays a `Resource`. (CLAUDE.md §2)
- **Naming LOCKED:** classes `PascalCase`, files `snake_case`, signals `snake_case` past-tense, handlers `_on_<emitter>_<signal>`. (CLAUDE.md §2)
- **Merge-by-id applies to ALL effects:** re-applying an effect whose `id` is already active never creates a second instance. Stacking effects (`max_stacks > 1`) add a stack (diminishing, capped); non-stacking (`max_stacks == 1`) just refresh duration. (Confirmed by designer.)
- **`[ASSUMPTION]` values** (editable data in `EffectLibrary`): SLOW `stack_magnitudes [-20, -10, -5]`, `max_stacks 3` (cap −35), `duration 2` (refreshed on re-apply).
- **DoT is out of scope** — separate category, later.
- **Godot binary (NOT on PATH):** `/c/Godot_v4.6.3-stable_win64_console.exe`. Run from the project root (the worktree dir, holds `project.godot`).
- **Run a test:** `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_<name>.gd`
- No new `class_name` is added; a cache rebuild isn't normally needed, but if a `--script` run reports a parse error about an existing class, run `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --editor --quit` once and retry. Use that same command as the compile check.
- **Benign at exit:** `ObjectDB instances leaked` / `resources still in use at exit` warnings are NOT failures; judge by `… TEST PASSED` + exit 0.
- Implements `docs/superpowers/specs/2026-06-19-stacking-debuffs-design.md`. Source of truth = `DESIGN.md`.

---

## File Structure

**Modified files:**
- `combat/resources/effect.gd` — add `max_stacks`, `stack_magnitudes`, `stacks` + `effective_magnitude()`/`add_stack()`.
- `combat/effect_library.gd` — author SLOW's stacking schedule.
- `combat/combatant.gd` — `attach_effect` merge-by-id (+ `_find_effect` helper); `recompute_initiative` sums `effective_magnitude()`.
- `combat/ui/combatant_panel.gd` — status line shows stacks + total.
- `tests/test_effect.gd` — extend with stacking + merge tests.

---

## Task 1: `Effect` stacking model + `EffectLibrary` schedule

**Files:**
- Modify: `combat/resources/effect.gd`
- Modify: `combat/effect_library.gd`
- Test: `tests/test_effect.gd` (append, inside `_initialize()` before the final `print(...)`)

**Interfaces:**
- Produces, on `Effect`: `@export var max_stacks: int = 1`, `@export var stack_magnitudes: Array[float] = []`, `var stacks: int = 1`; `func effective_magnitude() -> float`; `func add_stack() -> bool`.
- Produces: `EffectLibrary.make(&"slow")` now sets `max_stacks = 3`, `stack_magnitudes = [-20.0, -10.0, -5.0]` (plus the existing `magnitude = -20`, `duration = 2`).

- [ ] **Step 1: Write the failing test** — append this block to `tests/test_effect.gd`, inside `_initialize()`, immediately before the final `print(("EFFECT TEST PASSED" ...` line:

```gdscript
	# --- Stacking model: effective_magnitude by stack count, cap, and EffectLibrary schedule ---
	var s1: Effect = EffectLibrary.make(&"slow")
	_check(s1.max_stacks == 3, "slow max_stacks == 3 (got %d)" % s1.max_stacks)
	_check(s1.stack_magnitudes == [-20.0, -10.0, -5.0], "slow stack schedule (got %s)" % str(s1.stack_magnitudes))
	_check(s1.stacks == 1, "fresh slow starts at 1 stack (got %d)" % s1.stacks)
	_check(is_equal_approx(s1.effective_magnitude(), -20.0), "1 stack -> -20 (got %s)" % str(s1.effective_magnitude()))
	_check(s1.add_stack(), "2nd add_stack succeeds")
	_check(is_equal_approx(s1.effective_magnitude(), -30.0), "2 stacks -> -30 (got %s)" % str(s1.effective_magnitude()))
	_check(s1.add_stack(), "3rd add_stack succeeds")
	_check(is_equal_approx(s1.effective_magnitude(), -35.0), "3 stacks -> -35 (got %s)" % str(s1.effective_magnitude()))
	_check(not s1.add_stack(), "4th add_stack refused at cap")
	_check(s1.stacks == 3, "stacks capped at 3 (got %d)" % s1.stacks)
	_check(is_equal_approx(s1.effective_magnitude(), -35.0), "capped magnitude stays -35 (got %s)" % str(s1.effective_magnitude()))

	# --- Non-stacking effect: effective_magnitude is the flat magnitude; cannot add a stack ---
	var flat: Effect = Effect.new()
	flat.kind = Effect.Kind.INITIATIVE_MOD
	flat.magnitude = -7.0
	_check(is_equal_approx(flat.effective_magnitude(), -7.0), "non-stacking effective = flat magnitude (got %s)" % str(flat.effective_magnitude()))
	_check(not flat.add_stack(), "non-stacking add_stack refused (max_stacks 1)")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_effect.gd`
Expected: FAIL — `max_stacks`/`stack_magnitudes`/`effective_magnitude`/`add_stack` not defined.

- [ ] **Step 3: Add the stacking fields + methods to `combat/resources/effect.gd`**

After the existing `duration` export (line ~23), add:
```gdscript
## How many times this effect can stack on one bearer (1 = non-stacking). [ASSUMPTION] data.
@export var max_stacks: int = 1

## Per-stack magnitude increments for a stacking effect (e.g. SLOW = [-20, -10, -5] — diminishing).
## When non-empty, effective_magnitude() sums the first [member stacks] entries instead of using
## the flat [member magnitude]. [ASSUMPTION] data.
@export var stack_magnitudes: Array[float] = []

## Live stack count on an attached effect (a freshly made effect is 1 stack). Grown by add_stack().
var stacks: int = 1
```

Then add these methods (after `is_expired()`):
```gdscript
## The effect's current magnitude given its stack count. For a stacking effect (non-empty
## stack_magnitudes) this is the sum of the first [member stacks] increments; otherwise the flat
## [member magnitude]. Used by Combatant.recompute_initiative for INITIATIVE_MOD effects.
func effective_magnitude() -> float:
	if stack_magnitudes.is_empty():
		return magnitude
	var total: float = 0.0
	var n: int = mini(stacks, stack_magnitudes.size())
	for i: int in range(n):
		total += stack_magnitudes[i]
	return total

## Adds one stack, up to [member max_stacks]. Returns false (no change) when already at the cap or
## for a non-stacking effect (max_stacks == 1).
func add_stack() -> bool:
	if stacks < max_stacks:
		stacks += 1
		return true
	return false
```

- [ ] **Step 4: Author SLOW's schedule in `combat/effect_library.gd`**

In the `&"slow":` branch, after `e.duration = 2`, add:
```gdscript
				e.max_stacks = 3
				e.stack_magnitudes = [-20.0, -10.0, -5.0]
```
(So the full branch sets id, kind, magnitude −20, duration 2, max_stacks 3, stack_magnitudes [-20,-10,-5], then `return e`.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_effect.gd`
Expected: PASS — `EFFECT TEST PASSED`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/effect.gd combat/effect_library.gd tests/test_effect.gd
git commit -m "feat(combat): add Effect stacking model + SLOW diminishing schedule"
```

---

## Task 2: `Combatant.attach_effect` merge-by-id + panel display

**Files:**
- Modify: `combat/combatant.gd` (`attach_effect`, `recompute_initiative`, add `_find_effect`)
- Modify: `combat/ui/combatant_panel.gd` (`refresh_status`)
- Test: `tests/test_effect.gd` (append more, before the final `print(...)`)

**Interfaces:**
- Consumes: `Effect.effective_magnitude()`, `Effect.add_stack()`, `Effect.id`, `Effect.duration` (Task 1).
- Produces: `Combatant.attach_effect` merges by id; new private `_find_effect(id: StringName) -> Effect`; `recompute_initiative` sums `effective_magnitude()`.

- [ ] **Step 1: Write the failing test** — append this block to `tests/test_effect.gd`, inside `_initialize()`, immediately before the final `print(...)` line:

```gdscript
	# --- attach_effect merges a stacking debuff by id: diminishing, capped, never a 2nd instance ---
	var sc: Combatant = Combatant.new()
	sc.base_initiative = 60
	sc.recompute_initiative()
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.active_effects.size() == 1 and sc.current_initiative == 40, "1st slow: init 40, 1 effect (init %d, n %d)" % [sc.current_initiative, sc.active_effects.size()])
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.active_effects.size() == 1 and sc.current_initiative == 30, "2nd slow merges: init 30, still 1 effect (init %d, n %d)" % [sc.current_initiative, sc.active_effects.size()])
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.current_initiative == 25, "3rd slow: -35 -> init 25 (got %d)" % sc.current_initiative)
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.current_initiative == 25 and sc.active_effects.size() == 1, "4th slow capped: init 25, 1 effect (init %d)" % sc.current_initiative)
	_check(sc.active_effects[0].stacks == 3, "merged effect capped at 3 stacks (got %d)" % sc.active_effects[0].stacks)

	# --- re-applying refreshes the duration to the incoming value ---
	sc.active_effects[0].duration = 1   # simulate one tick elapsed
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.active_effects[0].duration == 2, "re-apply refreshes duration to 2 (got %d)" % sc.active_effects[0].duration)

	# --- non-stacking effect also merges by id (refresh only, no doubling, no 2nd instance) ---
	var nc: Combatant = Combatant.new()
	nc.base_initiative = 50
	nc.recompute_initiative()
	var w1: Effect = Effect.new()
	w1.id = &"weaken"; w1.kind = Effect.Kind.INITIATIVE_MOD; w1.magnitude = -5.0; w1.duration = 2; w1.max_stacks = 1
	nc.attach_effect(w1)
	var w2: Effect = Effect.new()
	w2.id = &"weaken"; w2.kind = Effect.Kind.INITIATIVE_MOD; w2.magnitude = -5.0; w2.duration = 2; w2.max_stacks = 1
	nc.attach_effect(w2)
	_check(nc.active_effects.size() == 1 and nc.current_initiative == 45, "non-stacking weaken merges: 1 effect, -5 not -10 (init %d, n %d)" % [nc.current_initiative, nc.active_effects.size()])

	# --- distinct ids attach as separate effects ---
	nc.attach_effect(EffectLibrary.make(&"slow"))
	_check(nc.active_effects.size() == 2 and nc.current_initiative == 25, "distinct id (slow) adds a 2nd effect: init 25 (n %d, init %d)" % [nc.active_effects.size(), nc.current_initiative])
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_effect.gd`
Expected: FAIL — the 2nd slow currently appends a separate effect (init would be 20, size 2), so the "merges" assertions fail.

- [ ] **Step 3: Rewrite `attach_effect` + `recompute_initiative` and add `_find_effect` in `combat/combatant.gd`**

Replace `recompute_initiative` (sum `effective_magnitude()`):

Find:
```gdscript
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.magnitude
	current_initiative = base_initiative + int(roundf(total))
```
Replace with:
```gdscript
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.effective_magnitude()
	current_initiative = base_initiative + int(roundf(total))
```

Replace `attach_effect`:

Find:
```gdscript
func attach_effect(effect: Effect) -> void:
	if effect == null:
		return
	# Defensively duplicate so a shared (.tres-loaded) Effect can never share a live duration
	# counter across combatants. Safe even for already-fresh EffectLibrary.make() instances.
	effect = effect.duplicate()
	active_effects.append(effect)
	recompute_initiative()
```
Replace with:
```gdscript
func attach_effect(effect: Effect) -> void:
	if effect == null:
		return
	# Merge by id: re-applying an effect already active never creates a second instance (this is
	# what prevents unbounded additive stacking). A stacking effect adds a stack (diminishing,
	# capped); a non-stacking one is a no-op on stacks. Either way the duration is refreshed.
	var existing: Effect = _find_effect(effect.id)
	if existing != null:
		existing.add_stack()                 # no-op at cap / for max_stacks == 1
		existing.duration = effect.duration   # refresh to the incoming duration
		recompute_initiative()
		return
	# New id: defensively duplicate so a shared (.tres-loaded) Effect can't share a live counter
	# across combatants (safe even for fresh EffectLibrary.make() instances), then append.
	effect = effect.duplicate()
	active_effects.append(effect)
	recompute_initiative()

## Returns the active effect with [param id], or null if none is active.
func _find_effect(id: StringName) -> Effect:
	for e: Effect in active_effects:
		if e != null and e.id == id:
			return e
	return null
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_effect.gd`
Expected: PASS — `EFFECT TEST PASSED`, exit 0.

- [ ] **Step 5: Confirm the Crushing→Slow integration still passes (single stack unchanged)**

Run: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_crushing_slow.gd`
Expected: PASS — one SLOW stack still drops init by 20 and re-sorts turn order.

- [ ] **Step 6: Show stacks + total in `combat/ui/combatant_panel.gd`**

In `refresh_status()`, replace the loop body:

Find:
```gdscript
	var parts: PackedStringArray = []
	for e: Effect in _combatant.active_effects:
		parts.append("%s %d (%d)" % [String(e.id).to_upper(), int(e.magnitude), e.duration])
	_status_label.text = ", ".join(parts)
```
Replace with:
```gdscript
	var parts: PackedStringArray = []
	for e: Effect in _combatant.active_effects:
		var stack_txt: String = (" x%d" % e.stacks) if e.stacks > 1 else ""
		parts.append("%s %d%s (%d)" % [String(e.id).to_upper(), int(e.effective_magnitude()), stack_txt, e.duration])
	_status_label.text = ", ".join(parts)
```

- [ ] **Step 7: Compile check + full suite**

Run: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --editor --quit`
Expected: exits 0, no parse/script errors.
Then run every suite and confirm each prints `… TEST PASSED`:
```bash
for t in effect main_phase_plan resource_pool crushing_slow reel_splice ultimate_sticky_wild turn_manager combatant phase_manager bonus_meter action_reel combat_loop; do
  "/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://tests/test_$t.gd" 2>/dev/null | grep -q "TEST PASSED" && echo "PASS $t" || echo "FAIL $t"
done
```
Expected: every line `PASS`.

- [ ] **Step 8: Commit**

```bash
git add combat/combatant.gd combat/ui/combatant_panel.gd tests/test_effect.gd
git commit -m "feat(combat): merge effects by id (stack diminishing / refresh); show stacks"
```

---

## Final verification

- [ ] **Whole suite green:** the 12-suite loop in Task 2 Step 7 prints all `PASS`.
- [ ] **Compile clean:** `--editor --quit` exits 0.
- [ ] **Human play-test (CLAUDE.md §5):** take repeated Crushing crits from the rat and confirm SLOW grows −20 → −30 → −35 (not −40+), caps at −35, the panel reads e.g. `SLOW -30 x2 (2)`, and each new crit refreshes the duration to 2.

---

## Self-review notes (author)

- **Spec coverage:** spec §2 part 1 (merge-by-id, all effects) → Task 2 `attach_effect` + the non-stacking-weaken test. spec §2 part 2 + §3 (diminishing/cap/schedule) → Task 1 `effective_magnitude`/`add_stack`/`stack_magnitudes` + EffectLibrary. spec §4 (recompute, refresh, tick unchanged) → Task 2 `recompute_initiative` + duration-refresh test (tick unchanged — not touched). spec §5 (UI) → Task 2 Step 6. spec §6 (tests) → both tasks' test blocks + the crushing_slow regression check.
- **Type consistency:** `effective_magnitude() -> float`, `add_stack() -> bool`, `max_stacks: int`, `stack_magnitudes: Array[float]`, `stacks: int`, `_find_effect(id: StringName) -> Effect` — used identically in tests, Effect, and Combatant.
- **Out of scope (spec §8):** DoT, new effects, resolution/chart/Ultimate/staging changes, per-stack durations — none touched.
- **Regression guard:** `recompute_initiative` now sums `effective_magnitude()`; for a single-stack SLOW that equals the old `magnitude` (−20), so `test_crushing_slow` is unaffected (Step 5 verifies).

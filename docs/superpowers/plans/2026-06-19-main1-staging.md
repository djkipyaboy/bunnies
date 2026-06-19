# Staged Main-Phase-1 Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Main-Phase-1 actions (Splice Storm reel, Fire Ultimate) staged toggles with a live preview that commit only on SPIN, and limit splice to one per turn.

**Architecture:** A new pure-logic `MainPhasePlan` (RefCounted) holds the turn's pending choices and computes the preview (reels, Stamina, wild indices); it mutates nothing until `commit()`, which delegates to the existing `Combatant.try_splice_reel`/`fire_sticky_wild`. The orchestrator (`combat.gd`) turns the buttons into toggles, renders the preview each toggle, and calls `commit()` on SPIN. The `CombatResolver`/`Combatant` authority rule is untouched.

**Tech Stack:** Godot 4.6.3-stable, GDScript (static-typed). Headless `SceneTree` test scripts under `tests/`.

## Global Constraints

- **Engine: Godot 4.6.3-stable. Language: GDScript only — never C#/.NET.** (CLAUDE.md §2)
- **Data = `Resource`; logic = `RefCounted`/`Node`; prefer static typing.** `MainPhasePlan` is transient runtime state → `RefCounted`, not `Resource`. (CLAUDE.md §2)
- **Naming LOCKED:** classes `PascalCase`, files `snake_case`, signals `snake_case` past-tense (never `on_`-prefixed), handlers `_on_<emitter>_<signal>`. (CLAUDE.md §2)
- **Staging mutates nothing.** Toggling/previewing must not spend Stamina, consume the meter, or change `turn_reels`. Only `commit()` (on SPIN) applies, by calling the existing committed methods. No inverse/refund logic.
- **Splice = one per turn** (a single bool toggle → max +1 reel). Reel band ceiling stays **5**. Ultimate costs **only** the Bonus Meter.
- **`[ASSUMPTION]` values** (kept as plan constructor args, not scattered literals): splice cost **2** Stamina, splice type **Storm**, reel cap **5**, wild reel **0**, wild spins **2**.
- **Godot binary (NOT on PATH):** `/c/Godot_v4.6.3-stable_win64_console.exe` (use the `_console` variant for headless stdout). Run all commands **from the project root** (the worktree dir, which holds `project.godot`).
- **Run a test:** `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_<name>.gd`
- **After adding a NEW `class_name`, build the class cache first** (REQUIRED on this worktree): `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --editor --quit` — also the script/scene compile check.
- **Benign at exit:** `ObjectDB instances leaked` / `resources still in use at exit` warnings are NOT failures; judge by `… TEST PASSED` + exit 0.
- Implements `docs/superpowers/specs/2026-06-19-main1-staging-design.md`. Source of truth = `DESIGN.md`.

---

## File Structure

**New files:**
- `combat/main_phase_plan.gd` — `MainPhasePlan`: staged Main-1 choices + preview computation + `commit()`.
- `tests/test_main_phase_plan.gd` — headless unit test for the plan.

**Modified files:**
- `combat/combat.gd` — buttons become staging toggles; per-toggle preview render; `commit()` on SPIN; a fresh plan per turn.
- `combat/ui/combatant_panel.gd` — `preview_resources()` (STA delta) + `set_meter_flash()` (pulse while a fire is staged).
- (`combat/ui/reel_strip.gd` — no change; its existing `set_wild()` is reused for the preview glow.)

---

## Task 1: `MainPhasePlan` staging layer

**Files:**
- Create: `combat/main_phase_plan.gd`
- Test: `tests/test_main_phase_plan.gd`

**Interfaces:**
- Consumes: `Combatant` (`turn_reels`, `resource_pool`, `bonus_meter`, `weapon.base_damage`, `wild_reel_indices()`, `try_splice_reel()`, `fire_sticky_wild()`), `ResourcePool.can_afford`, `BonusMeter.is_armed`, `ActionReel.make_default`, `DamageType`.
- Produces: `MainPhasePlan` (extends RefCounted):
  - `_init(c: Combatant, p_splice_type: DamageType, p_splice_cost := 2, p_reel_cap := 5, p_wild_reel := 0, p_wild_spins := 2)`
  - `var splice_staged: bool`, `var fire_ultimate_staged: bool`
  - `can_stage_splice() -> bool`, `can_stage_ultimate() -> bool`
  - `toggle_splice() -> void`, `toggle_ultimate() -> void`
  - `preview_reels() -> Array[ActionReel]`, `preview_stamina() -> int`, `will_consume_meter() -> bool`, `effective_wild_indices() -> Array[int]`
  - `commit() -> void`

- [ ] **Step 1: Write the failing test** — create `tests/test_main_phase_plan.gd`:

```gdscript
extends SceneTree

# Headless unit test for MainPhasePlan — staged Main-1 choices + preview, commit on SPIN.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_main_phase_plan.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_pc(stamina: int, meter_value: int) -> Combatant:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(slashing))
	var c: Combatant = Combatant.new()
	c.weapon = w
	c.resource_pool = ResourcePool.new()
	c.resource_pool.max_stamina = 5
	c.resource_pool.stamina = stamina
	c.bonus_meter = BonusMeter.new()
	c.bonus_meter.cap = 10
	c.bonus_meter.value = meter_value
	c.begin_turn()  # seeds turn_reels from the weapon (3 reels)
	return c

func _initialize() -> void:
	var storm: DamageType = load("res://combat/resources/types/storm.tres")

	# --- Fresh plan: nothing staged ---
	var c: Combatant = _mk_pc(3, 0)
	var plan: MainPhasePlan = MainPhasePlan.new(c, storm, 2, 5, 0, 2)
	_check(not plan.splice_staged and not plan.fire_ultimate_staged, "fresh plan stages nothing")
	_check(plan.preview_reels().size() == 3, "preview = 3 reels when nothing staged (got %d)" % plan.preview_reels().size())
	_check(plan.preview_stamina() == 3, "preview stamina = current when nothing staged (got %d)" % plan.preview_stamina())
	_check(not plan.will_consume_meter(), "no meter consumption when no ultimate staged")
	_check(plan.effective_wild_indices() == [], "no wild when nothing staged/active (got %s)" % str(plan.effective_wild_indices()))

	# --- Stage splice: preview grows, costs preview-only, NOTHING mutated ---
	plan.toggle_splice()
	_check(plan.splice_staged, "splice staged after toggle")
	_check(plan.preview_reels().size() == 4, "preview = 4 reels when splice staged (got %d)" % plan.preview_reels().size())
	_check(plan.preview_reels()[3].damage_type == storm, "previewed 4th reel is Storm-typed")
	_check(plan.preview_stamina() == 1, "preview stamina = 3 - 2 = 1 (got %d)" % plan.preview_stamina())
	_check(c.turn_reels.size() == 3, "PREVIEW DID NOT MUTATE turn_reels (got %d)" % c.turn_reels.size())
	_check(c.resource_pool.stamina == 3, "PREVIEW DID NOT SPEND stamina (got %d)" % c.resource_pool.stamina)

	# --- Un-stage splice reverts the preview ---
	plan.toggle_splice()
	_check(not plan.splice_staged and plan.preview_reels().size() == 3, "un-stage splice reverts preview")

	# --- Cannot stage splice when unaffordable ---
	var poor: Combatant = _mk_pc(1, 0)
	var plan_poor: MainPhasePlan = MainPhasePlan.new(poor, storm, 2, 5, 0, 2)
	plan_poor.toggle_splice()
	_check(not plan_poor.splice_staged, "splice not staged when unaffordable (1 < 2 STA)")

	# --- Cannot stage splice at the reel cap ---
	var capped: Combatant = _mk_pc(5, 0)
	capped.try_splice_reel(storm, 10.0, 0, 5)  # 3 -> 4
	capped.try_splice_reel(storm, 10.0, 0, 5)  # 4 -> 5 (cost 0 so stamina irrelevant)
	var plan_cap: MainPhasePlan = MainPhasePlan.new(capped, storm, 2, 5, 0, 2)
	plan_cap.toggle_splice()
	_check(not plan_cap.splice_staged, "splice not staged at 5-reel cap (turn_reels=%d)" % capped.turn_reels.size())

	# --- Ultimate: cannot stage unless armed ---
	var unarmed: Combatant = _mk_pc(3, 9)
	var plan_unarmed: MainPhasePlan = MainPhasePlan.new(unarmed, storm, 2, 5, 0, 2)
	plan_unarmed.toggle_ultimate()
	_check(not plan_unarmed.fire_ultimate_staged, "ultimate not staged below meter cap")

	var armed: Combatant = _mk_pc(3, 10)
	var plan_armed: MainPhasePlan = MainPhasePlan.new(armed, storm, 2, 5, 0, 2)
	plan_armed.toggle_ultimate()
	_check(plan_armed.fire_ultimate_staged, "ultimate staged when meter armed")
	_check(plan_armed.will_consume_meter(), "will_consume_meter true when ultimate staged")
	_check(plan_armed.effective_wild_indices() == [0], "staged fire -> wild [0] (got %s)" % str(plan_armed.effective_wild_indices()))
	_check(armed.bonus_meter.value == 10, "PREVIEW DID NOT CONSUME the meter (got %d)" % armed.bonus_meter.value)

	# --- effective_wild_indices reflects carryover even with nothing staged ---
	var carry: Combatant = _mk_pc(3, 10)
	carry.fire_sticky_wild(0, 2)  # simulate a prior-turn commit; meter now 0, reel 0 wild
	var plan_carry: MainPhasePlan = MainPhasePlan.new(carry, storm, 2, 5, 0, 2)
	_check(not plan_carry.fire_ultimate_staged, "carryover: nothing staged this turn")
	_check(plan_carry.effective_wild_indices() == [0], "carryover wild surfaces in preview (got %s)" % str(plan_carry.effective_wild_indices()))

	# --- commit: splice spends + appends ---
	var cs: Combatant = _mk_pc(3, 0)
	var pcs: MainPhasePlan = MainPhasePlan.new(cs, storm, 2, 5, 0, 2)
	pcs.toggle_splice()
	pcs.commit()
	_check(cs.turn_reels.size() == 4, "commit splice -> 4 reels (got %d)" % cs.turn_reels.size())
	_check(cs.resource_pool.stamina == 1, "commit splice spent 2 STA (got %d)" % cs.resource_pool.stamina)

	# --- commit: fire consumes meter + arms wild, never touches stamina ---
	var cf: Combatant = _mk_pc(4, 10)
	var pcf: MainPhasePlan = MainPhasePlan.new(cf, storm, 2, 5, 0, 2)
	pcf.toggle_ultimate()
	pcf.commit()
	_check(cf.bonus_meter.value == 0, "commit fire consumed the meter (got %d)" % cf.bonus_meter.value)
	_check(cf.wild_reel_indices() == [0], "commit fire armed reel 0 (got %s)" % str(cf.wild_reel_indices()))
	_check(cf.resource_pool.stamina == 4, "commit fire did NOT spend stamina (got %d)" % cf.resource_pool.stamina)

	# --- commit: nothing staged is a no-op ---
	var cn: Combatant = _mk_pc(3, 10)
	var pcn: MainPhasePlan = MainPhasePlan.new(cn, storm, 2, 5, 0, 2)
	pcn.commit()
	_check(cn.turn_reels.size() == 3 and cn.resource_pool.stamina == 3 and cn.bonus_meter.value == 10, "empty commit is a no-op")

	print(("MAIN PHASE PLAN TEST PASSED" if _failures == 0 else "MAIN PHASE PLAN TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Build the class cache, then run the test to verify it fails**

Run: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --editor --quit`
then: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_main_phase_plan.gd`
Expected: FAIL — `MainPhasePlan` is not yet defined.

- [ ] **Step 3: Write `combat/main_phase_plan.gd`**

```gdscript
class_name MainPhasePlan
extends RefCounted

## The staged, not-yet-committed Main-Phase-1 choices for one combatant's turn
## (DESIGN spec: 2026-06-19-main1-staging-design.md). Toggling a choice only updates a PREVIEW —
## nothing is spent/consumed/applied until [method commit] runs on SPIN. A fresh instance is built
## each turn. Pure logic; the scene renders the preview and owns the buttons.

var combatant: Combatant
var splice_type: DamageType
var splice_cost: int
var reel_cap: int
var wild_reel: int
var wild_spins: int

var splice_staged: bool = false
var fire_ultimate_staged: bool = false

func _init(c: Combatant, p_splice_type: DamageType, p_splice_cost: int = 2, p_reel_cap: int = 5, p_wild_reel: int = 0, p_wild_spins: int = 2) -> void:
	combatant = c
	splice_type = p_splice_type
	splice_cost = p_splice_cost
	reel_cap = p_reel_cap
	wild_reel = p_wild_reel
	wild_spins = p_wild_spins

## True if a splice can be newly STAGED: affordable AND under the reel-cap. Un-staging is always allowed.
func can_stage_splice() -> bool:
	if combatant == null or combatant.resource_pool == null:
		return false
	return combatant.resource_pool.can_afford({&"stamina": splice_cost}) and combatant.turn_reels.size() < reel_cap

## True if the Ultimate can be newly STAGED: the Bonus Meter is armed. Un-staging is always allowed.
func can_stage_ultimate() -> bool:
	return combatant != null and combatant.bonus_meter != null and combatant.bonus_meter.is_armed()

## Un-stages if staged; else stages only when [method can_stage_splice].
func toggle_splice() -> void:
	if splice_staged:
		splice_staged = false
	elif can_stage_splice():
		splice_staged = true

## Un-stages if staged; else stages only when [method can_stage_ultimate].
func toggle_ultimate() -> void:
	if fire_ultimate_staged:
		fire_ultimate_staged = false
	elif can_stage_ultimate():
		fire_ultimate_staged = true

## The reels the spin WOULD use: the committed turn reels plus one staged splice reel (cap-respecting).
## Read-only — never mutates the combatant.
func preview_reels() -> Array[ActionReel]:
	var reels: Array[ActionReel] = combatant.turn_reels.duplicate()
	if splice_staged and reels.size() < reel_cap:
		reels.append(ActionReel.make_default(splice_type))
	return reels

## The Stamina the combatant WOULD have after committing (current minus a staged splice cost).
func preview_stamina() -> int:
	if combatant == null or combatant.resource_pool == null:
		return 0
	var s: int = combatant.resource_pool.stamina
	return (s - splice_cost) if splice_staged else s

## True if committing WOULD consume the Bonus Meter (an Ultimate is staged this turn).
func will_consume_meter() -> bool:
	return fire_ultimate_staged

## The reels that WOULD be wild at spin: already-active carryover wild unioned with a staged fire.
func effective_wild_indices() -> Array[int]:
	var out: Array[int] = combatant.wild_reel_indices().duplicate()
	if fire_ultimate_staged and not (wild_reel in out):
		out.append(wild_reel)
	return out

## Applies the staged choices via the committed Combatant methods. Called once, on SPIN. The methods
## carry their own guards; staging already validated, so they succeed. No-op when nothing is staged.
func commit() -> void:
	if splice_staged:
		combatant.try_splice_reel(splice_type, combatant.weapon.base_damage, splice_cost, reel_cap)
	if fire_ultimate_staged:
		combatant.fire_sticky_wild(wild_reel, wild_spins)
```

- [ ] **Step 4: Build the class cache, then run the test to verify it passes**

Run: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --editor --quit`
then: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_main_phase_plan.gd`
Expected: PASS — `MAIN PHASE PLAN TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/main_phase_plan.gd tests/test_main_phase_plan.gd combat/main_phase_plan.gd.uid
git commit -m "feat(combat): add MainPhasePlan staging layer for Main-1 actions"
```
(The `.uid` is generated by the cache build in Step 4; include it if present.)

---

## Task 2: Wire staging + preview into the orchestrator and panel

**Files:**
- Modify: `combat/ui/combatant_panel.gd` (add `preview_resources()` + `set_meter_flash()`)
- Modify: `combat/combat.gd` (staging toggles, per-toggle preview render, commit on SPIN, fresh plan per turn)
- Test: full suite + headless compile (no new headless suite — this is scene wiring; behavior is play-test-verified per CLAUDE.md §5)

**Interfaces:**
- Consumes: `MainPhasePlan` (Task 1) and its full API.
- Produces: no new public logic API — scene/view wiring. The Splice/Fire-Ultimate buttons stage (not apply); SPIN commits then spins.

- [ ] **Step 1: Add preview methods to `combat/ui/combatant_panel.gd`**

Add a tween field near the other vars (after `var _combatant: Combatant`):
```gdscript
var _meter_flash_tween: Tween
```

Add these two methods after the existing `refresh_resources()` method:
```gdscript
## Shows a pending Stamina change ("STA 3 → 1 / 5") while a cost is staged; falls back to the plain
## readout when preview matches current. Cleared/refreshed by refresh_resources() after a commit.
func preview_resources(preview_stamina: int) -> void:
	if _stamina_label == null:
		return
	if _combatant == null or _combatant.resource_pool == null:
		_stamina_label.text = ""
		return
	var cur: int = _combatant.resource_pool.stamina
	if preview_stamina != cur:
		_stamina_label.text = "STA %d → %d / %d" % [cur, preview_stamina, _combatant.resource_pool.max_stamina]
	else:
		_stamina_label.text = "STA %d/%d" % [cur, _combatant.resource_pool.max_stamina]

## Pulses the Bonus Meter bar while an Ultimate is staged (signals "will be consumed on SPIN").
## Steady (default colour) when off. Cosmetic only.
func set_meter_flash(on: bool) -> void:
	if _meter_bar == null:
		return
	if _meter_flash_tween != null and _meter_flash_tween.is_valid():
		_meter_flash_tween.kill()
		_meter_flash_tween = null
	if on:
		_meter_flash_tween = create_tween().set_loops()
		_meter_flash_tween.tween_property(_meter_bar, "modulate", Color(1.6, 1.4, 0.4), 0.4)
		_meter_flash_tween.tween_property(_meter_bar, "modulate", Color(0.9, 0.8, 0.3), 0.4)
	else:
		_meter_bar.modulate = Color(0.9, 0.8, 0.3)
```

- [ ] **Step 2: Add fields + make the strips caption a member in `combat/combat.gd`**

After `var _storm_type: DamageType` (line ~31) add:
```gdscript
var _strips_caption: Label
var _plan: MainPhasePlan
```

In `_build_ui()`, replace the local strips caption:
```gdscript
	var strips_caption := Label.new()
	strips_caption.text = "Action reels"
	strips_caption.position = Vector2(40, 208)
	add_child(strips_caption)
```
with:
```gdscript
	_strips_caption = Label.new()
	_strips_caption.text = "Action reels"
	_strips_caption.position = Vector2(40, 208)
	add_child(_strips_caption)
```

- [ ] **Step 3: Build a fresh plan per turn + render the initial preview**

In `_on_turn_started`, replace this block:
```gdscript
	c.begin_turn()
	_phase_manager.start_turn()  # runs Upkeep → Main 1, pauses for Main-1 actions
	_prepare_strips(c.turn_reels)
	_end_turn_button.disabled = true
	if c.is_player:
		_awaiting_player_spin = true
		_spin_button.disabled = false
	else:
		_awaiting_player_spin = false
		_spin_button.disabled = true
		get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_do_spin, CONNECT_ONE_SHOT)
	# Refresh AFTER _awaiting_player_spin is set — the splice button's enabled state reads it.
	_refresh_main1_actions()
```
with:
```gdscript
	c.begin_turn()
	_plan = MainPhasePlan.new(c, _storm_type, 2, 5, 0, 2)  # [ASSUMPTION] cost 2, cap 5, wild reel 0, 2 spins
	_phase_manager.start_turn()  # runs Upkeep → Main 1, pauses for Main-1 actions
	_end_turn_button.disabled = true
	if c.is_player:
		_awaiting_player_spin = true
		_spin_button.disabled = false
	else:
		_awaiting_player_spin = false
		_spin_button.disabled = true
		get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_do_spin, CONNECT_ONE_SHOT)
	# Render the preview AFTER _awaiting_player_spin is set — button states read it.
	_refresh_main1_preview()
```

- [ ] **Step 4: Turn the action handlers into staging toggles**

Replace `_on_splice_pressed` and `_on_ultimate_pressed` (the whole two functions, currently applying immediately) with:
```gdscript
## Stages/un-stages the Storm splice (toggle). Applies nothing — commit happens on SPIN.
func _on_splice_pressed() -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	_plan.toggle_splice()
	_refresh_main1_preview()

## Stages/un-stages the Sticky-Wild Ultimate (toggle). Consumes nothing — commit happens on SPIN.
func _on_ultimate_pressed() -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	_plan.toggle_ultimate()
	_refresh_main1_preview()
```

- [ ] **Step 5: Replace `_refresh_main1_actions` with `_refresh_main1_preview` + a preview-wild helper**

Replace the whole `_refresh_main1_actions()` function with these two functions:
```gdscript
## Renders the staged Main-1 preview: preview reels (+ staged splice), wild glow (staged + carryover),
## reel-count and Stamina deltas, meter flash, and the toggle buttons' enabled/staged visual state.
func _refresh_main1_preview() -> void:
	if _plan == null:
		return
	_prepare_strips(_plan.preview_reels())
	_highlight_preview_wild()

	var base_n: int = _attacker.turn_reels.size()
	var prev_n: int = _plan.preview_reels().size()
	_strips_caption.text = ("Action reels  (%d → %d)" % [base_n, prev_n]) if prev_n != base_n else "Action reels"

	var panel: CombatantPanel = _panels[_attacker]
	panel.preview_resources(_plan.preview_stamina())
	panel.set_meter_flash(_plan.will_consume_meter())

	var is_player_main1: bool = _awaiting_player_spin and _attacker != null and _attacker.is_player
	_splice_button.disabled = not (is_player_main1 and (_plan.splice_staged or _plan.can_stage_splice()))
	_ultimate_button.disabled = not (is_player_main1 and (_plan.fire_ultimate_staged or _plan.can_stage_ultimate()))
	_splice_button.modulate = Color(0.6, 1.0, 0.6) if _plan.splice_staged else Color(1, 1, 1)
	_ultimate_button.modulate = Color(0.6, 1.0, 0.6) if _plan.fire_ultimate_staged else Color(1, 1, 1)

## Glows the strips that WOULD be wild at spin (staged fire ∪ carryover), per the plan's preview.
func _highlight_preview_wild() -> void:
	var wild: Array[int] = _plan.effective_wild_indices() if _plan != null else []
	var strips: Array = _strips_box.get_children()
	for i: int in range(strips.size()):
		(strips[i] as ReelStrip).set_wild(i in wild)
```

- [ ] **Step 6: Commit the plan on SPIN, then spin from the committed state**

Replace `_on_spin_pressed` with:
```gdscript
func _on_spin_pressed() -> void:
	if not _awaiting_player_spin:
		return
	_awaiting_player_spin = false
	if _plan != null:
		_plan.commit()  # spends Stamina / consumes meter / appends reel / arms wild — the ONLY apply point
	_spin_button.disabled = true
	_splice_button.disabled = true
	_ultimate_button.disabled = true
	_splice_button.modulate = Color(1, 1, 1)
	_ultimate_button.modulate = Color(1, 1, 1)
	(_panels[_attacker] as CombatantPanel).set_meter_flash(false)
	_prepare_strips(_attacker.turn_reels)  # re-sync strips to the committed reels (incl. a spliced reel)
	_phase_manager.proceed_to_combat()     # commit Main 1 → enter Combat
	_do_spin()
```

- [ ] **Step 7: Reset the toggle visuals when the spin finishes**

In `_finish_spin`, replace:
```gdscript
	_attacker.consume_wild_spin()
	_highlight_wild_strips()
	_splice_button.disabled = true
```
with:
```gdscript
	_attacker.consume_wild_spin()
	_highlight_wild_strips()
	_splice_button.disabled = true
	_ultimate_button.disabled = true
	_splice_button.modulate = Color(1, 1, 1)
	_ultimate_button.modulate = Color(1, 1, 1)
	(_panels[_attacker] as CombatantPanel).set_meter_flash(false)
```

- [ ] **Step 8: Build the class cache / compile check + full suite**

Run: `"/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --editor --quit`
Expected: exits 0, no parse/script errors (this is the compile gate — `combat.gd` references `MainPhasePlan` and the new panel methods).

Then run every suite and confirm each prints `… TEST PASSED`:
```bash
for t in main_phase_plan effect resource_pool crushing_slow reel_splice ultimate_sticky_wild turn_manager combatant phase_manager bonus_meter action_reel combat_loop; do
  "/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://tests/test_$t.gd" 2>/dev/null | grep -q "TEST PASSED" && echo "PASS $t" || echo "FAIL $t"
done
```
Expected: every line `PASS`. (No suite drives the orchestrator UI; `test_combat_loop` exercises the loop logic and must stay green. The staging/preview behavior itself is play-test-verified.)

- [ ] **Step 9: Commit**

```bash
git add combat/combat.gd combat/ui/combatant_panel.gd
git commit -m "feat(combat): stage/preview Main-1 toggles, commit on SPIN"
```

---

## Final verification

- [ ] **Whole suite green:** the 12-suite loop in Task 2 Step 8 prints all `PASS`.
- [ ] **Compile clean:** `--editor --quit` exits 0 with no errors.
- [ ] **Human play-test (CLAUDE.md §5 — the feel is the human's call):** in `combat.tscn`, confirm: toggling Splice adds/removes the 4th reel in the preview and shows `STA 3 → 1` without spending; toggling Fire Ultimate glows reel 1 and pulses the meter without consuming it; **both can be toggled off**; splice can only be staged once (no second reel); pressing SPIN commits both (Stamina debited, meter consumed, reel 1 crits) and resolves; on the carryover turn reel 1 still glows with no meter flash and no re-fire.

---

## Self-review notes (author)

- **Spec coverage:** spec §3.1 `MainPhasePlan` → Task 1 (all methods + the non-mutation property tested). spec §3.2 orchestrator → Task 2 Steps 3–7. spec §3.3 carryover → `effective_wild_indices` union (Task 1 test "carryover wild surfaces") + Task 2 `_highlight_preview_wild` + the no-flash path (fire not staged → `set_meter_flash(false)`). spec §4 indicators → Task 2 (strips, `preview_resources`, `set_meter_flash`, caption delta). spec §2 one-per-turn → single `splice_staged` bool (Task 1). spec §5 testing → Task 1 suite.
- **Type consistency:** `MainPhasePlan.new(c, storm, 2, 5, 0, 2)`, `toggle_splice/toggle_ultimate`, `preview_reels/preview_stamina/will_consume_meter/effective_wild_indices`, `commit`, `can_stage_splice/can_stage_ultimate` — used identically in the test, the class, and the orchestrator. Panel `preview_resources(int)` / `set_meter_flash(bool)` match their call sites in `_refresh_main1_preview`/`_on_spin_pressed`/`_finish_spin`.
- **Non-mutation guarantee** (the crux of "pure staging") is explicitly asserted in Task 1 (turn_reels/stamina/meter unchanged after preview calls).
- **Out of scope (spec §7):** no new abilities, no resolution/chart/Combatant-method changes, no skip-spin path, no reel-pick UI.

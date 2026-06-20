# Crit Diversity + Luck Stat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make spin results varied/non-patterned (shuffle reel face order), change the Ultimate from a forced uniform crit row to a 65%-crit-biased varied spin, and add the 6th stat **Luck** (edits reels to add crit-success faces).

**Architecture:** `ActionReel.make_default` shuffles its faces (balance-neutral — same counts, varied adjacency). The resolver's wild path becomes a 65% crit bias instead of a forced crit face. Luck is a new `Stats` field; `Combatant.apply_luck()` appends `luck` crit-success faces to each weapon reel (then reshuffles), applied once at setup. Approved design + decisions in `DECISIONS-LOG.md`.

**Tech Stack:** Godot 4.6.3-stable, GDScript (static-typed). Headless `SceneTree` tests.

## Global Constraints
- GDScript only — never C#; static typing; signals past-tense. (CLAUDE.md §2)
- **Per-combatant / N-vs-M safe** — Luck/reel edits are per-combatant (each combatant owns its weapon); no 1v1 hardcoding. (CLAUDE.md §7)
- **`[ASSUMPTION]`:** Ultimate wild crit chance **0.65**; Luck **+1 crit-success face per point** per weapon reel; reel face order shuffled per reel at creation (balance-neutral).
- **Pillar:** odds come from face COUNTS (the reel IS the dice) — Luck adds crit FACES, not hidden weights. Reel shuffle changes only adjacency, not counts. Round-up math unchanged.
- **Godot binary (NOT on PATH):** `/c/Godot_v4.6.3-stable_win64_console.exe`, from project root. Compile/cache: `… --editor --quit`. Benign at exit: `ObjectDB leaked`/`resources still in use` — judge by `… TEST PASSED` + exit 0.
- Decisions: `docs/superpowers/DECISIONS-LOG.md` (this cycle). Source of truth = `DESIGN.md`.

---

## Task 1: Reel shuffle + Ultimate crit-bias

**Files:** Modify `combat/resources/action_reel.gd` (shuffle), `combat/combat_resolver.gd` (wild bias); Test `tests/test_action_reel.gd` (composition order-independent), `tests/test_ultimate_sticky_wild.gd` (bias, statistical).

**Interfaces:** `ActionReel.make_default(type)` returns a reel whose faces are shuffled (same tier counts). Resolver: a wild reel lands its crit face with `WILD_CRIT_CHANCE` (0.65) probability, else a normal spin.

- [ ] **Step 1: Update the tests (RED).**
  - In `tests/test_action_reel.gd`: keep/ýadd an assertion that `make_default(...)` has the correct **tier counts** (1 crit-fail, 2 fail, 2 neutral, 4 success, 1 crit-success) computed by COUNTING faces (order-independent) — so it passes regardless of shuffle. (If the existing test asserts a specific face ORDER, change it to count tiers.)
  - In `tests/test_ultimate_sticky_wild.gd`: replace the "wild reel forces crit-success on spin 1/2" deterministic assertions with a **statistical** check — over **2000** wild resolves of a default reel, the crit-success rate is within **[0.58, 0.78]** (≈0.65 bias) AND strictly between the no-bias (~0.10) and forced (1.0) extremes; also assert **some** non-crit results occur (not always crit). Keep the arm/fire/consume/meter assertions unchanged (those still hold: firing arms the wild for 2 spins; only the per-spin OUTCOME is now biased not forced). Add a helper that resolves a single wild reel and returns its tier.

```gdscript
# (sketch for the statistical block in test_ultimate_sticky_wild.gd)
	var resolver: CombatResolver = CombatResolver.new()
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var crit := 0
	var noncrit := 0
	for i: int in range(2000):
		var reel: ActionReel = ActionReel.make_default(slashing)
		var atk: Array = resolver.resolve_combat_phase([reel], 10.0, null, [0])  # reel 0 wild
		if atk[0].face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: crit += 1
		else: noncrit += 1
	var rate: float = float(crit) / 2000.0
	_check(rate >= 0.58 and rate <= 0.78, "wild crit rate ~0.65 (got %.3f)" % rate)
	_check(noncrit > 0, "wild is biased, not forced (some non-crit)")
```

- [ ] **Step 2: Run both tests → RED** (shuffle not present / wild still forced).

- [ ] **Step 3: Shuffle in `combat/resources/action_reel.gd`.** At the end of `make_default`, before `return reel`, add `reel.faces.shuffle()`. (Balance-neutral; tier counts unchanged.)

- [ ] **Step 4: Crit-bias in `combat/combat_resolver.gd`.** Add a const `const WILD_CRIT_CHANCE: float = 0.65  # [ASSUMPTION]`. In `_resolve_single`, replace the wild face/index selection so a wild reel lands its crit face only with that probability:
```gdscript
	var face: ReelFace
	var index: int
	if is_wild and randf() < WILD_CRIT_CHANCE:
		face = _crit_face(reel)
		index = reel.faces.find(face)
	else:
		face = reel.spin()
		index = reel.get_last_index()
```
(The non-crit wild case is a normal weighted spin; combined with shuffled order this gives varied grids. `_crit_face` already falls back to a spin if the reel has no crit face.)

- [ ] **Step 5: Run both tests → GREEN.** Then regression: `test_payline_grid`, `test_crushing_slow`, `test_reel_splice`, `test_combat_loop` → green (shuffle is balance-neutral; the wild param still drives the bias).

- [ ] **Step 6: Commit** — `git add` the two source files + two tests; `git commit -m "feat(combat): shuffle reel face order; Ultimate crit-bias 65% (was forced)"`.

---

## Task 2: Luck stat (6th) + reel crit-face edit + demo + readout

**Files:** Modify `combat/resources/stats.gd` (`luck`), `combat/combatant.gd` (`apply_luck`), `combat/combat.gd` (wire + gear Luck on Martin), `combat/ui/combatant_panel.gd` (`LCK` in stat line); Test `tests/test_stats.gd` (luck + apply_luck).

**Interfaces:** `Stats.luck: int` (and summed in `plus`). `Combatant.apply_luck()` appends `effective_stats().luck` crit-success faces to each `weapon.reels` reel, then shuffles that reel.

- [ ] **Step 1: Write the failing test** — append to `tests/test_stats.gd` (before final print):
```gdscript
	# --- Luck: plus() includes luck; apply_luck adds crit faces to each weapon reel ---
	var ls: Stats = Stats.new(); ls.luck = 2
	_check(ls.plus(Stats.new()).luck == 2, "Stats.plus sums luck")
	var slashing2: DamageType = load("res://combat/resources/types/slashing.tres")
	var lw: Weapon = Weapon.new()
	lw.base_damage = 10.0
	lw.reels.append(ActionReel.make_default(slashing2))
	var base_crit: int = 0
	for f: ReelFace in lw.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: base_crit += 1
	var lc: Combatant = Combatant.new()
	lc.weapon = lw
	lc.base_stats = ls   # luck 2
	lc.apply_luck()
	var new_crit: int = 0
	for f: ReelFace in lc.weapon.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: new_crit += 1
	_check(new_crit == base_crit + 2, "apply_luck adds 2 crit faces (Luck 2): %d -> %d" % [base_crit, new_crit])
	# Idempotency note: apply_luck is called ONCE at setup; not re-applied.
```

- [ ] **Step 2: Run → RED** (`luck`/`apply_luck` undefined).

- [ ] **Step 3: Add `luck` to `combat/resources/stats.gd`** — add `@export var luck: int = 0` with the others, and include it in `plus`: `s.luck = luck + (other.luck if other != null else 0)`.

- [ ] **Step 4: Add `apply_luck` to `combat/combatant.gd`:**
```gdscript
## Edits this combatant's weapon reels to add crit-success faces equal to its Luck (the reel IS the
## dice — Luck raises crit ODDS via more crit FACES, then reshuffles to distribute them). Call ONCE
## at setup (after gear/apply_stats); not idempotent — do not re-apply. [ASSUMPTION] +1 face / Luck.
func apply_luck() -> void:
	if weapon == null:
		return
	var n: int = effective_stats().luck
	if n <= 0:
		return
	for reel: ActionReel in weapon.reels:
		for i: int in range(n):
			var f: ReelFace = ReelFace.new()
			f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
			f.multiplier = 2.0
			reel.faces.append(f)
		reel.faces.shuffle()
```

- [ ] **Step 5: Run → GREEN.**

- [ ] **Step 6: Wire into the orchestrator** — in `combat/combat.gd._make_combatant`, after `c.apply_stats()` and before `c.start_combat()`, add `c.apply_luck()`. Give Martin some Luck via gear: in `_build_scenario`, add `jerkin_stats.luck = 2` (`[ASSUMPTION]` — visible crit bump) to the Padded Jerkin (or a note that it's on the jerkin). The rat keeps Luck 0.

- [ ] **Step 7: Show `LCK` on the panel** — in `combat/ui/combatant_panel.gd._refresh_stats`, extend the stat line to include luck, e.g. `"MGT %d  FIN %d  VIG %d  FOC %d  GRT %d  LCK %d" % [s.might, s.finesse, s.vigor, s.focus, s.grit, s.luck]`.

- [ ] **Step 8: Compile + full suite** — `… --editor --quit` (exit 0); then every suite (stats, initiative_tiebreak, might_damage, stun, payline_library, payline_resolver, payline_grid, payline_rewards, effect, main_phase_plan, resource_pool, crushing_slow, reel_splice, ultimate_sticky_wild, turn_manager, combatant, phase_manager, bonus_meter, action_reel, combat_loop) → all `TEST PASSED`. Update any literal-damage/crit-count assertion changed by Luck/shuffle and note it.

- [ ] **Step 9: Commit** — `git commit -m "feat(combat): add Luck (6th stat) — edits reels to add crit faces; Martin demo + LCK readout"`.

---

## Final verification
- [ ] Whole suite green. Compile clean.
- [ ] **Human play-test:** Martin's panel shows `LCK 2`; his reels visibly crit a bit more often; the Ultimate now produces VARIED grids (not always top-HIT/mid-CRIT+/bottom-CRIT−) with crits ~65% per wild reel → diverse paylines.

## Self-review notes (author)
- **Coverage:** reel shuffle → T1 Step 3; Ultimate 65% bias → T1 Step 4 (+ statistical test); Luck stat → T2 (Stats.luck, apply_luck, wiring, readout). Luck "extra paylines" deferred (DECISIONS-LOG).
- **Types:** `WILD_CRIT_CHANCE`, `Stats.luck`, `apply_luck()`, `ReelFace.ResultTier.CRIT_SUCCESS` — consistent.
- **Balance-neutral shuffle:** make_default tier counts unchanged → damage/meter odds unchanged; only adjacency varies. Luck changes counts deliberately (more crit faces).
- **N-vs-M:** apply_luck mutates each combatant's OWN weapon reels once; per-combatant; no shared/1v1 assumption.
- **Idempotency:** apply_luck called once at setup; documented not-idempotent.

# Stat System + Starter Gear Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add 5 flat-modifier stats (Might/Finesse/Vigor/Focus/Grit) that feed damage/initiative/HP/resource-pool/Bonus-Meter, an initiative tie-break, and a starter armor piece equipping Might+Finesse on Martin.

**Architecture:** A `Stats` resource holds the 5 ints; `Gear` carries `stat_bonuses`; `Combatant.effective_stats()` = base + gear, and `apply_stats()` derives `max_hp`/`max_stamina`/`meter.floor`. Finesse folds into the initiative roll + breaks ties (with a stored d10 reel as the final tiebreak); Might is a flat per-hit damage add in the resolver. All new params default to no-op (backward compatible). Damage rounds up.

**Tech Stack:** Godot 4.6.3-stable, GDScript (static-typed). Headless `SceneTree` tests under `tests/`.

## Global Constraints

- **Engine Godot 4.6.3-stable. GDScript only — never C#.** Data = `Resource`; static typing. (CLAUDE.md §2)
- **Naming LOCKED:** classes PascalCase, files snake_case, signals snake_case past-tense.
- **Flat direct modifiers:** the stat int IS the bonus (no curve). `[ASSUMPTION]` raw 1:1 for all five.
- **Mappings:** Might→flat damage/hit; Finesse→initiative + tie-break; Vigor→max HP; Focus→max Stamina; Grit→Bonus-Meter floor.
- **Tie-break order:** `current_initiative` desc → effective Finesse desc → stored `tiebreak_roll` (d10) desc.
- **Round UP (`ceili`)** all damage. New params default to no-op (existing callers/tests unaffected).
- **Godot binary (NOT on PATH):** `/c/Godot_v4.6.3-stable_win64_console.exe`, from the project root. New `class_name`s need a cache build first (`… --editor --quit`); also the compile check. Benign at exit: `ObjectDB leaked`/`resources still in use` — judge by `… TEST PASSED` + exit 0.
- Implements `docs/superpowers/specs/2026-06-20-stat-system-design.md`. Source of truth = `DESIGN.md`.

---

## File Structure
**New:** `combat/resources/stats.gd` (`Stats`), `combat/resources/gear.gd` (`Gear`); tests `test_stats.gd`, `test_initiative_tiebreak.gd`, `test_might_damage.gd`.
**Modified:** `combat/combatant.gd` (stats/gear/effective_stats/apply_stats/tiebreak_roll), `combat/turn_manager.gd` (finesse roll + comparator), `combat/combat_resolver.gd` (`flat_damage_bonus`), `combat/combat.gd` (build with stats+gear, pass might, stat readout), `combat/ui/combatant_panel.gd` (stat line).

---

## Task 1: `Stats` + `Gear` resources + `Combatant` integration

**Files:** Create `combat/resources/stats.gd`, `combat/resources/gear.gd`; Modify `combat/combatant.gd`; Test `tests/test_stats.gd`.

**Interfaces:**
- `Stats` (Resource): `might/finesse/vigor/focus/grit: int`; `plus(other: Stats) -> Stats`.
- `Gear` (Resource): `display_name: String`, `enum Slot {WEAPON,ARMOR,TRINKET}`, `slot: Slot`, `stat_bonuses: Stats`.
- `Combatant`: `base_stats: Stats`, `gear: Array[Gear]`, `base_max_hp/base_max_stamina/base_meter_floor: int`, `tiebreak_roll: int`; `effective_stats() -> Stats`; `apply_stats() -> void`.

- [ ] **Step 1: Write the failing test** — create `tests/test_stats.gd`:

```gdscript
extends SceneTree

# Headless unit test for Stats/Gear + Combatant stat integration (DESIGN spec 2026-06-20).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stats.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _stats(mi: int, fi: int, vi: int, fo: int, gr: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr
	return s

func _initialize() -> void:
	# plus() sums fields.
	var sum: Stats = _stats(1,2,3,4,5).plus(_stats(10,20,30,40,50))
	_check(sum.might == 11 and sum.finesse == 22 and sum.vigor == 33 and sum.focus == 44 and sum.grit == 55, "Stats.plus sums fields")

	# effective_stats = base + each gear's bonuses.
	var c: Combatant = Combatant.new()
	c.base_stats = _stats(1,0,0,0,0)
	var jerkin: Gear = Gear.new()
	jerkin.slot = Gear.Slot.ARMOR
	jerkin.stat_bonuses = _stats(3,2,0,0,0)
	c.gear = [jerkin]
	var eff: Stats = c.effective_stats()
	_check(eff.might == 4 and eff.finesse == 2, "effective = base Might 1 + jerkin Might 3 = 4, Finesse 2 (got M%d F%d)" % [eff.might, eff.finesse])

	# apply_stats derives max_hp / max_stamina / meter.floor from effective stats.
	var d: Combatant = Combatant.new()
	d.base_max_hp = 40; d.base_max_stamina = 5; d.base_meter_floor = 3
	d.resource_pool = ResourcePool.new(); d.resource_pool.stamina = 5
	d.bonus_meter = BonusMeter.new()
	d.base_stats = _stats(0,0,2,1,4)  # vigor 2, focus 1, grit 4
	d.apply_stats()
	_check(d.max_hp == 42, "max_hp = base 40 + vigor 2 = 42 (got %d)" % d.max_hp)
	_check(d.resource_pool.max_stamina == 6, "max_stamina = base 5 + focus 1 = 6 (got %d)" % d.resource_pool.max_stamina)
	_check(d.bonus_meter.floor == 7, "meter floor = base 3 + grit 4 = 7 (got %d)" % d.bonus_meter.floor)

	# null base_stats / no gear -> all zeros (safe).
	var e: Combatant = Combatant.new()
	var z: Stats = e.effective_stats()
	_check(z.might == 0 and z.finesse == 0, "no base/gear -> zero stats")

	print(("STATS TEST PASSED" if _failures == 0 else "STATS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Build cache, run to verify it fails** — `… --editor --quit` then `… --script res://tests/test_stats.gd` → FAIL (`Stats`/`Gear` undefined).

- [ ] **Step 3: Write `combat/resources/stats.gd`**

```gdscript
class_name Stats
extends Resource

## The five character stats (DESIGN spec 2026-06-20). Flat direct modifiers — the value IS the bonus.
## Might→damage, Finesse→initiative+tiebreak, Vigor→HP, Focus→resource pool, Grit→Bonus-Meter floor.
## [ASSUMPTION] working range ~0–6.

@export var might: int = 0
@export var finesse: int = 0
@export var vigor: int = 0
@export var focus: int = 0
@export var grit: int = 0

## Returns a new Stats with each field summed (this + other). Null other is treated as zeroes.
func plus(other: Stats) -> Stats:
	var s: Stats = Stats.new()
	s.might = might + (other.might if other != null else 0)
	s.finesse = finesse + (other.finesse if other != null else 0)
	s.vigor = vigor + (other.vigor if other != null else 0)
	s.focus = focus + (other.focus if other != null else 0)
	s.grit = grit + (other.grit if other != null else 0)
	return s
```

- [ ] **Step 4: Write `combat/resources/gear.gd`**

```gdscript
class_name Gear
extends Resource

## An equippable item (DESIGN.md A7: Weapon/Armor/Trinket). For now it carries stat bonuses only;
## Combatant.effective_stats() reads them. (Weapon reel-editing / Trinket effects are future work.)

enum Slot { WEAPON, ARMOR, TRINKET }

@export var display_name: String = ""
@export var slot: Slot = Slot.ARMOR
@export var stat_bonuses: Stats
```

- [ ] **Step 5: Modify `combat/combatant.gd`** — add fields + methods.

After `var resource_pool: ResourcePool` add:
```gdscript
## Base (innate) stats from race/class. Gear adds on top — see [method effective_stats].
var base_stats: Stats

## Equipped items contributing stat bonuses (DESIGN.md A7).
var gear: Array[Gear] = []

## Pre-stat seeds; the live max_hp / pool max / meter floor are DERIVED in [method apply_stats].
var base_max_hp: int = 1
var base_max_stamina: int = 0
var base_meter_floor: int = 0
```
After `var base_initiative: int = 0` add:
```gdscript
## Final initiative tie-break — a stored d10 reel roll set in TurnManager.roll_initiative.
var tiebreak_roll: int = 0
```
Add to the Public API (near `recompute_initiative`):
```gdscript
## Effective stats = base_stats + every equipped gear's stat_bonuses (null-safe → zeroes).
func effective_stats() -> Stats:
	var s: Stats = Stats.new()
	if base_stats != null:
		s = s.plus(base_stats)
	for g: Gear in gear:
		if g != null:
			s = s.plus(g.stat_bonuses)
	return s

## Recomputes the stat-derived values (max HP / pool max / meter floor). Call at setup AFTER gear is
## equipped and BEFORE start_combat(). [ASSUMPTION] flat 1:1 mappings.
func apply_stats() -> void:
	var s: Stats = effective_stats()
	max_hp = base_max_hp + s.vigor
	if resource_pool != null:
		resource_pool.max_stamina = base_max_stamina + s.focus
		resource_pool.stamina = mini(resource_pool.stamina, resource_pool.max_stamina)
	if bonus_meter != null:
		bonus_meter.floor = base_meter_floor + s.grit
```

- [ ] **Step 6: Build cache, run to verify it passes** — `STATS TEST PASSED`, exit 0.

- [ ] **Step 7: Commit**
```bash
git add combat/resources/stats.gd combat/resources/gear.gd combat/resources/stats.gd.uid combat/resources/gear.gd.uid combat/combatant.gd tests/test_stats.gd
git commit -m "feat(combat): Stats + Gear resources; Combatant effective_stats + apply_stats"
```

---

## Task 2: Finesse → initiative + tie-break (`TurnManager`)

**Files:** Modify `combat/turn_manager.gd`; Test `tests/test_initiative_tiebreak.gd`.

**Interfaces:**
- Consumes: `Combatant.effective_stats()`, `Combatant.tiebreak_roll`, `Combatant.base_initiative`.
- Produces: `roll_initiative` folds Finesse into `base_initiative` and sets `tiebreak_roll`; `get_turn_order` breaks ties by Finesse then `tiebreak_roll`.

- [ ] **Step 1: Write the failing test** — create `tests/test_initiative_tiebreak.gd`:

```gdscript
extends SceneTree

# Headless test: initiative tie-break order = current_initiative -> Finesse -> tiebreak_roll.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_initiative_tiebreak.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(name: String, init: int, finesse: int, tb: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name
	c.base_stats = Stats.new(); c.base_stats.finesse = finesse
	c.current_initiative = init
	c.tiebreak_roll = tb
	return c

func _names(order: Array) -> Array:
	var out: Array = []
	for c: Combatant in order: out.append(c.display_name)
	return out

func _initialize() -> void:
	var tm: TurnManager = TurnManager.new()

	# Equal current_initiative -> higher Finesse acts first.
	tm.combatants = [_mk("lowFin", 50, 1, 5), _mk("highFin", 50, 4, 5)]
	_check(_names(tm.get_turn_order()) == ["highFin", "lowFin"], "tie broken by Finesse: %s" % str(_names(tm.get_turn_order())))

	# Equal current_initiative + equal Finesse -> higher tiebreak_roll first.
	tm.combatants = [_mk("lowRoll", 50, 2, 3), _mk("highRoll", 50, 2, 9)]
	_check(_names(tm.get_turn_order()) == ["highRoll", "lowRoll"], "tie broken by tiebreak_roll: %s" % str(_names(tm.get_turn_order())))

	# Higher current_initiative still wins regardless of finesse/roll.
	tm.combatants = [_mk("fast", 80, 0, 0), _mk("slow", 30, 9, 9)]
	_check(_names(tm.get_turn_order()) == ["fast", "slow"], "current_initiative dominates")

	# roll_initiative folds Finesse into base_initiative and sets a tiebreak_roll in 0..9.
	var tm2: TurnManager = TurnManager.new()
	var hero: Combatant = Combatant.new(); hero.base_stats = Stats.new(); hero.base_stats.finesse = 5
	tm2.combatants = [hero]
	tm2.roll_initiative()
	_check(hero.base_initiative >= 1 + 5 and hero.base_initiative <= 100 + 5, "finesse folded into base_initiative (got %d)" % hero.base_initiative)
	_check(hero.current_initiative == hero.base_initiative, "current == base after roll (no effects)")
	_check(hero.tiebreak_roll >= 0 and hero.tiebreak_roll <= 9, "tiebreak_roll in 0..9 (got %d)" % hero.tiebreak_roll)

	print(("INITIATIVE TIEBREAK TEST PASSED" if _failures == 0 else "INITIATIVE TIEBREAK TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run to verify it fails** — `… --script res://tests/test_initiative_tiebreak.gd` → FAIL (finesse not folded; comparator ignores finesse/tiebreak).

- [ ] **Step 3: Modify `combat/turn_manager.gd`** — `roll_initiative`:
```gdscript
func roll_initiative() -> void:
	for c: Combatant in combatants:
		var value: int = InitiativeReel.roll_percentile(_initiative_tens, _initiative_ones)
		c.base_initiative = value + c.effective_stats().finesse
		c.tiebreak_roll = _initiative_tens.spin().digit  # stored d10 final tie-break (a spin, not randf)
		c.recompute_initiative()
		initiative_rolled.emit(c, value)
```
`get_turn_order` comparator:
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

- [ ] **Step 4: Run to verify it passes** — `INITIATIVE TIEBREAK TEST PASSED`, exit 0.

- [ ] **Step 5: Regression** — run `test_turn_manager` (its `_mk` sets `current_initiative` directly and leaves finesse 0/tiebreak 0, so sorting is unchanged for distinct values) and `test_combat_loop`. Both must stay green.

- [ ] **Step 6: Commit**
```bash
git add combat/turn_manager.gd tests/test_initiative_tiebreak.gd
git commit -m "feat(combat): Finesse folds into initiative + breaks ties (Finesse, then d10)"
```

---

## Task 3: Might → flat damage (`CombatResolver`)

**Files:** Modify `combat/combat_resolver.gd`; Test `tests/test_might_damage.gd`.

**Interfaces:**
- Produces: `resolve_combat_phase(..., flat_damage_bonus: int = 0, ...)` — added per damaging reel; default 0 = no-op.

- [ ] **Step 1: Write the failing test** — create `tests/test_might_damage.gd`:

```gdscript
extends SceneTree

# Headless test: Might adds flat damage per damaging hit (round-up order preserved).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_might_damage.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _one_face(tier: ReelFace.ResultTier, mult: float) -> ActionReel:
	var r: ActionReel = ActionReel.new()
	var f: ReelFace = ReelFace.new(); f.result_tier = tier; f.multiplier = mult
	r.faces.append(f)
	return r

func _initialize() -> void:
	var resolver: CombatResolver = CombatResolver.new()
	var SU := ReelFace.ResultTier.SUCCESS
	var NE := ReelFace.ResultTier.NEUTRAL

	# Success, base 10, no type (x1.0), Might +3 -> 13.
	var a: Array = resolver.resolve_combat_phase([_one_face(SU, 1.0)], 10.0, null, [], 1, 3)
	_check(a[0].final_damage == 13, "10x1 + Might 3 = 13 (got %d)" % a[0].final_damage)

	# Default flat_damage_bonus 0 -> unchanged (regression).
	var b: Array = resolver.resolve_combat_phase([_one_face(SU, 1.0)], 10.0)
	_check(b[0].final_damage == 10, "Might default 0 -> 10 (got %d)" % b[0].final_damage)

	# Non-damaging tier (neutral) gets NO flat bonus.
	var c: Array = resolver.resolve_combat_phase([_one_face(NE, 0.0)], 10.0, null, [], 1, 3)
	_check(c[0].final_damage == 0, "neutral + Might 3 -> 0 damage (got %d)" % c[0].final_damage)

	print(("MIGHT DAMAGE TEST PASSED" if _failures == 0 else "MIGHT DAMAGE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run to verify it fails** — `… --script res://tests/test_might_damage.gd` → FAIL (extra positional arg / no bonus applied).

- [ ] **Step 3: Modify `combat/combat_resolver.gd`** — insert `flat_damage_bonus` after `weapon_reel_count`, before `extra_lines`, in `resolve_combat_phase`:
```gdscript
func resolve_combat_phase(reels: Array[ActionReel], base_damage: float, target_type: DamageType = null, wild_reel_indices: Array[int] = [], weapon_reel_count: int = -1, flat_damage_bonus: int = 0, extra_lines: Array = []) -> Array[AttackResult]:
```
Pass it into `_resolve_single` in the loop — change `_resolve_single(reels[i], base_damage, target_type, is_wild)` to `_resolve_single(reels[i], base_damage, target_type, is_wild, flat_damage_bonus)`. Update `_resolve_single`'s signature and the damage line:
```gdscript
func _resolve_single(reel: ActionReel, base_damage: float, target_type: DamageType, is_wild: bool = false, flat_damage_bonus: int = 0) -> AttackResult:
```
and where it computes `final_damage` for a damaging face:
```gdscript
			attack.final_damage = ceili(raw * type_mult) + flat_damage_bonus
```
(Only the `deals_damage()` branch — non-damaging tiers stay 0.)

> Implementer note: the orchestrator's existing payline call passes 5 args (`…, weapon_reel_count`); with `flat_damage_bonus` inserted before `extra_lines`, that call still resolves (both default). Task 4 updates it to pass Might.

- [ ] **Step 4: Run to verify it passes** — `MIGHT DAMAGE TEST PASSED`, exit 0.

- [ ] **Step 5: Regression** — run `test_payline_grid`, `test_crushing_slow`, `test_combat_loop` → green (the new param defaults to no-op).

- [ ] **Step 6: Commit**
```bash
git add combat/combat_resolver.gd tests/test_might_damage.gd
git commit -m "feat(combat): Might adds flat damage per hit (resolver flat_damage_bonus)"
```

---

## Task 4: Orchestrator wiring + starter gear + stat readout

**Files:** Modify `combat/combat.gd`, `combat/ui/combatant_panel.gd`; Test `tests/test_combat_loop.gd` (pass Might in the loop).

**Interfaces:** Consumes Tasks 1–3. View/wiring; verified by compile + full suite + play-test.

- [ ] **Step 1: Update the integration loop** — in `tests/test_combat_loop.gd._on_turn_started`, pass Might so the integration exercises it. Change the resolve call to append `c.effective_stats().might`:
```gdscript
	var attacks: Array = _resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, defender.defense_type, c.wild_reel_indices(), c.weapon.reels.size(), c.effective_stats().might)
```

- [ ] **Step 2: Run it to verify it still passes** — `test_combat_loop` → green (combatants have no stats → Might 0, unchanged).

- [ ] **Step 3: Build combatants with stats + gear in `combat/combat.gd`** — replace `_make_combatant` to seed base_* + stats + gear and derive via `apply_stats()`:

Find the current `_make_combatant` body that sets `c.max_hp = max_hp` … `c.start_combat()` and replace the relevant lines so it takes stats/gear. New signature + body:
```gdscript
func _make_combatant(name: String, is_player: bool, max_hp: int, defense: DamageType, weapon: Weapon, meter_visible: bool, base_stats: Stats = null, items: Array[Gear] = []) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name
	c.is_player = is_player
	c.defense_type = defense
	c.weapon = weapon
	c.base_max_hp = max_hp
	c.base_meter_floor = 3
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = 10
	meter.is_visible = meter_visible
	c.bonus_meter = meter
	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = 3
		pool.regen_per_turn = 1
		c.resource_pool = pool
		c.base_max_stamina = 5
	c.base_stats = base_stats
	c.gear = items
	c.apply_stats()       # derive max_hp / max_stamina / meter.floor from stats BEFORE seeding hp
	c.start_combat()
	return c
```
(The old code set `meter.floor = 3` and `pool.max_stamina = 5` directly — those become `base_meter_floor`/`base_max_stamina` + `apply_stats()`.)

- [ ] **Step 4: Equip Martin's starter gear in `_build_scenario`** — after loading types, before building `_pc`, add the Padded Jerkin and build Martin with it:
```gdscript
	# [ASSUMPTION] starter armor: Might 3 (noticeable +3/hit), Finesse 2 (wins the init tie vs the rat).
	var jerkin_stats: Stats = Stats.new()
	jerkin_stats.might = 3
	jerkin_stats.finesse = 2
	var jerkin: Gear = Gear.new()
	jerkin.display_name = "Padded Jerkin"
	jerkin.slot = Gear.Slot.ARMOR
	jerkin.stat_bonuses = jerkin_stats
```
Then change the `_pc` / `_enemy` construction to pass stats/gear:
```gdscript
	_pc = _make_combatant("Martin (Mouse)", true, 100, slashing, _make_weapon(10.0, slashing, 3), true, Stats.new(), [jerkin])
	_enemy = _make_combatant("Cluny's Rat", false, 100, earth, _make_weapon(8.0, crushing, 2), false, Stats.new(), [])
```

- [ ] **Step 5: Pass Might into the spin** — in `combat/combat.gd._do_spin`, add `_attacker.effective_stats().might` to the resolve call:
```gdscript
	var attacks: Array = _resolver.resolve_combat_phase(reels, _attacker.weapon.base_damage, _defender.defense_type, _attacker.wild_reel_indices(), weapon_count, _attacker.effective_stats().might)
```
(`weapon_count` is the existing local `= _attacker.weapon.reels.size()`.)

- [ ] **Step 6: Show stats on the panel** — in `combat/ui/combatant_panel.gd`, add a `_stats_label: Label` child in `_ready()` and set it in `bind()`:
```gdscript
func _refresh_stats() -> void:
	if _stats_label == null or _combatant == null:
		return
	var s: Stats = _combatant.effective_stats()
	_stats_label.text = "MGT %d  FIN %d  VIG %d  FOC %d  GRT %d" % [s.might, s.finesse, s.vigor, s.focus, s.grit]
```
Declare `var _stats_label: Label`, create it in `_ready()` (add to the `box`), and call `_refresh_stats()` from `bind()`. (Placeholder readout; feel judged in play-test.)

- [ ] **Step 7: Compile check + full suite**

Run `… --editor --quit` (exit 0). Then run every suite:
```bash
for t in stats initiative_tiebreak might_damage payline_library payline_resolver payline_grid payline_rewards effect main_phase_plan resource_pool crushing_slow reel_splice ultimate_sticky_wild turn_manager combatant phase_manager bonus_meter action_reel combat_loop; do
  "/c/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://tests/test_$t.gd" 2>/dev/null | grep -q "TEST PASSED" && echo "PASS $t" || echo "FAIL $t"
done
```
Expected: all `PASS`. Update any literal-damage assertion changed by Might/round-up and note it.

- [ ] **Step 8: Commit**
```bash
git add combat/combat.gd combat/ui/combatant_panel.gd tests/test_combat_loop.gd
git commit -m "feat(combat): wire stats+gear into combatants; Padded Jerkin on Martin; stat readout"
```

---

## Final verification
- [ ] **Whole suite green** (19 suites). **Compile clean.**
- [ ] **Human play-test (CLAUDE.md §5):** Martin's panel shows `MGT 3 FIN 2 …`; his hits land ~+3 higher than before (Might 3); he reliably wins initiative ties vs the rat (Finesse 2 + tie-break). The rat (no stats) is unchanged.

## Self-review notes (author)
- **Spec coverage:** §2 Stats → Task 1; §3 levers → Task 1 (Vigor/Focus/Grit in apply_stats), Task 2 (Finesse), Task 3 (Might); §4 Combatant → Task 1; §5 Gear + starter → Tasks 1+4; §6 tie-break → Task 2; §7 Might resolver → Task 3; §8 orchestrator → Task 4; §9 tests → each task.
- **Type consistency:** `Stats{might,finesse,vigor,focus,grit}` + `plus`, `Gear{display_name,slot,stat_bonuses}`, `effective_stats()`, `apply_stats()`, `tiebreak_roll`, `flat_damage_bonus` param position (after `weapon_reel_count`, before `extra_lines`) — consistent across tasks/tests and the existing payline call.
- **Backward-compat:** `flat_damage_bonus` defaults 0; `apply_stats` only changes the live scenario; existing `test_turn_manager`/`test_combat_loop` use zero stats. Regression steps included.
- **Out of scope (spec §11):** Luck, level-up growth, full gear loadout/item pool, type re-theming — none built.

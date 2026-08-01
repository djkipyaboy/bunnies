# Playtest Fixes Batch (2026-07-31) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the bugs and UI gaps found during the 2026-07-31 live playtest of the Team-Up! minigame and a deep Hollow Warden fight, and clear combat effects at the end of every fight per the player's design decision.

**Architecture:** Seven independent, small fixes to `combat/combat.gd`, `combat/combatant.gd`, `combat/ui/combatant_panel.gd`, and `combat/ui/team_up_panel.gd`. No new files except tests. Each task is a self-contained bug fix or UI addition with its own headless test; none depend on another task's code (though several touch the same files, so run them in the listed order to avoid merge conflicts).

**Tech Stack:** Godot 4.6.3-stable, GDScript, headless test runner (`Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/<file>.gd`, executable lives ONE DIRECTORY ABOVE the repo at `C:\bunnies\bunnies-main\`).

## Global Constraints

- Godot 4.6.3-stable, GDScript only — no C#.
- Static typing throughout (typed vars, typed function signatures).
- All combat damage/heal math rounds UP (`ceili`), project-wide — never floor/round-to-nearest.
- Naming: PascalCase classes, snake_case script files, snake_case past-tense signals, `_on_<emitter>_<signal>` handlers.
- Keep every design N-vs-M / party-ready — no 1v1-only assumptions in new code.
- Run each new/modified test via the headless runner and confirm PASS before committing.
- Balance/magnitude numbers already in the code (Guarded 0.75, Indestructible 0.0, etc.) are pre-existing `[ASSUMPTION]`s — do not retune them as part of these fixes.

---

### Task 1: Payline crit-line bonus damage and splash damage must respect incoming/outgoing damage multipliers

**Files:**
- Modify: `combat/combat.gd:2284-2323` (`_on_paylines_resolved`, `CRIT_SUCCESS` branch)
- Modify: `combat/combat.gd:2267-2280` (`_splash_half_to_others`)
- Test: Create `tests/test_payline_and_splash_damage_multiplier.gd`

**Interfaces:**
- Consumes: `Combatant.outgoing_damage_multiplier(defender: Combatant = null) -> float` (`combatant.gd:930`), `Combatant.incoming_damage_multiplier() -> float` (`combatant.gd:940`), `Combatant.take_damage(amount: int) -> void` (`combatant.gd:361`), `Combatant.attach_effect`/`remove_effect`/`has_effect` (all pre-existing).
- Produces: no new public API — this is an internal correctness fix. Both functions keep their existing signatures.

**Context:** Confirmed via direct code reading during the 2026-07-31 playtest debrief: the normal per-reel weapon attack path (`combat.gd:1854`) correctly multiplies damage by `_attacker.outgoing_damage_multiplier(_defender) * _defender.incoming_damage_multiplier()` before it reaches `take_damage()`. The CRIT LINE payline bonus (`_on_paylines_resolved`) and `_splash_half_to_others()` (used by Ranger Collateral Damage and Warden Earthquake) both call `take_damage()` with a raw, unmultiplied amount — silently bypassing Indestructible, Guarded, Weakened, Empowered, and any future incoming/outgoing multiplier effect. This is exactly why the Hollow Warden's crit-payline hits landed for real damage during the playtest while it was mechanically Indestructible.

- [ ] **Step 1: Write the failing test**

Create `tests/test_payline_and_splash_damage_multiplier.gd`:

```gdscript
extends SceneTree

## Headless test: payline crit-line bonus damage and _splash_half_to_others() must respect the
## SAME outgoing/incoming damage-multiplier math normal reel attacks already use (Indestructible,
## Guarded, etc.) — playtest 2026-07-31 found both paths calling take_damage() with a raw,
## unmitigated amount.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_payline_and_splash_damage_multiplier.gd

var _instance: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _make_armed_attacker(type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = "TestAttacker"
	c.is_player = true
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.base_stats = Stats.new()
	c.base_max_hp = 200
	c.apply_stats()
	c.start_combat()
	return c

func _make_target(is_player_side: bool) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = "TestTarget"
	c.is_player = is_player_side
	c.base_stats = Stats.new()
	c.base_max_hp = 300
	c.apply_stats()
	c.start_combat()
	return c

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Combat = _instance as Combat
		var crushing: DamageType = load("res://combat/resources/types/crushing.tres")

		# --- CRIT LINE bonus damage must respect the defender's incoming multiplier ---
		var attacker: Combatant = _make_armed_attacker(crushing)
		var defender: Combatant = _make_target(false)
		defender.attach_effect(EffectLibrary.make(&"indestructible"))
		combat._attacker = attacker
		combat._defender = defender
		combat._panels[attacker] = CombatantPanel.new()
		combat._panels[defender] = CombatantPanel.new()

		var hit := PaylineResolver.PaylineHit.new()
		hit.tier = ReelFace.ResultTier.CRIT_SUCCESS
		hit.length = 3
		hit.cells = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
		var hp_before: int = defender.hp
		combat._on_paylines_resolved([hit])
		_check(defender.hp == hp_before, "Indestructible blocks the CRIT LINE bonus entirely (dealt %d)" % (hp_before - defender.hp))

		defender.remove_effect(&"indestructible")
		hp_before = defender.hp
		combat._on_paylines_resolved([hit])
		_check(defender.hp < hp_before, "the CRIT LINE bonus still deals real damage once Indestructible is gone")

		# --- _splash_half_to_others() must apply each OTHER target's OWN incoming multiplier ---
		var splasher: Combatant = _make_armed_attacker(crushing)
		var primary: Combatant = _make_target(false)
		var guarded_enemy: Combatant = _make_target(false)
		guarded_enemy.attach_effect(EffectLibrary.make(&"guarded"))
		var plain_enemy: Combatant = _make_target(false)
		combat._attacker = splasher
		combat._defender = primary
		combat._turn_manager.combatants = [splasher, primary, guarded_enemy, plain_enemy]
		combat._panels[guarded_enemy] = CombatantPanel.new()
		combat._panels[plain_enemy] = CombatantPanel.new()

		var guarded_hp_before: int = guarded_enemy.hp
		var plain_hp_before: int = plain_enemy.hp
		combat._splash_half_to_others(splasher, 40, "Crushing")
		var guarded_dmg: int = guarded_hp_before - guarded_enemy.hp
		var plain_dmg: int = plain_hp_before - plain_enemy.hp
		_check(guarded_dmg > 0 and plain_dmg > 0, "both targets took some splash damage")
		_check(guarded_dmg < plain_dmg, "Guarded's 0.75 incoming multiplier reduces its splash vs. the plain target (guarded=%d plain=%d)" % [guarded_dmg, plain_dmg])
		_check(guarded_dmg == ceili(ceili(40 * 0.5) * 0.75), "Guarded splash matches ceil(ceil(40*0.5) * 0.75) exactly (got %d)" % guarded_dmg)

		print(("PAYLINE/SPLASH DAMAGE MULTIPLIER TEST PASSED" if _failures == 0 else "PAYLINE/SPLASH DAMAGE MULTIPLIER TEST FAILED: %d" % _failures))
		quit(_failures)
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `C:\bunnies\bunnies-main`): `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_payline_and_splash_damage_multiplier.gd`
Expected: FAIL on both the "Indestructible blocks the CRIT LINE bonus entirely" check and the "Guarded's 0.75 incoming multiplier reduces its splash" check (current code deals full, unmitigated damage in both cases).

- [ ] **Step 3: Fix `_on_paylines_resolved`'s CRIT_SUCCESS branch**

In `combat/combat.gd`, inside the `match hit.tier:` block's `ReelFace.ResultTier.CRIT_SUCCESS:` case, change:

```gdscript
			ReelFace.ResultTier.CRIT_SUCCESS:
				var weapon_type: DamageType = _attacker.weapon.reels[0].damage_type if not _attacker.weapon.reels.is_empty() else null
				var type_mult: float = weapon_type.multiplier_against(_defender.defense_type) if weapon_type != null else 1.0
				var bonus: int = ceili(_attacker.weapon_effective_base_damage() * (float(hit.length) / 3.0) * type_mult)
				_defender.take_damage(bonus)
```

to:

```gdscript
			ReelFace.ResultTier.CRIT_SUCCESS:
				var weapon_type: DamageType = _attacker.weapon.reels[0].damage_type if not _attacker.weapon.reels.is_empty() else null
				var type_mult: float = weapon_type.multiplier_against(_defender.defense_type) if weapon_type != null else 1.0
				var line_dmg_mult: float = _attacker.outgoing_damage_multiplier(_defender) * _defender.incoming_damage_multiplier()
				var bonus: int = ceili(_attacker.weapon_effective_base_damage() * (float(hit.length) / 3.0) * type_mult * line_dmg_mult)
				_defender.take_damage(bonus)
```

Leave the rest of the branch (the log line, `_append_banner`, the Inspirational block) unchanged.

- [ ] **Step 4: Fix `_splash_half_to_others`**

In `combat/combat.gd`, change:

```gdscript
func _splash_half_to_others(attacker: Combatant, total: int, type_label: String, fraction: float = 0.5) -> Array[Combatant]:
	var damaged: Array[Combatant] = []
	var splash: int = ceili(total * fraction)
	if splash <= 0:
		return damaged
	for other: Combatant in _enemies_of(attacker):
		if other == _defender:
			continue
		other.take_damage(splash)
		damaged.append(other)
		_log("  💥 splash → %s takes %d %s (%.0f%% of %d)." % [other.display_name, splash, type_label, fraction * 100.0, total])
		if _panels.has(other):
			(_panels[other] as CombatantPanel).refresh_status()
	return damaged
```

to:

```gdscript
func _splash_half_to_others(attacker: Combatant, total: int, type_label: String, fraction: float = 0.5) -> Array[Combatant]:
	var damaged: Array[Combatant] = []
	var base_splash: int = ceili(total * fraction)
	if base_splash <= 0:
		return damaged
	for other: Combatant in _enemies_of(attacker):
		if other == _defender:
			continue
		var dmg_mult: float = attacker.outgoing_damage_multiplier(other) * other.incoming_damage_multiplier()
		var splash: int = ceili(base_splash * dmg_mult)
		other.take_damage(splash)
		damaged.append(other)
		_log("  💥 splash → %s takes %d %s (%.0f%% of %d)." % [other.display_name, splash, type_label, fraction * 100.0, total])
		if _panels.has(other):
			(_panels[other] as CombatantPanel).refresh_status()
	return damaged
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_payline_and_splash_damage_multiplier.gd`
Expected: PASS, all checks `ok`.

- [ ] **Step 6: Run the pre-existing payline/collateral/earthquake suites to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_payline_grid.gd`, `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_collateral.gd`, `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_earthquake.gd`
Expected: all PASS unchanged (these don't exercise a non-neutral multiplier, so `dmg_mult`/`line_dmg_mult` default to 1.0 and behave exactly as before).

- [ ] **Step 7: Commit**

```bash
git add combat/combat.gd tests/test_payline_and_splash_damage_multiplier.gd
git commit -m "fix(combat): apply incoming/outgoing damage multipliers to payline crit-line bonus and splash damage"
```

---

### Task 2: Hollow Warden Indestructible must clear the instant both phase-2 minions die, not at the boss's next turn

**Files:**
- Modify: `combat/combat.gd:2212-2243` (`_check_boss_phase_transition`)
- Modify: `tests/test_boss_phase_transition.gd` (add a regression assertion)

**Interfaces:**
- Consumes: `Combatant.defeated` signal (`combatant.gd:376-377`, emitted exactly once at the hp==0 transition), `Combatant.boss_phase_two_active`/`boss_phase_minion_ids`/`remove_effect`/`attach_effect` (all pre-existing).
- Produces: new private method `_on_boss_phase_minion_defeated(c: Combatant) -> void` on `Combat` — internal, no other task depends on it.

**Context:** `_check_boss_phase_transition()` is only called from `_on_turn_started`, gated to when the acting combatant IS the boss — so under the current code, the "both minions dead → clear Indestructible" check only runs at the START of the boss's own next turn, even though the code's own docstring says it should fire "the instant both minions die." During the 2026-07-31 playtest, another PC's whole turn (including a Double or Nothing) resolved against the boss while it was mechanically still Indestructible, in the gap between the second minion dying and the boss's own turn starting.

- [ ] **Step 1: Add a failing regression assertion to the existing test**

In `tests/test_boss_phase_transition.gd`, find this block:

```gdscript
			# Kill both phase-2 minions — Indestructible clears, Empowered applies.
			for m: Combatant in boss.boss_phase_minion_ids:
				m.take_damage(m.hp)
			combat._check_boss_phase_transition(boss)
			_check(not boss.boss_phase_two_active, "phase 2 ends once both minions are dead")
			_check(not boss.has_effect(&"indestructible"), "Indestructible clears when phase 2 ends")
			_check(boss.has_effect(&"empowered"), "Empowered applies once phase 2 ends")
```

Replace it with (inserting the new instant-clear assertions BEFORE the existing poll call, so they prove the clear happened without needing that poll):

```gdscript
			# Kill both phase-2 minions — Indestructible must clear INSTANTLY (2026-07-31 fix), before
			# any further call to _check_boss_phase_transition() (i.e. before the boss's own next turn).
			for m: Combatant in boss.boss_phase_minion_ids:
				m.take_damage(m.hp)
			_check(not boss.has_effect(&"indestructible"), "Indestructible clears the INSTANT both phase-2 minions die, with no further poll needed")
			_check(not boss.boss_phase_two_active, "phase 2 flag clears instantly too")
			_check(boss.has_effect(&"empowered"), "Empowered applies instantly as well")
			combat._check_boss_phase_transition(boss)  # a subsequent poll must be a harmless no-op now
			_check(not boss.boss_phase_two_active, "phase 2 stays ended after the subsequent poll")
			_check(not boss.has_effect(&"indestructible"), "Indestructible stays cleared after the subsequent poll")
			_check(boss.has_effect(&"empowered"), "Empowered persists after the subsequent poll")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_boss_phase_transition.gd`
Expected: FAIL on the three new instant-clear checks (current code only clears when `_check_boss_phase_transition` itself is called and finds both minions dead — killing the minions directly via `take_damage` does not clear anything by itself yet).

- [ ] **Step 3: Implement the instant-clear fix**

In `combat/combat.gd`, change `_check_boss_phase_transition`:

```gdscript
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
```

to:

```gdscript
func _check_boss_phase_transition(c: Combatant) -> void:
	c.boss_turns_taken += 1
	if c.boss_phase_two_active:
		return   # clearing now fires instantly off the minions' own `defeated` signal — see _on_boss_phase_minion_defeated
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
		minion_a.defeated.connect(_on_boss_phase_minion_defeated.bind(c))
		minion_b.defeated.connect(_on_boss_phase_minion_defeated.bind(c))

## Fires the instant Indestructible clear the moment BOTH phase-2 minions are dead (playtest
## 2026-07-31: the previous turn-start-polled check left Indestructible mechanically active for
## every OTHER combatant's turn between the second minion's death and the boss's own next turn).
## Connected to each minion's `defeated` signal at spawn time in _check_boss_phase_transition().
func _on_boss_phase_minion_defeated(c: Combatant) -> void:
	if not c.boss_phase_two_active:
		return
	for m: Combatant in c.boss_phase_minion_ids:
		if m.is_alive():
			return
	c.remove_effect(&"indestructible")
	c.boss_phase_two_active = false
	var emp: Effect = EffectLibrary.make(&"empowered")
	emp.duration = 999   # "until end of combat" — this boss-only grant, not the 2-turn player-facing version
	c.attach_effect(emp)
	_log("  ☾ The Hollow Warden's minions have fallen — it is EMPOWERED!")
	if _panels.has(c):
		(_panels[c] as CombatantPanel).refresh_status()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_boss_phase_transition.gd`
Expected: PASS, every check `ok` (including the pre-existing cooldown/sacrifice checks later in the file — they only depend on the 40%-threshold branch, which this fix does not touch).

- [ ] **Step 5: Run the full Hollow Warden integration suite to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_hollow_warden_full_sequence.gd`
Expected: PASS unchanged.

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd tests/test_boss_phase_transition.gd
git commit -m "fix(combat): clear the Hollow Warden's Indestructible the instant both phase-2 minions die"
```

---

### Task 3: CombatantPanel must show already-active effects immediately, and Regrowth must refresh its target's panel

**Files:**
- Modify: `combat/ui/combatant_panel.gd:92-115` (`bind`)
- Modify: `combat/combat.gd:1770-1786` (Regrowth's `regrowth_pending` block)
- Test: Create `tests/test_combatant_panel_bind_shows_existing_effects.gd`
- Test: Modify `tests/test_regrowth.gd` (add an orchestrator-level assertion)

**Interfaces:**
- Consumes: `CombatantPanel.refresh_status()` (`combatant_panel.gd:146-158`, pre-existing, unchanged).
- Produces: no new public API — `bind()` keeps its existing signature; it now additionally calls `refresh_status()`.

**Context:** Every effect-mutating call site in `combat.gd` already calls `refresh_status()` immediately when it changes an effect — this is NOT a lazy, turn-start-only system. The one real gap is `CombatantPanel.bind()` itself: it never calls `refresh_status()` when a panel is first constructed. This is exactly why a combatant who already has an effect attached when a NEW panel is built for them (e.g. a real Combatant reused across encounters via CombatHandoff, or the Hollow Warden's phase-2 minions built mid-fight) shows a blank status line until their own first turn calls `_on_turn_started` → refresh. Separately, Regrowth's `ally.attach_effect(regen)` (`combat.gd:1784`) is missing the immediate `refresh_status()` call its sibling blocks (Foresight via the shield signal, the Warden curse block right below it) already have.

- [ ] **Step 1: Write the failing CombatantPanel test**

Create `tests/test_combatant_panel_bind_shows_existing_effects.gd`:

```gdscript
extends SceneTree

## Headless test: CombatantPanel.bind() must show an ALREADY-ACTIVE effect immediately, with no
## manual refresh_status() call needed — playtest 2026-07-31 found a combatant carrying an effect
## into a freshly-built panel (CombatHandoff reuses the same real Combatant across encounters)
## showed BLANK status until that combatant's own first turn.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combatant_panel_bind_shows_existing_effects.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	c.display_name = "TestCombatant"
	c.base_stats = Stats.new()
	c.base_max_hp = 100
	c.apply_stats()
	c.start_combat()
	c.attach_effect(EffectLibrary.make(&"guarded"))  # attached BEFORE the panel exists

	var panel: CombatantPanel = CombatantPanel.new()
	root.add_child(panel)  # _ready() must run before bind() for the labels to exist
	panel.bind(c)

	_check(panel._status_label.text.contains("GUARDED"), "bind() shows an already-active effect immediately (got '%s')" % panel._status_label.text)

	print(("COMBATANTPANEL BIND SHOWS EXISTING EFFECTS TEST PASSED" if _failures == 0 else "COMBATANTPANEL BIND SHOWS EXISTING EFFECTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combatant_panel_bind_shows_existing_effects.gd`
Expected: FAIL — `_status_label.text` is empty right after `bind()`.

- [ ] **Step 3: Fix `CombatantPanel.bind()`**

In `combat/ui/combatant_panel.gd`, at the end of `bind()`, change:

```gdscript
	if c.resource_pool != null:
		c.resource_pool.pool_changed.connect(_on_pool_changed)
	c.shield_changed.connect(_on_shield_changed)
	refresh_resources()
	refresh_shield()
	_refresh_stats()
	_refresh_types()
```

to:

```gdscript
	if c.resource_pool != null:
		c.resource_pool.pool_changed.connect(_on_pool_changed)
	c.shield_changed.connect(_on_shield_changed)
	refresh_resources()
	refresh_shield()
	refresh_status()
	_refresh_stats()
	_refresh_types()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combatant_panel_bind_shows_existing_effects.gd`
Expected: PASS.

- [ ] **Step 5: Write the failing Regrowth orchestrator test**

In `tests/test_regrowth.gd`, add this block right before the final `print(...)`/`quit(_failures)` lines (this requires the file to become a scene-driven test — change `func _initialize() -> void:` to keep its existing body but move the new scene-dependent check into a `_process`-driven block, since `_initialize()` alone can't instantiate/wait on `combat.tscn`):

Replace the file's structure so it reads:

```gdscript
extends SceneTree

# Headless test: Warden "Regrowth" (L7, Task 30) — stage_regrowth spends Mana and flags the
# pending ally-Regen grant. The ally-picking (_lowest_hp_pct_ally) and attach_effect(&"regen")
# application are orchestrator-level (combat.gd) — verified end-to-end below via _commit_main1().
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_regrowth.gd

var _instance: Node
var _frames: int = 0
var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames != 2:
		return false

	# --- stage_regrowth spends Mana + flags pending when affordable ---
	var warden: Combatant = Combatant.new()
	warden.resource_pool = ResourcePool.new()
	warden.resource_pool.mana = 4
	warden.resource_pool.max_mana = 12
	_check(warden.stage_regrowth(4), "stage succeeds with 4 mana")
	_check(warden.regrowth_pending, "pending flag set")
	_check(warden.resource_pool.mana == 0, "4 mana spent (got %d)" % warden.resource_pool.mana)

	# --- unaffordable → false, no change ---
	_check(not warden.stage_regrowth(4), "stage fails when unaffordable")
	_check(warden.resource_pool.mana == 0, "mana unchanged on failed stage (got %d)" % warden.resource_pool.mana)
	_check(warden.regrowth_pending, "pending flag unchanged (still true) on failed stage")

	# --- a fresh combatant that never staged never has the flag set ---
	var other: Combatant = Combatant.new()
	other.resource_pool = ResourcePool.new()
	other.resource_pool.mana = 0
	other.resource_pool.max_mana = 12
	_check(not other.stage_regrowth(4), "stage fails with 0 mana")
	_check(not other.regrowth_pending, "pending flag stays false when unaffordable from the start")

	# --- Regression (final-review finding I1): unseeded regen heals 0, seeded-from-weapon heals > 0 ---
	var unseeded: Effect = EffectLibrary.make(&"regen")
	unseeded.stacks = 1
	_check(unseeded.dot_damage() == 0, "BUG regression check: unseeded regen heals 0 (got %d)" % unseeded.dot_damage())

	var seeded: Effect = EffectLibrary.make(&"regen")
	seeded.dot_base_damage = 20.0  # stand-in for _attacker.weapon.base_damage
	seeded.stacks = 1
	_check(seeded.dot_damage() > 0, "FIX check: regen seeded from weapon base heals > 0 (got %d)" % seeded.dot_damage())

	# --- orchestrator-level: Regrowth's target's panel must refresh IMMEDIATELY, not just at their
	# own next turn (playtest 2026-07-31 found this call site missing the refresh its siblings have).
	var combat: Combat = _instance as Combat
	var caster: Combatant = Combatant.new()
	caster.display_name = "Caster"; caster.is_player = true
	var w: Weapon = Weapon.new(); w.base_damage = 10.0
	caster.weapon = w
	caster.base_stats = Stats.new(); caster.base_max_hp = 100; caster.apply_stats(); caster.start_combat()
	var ally: Combatant = Combatant.new()
	ally.display_name = "Ally"; ally.is_player = true
	ally.base_stats = Stats.new(); ally.base_max_hp = 100; ally.apply_stats(); ally.start_combat()
	ally.hp = 50  # damaged, so _lowest_hp_pct_ally picks this ally over the caster
	caster.regrowth_pending = true
	combat._attacker = caster
	combat._turn_manager.combatants = [caster, ally]
	combat._panels[caster] = CombatantPanel.new()
	combat._panels[ally] = CombatantPanel.new()
	root.add_child(combat._panels[ally])  # _ready() must run so _status_label exists to assert on
	combat._plan = MainPhasePlan.new(caster, 0, 5, 2, null)
	combat._commit_main1()
	_check(ally.has_effect(&"regen"), "Regrowth attaches Regen to the lowest-HP%% living ally")
	_check((combat._panels[ally] as CombatantPanel)._status_label.text.contains("REGEN"), "the ally's panel shows Regen immediately, not just at their own next turn")

	print(("REGROWTH TEST PASSED" if _failures == 0 else "REGROWTH TEST FAILED: %d" % _failures))
	quit(_failures)
	return true
```

- [ ] **Step 6: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_regrowth.gd`
Expected: the pre-existing checks still PASS; the new "the ally's panel shows Regen immediately" check FAILS.

(If `MainPhasePlan.new(caster, 0, 5, 2, null)`'s 5-argument shape doesn't match — check `combat/main_phase_plan.gd`'s actual constructor and adjust the call to match; the intent is a plan with no ability/ultimate staged, just enough for `_commit_main1()` to run to the `regrowth_pending` block without erroring.)

- [ ] **Step 7: Fix the Regrowth call site**

In `combat/combat.gd`, change:

```gdscript
			_attacker.apply_rider_talent_adjustments(&"regen", regen, ally)
			ally.attach_effect(regen)
			_log("  🌿 %s grants Regrowth to %s." % [_attacker.display_name, ally.display_name])
		_attacker.regrowth_pending = false
```

to:

```gdscript
			_attacker.apply_rider_talent_adjustments(&"regen", regen, ally)
			ally.attach_effect(regen)
			_log("  🌿 %s grants Regrowth to %s." % [_attacker.display_name, ally.display_name])
			if _panels.has(ally):
				(_panels[ally] as CombatantPanel).refresh_status()
		_attacker.regrowth_pending = false
```

- [ ] **Step 8: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_regrowth.gd`
Expected: PASS, all checks `ok`.

- [ ] **Step 9: Run the wider CombatantPanel/status-effect suites to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combatant_panel.gd`, `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_hollow_warden_full_sequence.gd`
Expected: both PASS unchanged (bind() calling refresh_status() one extra time at construction is additive, not a behavior change to anything already asserted).

- [ ] **Step 10: Commit**

```bash
git add combat/ui/combatant_panel.gd combat/combat.gd tests/test_combatant_panel_bind_shows_existing_effects.gd tests/test_regrowth.gd
git commit -m "fix(combat): refresh CombatantPanel status at bind time and after Regrowth"
```

---

### Task 4: Clear all combat effects (and any residual shield) when a fight ends

**Files:**
- Modify: `combat/combatant.gd` (new method, near `cleanse()` at line 1165)
- Modify: `combat/combat.gd:2561` (`_on_combat_ended`)
- Test: Create `tests/test_clear_combat_effects_on_combat_end.gd`

**Interfaces:**
- Consumes: `Combatant.active_effects: Array[Effect]` (`combatant.gd:239`), `Combatant.shield_hp`/`shield_turns` (`combatant.gd:346-347`), `Combatant.shield_changed` signal (`combatant.gd:51`).
- Produces: new public method `Combatant.clear_combat_effects() -> void`. No other task in this plan calls it, but future work (e.g. the deferred pre-buffed-combat-start idea, see project memory) will build on top of a clean baseline this establishes.

**Context:** Player decision 2026-07-31: temporary combat effects (Guarded, Taunt, Evasion, etc.) must NOT survive from one fight into a completely separate later encounter. Currently `_on_combat_ended()` never clears anything, and `CombatHandoff` reuses the SAME real `Combatant` instances (not fresh rebuilds) across sequential encounters within one dungeon run — so effects genuinely persist. `cleanse()` (`combatant.gd:1165-1169`) is the wrong tool here: it deliberately keeps beneficial effects (that's its whole point, as a debuff-removal ability), so a fresh method is needed that clears everything, unconditionally.

- [ ] **Step 1: Write the failing test**

Create `tests/test_clear_combat_effects_on_combat_end.gd`:

```gdscript
extends SceneTree

## Headless test: Combatant.clear_combat_effects() wipes ALL active effects (buff + debuff) and any
## residual shield, and _on_combat_ended() calls it for every _pcs member — player decision
## 2026-07-31: combat effects must NOT survive from one fight into a separate later encounter,
## since CombatHandoff reuses the same real Combatant instances across sequential fights.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_clear_combat_effects_on_combat_end.gd

var _instance: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# --- Combatant.clear_combat_effects() itself ---
		var solo: Combatant = Combatant.new()
		solo.base_stats = Stats.new(); solo.base_max_hp = 100; solo.apply_stats(); solo.start_combat()
		solo.attach_effect(EffectLibrary.make(&"guarded"))
		solo.attach_effect(EffectLibrary.make(&"taunt"))
		solo.apply_shield(20, 2)
		solo.clear_combat_effects()
		_check(solo.active_effects.is_empty(), "clear_combat_effects wipes every effect, including beneficial ones cleanse() would keep")
		_check(solo.shield_hp == 0 and solo.shield_turns == 0, "clear_combat_effects also zeroes any residual shield (got %d/%d)" % [solo.shield_hp, solo.shield_turns])

		# --- wired into _on_combat_ended() for every _pcs member ---
		var combat: Combat = _instance as Combat
		var pc1: Combatant = Combatant.new()
		pc1.display_name = "PC1"; pc1.is_player = true
		pc1.base_stats = Stats.new(); pc1.base_max_hp = 100; pc1.apply_stats(); pc1.start_combat()
		pc1.attach_effect(EffectLibrary.make(&"guarded"))
		var pc2: Combatant = Combatant.new()
		pc2.display_name = "PC2 (companion)"; pc2.is_player = true
		pc2.base_stats = Stats.new(); pc2.base_max_hp = 100; pc2.apply_stats(); pc2.start_combat()
		pc2.attach_effect(EffectLibrary.make(&"taunt"))
		combat._pcs = [pc1, pc2]
		combat._enemies = []
		combat._arrived_via_handoff = false

		combat._on_combat_ended(true)
		_check(pc1.active_effects.is_empty(), "PC1's effects are cleared when combat ends")
		_check(pc2.active_effects.is_empty(), "PC2's (companion's) effects are cleared too")

		print(("CLEAR COMBAT EFFECTS ON COMBAT END TEST PASSED" if _failures == 0 else "CLEAR COMBAT EFFECTS ON COMBAT END TEST FAILED: %d" % _failures))
		quit(_failures)
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_clear_combat_effects_on_combat_end.gd`
Expected: FAIL — `Combatant.clear_combat_effects()` doesn't exist yet (compile error / method-not-found), and even once stubbed in, `pc1`/`pc2`'s effects would remain after `_on_combat_ended(true)`.

- [ ] **Step 3: Add `Combatant.clear_combat_effects()`**

In `combat/combatant.gd`, add this method near `cleanse()` (after line 1169):

```gdscript
## Clears every active effect (buff AND debuff) plus any residual shield, for a fresh start in a
## brand-new encounter (player decision 2026-07-31 — CombatHandoff reuses the same real Combatant
## instances across sequential fights, so without this, Guarded/Taunt/Evasion/etc. would silently
## survive from one unrelated fight into the next). Unlike cleanse(), which keeps beneficial
## effects, this clears everything. Deliberately does NOT touch cooldowns/bonus_meter/xp — those
## aren't the reported problem and have no reason to reset at combat end.
func clear_combat_effects() -> void:
	active_effects.clear()
	shield_hp = 0
	shield_turns = 0
	shield_changed.emit(shield_hp, shield_turns)
```

- [ ] **Step 4: Wire it into `_on_combat_ended()`**

In `combat/combat.gd`, at the top of `func _on_combat_ended(winner_is_player: bool) -> void:`, change:

```gdscript
func _on_combat_ended(winner_is_player: bool) -> void:
	_last_result_won = winner_is_player
```

to:

```gdscript
func _on_combat_ended(winner_is_player: bool) -> void:
	for c: Combatant in _pcs:
		c.clear_combat_effects()
	_last_result_won = winner_is_player
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_clear_combat_effects_on_combat_end.gd`
Expected: PASS, all checks `ok`.

- [ ] **Step 6: Run the wider combat-end suites to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_npcs.gd`, `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_bench_survives_combat.gd`
Expected: both PASS unchanged (neither asserts on `active_effects` surviving combat end).

- [ ] **Step 7: Commit**

```bash
git add combat/combatant.gd combat/combat.gd tests/test_clear_combat_effects_on_combat_end.gd
git commit -m "feat(combat): clear all combat effects and residual shield when a fight ends"
```

---

### Task 5: Riposte Storm charge counter on CombatantPanel

**Files:**
- Modify: `combat/ui/combatant_panel.gd` (new label + `refresh_riposte()`, called from `bind()`)
- Modify: `combat/combat.gd:1838` (gain-charge site), `combat/combat.gd:1722-1724` (post-commit self-cast refresh block)
- Test: Create `tests/test_riposte_charge_counter.gd`

**Interfaces:**
- Consumes: `Combatant.riposte_charges: int` (`combatant.gd:295`), `Combatant.gain_riposte_charges()` (`combatant.gd:301-302`), `Combatant.fire_riposte_storm()` (`combatant.gd:1495-1504`, resets `riposte_charges = 0`).
- Produces: new public method `CombatantPanel.refresh_riposte() -> void`.

**Context:** `Combatant.riposte_charges` (Skirmisher Riposte Storm) has zero UI display anywhere. It's gained via `_defender.gain_riposte_charges(weapon_reel_count)` at `combat.gd:1838` (an enemy attacking an Evasive Skirmisher) and reset to 0 inside `fire_riposte_storm()` when the Skirmisher spends it. The generic post-commit refresh block at `combat.gd:1722-1724` already refreshes `_attacker`'s panel right after any self-cast ability (including Riposte Storm) resolves — this task extends that same block, plus adds one new call at the gain-charge site (a cross-combatant event that block doesn't cover) and includes the counter in the bind()-time refresh Task 3 already added.

- [ ] **Step 1: Write the failing test**

Create `tests/test_riposte_charge_counter.gd`:

```gdscript
extends SceneTree

## Headless test: Basil's (Skirmisher) Riposte Storm charge count must be visible on the panel —
## playtest 2026-07-31 found riposte_charges had NO UI display anywhere.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_riposte_charge_counter.gd

var _instance: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# --- CombatantPanel-level: refresh_riposte() renders the count, blank at 0 ---
		var c: Combatant = Combatant.new()
		c.base_stats = Stats.new(); c.base_max_hp = 100; c.apply_stats(); c.start_combat()
		var panel: CombatantPanel = CombatantPanel.new()
		root.add_child(panel)
		panel.bind(c)
		_check(panel._riposte_label.text == "", "blank at 0 charges right after bind()")
		c.gain_riposte_charges(3)
		panel.refresh_riposte()
		_check(panel._riposte_label.text.contains("3"), "shows the charge count once gained (got '%s')" % panel._riposte_label.text)

		# --- combat.gd wiring: gaining a charge on the defender's panel refreshes it live ---
		var combat: Combat = _instance as Combat
		var defender: Combatant = Combatant.new()
		defender.base_stats = Stats.new(); defender.base_max_hp = 100; defender.apply_stats(); defender.start_combat()
		defender.attach_effect(EffectLibrary.make(&"evasion"))
		var attacker: Combatant = Combatant.new()
		attacker.is_player = false
		var w: Weapon = Weapon.new(); w.base_damage = 5.0
		w.reels.append(ActionReel.make_default(null))
		attacker.weapon = w
		attacker.turn_reels = [w.reels[0]]
		combat._attacker = attacker
		combat._defender = defender
		combat._panels[defender] = CombatantPanel.new()
		root.add_child(combat._panels[defender])
		combat._panels[defender].bind(defender)

		defender.gain_riposte_charges(1)
		(combat._panels[defender] as CombatantPanel).refresh_riposte()
		_check((combat._panels[defender] as CombatantPanel)._riposte_label.text.contains("1"), "the defender's panel shows the gained charge")

		print(("RIPOSTE CHARGE COUNTER TEST PASSED" if _failures == 0 else "RIPOSTE CHARGE COUNTER TEST FAILED: %d" % _failures))
		quit(_failures)
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_riposte_charge_counter.gd`
Expected: FAIL — `_riposte_label` and `refresh_riposte()` don't exist yet.

- [ ] **Step 3: Add the label + refresh method to CombatantPanel**

In `combat/ui/combatant_panel.gd`, add the field near the other labels:

```gdscript
var _shield_label: Label
var _riposte_label: Label
```

In `_ready()`, add right after `_shield_label` is built and added:

```gdscript
	_shield_label = Label.new()
	_shield_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	box.add_child(_shield_label)

	_riposte_label = Label.new()
	_riposte_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.9))
	box.add_child(_riposte_label)
```

Add the new method near `refresh_shield()`:

```gdscript
## Updates the Riposte Storm charge counter ("⚔ Riposte charges: 3" while charges > 0, blank
## otherwise) — riposte_charges is 0 and never gained for every non-Skirmisher class, so a
## non-Skirmisher panel simply stays blank. Call from bind() + wherever gain_riposte_charges()/
## fire_riposte_storm() run.
func refresh_riposte() -> void:
	if _riposte_label == null:
		return
	if _combatant != null and _combatant.riposte_charges > 0:
		_riposte_label.text = "⚔ Riposte charges: %d" % _combatant.riposte_charges
	else:
		_riposte_label.text = ""
```

In `bind()`, add the call alongside the others:

```gdscript
	refresh_resources()
	refresh_shield()
	refresh_status()
	refresh_riposte()
	_refresh_stats()
	_refresh_types()
```

- [ ] **Step 4: Wire the two combat.gd call sites**

In `combat/combat.gd`, change the gain-charge site:

```gdscript
			_defender.gain_riposte_charges(weapon_reel_count)
```

to:

```gdscript
			_defender.gain_riposte_charges(weapon_reel_count)
			if _panels.has(_defender):
				(_panels[_defender] as CombatantPanel).refresh_riposte()
```

And extend the post-commit self-cast refresh block:

```gdscript
	if did_ability or did_extra != &"" or did_ultimate:
		(_panels[_attacker] as CombatantPanel).refresh_status()
		(_panels[_attacker] as CombatantPanel).refresh_resources()
```

to:

```gdscript
	if did_ability or did_extra != &"" or did_ultimate:
		(_panels[_attacker] as CombatantPanel).refresh_status()
		(_panels[_attacker] as CombatantPanel).refresh_resources()
		(_panels[_attacker] as CombatantPanel).refresh_riposte()
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_riposte_charge_counter.gd`
Expected: PASS, all checks `ok`.

- [ ] **Step 6: Run the wider CombatantPanel suite to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combatant_panel.gd`
Expected: PASS unchanged.

- [ ] **Step 7: Commit**

```bash
git add combat/ui/combatant_panel.gd combat/combat.gd tests/test_riposte_charge_counter.gd
git commit -m "feat(combat): show Riposte Storm charge count on CombatantPanel"
```

---

### Task 6: Team-Up! panel becomes a real, opaque center-band modal (not full-screen)

**Files:**
- Modify: `combat/ui/team_up_panel.gd` (repositioning, explicit opaque background, explicit mouse filter)
- Test: Create `tests/test_team_up_panel_center_band.gd`

**Interfaces:**
- Consumes: none new.
- Produces: no public API change — `open_for(config, allies, enemies)` keeps its exact signature. Internal layout constants change.

**Context:** Player's own mental model, confirmed as the intended design: the Team-Up window should occupy the CENTER BAND of the screen (everything between the two combatant columns), not the literal full window — and it should be visibly opaque, since right now the reel strips and ability-toggle button rows are visible/clickable behind it. The party column sits at `x=24`, width `300` (ends at `x=324`); the enemy column starts at `x=1276` (see `combat.gd:276` and `combat.gd:557`). The window is `1600x900`. The center band is therefore roughly `x=340` to `x=1276` (a `340,60`-origin, `920x780`-size rect leaves a clean margin on all sides and never overlaps either combatant column). `TeamUpPanel` currently uses `Control.PRESET_FULL_RECT` with the theme's default (unstyled) `Panel` background — this task gives it an explicit rect and an explicit opaque `StyleBoxFlat` override so its visibility no longer depends on whatever the project's theme happens to do with an unstyled `Panel`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_up_panel_center_band.gd`:

```gdscript
extends SceneTree

## Headless test: TeamUpPanel must be a real, opaque, click-blocking modal confined to the CENTER
## BAND between the two combatant columns (x≈340..1260), not a literal full-screen overlay with an
## unstyled (theme-default) background — playtest 2026-07-31 found it overlapping/see-through
## against the reel strips and ability-toggle button rows.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_center_band.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var panel: TeamUpPanel = TeamUpPanel.new()
	root.add_child(panel)

	_check(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "explicitly blocks mouse input to whatever's behind it")

	var left_column_right_edge: float = 324.0   # party column: x=24, width 300
	var enemy_column_left_edge: float = 1276.0
	_check(panel.position.x >= left_column_right_edge, "panel's left edge clears the party column (got x=%f)" % panel.position.x)
	_check(panel.position.x + panel.size.x <= enemy_column_left_edge, "panel's right edge clears the enemy column (got right=%f)" % (panel.position.x + panel.size.x))
	_check(panel.size.x < 1600.0 and panel.size.y < 900.0, "panel is NOT literally full-screen (got %s)" % panel.size)

	var style: StyleBox = panel.get_theme_stylebox("panel")
	_check(style is StyleBoxFlat, "has an explicit StyleBoxFlat background override (not the theme default)")
	if style is StyleBoxFlat:
		_check((style as StyleBoxFlat).bg_color.a >= 0.95, "background is opaque (alpha >= 0.95, got %f)" % (style as StyleBoxFlat).bg_color.a)

	print(("TEAM UP PANEL CENTER BAND TEST PASSED" if _failures == 0 else "TEAM UP PANEL CENTER BAND TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_center_band.gd`
Expected: FAIL on the rect and stylebox checks (currently `PRESET_FULL_RECT`, no stylebox override).

- [ ] **Step 3: Reposition and restyle the panel, and its children, to fit the new rect**

In `combat/ui/team_up_panel.gd`, change the constants and `_ready()`:

```gdscript
const GRID_COLS: int = 5
const GRID_ROWS: int = 3
const CELL_SIZE: float = 90.0
const CELL_GAP: float = 10.0
const GRID_ORIGIN: Vector2 = Vector2(300, 150)

var _minigame: TeamUpMinigame
var _damage_type: DamageType
var _allies: Array = []
var _enemies: Array = []
var _cell_buttons: Array = []   # [col][row] = Button
var _spin_button: Button
var _status_label: Label
var _tally_label: Label
var _continue_button: Button
var _resolve_lines: Array[String] = []   # last resolved round's log lines, handed back via `completed`

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_grid()

	_spin_button = Button.new()
	_spin_button.text = "Spin"
	_spin_button.position = Vector2(700, 560)
	_spin_button.custom_minimum_size = Vector2(160, 44)
	_spin_button.pressed.connect(_on_spin_pressed)
	add_child(_spin_button)

	_status_label = Label.new()
	_status_label.position = Vector2(300, 500)
	_status_label.custom_minimum_size = Vector2(1000, 30)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)

	_tally_label = Label.new()
	_tally_label.position = Vector2(300, 620)
	_tally_label.custom_minimum_size = Vector2(1000, 60)
	_tally_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tally_label.visible = false
	add_child(_tally_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(700, 700)
	_continue_button.custom_minimum_size = Vector2(200, 50)
	_continue_button.visible = false
	_continue_button.pressed.connect(func() -> void:
		visible = false
		completed.emit(_resolve_lines))
	add_child(_continue_button)
```

to:

```gdscript
const GRID_COLS: int = 5
const GRID_ROWS: int = 3
const CELL_SIZE: float = 90.0
const CELL_GAP: float = 10.0
# Local (panel-relative) origin — the panel itself is now confined to the CENTER BAND between the
# two combatant columns (playtest 2026-07-31: was literal full-screen, overlapping/see-through
# against the reel strips and ability-toggle rows). Party column ends at x=324, enemy column
# starts at x=1276 (combat.gd), so this rect clears both with margin on every side.
const PANEL_RECT_POSITION: Vector2 = Vector2(340, 60)
const PANEL_RECT_SIZE: Vector2 = Vector2(920, 780)
const GRID_ORIGIN: Vector2 = Vector2(215, 40)   # local to the panel, roughly centered horizontally

var _minigame: TeamUpMinigame
var _damage_type: DamageType
var _allies: Array = []
var _enemies: Array = []
var _cell_buttons: Array = []   # [col][row] = Button
var _spin_button: Button
var _status_label: Label
var _tally_label: Label
var _continue_button: Button
var _resolve_lines: Array[String] = []   # last resolved round's log lines, handed back via `completed`

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = PANEL_RECT_POSITION
	size = PANEL_RECT_SIZE
	custom_minimum_size = PANEL_RECT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 1.0)   # fully opaque, independent of whatever the project theme does with an unstyled Panel
	bg.border_color = Color(0.5, 0.45, 0.2)
	bg.set_border_width_all(3)
	add_theme_stylebox_override("panel", bg)
	visible = false
	_build_grid()

	_spin_button = Button.new()
	_spin_button.text = "Spin"
	_spin_button.position = Vector2(380, 350)
	_spin_button.custom_minimum_size = Vector2(160, 44)
	_spin_button.pressed.connect(_on_spin_pressed)
	add_child(_spin_button)

	_status_label = Label.new()
	_status_label.position = Vector2(60, 410)
	_status_label.custom_minimum_size = Vector2(800, 30)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)

	_tally_label = Label.new()
	_tally_label.position = Vector2(60, 450)
	_tally_label.custom_minimum_size = Vector2(800, 60)
	_tally_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tally_label.visible = false
	add_child(_tally_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(360, 520)
	_continue_button.custom_minimum_size = Vector2(200, 50)
	_continue_button.visible = false
	_continue_button.pressed.connect(func() -> void:
		visible = false
		completed.emit(_resolve_lines))
	add_child(_continue_button)
```

Note: `_build_grid()` reads `GRID_ORIGIN`, which is now panel-local instead of screen-space — no change needed inside `_build_grid()` itself, since it already just adds `GRID_ORIGIN + offset` to each button's `position` (which was always interpreted relative to the panel's own top-left; only the panel's own top-left moved).

- [ ] **Step 4: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_center_band.gd`
Expected: PASS, all checks `ok`.

- [ ] **Step 5: Run the wider Team-Up suite to confirm no regression**

Run every `test_team_up*.gd` and `test_jackpot*.gd` file headlessly (e.g. `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame.gd`, and any other `test_team_up_*.gd`/`test_jackpot_*.gd` files present in `tests/`).
Expected: all PASS unchanged (none of them assert on screen-space pixel positions of the panel or its buttons — repositioning is purely visual/layout).

- [ ] **Step 6: Commit**

```bash
git add combat/ui/team_up_panel.gd tests/test_team_up_panel_center_band.gd
git commit -m "fix(combat): confine the Team-Up panel to an opaque center-band modal"
```

**Note for the human playtester:** this fix guarantees the panel's rect, opacity, and mouse-filter are all correct by construction — headless tests can't simulate real mouse-click propagation, so confirm live that clicking where a reel/ability button would normally be, while Team-Up is open, no longer does anything in the background.

---

### Task 7: Team-Up symbol legend + payline-preview toggle

**Files:**
- Modify: `combat/ui/team_up_panel.gd`
- Test: Create `tests/test_team_up_panel_legend_and_payline_preview.gd`

**Interfaces:**
- Consumes: `PaylineLibrary.lines_for(width: int) -> Array` (`combat/payline_library.gd:13`), the `TypeChartPanel._add_legend()` precedent (`combat/ui/type_chart_panel.gd:143-156`, for style only — not called directly, since it's on a different class).
- Produces: no public API change.

**Context:** No hover tooltip or legend exists anywhere on the Team-Up grid explaining what each symbol does, and there's no equivalent of the main combat screen's "Paylines" preview toggle (`combat.gd:404-409`/`_on_paylines_pressed()`) for the Team-Up grid's own payline patterns. This task adds both: a static legend row at the bottom of the panel, and a "Show Paylines" toggle button that cycles through `PaylineLibrary.lines_for(_minigame.grid.size())`, highlighting one line's cells at a time on the grid's own buttons.

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_up_panel_legend_and_payline_preview.gd`:

```gdscript
extends SceneTree

## Headless test: TeamUpPanel gets a symbol legend and a payline-preview cycle toggle — playtest
## 2026-07-31 asked for both ("a Key at the bottom... describes what each reel face does, as well
## as a payline toggle to show players what to be aiming for with their reel face locks").
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_legend_and_payline_preview.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var panel: TeamUpPanel = TeamUpPanel.new()
	root.add_child(panel)

	_check(panel._legend_label != null, "a legend label exists")
	var legend_text: String = panel._legend_label.text
	for symbol_name: String in ["Strike", "Mend", "Ward", "Break", "Surge"]:
		_check(legend_text.contains(symbol_name), "legend mentions %s" % symbol_name)

	_check(panel._payline_preview_button != null, "a payline-preview toggle button exists")

	# Open a real round so the grid/minigame exist, then exercise the cycle. TeamUpReel.make_default()
	# is the established test convention (see tests/test_team_up_minigame.gd) — a bare TeamUpReel.new()
	# has no faces and would crash on spin().
	var reels: Array[TeamUpReel] = []
	for i in range(5):
		reels.append(TeamUpReel.make_default([[&"strike", 1]]))
	var config: Dictionary = {"reels": reels, "lock_tokens": 9, "max_spins": 5, "damage_type": null}
	panel.open_for(config, [], [])
	panel._on_spin_pressed()  # populate the grid so there's something to preview lines over

	_check(panel._payline_preview_cells.is_empty(), "no preview highlighted before the toggle is pressed")
	panel._on_payline_preview_pressed()
	_check(not panel._payline_preview_cells.is_empty(), "pressing the toggle highlights one payline's cells")
	var first_cells: Array = panel._payline_preview_cells.duplicate()
	panel._on_payline_preview_pressed()
	_check(panel._payline_preview_cells != first_cells or PaylineLibrary.lines_for(5).size() == 1, "pressing again cycles to a different line (unless there's only one)")

	print(("TEAM UP PANEL LEGEND AND PAYLINE PREVIEW TEST PASSED" if _failures == 0 else "TEAM UP PANEL LEGEND AND PAYLINE PREVIEW TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_legend_and_payline_preview.gd`
Expected: FAIL — `_legend_label`, `_payline_preview_button`, `_payline_preview_cells`, and `_on_payline_preview_pressed()` don't exist yet.

- [ ] **Step 3: Add the legend, the toggle, and the preview cycle**

In `combat/ui/team_up_panel.gd`, add new fields alongside the existing ones:

```gdscript
var _legend_label: RichTextLabel
var _payline_preview_button: Button
var _payline_preview_cells: Array = []
var _payline_cycle_index: int = -1
```

At the end of `_ready()` (after the `_continue_button` block), add:

```gdscript
	_legend_label = RichTextLabel.new()
	_legend_label.bbcode_enabled = true
	_legend_label.fit_content = true
	_legend_label.scroll_active = false
	_legend_label.position = Vector2(40, 600)
	_legend_label.custom_minimum_size = Vector2(840, 140)
	_legend_label.text = "[b]Key:[/b]  [color=#e0a040]Strike[/color] damages ALL enemies  •  [color=#5fd35f]Mend[/color] heals ALL allies  •  [color=#5fd3d3]Ward[/color] shields ALL allies  •  [color=#d35f5f]Break[/color] applies Weakened to ALL enemies  •  [color=#d3d35f]Surge[/color] amplifies every OTHER symbol +50%% per completed Surge line this round (a lone Surge cell does nothing by itself)"
	add_child(_legend_label)

	_payline_preview_button = Button.new()
	_payline_preview_button.text = "Show Paylines"
	_payline_preview_button.position = Vector2(560, 350)
	_payline_preview_button.custom_minimum_size = Vector2(160, 44)
	_payline_preview_button.tooltip_text = "Cycle through this round's payline patterns one at a time (legibility aid)."
	_payline_preview_button.pressed.connect(_on_payline_preview_pressed)
	add_child(_payline_preview_button)
```

Add the cycle handler, and clear the preview whenever the grid state changes (a new round opens or a spin resolves):

```gdscript
## Cycles this round's payline patterns one at a time over the Team-Up grid (mirrors combat.gd's
## own "Paylines" button for the main weapon reels — legibility: one line, not all at once).
func _on_payline_preview_pressed() -> void:
	if _minigame == null:
		return
	var lines: Array = PaylineLibrary.lines_for(_minigame.grid.size())
	if lines.is_empty():
		return
	_payline_cycle_index += 1
	if _payline_cycle_index >= lines.size():
		_payline_cycle_index = -1
		_payline_preview_cells = []
		_refresh_grid()
		return
	_payline_preview_cells = lines[_payline_cycle_index]
	_refresh_grid()

## Clears the payline-preview highlight (new round / new spin state).
func _clear_payline_preview() -> void:
	_payline_cycle_index = -1
	_payline_preview_cells = []
```

Update `open_for()` to clear the preview on a fresh round:

```gdscript
func open_for(config: Dictionary, allies: Array, enemies: Array) -> void:
	var reels: Array[TeamUpReel] = config.get("reels", [])
	_minigame = TeamUpMinigame.new(reels, config.get("lock_tokens", 0), config.get("max_spins", 0))
	_damage_type = config.get("damage_type", null)
	_allies = allies
	_enemies = enemies
	_continue_button.visible = false
	_tally_label.visible = false
	_spin_button.disabled = false
	_resolve_lines = []
	_clear_payline_preview()
	_refresh_grid()
	visible = true
```

And clear it on every spin, in `_on_spin_pressed()`:

```gdscript
func _on_spin_pressed() -> void:
	if _minigame.spin():
		_clear_payline_preview()
		_refresh_grid()
		if _minigame.is_complete():
			_resolve()
```

Finally, layer the preview tint on top of the existing locked-state tint in `_refresh_grid()` — change:

```gdscript
			var face: ReelFace = _minigame.grid[c][r]
			btn.text = String(face.team_up_symbol).capitalize() if face != null else ""
			btn.disabled = _minigame.locked[c][r] or _minigame.is_complete()
			btn.modulate = Color(0.6, 1.0, 0.6) if _minigame.locked[c][r] else Color(1, 1, 1)
```

to:

```gdscript
			var face: ReelFace = _minigame.grid[c][r]
			btn.text = String(face.team_up_symbol).capitalize() if face != null else ""
			btn.disabled = _minigame.locked[c][r] or _minigame.is_complete()
			if _minigame.locked[c][r]:
				btn.modulate = Color(0.6, 1.0, 0.6)
			elif _payline_preview_cells.has(Vector2i(c, r)):
				btn.modulate = Color(1.6, 1.5, 0.5)
			else:
				btn.modulate = Color(1, 1, 1)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_legend_and_payline_preview.gd`
Expected: PASS, all checks `ok`.

(If `TeamUpReel.new()`/the `config` dictionary shape doesn't line up with `TeamUpMinigame`'s actual constructor, check `combat/team_up_minigame.gd` and `combat/resources/team_up_reel.gd` and adjust the test's setup to match — the intent is just "a real minigame with a real grid exists so `_on_spin_pressed`/`_refresh_grid`/the preview cycle have something to operate on.")

- [ ] **Step 5: Run the wider Team-Up suite to confirm no regression**

Run every `test_team_up*.gd` file headlessly.
Expected: all PASS unchanged.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/team_up_panel.gd tests/test_team_up_panel_legend_and_payline_preview.gd
git commit -m "feat(combat): add a symbol legend and payline-preview toggle to the Team-Up panel"
```

---

## Final Verification

After all 7 tasks are committed:

- [ ] Run the FULL headless test suite (every `tests/test_*.gd` file) and confirm no new failures beyond the two pre-existing, already-documented ones (`tests/test_adventuring_board_panel.gd`'s internal FAIL that never propagates to a nonzero exit code, and the intermittent teardown-only SIGSEGV flake class — both confirmed pre-existing in project history, not caused by this plan).
- [ ] Launch the real game (`cd "C:/bunnies/bunnies-main" && ./Godot_v4.6.3-stable_win64_console.exe --path bunnies res://world/overworld_demo.tscn`) for a human playtest covering: effects no longer carrying between fights, the Riposte Storm counter, the Team-Up panel's new center-band/opaque look and its legend/payline-preview toggle, and (if reachable) a Team-Up round fired while the Hollow Warden is Indestructible.

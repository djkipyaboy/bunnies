# The Hollow Warden Boss Fight — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Plan 2 of 3 for the combined dungeon-boss + Lost Cat feature brainstormed
> 2026-07-18 (`docs/superpowers/specs/2026-07-18-dungeon-boss-and-lost-cat-quest-design.md`). That
> combined document is the source of the design DECISIONS below — the player dictated the full fight
> design in one detailed message and confirmed every follow-up question during that brainstorm; no
> new design ground is broken here. This document exists because that combined spec bundled 3
> genuinely separate subsystems (damage types, the boss fight, the quest system) and the team agreed
> to plan/build them as 3 sequential plans. **Plan 1 (Light/Dark damage types) is SHIPPED** (main,
> commits `068b4fc..1ae526a`) — `DamageType.Type.LIGHT`/`DARK` exist, `dark.tres`/`light.tres` are
> generated, both UI pieces render 8 types. This document re-derives the boss-fight architecture
> against the CURRENT codebase (re-verified 2026-07-19, not just the 2026-07-18 research pass) so the
> implementation plan can be written with zero placeholders. **Plan 3 (the Lost Cat quest system) is
> explicitly out of scope here** — see §4.

## 1. Goal

Floor 4 of the dungeon holds The Hollow Warden: a 550-HP, Dark-typed, multi-phase boss with two
minion-summoning phases, a phase transition with a 10-turn re-trigger cooldown, and the game's first
enemy Ultimate. This is the dungeon's actual difficulty/depth payoff and the first boss-tier fight in
the game.

## 2. Decisions locked during brainstorming (2026-07-18, restated for this document's scope)

### Stats and normal attacks
- **550 max HP.** Defense type: **Dark**. Weapon type: **Dark**, 3 reels, 12.0 base damage per HIT,
  standard 1.5× on a crit success (the existing per-reel resolution math — no new damage formula).

### Phase 1 (fight start)
- The encounter starts with the boss **plus two 30-HP minions already in the fight** — not spawned
  by any script. This reuses the exact same "multi-enemy floor" mechanism already shipped for floors
  2-3 (`enemy_ids = [&"rat", &"ferret"]` etc.) with zero new plumbing: floor 4's `OverworldEnemy` gets
  `enemy_ids = [&"hollow_warden", &"warden_acolyte_lesser", &"warden_acolyte_lesser"]`.
- Both minions are **unstunnable** and **always act last** in turn order, regardless of their
  initiative roll.
- Minion A's turn: heals the boss +30 HP and applies the existing `guarded` effect to it.
- Minion B's turn: applies a NEW flat, stacking, party-wide AoE DoT (`warden_curse`: 4 / 7 / 10
  damage per turn, 3-turn duration per stack, up to 3 stacks) — flat, not derived from any weapon,
  unlike every existing DoT in this codebase.
- Both minion types keep a real (weak) weapon and **always fire their signature ability every
  turn**, reusing the exact existing greedy-ability-use AI pattern (`_enemy_stage_ability()`, the
  same mechanism the ferret's Flurry and stoat's Hunter's Mark already use).

### Phase transition (checked at the start of the boss's own turn)
The FIRST time the boss's HP drops below 40% (220 HP), three things happen at once:
1. The boss gains **Indestructible** — all *direct* damage taken reduced to 0; DoT still applies in
   full (the existing damage pipeline already keeps these separate). Lasts until both of THIS
   phase's two new minions are dead — not a turn-counted duration.
2. Two new **90-HP** minions spawn (same abilities/always-last/unstunnable rules as phase 1).
3. On every boss turn while Indestructible is active, the boss's normal attack is replaced by
   **Darkness Rampage**: a 4-reel WILD (crit-biased) AoE hitting the whole PC party, 18 damage per
   HIT, standard 1.5× crit, and the boss heals for half the total damage it deals that spin.

Once both of that phase's minions are dead: Indestructible clears, and the boss gains the
**existing** `empowered` effect (1.4× outgoing damage — not a new effect) for the rest of combat.

**10-turn cooldown, re-triggerable:** if the boss's HP is still below 40% after 10 of *its own*
turns since the last trigger, the whole transition repeats (sacrifice check → Indestructible → 2
new 90-HP minions → Darkness Rampage cycle again). **Indestructible always supersedes Empowered** —
a later re-trigger suspends Empowered while Indestructible is active again; finishing that cycle
(minions dead) always re-applies Empowered, first cycle or later. They never stack.

### Ultimate: "Dark Reinforcements"
Fires once the boss's Bonus Meter is full. The boss has a real, **visible** `BonusMeter` — the
first time this project's documented-but-unused "Elite/Boss meter is visible" rule is actually
built. Summons two MORE **30-HP** minions (phase-1 stats/behavior, always-last, unstunnable) — a
pure escalation move, no direct damage. **If these Ultimate-summoned minions are still alive when
the boss's next phase transition triggers, they are sacrificed** (instant, no-reward removal) **and
the boss heals for half their combined remaining HP** at that moment.

**No other base ability.** The kit is exactly: normal attacks, phase-locked Darkness Rampage, and
the Ultimate.

**Sacrificed minions (of any kind) grant no Amber/XP/loot** — removed by the boss's own script, not
defeated in battle; granting rewards would let players farm by ignoring reinforcements and waiting
for a free sacrifice-heal cycle.

## 3. Architecture

### 3.1 New status effects (`combat/effect_library.gd`)

`warden_curse` — a FLAT stacking party-wide DoT, following the exact `bleed`/`cursed` shape but with
a flat (not weapon-derived) magnitude:
```gdscript
&"warden_curse":
    var e := Effect.new()
    e.id = &"warden_curse"
    e.kind = Effect.Kind.DAMAGE_OVER_TIME
    e.duration = 3
    e.max_stacks = 3
    e.dot_fractions = [4.0, 7.0, 10.0]
    e.beneficial = false
    return e
```
Every existing DoT seeds `dot_base_damage` from the caster's `weapon_effective_base_damage()` at
apply time in `combat/combat.gd` (the two existing seed sites are the Rend→Bleed rider at
`_apply_attack` ~line 1699 and Regrowth's Regen seed in `_commit_main1` ~line 1482). This effect
needs the SAME kind of one-line seed wherever Minion B's ability applies it — but seeded to a FLAT
baseline instead of a weapon: `curse.dot_base_damage = 1.0`. `Effect.dot_damage()`'s existing
`ceili(dot_base_damage * dot_fractions[idx])` formula then produces exactly 4/7/10 per stack.

`indestructible` — reuses the EXISTING `MULTIPLIER_EDIT` mechanism, zero new `Effect.Kind` needed:
```gdscript
&"indestructible":
    var e := Effect.new()
    e.id = &"indestructible"
    e.kind = Effect.Kind.MULTIPLIER_EDIT
    e.magnitude = 0.0
    e.affects_incoming = true
    e.duration = 99   # cleared explicitly by the orchestrator (§3.3), not by turn-count expiry
    e.beneficial = true
    return e
```
Confirmed (re-read `combat/combatant.gd` 2026-07-19): `incoming_damage_multiplier()` (line 469) is
folded into `dmg_mult` at `combat.gd` ~line 1530, which feeds `_resolver.resolve_combat_phase(...)`
— this is strictly the DIRECT-hit resolution path. The DoT tick path (`_apply_dot`) uses the
completely separate `dot_damage_multiplier()` hook (line 478) and never reads
`incoming_damage_multiplier()`. So Indestructible blocking direct damage while leaving DoT untouched
is automatic — no extra plumbing needed.

**No method currently exists to remove a single active effect by id before its duration expires** —
`Combatant.tick_effects()` (combatant.gd:540) only drops effects whose `duration` has hit 0, and
`cleanse()` (line 548) removes ALL debuffs indiscriminately (Indestructible is `beneficial = true`
from the boss's own perspective, so cleanse wouldn't even target it, and cleanse is player-facing
anyway). Add one new small method to `Combatant`, mirroring `cleanse()`'s directness:
```gdscript
## Removes the active effect with [param id], if any, then refreshes the derived sort key. Used by
## the boss phase-transition orchestrator to clear Indestructible the instant both its minions die —
## not a turn-counted expiry, so tick_effects()/cleanse() can't do this.
func remove_effect(id: StringName) -> void:
    active_effects = active_effects.filter(func(e: Effect) -> bool: return e.id != id)
    recompute_initiative()
```

**"Always acts last"** and **"cannot be stunned"** reuse EXISTING mechanisms, no new `Effect.Kind`:
- `Combatant` gains one new field: `var acts_last: bool = false`.
  `TurnManager.get_turn_order()`'s sort comparator (`combat/turn_manager.gd:61-68`) gets one new
  check inserted BEFORE the initiative compare:
  ```gdscript
  ordered.sort_custom(func(a: Combatant, b: Combatant) -> bool:
      if a.acts_last != b.acts_last:
          return b.acts_last   # false (normal) sorts before true (acts-last), regardless of initiative
      if a.current_initiative != b.current_initiative:
          return a.current_initiative > b.current_initiative
      ...
  ```
- "Cannot be stunned" is a permanent effect with `grants_stun_immunity = true` attached to the
  minion at spawn time. `Combatant.evaluate_stun()` (combatant.gd:1073-1084) already checks
  `active_effects` for this flag unconditionally, overriding even a forced stun (existing precedent:
  Mountain Stance). No new mechanism needed — attach a permanent copy of a small new immunity effect
  (or reuse `EffectLibrary.make()`'s pattern) at minion construction time in `EnemyLibrary` (§3.2).

### 3.2 `EnemyLibrary` — The Hollow Warden + 2 minion types

Re-read `combat/enemy_library.gd` in full (2026-07-19) — current `_build()` signature:
```gdscript
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int, defense: DamageType, hp: int, ability_id: StringName = &"", ability_cost: int = 0, loot_table_id: StringName = &"", amber_reward: int = 0) -> Combatant:
```
It currently hardcodes `c.ultimate_id = &""` and `meter.is_visible = false` for every enemy (there
is ZERO existing boss/Elite content, so both need to become real values for the first time). Extend
`_build()`'s signature with two new trailing optional params, defaulted so the 3 existing enemies
(rat/ferret/stoat) are completely unaffected:
```gdscript
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int,
        defense: DamageType, hp: int, ability_id: StringName = &"", ability_cost: int = 0,
        loot_table_id: StringName = &"", amber_reward: int = 0,
        ultimate_id: StringName = &"", meter_visible: bool = false) -> Combatant:
    ...
    c.ultimate_id = ultimate_id   # replaces the hardcoded &""
    ...
    meter.cap = 15                # keep the existing enemy meter cap — same cap every PC Ultimate uses
    meter.is_visible = meter_visible   # replaces the hardcoded false
    ...
```
New registry entry, id `&"hollow_warden"`: weapon type/defense both `dark.tres`, 3 reels, base
damage 12.0, HP 550, `ultimate_id = &"dark_reinforcements"`, `meter_visible = true`, `is_boss = true`
(new field, §3.3), `acts_last = false` (default — the boss itself acts on its own initiative roll
normally). Amber reward higher than any existing enemy — `[ASSUMPTION]` 50, tunable by playtest like
every other placeholder magnitude in this project. No `loot_table_id` this pass (the Treasure Trove
reward is a separate, later roadmap step; the boss's own combat-loot stays minimal so it doesn't
compete with that future reward).

Two new minion tiers, each in 2 ability-role variants (4 registry ids total — see below), built via
a small shared helper (every variant is identical except HP and which ability id it carries, so a
shared builder avoids duplicating the whole stamp):
```gdscript
static func _build_acolyte(hp: int, ability_id: StringName) -> Combatant:
    var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
    var c: Combatant = _build("Warden Acolyte", crushing, 3.0, 1, crushing, hp, ability_id, 0)
    c.acts_last = true
    var immune: Effect = Effect.new()
    immune.id = &"warden_acolyte_immunity"
    immune.kind = Effect.Kind.MULTIPLIER_EDIT   # inert kind — this effect exists only to carry the flag below
    immune.magnitude = 1.0
    immune.duration = 999
    immune.beneficial = true
    immune.grants_stun_immunity = true
    c.attach_effect(immune)
    return c
```
Registered in `EnemyLibrary.make()`'s match statement (exact 4 ids given below, §3.2 continues
after the ability discussion), but **NOT added to `EnemyLibrary.IDS`** (confirmed via
`combat/combat.gd:696-714`: `IDS` drives the standalone "Choose Enemy Combatants" testing-roster
picker's selectable list — the boss and its minions are a scripted dungeon encounter only, never
player-selectable there, matching how dungeon floors already place enemies by literal `enemy_ids`
arrays independent of `IDS` membership). `&"hollow_warden"` is likewise registered in `make()` but
excluded from `IDS` for the same reason.

**Minion ability** (`&"warden_support"`) is driven by the SAME greedy always-fire AI pattern
`_enemy_stage_ability()` (combat.gd:870-880) already uses for Flurry/Hunter's Mark — this needs one
new `match` branch, but the ability alternates between "heal+guard the boss" and "curse the party"
depending on WHICH minion is acting, which the existing pattern (a single ability id → a single
fixed behavior) doesn't model. Resolve this by giving the two roles two distinct ability ids instead
of one shared id:
- `&"warden_support_heal"` (Minion A's role): `_enemy_stage_ability()` stages it unconditionally
  (always-fire, mirroring Flurry) when `_plan.can_stage_ability()`; the orchestrator's `_commit_main1`
  applies it directly (this ability has no reel/damage component, so — like Foresight/Regrowth's
  existing `_pending` flag pattern — set a new `heal_boss_pending: bool` field on `Combatant`,
  consumed in `_commit_main1`: heal the boss (whichever boss combatant is the ability-user's ally with
  `is_boss == true`) 30 HP and attach `EffectLibrary.make(&"guarded")` to it).
- `&"warden_support_curse"` (Minion B's role): same always-fire staging; consumed via a new
  `curse_party_pending: bool` field — the orchestrator attaches a freshly-seeded `warden_curse`
  (`dot_base_damage = 1.0`, per §3.1) to every living PC (`_enemies_of(minion)`, which — since the
  minion `is_player == false` — already correctly returns all living PCs; the exact same helper
  Darkness Rampage's AoE reuses, §3.5).

`EnemyLibrary.make(id: StringName)` takes a single id with no room for an extra role param without
changing every existing call site — so the role lives in the id itself. `_build_acolyte(hp: int,
ability_id: StringName) -> Combatant` takes the ability id as a parameter; `EnemyLibrary.make()`'s
match statement registers exactly 4 ids, one per tier/role combination:
```gdscript
&"warden_acolyte_lesser_healer": return _build_acolyte(30, &"warden_support_heal")
&"warden_acolyte_lesser_curser": return _build_acolyte(30, &"warden_support_curse")
&"warden_acolyte_greater_healer": return _build_acolyte(90, &"warden_support_heal")
&"warden_acolyte_greater_curser": return _build_acolyte(90, &"warden_support_curse")
```
These 4 ids are what §3.3/§3.4/§3.7 spawn/place by name — every code sample elsewhere in this
document already uses them.

### 3.3 Boss phase-transition orchestration

New per-Combatant fields (used only by the boss; every other Combatant leaves these at defaults):
```gdscript
var is_boss: bool = false
var boss_phase_two_active: bool = false
var boss_turns_taken: int = 0
var boss_last_phase_trigger_turn: int = -1
var boss_phase_minion_ids: Array[Combatant] = []   # the CURRENT phase's 2 minions, so we know when both are dead
var boss_reinforcement_ids: Array[Combatant] = []  # Ultimate-summoned minions, tracked separately for the sacrifice check
```
No existing per-combatant own-turn counter exists in `combatant.gd` (confirmed 2026-07-19) — do NOT
add a universal counter to the shared `begin_turn()` path (every other Combatant has no use for it,
and this project's YAGNI discipline (CLAUDE.md §7) argues against a codebase-wide field for a
single-boss need). `boss_turns_taken` is incremented at the top of the new orchestrator method
below, which only ever runs when `c.is_boss` is true.

New orchestrator method in `combat/combat.gd`, `_check_boss_phase_transition(c: Combatant) -> void`,
called once per turn — the natural hook point (re-confirmed 2026-07-19) is `_on_turn_started()`
(combat.gd:994), immediately after `c.begin_turn()` (line 1016) and before `_plan = MainPhasePlan.new(...)`
(line 1017), guarded by `if c.is_boss:`:
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
            (_panels[c] as CombatantPanel).refresh_status()
        return   # a transition can't re-trigger the same turn it just resolved
    var hp_below_threshold: bool = c.hp < int(c.max_hp * 0.4)
    var cooldown_elapsed: bool = c.boss_last_phase_trigger_turn == -1 or (c.boss_turns_taken - c.boss_last_phase_trigger_turn) >= 10
    if hp_below_threshold and cooldown_elapsed:
        _sacrifice_reinforcements(c)
        c.remove_effect(&"empowered")   # Indestructible always supersedes Empowered (§2) — never both active
        c.attach_effect(EffectLibrary.make(&"indestructible"))
        var minion_a: Combatant = _spawn_enemy_mid_combat(&"warden_acolyte_greater_healer")
        var minion_b: Combatant = _spawn_enemy_mid_combat(&"warden_acolyte_greater_curser")
        c.boss_phase_minion_ids = [minion_a, minion_b]
        c.boss_phase_two_active = true
        c.boss_last_phase_trigger_turn = c.boss_turns_taken
        _log("  ☾ The Hollow Warden becomes INDESTRUCTIBLE and summons reinforcements!")
        (_panels[c] as CombatantPanel).refresh_status()

func _sacrifice_reinforcements(c: Combatant) -> void:
    var total_hp: int = 0
    for m: Combatant in c.boss_reinforcement_ids:
        if m.is_alive():
            total_hp += m.hp
            m.take_damage(m.hp)   # instant removal — take_damage already emits `defeated`, no reward hookup exists for this path (see below)
    if total_hp > 0:
        c.heal(ceili(total_hp / 2.0))
        _log("  ☾ The Hollow Warden sacrifices its reinforcements, healing %d HP." % ceili(total_hp / 2.0))
    c.boss_reinforcement_ids.clear()
```
**Why the explicit `remove_effect(&"empowered")` matters**: `outgoing_damage_multiplier()`
(combatant.gd:460) and `incoming_damage_multiplier()` (line 469) are independent products over
DIFFERENT effect subsets (`affects_incoming == false` vs `== true`) — Empowered (outgoing) and
Indestructible (incoming) don't naturally conflict or overwrite each other; without this explicit
removal they'd silently both be active at once, and Darkness Rampage's damage would incorrectly
still carry Empowered's 1.4× multiplier during an Indestructible window. The locked design ("they
never stack") has to be enforced here, not assumed from the effect system alone.

**"No reward" for sacrificed minions is automatic, not something to suppress**: `_on_enemy_defeated`
(the XP/Amber grant hookup) is connected per-enemy at `_build_combatants()` time — but reinforcement
minions are appended via `_spawn_enemy_mid_combat()` (§3.6), which does NOT connect that signal (only
the original `_build_combatants()` loop does). So `m.take_damage(m.hp)` here correctly emits
`defeated` (for any other listener, e.g. UI cleanup) but grants nothing, with no special-casing
needed.

Enemy Ultimate-firing (needed for Dark Reinforcements to ever trigger) — **confirmed via a fresh
2026-07-19 read of `combat.gd`: there is currently ZERO enemy-side Ultimate logic anywhere** (every
enemy hardcodes `ultimate_id = &""` today, per `enemy_library.gd:49`). Extend `_enemy_stage_ability()`
(combat.gd:870-880), which is called from `_do_spin()` (line 1491) immediately before
`_commit_main1()` (line 1492) on every enemy turn:
```gdscript
func _enemy_stage_ability() -> void:
    if _plan == null or _attacker == null or _attacker.is_player:
        return
    if _attacker.ultimate_id != &"" and _attacker.bonus_meter != null and _attacker.bonus_meter.is_armed():
        _plan.toggle_ultimate()   # mirrors the player-facing _on_ultimate_pressed() path exactly
        return   # firing the Ultimate this turn instead of the base ability (mirrors the player's own mutual-exclusion rule)
    match _attacker.ability_id:
        &"flurry":
            ...   # existing branches unchanged
```
This flows through the existing `_commit_main1()` (line 1415-1485) unchanged — it already logs
`"★ ... fires ULTIMATE — ..."` (line 1433) for any combatant, player or enemy, once
`_plan.fire_ultimate_staged` is true. Confirm `MainPhasePlan.toggle_ultimate()`'s exact signature by
reading `combat/main_phase_plan.gd` directly before implementing this step (not read in this research
pass) — the plan's task brief for this piece should read that file first.

### 3.4 "Dark Reinforcements" Ultimate — spawns minions, deals no damage

Unlike every existing Ultimate, Dark Reinforcements has no reel/damage component at all. Apply it
directly in `_commit_main1()`'s existing `did_ultimate` branch (combat.gd:1432-1433), immediately
after the log line:
```gdscript
if did_ultimate:
    _log("  ★ %s fires ULTIMATE — %s!" % [_attacker.display_name, _ultimate_name(_attacker.ultimate_id)])
    if _attacker.ultimate_id == &"dark_reinforcements":
        var r1: Combatant = _spawn_enemy_mid_combat(&"warden_acolyte_lesser_healer")
        var r2: Combatant = _spawn_enemy_mid_combat(&"warden_acolyte_lesser_curser")
        _attacker.boss_reinforcement_ids.append_array([r1, r2])
        _log("  ☾ Dark Reinforcements — 2 acolytes join the fight!")
```
Add `&"dark_reinforcements"` to `_ultimate_label()`/`_ultimate_name()` (combat.gd:972-992, both
simple `match` statements with one line per existing Ultimate — add one line each, e.g.
`&"dark_reinforcements": return "ULTIMATE: Dark Reinforcements"` and
`&"dark_reinforcements": return "DARK REINFORCEMENTS (summon 2 acolytes)"`).

### 3.5 Darkness Rampage — the boss's phase-locked AoE attack

Confirmed via a fresh 2026-07-19 read of `combatant.gd`: every existing multi-reel AoE Ultimate
(Rampage, Big Bang, Earthquake) is driven by a `fire_X()` method gated on
`bonus_meter.is_armed()`, which sets `turn_reels`/`sticky_wild_count`/`sticky_wild_spins_remaining`/
`aoe_spins_remaining` directly, then a same-shaped `is_X_active()`/`consume_X_spin()` pair. Darkness
Rampage is NOT meter-gated — it auto-replaces the boss's normal attack every turn while Indestructible
is active — so it should set these SAME underlying fields directly from the phase-transition
orchestrator, bypassing the meter-gated `fire_X()` wrapper entirely (there is no player/AI "staging"
step for it; it's a state-driven turn-shape change). Add to `Combatant`:
```gdscript
var darkness_rampage_spins_remaining: int = 0

func is_darkness_rampage_active() -> bool:
    return darkness_rampage_spins_remaining > 0

func consume_darkness_rampage_spin() -> void:
    if darkness_rampage_spins_remaining > 0:
        darkness_rampage_spins_remaining -= 1
```
In `_on_turn_started()` (combat.gd), after `_check_boss_phase_transition(c)` runs (so a
just-triggered phase-2 transition takes effect the SAME turn), if `c.is_boss and
c.boss_phase_two_active`: replace `c.begin_turn()`'s weapon-baseline reel set with 4 Dark reels,
mirroring Big Bang's construction (`fire_big_bang`, combatant.gd:1182-1192) but without the
meter-consume step:
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
`_targets_for(attacker)` (combat.gd:1727-1730) already returns `_enemies_of(attacker)` whenever
`attacker.is_aoe_active()` — and `_enemies_of(c)` (combat.gd:1733-1738) is `other.is_player != c.is_player`,
so when the BOSS (is_player=false) is the attacker, this already resolves to "every living PC,"
exactly the AoE target set Darkness Rampage needs. **No new targeting mechanism required** — this is
the same mechanism Rampage/Collateral/Big Bang/Earthquake already share.

Weapon base damage for Darkness Rampage's 18-damage HIT: the reel/resolver math already computes
`final_damage` from `_attacker.weapon_effective_base_damage()` (combat.gd:1536) — since the boss's
weapon is already `12.0` base damage (§3.2) and Darkness Rampage needs 18, either (a) give the boss a
second weapon-like base-damage value specifically for this attack (a new `Combatant` field,
`darkness_rampage_base_damage: float = 18.0`, read by a modified resolve call only on a Darkness
Rampage turn), or (b) simpler: since the boss's own `weapon.base_damage` is otherwise only used on
its OWN turns and never referenced elsewhere, just set `c.weapon.base_damage = 18.0` for the duration
of a Darkness Rampage turn and restore it to `12.0` immediately after `_do_spin()` resolves that
turn's attacks (mirroring how `begin_turn()` already resets `turn_reels` fresh each turn — the weapon
resource itself is shared/mutated in place elsewhere in this codebase for turn-scoped state, e.g.
Aimed Shot's temporary `empowered` attach). Option (b) is simpler and needs no new field — the plan
should pick it unless the implementer finds a reason `weapon.base_damage` is read somewhere
unexpected between turns (grep for `weapon.base_damage`/`weapon_effective_base_damage` reads outside
`_do_spin`'s own turn before committing to this).

Self-heal: mirror Big Bang's exact `_finish_spin()` pattern (combat.gd:1852-1868) — track a new
`_darkness_rampage_total: int` field on `Combat` (the scene script), computed in `_do_spin()`
alongside the existing `_big_bang_total`/`_earthquake_total`/`_collateral_total` (combat.gd
1543-1558):
```gdscript
_darkness_rampage_total = 0
if _attacker.is_darkness_rampage_active():
    for a in attacks:
        _darkness_rampage_total += a.final_damage
```
and in `_finish_spin()`, alongside the existing per-Ultimate blocks (combat.gd ~1849-1882):
```gdscript
if _attacker.is_darkness_rampage_active():
    var heal_amt: int = ceili(_darkness_rampage_total / 2.0)
    _attacker.heal(heal_amt)
    _log("  ☾ Darkness Rampage: %d total damage → The Hollow Warden heals %d HP." % [_darkness_rampage_total, heal_amt])
    (_panels[_attacker] as CombatantPanel).refresh_status()
    _attacker.consume_darkness_rampage_spin()
```
(`consume_aoe_spin()`/`consume_wild_spin()` are already called unconditionally later in
`_finish_spin()` — line 1912-1913 — so no separate cleanup needed for those two shared fields.)

### 3.6 Mid-fight minion spawning — the one genuinely new piece of plumbing

Confirmed via a fresh 2026-07-19 read: `_build_combatants()` (combat.gd:176-236) builds every
Combatant ONCE at fight start; `_enemies_of()`/`_allies_of()` compute fresh from
`_turn_manager.combatants` on every call (not a cached snapshot), so once a new Combatant is
appended there, targeting/AoE/win-check logic picks it up automatically. What's genuinely missing —
confirmed no existing mechanism does this — is spawning a NEW Combatant mid-fight, after
`_build_combatants()` has already run. New helper, `_spawn_enemy_mid_combat(id: StringName) ->
Combatant`:
```gdscript
func _spawn_enemy_mid_combat(id: StringName) -> Combatant:
    var c: Combatant = EnemyLibrary.make(id)
    _turn_manager.combatants.append(c)
    _enemies.append(c)
    var right_column_index: int = _enemies.size() + _dummies.size() - 1
    var p := CombatantPanel.new()
    p.position = Vector2(1276.0, 80.0 + right_column_index * (278.0 + 14.0))
    add_child(p)
    _panels[c] = p
    p.bind(c)
    # Not connected to _on_enemy_defeated (XP/Amber): reinforcement/phase minions grant no reward
    # whether they die in battle or are sacrificed (§2's "no reward" rule) — this is DELIBERATE, not
    # an oversight; do not add this connection.
    _turn_manager._order.append(c)   # must act THIS round, not wait for next round's get_turn_order()
    return c
```
This extracts the panel-creation shape already inline in `_place_party_column()`
(combat.gd:476-484) into a reusable single-Combatant form, rather than restructuring
`_place_party_column` itself (which stays used, unchanged, for the initial 1276.0-x enemy column at
fight start). `_turn_manager._order` is currently a private (`_`-prefixed) field with no public
append method — the plan's implementation task should either add a small
`TurnManager.insert_acting_this_round(c: Combatant) -> void` method (`_order.append(c)`) rather than
reaching into `_`-prefixed state from `combat.gd` directly, matching this codebase's existing
practice of small purpose-built public methods on `TurnManager` (e.g. `roll_d100()`) rather than
exposing internals. Given `acts_last = true` on every minion this spawns (§3.2), appending at the
end of `_order` is correct without needing position-aware insertion logic — a minion appended this
way naturally acts after every already-ordered combatant for the remainder of THIS round, and next
round's fresh `get_turn_order()` call will re-sort it correctly by its `acts_last`/initiative rule
regardless.

**Behavioral contract for the implementation task** (this is the one part of this spec too dependent
on exact line-level internals to hand over as fully dictated code beyond the sketch above): a
Combatant spawned via `_spawn_enemy_mid_combat()` must be fully playable in the SAME round it
appears — targetable by `_enemy_pick_target`/AoE, panel-visible with correct HP/status display, and
takes its own turn before the round ends — not merely present in a data array. The implementation
task should read `_build_combatants()`, `_place_party_column()`, and `turn_manager.gd`'s
`_start_next_round()`/`_announce_current()` directly before writing this method, and its test must
prove the contract end-to-end (spawn mid-round, assert the new Combatant takes a turn that same
round) rather than only asserting it exists in `_enemies`/`combatants`.

### 3.7 Floor 4 placement

`world/dungeon_demo.gd` — floor 4 (index 3) currently has only a `StairsUp`, no enemy (confirmed:
floor 4 was deliberately left without a placeholder encounter in the 2026-07-18 escalating-floors
work — "reserved for the boss, a later step," per `tests/test_dungeon_demo_scene.gd`). Add a single
`OverworldEnemy` placement using the SAME `_place_dungeon_enemy()`/`is_defeated()`-gated convention
floors 1-3 already use:
```gdscript
var floor4_ids: Array[StringName] = [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser"]
_place_dungeon_enemy("DungeonFloor4Enemy", floor4_ids, floor_bounds(3).position + ENEMY_LOCAL, 3)
```
No new placement mechanism needed — this is exactly the existing multi-enemy floor pattern (§2 phase
1's key simplification: the phase-1 minions are ordinary starting combatants, not a spawned pair).

## 4. Out of scope

- **The Lost Cat quest** (accept/track/turn-in flow, the cat interactable, the Thank You Note, the
  on-screen quest tracker) — Plan 3, not touched here. Floor 4's cat placeholder is NOT added by this
  plan; Plan 3 adds it once this boss's `is_defeated()` state is real and testable.
- **The Treasure Trove reward** — a separate, later roadmap step.
- **Any use of the Light damage type** — Plan 1 created it; nothing uses it yet, including this boss
  (it deals/defends Dark only).
- **Seer's "Select your Fate" type-picker** extending to 8 buttons — confirmed deliberately deferred
  (Plan 1's own scope note, unchanged here).
- **Balancing any of this fight's numeric magnitudes** (550 HP, 12/18 base damage, 40% threshold, the
  10-turn cooldown, minion HP/Amber values) — all `[ASSUMPTION]` per CLAUDE.md §4, tuned by playtest
  after the fight is functionally correct, not now.
- **A generic reusable "boss" framework** (`docs/design-bible/28-encounter-design-framework.md`'s
  unapproved BossPhase architecture) — this boss is hand-built with bounded hooks into the existing
  turn/phase functions, matching this project's existing per-class/per-enemy hand-authored style, not
  a new generic system.

## 5. Testing plan

- **New effects**: `warden_curse`'s flat 4/7/10 stacking DoT (seeded via a fixed `dot_base_damage`,
  not weapon-derived); `indestructible` (`incoming_damage_multiplier() == 0.0` for a direct hit, but
  a DoT tick on the same combatant is unaffected — proving the documented pipeline separation holds
  for this specific new effect); `Combatant.remove_effect()` genuinely removes an unexpired effect
  early and nothing else.
- **Turn order**: an `acts_last = true` combatant always sorts after every `acts_last = false`
  combatant in `get_turn_order()`, regardless of initiative roll; stun immunity holds from turn 1
  with no prior cast needed (permanent `grants_stun_immunity` effect attached at construction).
- **EnemyLibrary**: The Hollow Warden's stats/`ultimate_id`/`meter_visible`/`is_boss`; both acolyte
  variants' HP/`acts_last`/stun-immunity/ability-id-per-role; confirm neither the boss nor either
  acolyte id appears in `EnemyLibrary.IDS`.
- **Enemy Ultimate-firing**: a focused test proving `_enemy_stage_ability()` stages an enemy's
  Ultimate once its meter is full (in preference to its base ability that same turn), flowing through
  the existing `_commit_main1()` unchanged, correctly logging "fires ULTIMATE."
- **Mid-fight spawn**: an end-to-end combat test triggering `_spawn_enemy_mid_combat()` mid-round and
  confirming the new Combatant is genuinely playable THIS round — targetable, panel-visible, takes
  its turn before the round ends — not just present in a data array (the behavioral contract from
  §3.6).
- **Darkness Rampage**: a scripted spin proving all 4 reels are Dark/WILD, the attack hits every
  living PC (not just the primary defender), damage lands per the 18-base/1.5×-crit formula, and the
  boss heals `ceili(total/2)` afterward.
- **Full phase-transition sequence**: a scripted fight proving the whole cycle — phase-1 minions'
  scripted actions (heal+guard / curse), the 40%-HP trigger, Indestructible blocking a direct hit but
  not a DoT tick, Darkness Rampage firing every Indestructible turn, Indestructible clearing exactly
  when both phase-2 minions die, Empowered applying afterward, the 10-turn-of-the-boss's-own-turns
  cooldown correctly gating a re-trigger (not 10 global rounds), and Ultimate-summoned reinforcements
  being sacrificed (no reward, boss heals half their HP) if still alive at a later trigger.
- **`Combatant.heal()`/`take_damage()` interplay used by the sacrifice mechanic**: confirm
  `take_damage(m.hp)` on a reinforcement correctly emits `defeated` (for any listener) while granting
  no XP/Amber, since `_spawn_enemy_mid_combat()` deliberately never connects that signal.
- **End-to-end**: a full human playtest — descend to floor 4, fight The Hollow Warden through the
  phase-1 minions and at least one full phase transition (ideally long enough to see the 10-turn
  cooldown re-trigger), fire the boss's Ultimate if its meter fills, and win or lose cleanly (losing
  should behave exactly like any other dungeon fight loss — no special-casing needed here, per the
  existing loss-handling architecture).

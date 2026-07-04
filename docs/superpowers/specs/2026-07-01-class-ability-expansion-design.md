# Class Ability Expansion — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Supersedes the brainstorm menu at
> `2026-06-30-class-ability-expansion-brainstorm.md` (kept for history). This is the source of
> truth for implementation. All numeric magnitudes are `[ASSUMPTION]` — data-driven, tuned post-
> playtest per CLAUDE.md §4, never hardcoded as "the" balance.

## 1. Goal

Every class grows from **1 base ability + 1 Ultimate** to **4 base abilities + 1 Ultimate**, gated
by a brand-new **character level** concept (does not exist in the codebase today):

| Level | Unlock |
|---|---|
| L1 | Base ability #1 (existing) |
| L3 | Ultimate (existing) |
| L5 | Base ability #2 (NEW) |
| L7 | Base ability #3 (NEW) |
| L9 | Base ability #4 (NEW) — **ultimate-tier**: gated by a new per-ability **cooldown** system, not just resource cost |

Plus an **ENDGAME combat tester** scene/mode: every combatant spawns at max level (≥9) so all 4
abilities + Ultimate are simultaneously selectable, for human playtesting of the full kits.

## 2. New infrastructure (net-new, not extensions of existing fields)

Per the architecture audit (`character_class.gd`, `combatant.gd`, `main_phase_plan.gd`,
`effect.gd`, `enemy_ai.gd`):

### 2.1 Character level
- New `level: int` on `Combatant` (or set at `ClassLibrary.build_combatant` time).
- `CharacterClass.ability_id: StringName` (singular) → **`abilities: Array[AbilityDef]`**, a new
  lightweight `Resource` (`combat/resources/ability_def.gd`): `id: StringName`,
  `unlock_level: int`, `cost: Dictionary`, `resource: StringName`, `cooldown_turns: int` (0 = no
  cooldown). The existing L1 ability becomes `abilities[0]` with `unlock_level = 1`.
- `Combatant.unlocked_abilities()` filters `abilities` by `level >= unlock_level`.
- `MainPhasePlan` changes from "one ability_id toggle" to "choose one unlocked ability id per
  turn" — the commit-time `match ability_id:` dispatch grows per new ability but the shape (one
  staged ability, spend its cost, apply its effect) is unchanged.

### 2.2 Cooldowns
- New `Combatant.cooldowns: Dictionary` (`StringName -> int`, remaining turns). Decremented at
  that combatant's own Upkeep phase (alongside existing resource regen).
- `MainPhasePlan.can_stage_ability()` gains a cooldown check: `cooldowns.get(id, 0) <= 0`.
- On commit, if the staged ability has `cooldown_turns > 0`, set `cooldowns[id] = cooldown_turns`.
- Only L9 abilities set a cooldown in this pass (L1/L5/L7 stay resource-cost-only, matching today).

### 2.3 Effect resource — two new optional fields
`combat/resources/effect.gd` gets two additive fields (default empty/0, so all 16 existing
effects are untouched):
- `immune_effect_ids: Array[StringName] = []` — while this effect is active on a combatant,
  `attach_effect` refuses to attach any incoming effect whose id is in this list. Powers Mountain
  Stance's CC immunity.
- `thorns_pct: float = 0.0` — when a combatant with this effect active takes a hit, the attacker
  takes back `thorns_pct` of the damage dealt, same damage type. Powers Bastion.

### 2.4 EnemyAI — Taunt awareness
`EnemyAI.pick_target` gains a pre-filter: if any living PC has effect `&"taunt"`, narrow the
candidate pool to just the taunting PCs *before* running the existing type-effectiveness →
lowest-HP tiering. If zero PCs are taunting, behavior is unchanged. Multiple simultaneous taunters
resolve via the existing tiering among just that subset — never a hard lock to one target. Player
targeting is never restricted by Taunt (unchanged).

### 2.5 Riposte-charge counter (Skirmisher-only, but generic field)
New `Combatant.riposte_charges: int = 0`. Incremented whenever the **Evasion** effect downgrades
an incoming hit face to a miss against that combatant. Reset to 0 when Riposte Storm is used.

## 3. Shared new-effect vocabulary (10 new, reusing existing `kind` enum — no enum changes)

| id | kind | beneficial | stacking | notes |
|---|---|---|---|---|
| `sundered` | MULTIPLIER_EDIT | false | refresh, no stack | incoming dmg ×1.25 `[ASSUMPTION]`, 2t |
| `weakened` | MULTIPLIER_EDIT | false | refresh, no stack | outgoing dmg ×0.75 `[ASSUMPTION]`, 2t |
| `jinxed` | REEL_FACE_EDIT | false | refresh, no stack | own success→neutral, crit-success→success, 2t |
| `rooted` | INITIATIVE_MOD | false | refresh, no stack | one-time −30 `[ASSUMPTION]` (heavier than Slow's −20 tier), 2t |
| `guarded` | MULTIPLIER_EDIT | true | refresh, no stack | incoming dmg ×0.75 or ×0.5 depending on source ability; last-applied wins (matches existing refresh semantics) |
| `taunt` | REEL_FACE_EDIT | true | refresh, no stack | pure marker, no face edit, mirrors Hunter's Mark's "kind chosen loosely" precedent |
| `empowered` | MULTIPLIER_EDIT | true | refresh, no stack | outgoing dmg × varies by source ability (1.4–1.6 `[ASSUMPTION]`) |
| `evasion` | REEL_FACE_EDIT | true | refresh, no stack | incoming success/crit-success → miss, 2t |
| `regen` | DAMAGE_OVER_TIME | true | mirrors Bleed's tiered stack | heal per turn instead of damage |
| `cursed` | DAMAGE_OVER_TIME | false | mirrors Bleed's tiered stack | Mystic-typed DoT |

Already exist, reused as-is: Bleed, Slow, Stunned, Hunter's Mark, Inspirational, Shielded.

## 4. Per-class ability specs

Costs/magnitudes are `[ASSUMPTION]`. Each class's L1/L3 rows are the **existing, unchanged**
abilities, included only for unlock-order context.

### ⚔️ Warrior — Stamina
| Lvl | Ability | Effect |
|---|---|---|
| 1 | Rend (existing) | Slashing, stacking Bleed |
| 3 | Wild (existing Ultimate) | — |
| 5 | **Sundering Strike** (NEW) | Slashing reel; on hit, applies `sundered` to target. Cost 3 stamina. |
| 7 | **Heroic Guard** (NEW) | Self-cast, no reel. Grants self `guarded` (×0.75) + `taunt`, 2t. Cost 3 stamina. |
| 9 | **Second Wind** (NEW, ultimate-tier) | Self-cast. Heals 30% max HP (ceil), Cleanses all debuffs, grants self `guarded`, 2t. Cost 5 stamina. **CD 4 turns.** |

### 🛡️ Vanguard — Stamina
| Lvl | Ability | Effect |
|---|---|---|
| 1 | Heft (existing) | Reel-edit reliability |
| 3 | Rampage (existing Ultimate) | — |
| 5 | **Bloodwrath** (NEW) | Self-cast. Grants `empowered` scaling with missing HP% (+1% per 2% HP missing, cap +40%), 2t. Cost 3 stamina. |
| 7 | **Quake Slam** (NEW) | Crushing reel; on hit, reliably applies `slow` (existing effect/stacking rule). Cost 4 stamina. |
| 9 | **Mountain Stance** (NEW, ultimate-tier) | Self-cast. Grants heavy `guarded` (×0.5) + `immune_effect_ids = [slow, stunned, rooted]` + `taunt`, 3t. Cost 5 stamina. **CD 4 turns.** |

### 🗡️ Skirmisher — Stamina
| Lvl | Ability | Effect |
|---|---|---|
| 1 | Flurry (existing) | Splice extra reel |
| 3 | Sticky-Wild (existing Ultimate) | — |
| 5 | **Feint & Riposte** (NEW, updated) | Self-cast. Grants `evasion` + `taunt` together, 2t. Cost 3 stamina. |
| 7 | **Quickstep** (NEW) | Self-cast. Grants `haste` — reuse INITIATIVE_MOD kind, +20 one-time (mirrors Slow's −20 tier, inverted), 2t. Cost 3 stamina. |
| 9 | **Riposte Storm** (NEW, ultimate-tier) | Active. Consumes `riposte_charges` (built while Evasion is active and an attack whiffs against him); nova reel deals +15% weapon damage per charge (cap 5 charges), then resets charges to 0. Fires at baseline if 0 charges. Cost 4 stamina. **CD 3 turns.** |

**Taunt/AI note:** pairing `taunt` onto Feint & Riposte (not a standalone ability) is the fix for
enemy AI ignoring the Skirmisher — see §2.4.

### 🎲 Chancer — Stamina
| Lvl | Ability | Effect |
|---|---|---|
| 1 | Re-roll (existing) | — |
| 3 | Wildcard Gamble (existing Ultimate) | — |
| 5 | **Loaded Dice** (NEW) | Self-cast. Adds crit faces this spin (reuse `apply_luck`-style injection) + lights one `extra_lines` payline. Cost 3 stamina. |
| 7 | **Jinx the Odds** (NEW) | Attack reel; on hit, applies `jinxed`, 2t. Cost 3 stamina. |
| 9 | **Double or Nothing** (NEW, ultimate-tier, special mechanic) | Self-cast. **Cost = 100% of current remaining stamina** (min 1). Grants `empowered` (×1.5) + a crit-fail-recoils-as-self-damage flag to the *next* spin. When that spin resolves: each non-fail reel refunds 1 stamina (ASSUMPTION, scales with reel count); any crit-fail reel deals its own rolled damage back to the Chancer. **CD 7 turns.** |

### 🏹 Ranger — Stamina
| Lvl | Ability | Effect |
|---|---|---|
| 1 | Hunter's Mark (existing) | — |
| 3 | Collateral Damage (existing Ultimate) | — |
| 5 | **Aimed Shot** (NEW) | Piercing reel with a one-shot `empowered` baked in; extra multiplier if target already has Hunter's Mark. Cost 3 stamina. |
| 7 | **Snare Trap** (NEW) | Attack reel; on hit, applies `rooted`. Cost 4 stamina. |
| 9 | **Crippling Shot** (NEW, ultimate-tier, includes player's requested rider) | Piercing called-shot; on hit, applies `weakened`, AND deals +50% bonus damage if target currently has `slow`, `rooted`, or `stunned` (checked via `has_effect` on any of the three). Cost 5 stamina. **CD 3 turns.** |

### 🔮 Seer — Mana
| Lvl | Ability | Effect |
|---|---|---|
| 1 | Select your Fate! (existing) | — |
| 3 | The Big Bang (existing Ultimate) | — |
| 5 | **Hex** (NEW) | Mystic attack reel; on hit, applies `cursed` (mirrors Bleed's stack tiers), 3t. Cost 4 mana. |
| 7 | **Foresight** (NEW) | Support, targets an ally. Grants `shielded` (reuse existing effect; flat shield ≈15% of caster's max mana, ceil). Cost 4 mana. |
| 9 | **Mana Surge** (NEW, ultimate-tier) | Self-cast. Applies `empowered` (×1.6) to caster's own next heavy 2-reel attack only, consumed after that spin. Cost 6 mana. **CD 4 turns.** |

### 🪨 Warden — Mana
| Lvl | Ability | Effect |
|---|---|---|
| 1 | Rallying Cry (existing) | — |
| 3 | Earthquake (existing Ultimate) | — |
| 5 | **Entangle** (NEW) | Earth attack reel; on hit, applies `rooted` (shared def with Ranger's Snare Trap). Cost 4 mana. |
| 7 | **Regrowth** (NEW) | Support, targets an ally. Grants `regen` (mirrors Bleed's stack tiers, heals instead), 3t. Cost 4 mana. |
| 9 | **Bastion** (NEW, ultimate-tier) | Self-cast. Grants heavy `guarded` (×0.5) + `taunt` + `thorns_pct = 0.20`, 3t. Cost 6 mana. **CD 4 turns.** |

## 5. ENDGAME combat tester

New start-of-encounter option (alongside the existing selection screen): spawns every combatant
at `level = 9` so all 4 abilities + Ultimate are unlocked and selectable, for playtesting full
kits without a real progression system. Reuses the existing party/enemy roster selection UI —
only the spawned `level` differs.

## 6. Test plan

Headless suites under `tests/`, one per new subsystem, following the existing `extends SceneTree`
+ `_check()` pattern:
- `test_character_level.gd` — unlock filtering by level.
- `test_ability_cooldown.gd` — cooldown set on commit, decrements at upkeep, blocks re-staging.
- `test_effect_immunity.gd` — `immune_effect_ids` blocks attach; unaffected effects still attach.
- `test_effect_thorns.gd` — thorns reflects correct %, correct damage type.
- `test_enemy_ai_taunt.gd` — AI narrows to taunters; multi-taunter tie-break unchanged; no-taunt
  path unchanged (regression).
- Per-class new-ability tests (14 total, one per new ability) mirroring existing per-ability
  tests (`test_ability_cost.gd`, `test_bleed.gd` style): effect applied, cost spent, cooldown set
  where applicable, riposte-charge accrual/consumption, Chancer's all-in cost + refund math.
- Full regression: existing 69 suites must stay green.

## 7. Explicitly out of scope (this pass)

- Real leveling/XP/progression systems (level is a test/tester knob only, per
  [[design-bible-out-of-combat]] talents work being separate and later).
- Talents/Reel Points — comes after this ability depth per prior direction.
- Tuning any `[ASSUMPTION]` number by feel — that's a post-playtest pass.

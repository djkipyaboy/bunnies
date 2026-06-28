# Enemy AI v1 + Enemy Variation + Selection-Screen Polish — Design

> **Date:** 2026-06-28 · **Branch:** `nvm-party-combat` · **Status:** approved, pre-implementation.
> Source of truth is `DESIGN.md`; this spec records one iteration on the N-vs-M party prototype.
> Supersedes the placeholder enemy-AI note in `2026-06-29-nvm-party-combat-design.md` §4.

## 1. Motivation

The N-vs-M party prototype runs, but the three enemies are interchangeable (no roles, no abilities)
and the AI is a deliberate placeholder (`first_living`). This iteration makes the test *realistic*:
enemies vary by weapon/role, two of them borrow a PC base ability, and the AI both **targets
intelligently** (by type effectiveness, then lowest HP) and **uses its abilities**. Alongside, the
character-select screen gets the legibility polish a first-time playtester needs — multi-line
tooltips, combat-role badges, and vertically-centred columns.

Two parts ship together (one branch, one merge): **enemy variation + AI** (the substantive change)
and **selection-screen polish** (UI).

## 2. Part A — Enemy weapon / role variation

`EnemyLibrary` gains a per-enemy **combat role** and, for two of the three, a **borrowed PC base
ability** (and a small stamina pool to pay for it). No enemy gets an Ultimate.

| Enemy | Damage type (flavor) | Role | Base ability | Stamina pool | Ultimate |
|---|---|---|---|---|---|
| Cluny's Rat | Crushing (cudgel) | `&"melee"` | — | none | none |
| Redtooth (Ferret) | Slashing (**dagger**) | `&"melee"` | `&"flurry"` (Skirmisher) | sized for Flurry | none |
| Killconey (Stoat) | Piercing (**bow**) | `&"ranged"` | `&"hunters_mark"` (Ranger) | sized for Mark | none |

- Damage types are unchanged from the current `EnemyLibrary` (ferret = Slashing, stoat = Piercing);
  only the *flavor* (dagger / bow) and the new role/ability are added. Rat is unchanged.
- The ferret/stoat `Combatant` is built with a `ResourcePool` whose starting stamina ≥ its ability
  cost and a small regen, so the greedy AI (Part B) can fire the ability each turn it chooses to.
  `ability_id` / `ability_cost` / `ability_resource` are set so `MainPhasePlan.commit()` applies them
  through the **same path PCs use**. `ultimate_id` is left empty (no Ultimate path for enemies).
- The rat keeps no pool / no ability — it's the plain melee baseline.
- Combat role is **data**, not behavior: it drives the selection-screen badge/tooltip only. The AI's
  targeting reads the *damage type vs defense* chart, not the role label.

### Chancer (player) role
Chancer is **`&"ranged"`** — lore: a slingshot firing magically (Storm) empowered seeds. The Storm
damage type and all existing Chancer mechanics are unchanged; this only sets its role for the badge.

### Where role lives
Add `@export var combat_role: StringName = &"melee"` to `CharacterClass` (player classes set it in
`ClassLibrary`). Enemies are plain `Combatant`s built by `EnemyLibrary`, so the *enemy* role is held
in `EnemyLibrary` (a small `id → role` lookup, like `EnemyLibrary.label`), not on `CharacterClass`.

Player-class roles:

| Class | Role |
|---|---|
| Warrior, Vanguard, Skirmisher | `&"melee"` |
| Ranger, Chancer | `&"ranged"` |
| Seer, Warden | `&"caster"` |

## 3. Part B — First-iteration enemy AI

Two **pure, isolated, unit-testable** policies. Both live as static functions (in `combat.gd`
alongside `first_living`, or a small `EnemyAI` helper — implementer's call, but they MUST be pure and
scene-free so they're tested without the scene).

### 3.1 Targeting — `pick_target(attacker, pcs) -> Combatant`

Replaces the `_enemy_pick_target` placeholder. Inputs: the attacking enemy and the array of PCs
(living + dead; the function filters). Algorithm:

1. Filter to **living** PCs. If none, return `null` (caller already guards combat-over).
2. For each living PC, compute `eff = attacker.weapon_type().multiplier_against(pc.defense_type)`.
3. Partition into tiers: **super-effective** (`eff > 1.0`), **neutral** (`eff == 1.0`),
   **resisted** (`eff < 1.0`).
4. Choose the best non-empty tier in order: super-effective → neutral → resisted.
   *(If the only living PCs are resisted matchups, the enemy still attacks the best of them — it does
   not pass its turn.)*
5. Within the chosen tier, return the PC with the **lowest current HP** (`hp`). This is also the
   tie-break when several PCs share the top tier. Ties on HP resolve by party order (stable: first
   living wins) so the result is deterministic for tests.

Notes:
- Float compare uses a small epsilon for the `== 1.0` neutral test (chart values are authored
  multiples like 0.75 / 1.0 / 1.25, so exact compare is fine, but guard with `is_equal_approx`).
- `weapon_type()` is the enemy's single weapon type (enemies have one weapon); no per-reel typing.

### 3.2 Ability use — greedy, on the enemy turn

After the enemy's primary target is chosen (`pick_target`) and `_plan` is built, the AI decides
whether to stage the enemy's base ability. Policy (greedy, with one guard):

- **No ability** (rat) → nothing staged; normal attack.
- **Flurry** (ferret) → stage if **affordable** (`_plan` can stage it / resource_pool affords
  `ability_cost`). Pure upside, so always fire when affordable.
- **Hunter's Mark** (stoat) → stage if **affordable AND the chosen target is not already marked**
  (`not target.has_effect(&"hunters_mark")`). Don't waste it re-marking the same PC.

Mechanically the enemy turn sets the same plan flag the PC toggle sets (`_plan.ability_staged`,
respecting `MainPhasePlan`'s existing stage/affordability check), then `_do_spin →
proceed_to_combat()` commits it via `MainPhasePlan.commit()` — identical apply path to a PC.

### 3.3 Enemy commit wiring (Hunter's Mark attach)

The PC spin path (`_on_spin_pressed`) attaches the `&"hunters_mark"` debuff to `_defender` after
commit (when `hunters_mark_pending`). The enemy path (`_do_spin`) must do the **same attach** so a
stoat's mark actually lands on its target PC. The downstream face-swap is already side-agnostic
(`_do_spin:1076` swaps whenever `_defender.has_effect(&"hunters_mark")`), so once the enemy attaches
the mark, every enemy attacking that PC benefits — no further change.

The enemy must NOT reach any Ultimate code (no `ultimate_id` set → `_plan.fire_ultimate_staged`
stays false; the enemy turn never stages an Ultimate).

## 4. Part C — Selection-screen polish

All three changes are confined to the start overlay (`_build_start_overlay` / `_build_roster_list`).
Badges and role data exist **on the selection screen only** for now (the in-combat `CombatantPanel`
is untouched; eventual character-creation screens will host the production badge).

### 4.1 Multi-line tooltips

Reformat the per-class tooltip strings (currently single long lines in `_class_tooltip`) into ~3–4
short newline-separated lines, and add a parallel `_enemy_tooltip(id)`. Suggested shape per entry:

```
<Display name>
<Type> · <N> reels · <Role>
Ability: <one line>
Ultimate: <one line>   (omit for enemies / abilityless)
```

Wire `tooltip_text` on every roster button (both lists). The roster-list builder gains an optional
`tooltip` provider (a `Callable id -> String`) so both lists stay generic.

### 4.2 Role badges — `RoleVisuals`

A new helper `combat/ui/role_visuals.gd` (mirrors `combat/ui/type_visuals.gd`):

- `static func label(role: StringName) -> String` → `"MELEE"` / `"RANGED"` / `"CASTER"`.
- `static func color(role: StringName) -> Color` → identity color
  (melee = warm red, ranged = green, caster = blue-violet; exact values are placeholders).
- Unknown role → a neutral grey label `"—"` (defensive default).

Render: a compact pill = a `Label` with a `StyleBoxFlat` background (rounded corners, the role color
at reduced alpha, contrasting text), placed to the **right** of each roster button. The roster-list
builder gains an optional `role` provider (`Callable id -> StringName`); when present it adds the
badge beside each button.

### 4.3 Vertical centering

`_build_roster_list` currently starts at a hardcoded `top_y = 120`. Compute the list block height
(`heading + ids.size() * STEP`) and choose a `top_y` that centers the block in the window's
mid-region — between the title/subtitle band at top and the BEGIN/dummy buttons at the bottom. Both
columns use the same computed `top_y` so they align. Keep the existing column X positions.

## 5. Testing

- **`test_enemy_ai`** (new, pure) — `pick_target`: super-effective chosen over neutral; neutral over
  resisted; lowest-HP tie-break within a tier; all-resisted fallback still returns a PC; dead PCs
  skipped; empty → null.
- **`test_role_visuals`** (new, pure) — `RoleVisuals.label`/`color` for the three roles + unknown
  default; assert `ClassLibrary` gives every class a non-empty valid role and `EnemyLibrary` gives
  every enemy a valid role.
- **`test_enemy_abilities`** (new) — build a ferret: staging Flurry raises its turn reel count by 1;
  build a stoat: after its commit, its target PC `has_effect(&"hunters_mark")`; assert neither enemy
  has an `ultimate_id` / can stage an Ultimate. Rat: no ability staged.
- **Existing suites stay green**, especially `test_scene_party_smoke` / `test_scene_load_seer`
  (overlay still builds) and `test_party_combat` (turn flow). Run the full headless suite before
  commit.

## 6. Out of scope (YAGNI)

- No enemy Ultimates; no enemy Main-1 preview UI (enemies stage silently).
- No in-combat role badges on `CombatantPanel` (selection screen only this iteration).
- No new damage types or weapon-category system — "dagger/bow/slingshot" are flavor names over the
  existing six damage types, not a new data axis.
- No smarter AI (threat tables, ability sequencing, focus-fire memory) — greedy + the targeting
  rule is the first iteration; richer policy is a later pass.

## 7. Decisions locked

- Chancer = Ranged (slingshot). Stoat = Ranged bow + Hunter's Mark. Ferret = Melee dagger + Flurry.
  Rat = plain Melee. No enemy Ultimates.
- AI targeting: super-effective → neutral → resisted, lowest-HP tie-break/fallback.
- AI ability use: greedy when affordable; stoat won't re-mark an already-marked target.
- Enemies that have an ability get a small stamina pool (consistent economy via the existing
  commit path); abilityless enemies (rat) stay pool-less.
- Badges + role data are selection-screen-only for now.

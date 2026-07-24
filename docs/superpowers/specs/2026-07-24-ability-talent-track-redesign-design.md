# Ability & Universal Talent Tracks — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed 2026-07-24, mid-execution of the 2026-07-23 ability/talent
> redesign plan, after the player reviewed the original Task 12 checkpoint (universal perks only)
> and asked for a bigger system. **This spec supersedes §5 ("talent points & perks") and §6
> ("talent UI & input wiring") of `2026-07-23-ability-talent-redesign-design.md` — §§1-4, 7-8 of
> that spec remain locked and unchanged** (the ability-level compression to L1-4 and the 7 per-class
> L5 passives are already shipped as Tasks 1-11 and are untouched by this revision). This spec
> locks the STRUCTURE of two parallel talent tracks; the actual content (126 ability-talent options,
> the 10 universal perks — already shown to and liked by the player) is explicitly deferred to the
> implementation plan/build phase — see §5.

## 1. Goal

Replace the single "6 talent points, spent freely on a shared universal+class-flavored pool across
L5-10" model with **two independent tracks**, so that (a) every learnable thing a class has — its 4
abilities, its passive, its Ultimate — gets its own small, level-gated customization moment, and (b)
general stat growth follows a D&D-style ability-score-improvement cadence, separate from the
ability-specific track entirely.

## 2. Decisions locked during brainstorming

- **Two tracks, fully independent.** A character accumulates points in both simultaneously; neither
  track's points are spendable on the other.
- **Track A — Ability Talents (new).** One point per level, L5 through L10 (6 total), but **each
  point is bound to a specific row** — it can only be spent on that row's 3 options, never banked
  for a different row:
  | Level | Row unlocked |
  |---|---|
  | 5 | Base ability (the class's L1 ability) |
  | 6 | The ability that unlocked at L2 |
  | 7 | The ability that unlocked at L3 |
  | 8 | The ability that unlocked at L4 |
  | 9 | The class's L5 passive |
  | 10 | The Ultimate |

  Each row offers **exactly 3 options**, simple in scope per the player's own framing — "adding an
  additional effect or increasing damage by a percentage," not new mechanics. A row caps at **1
  pick, ever** (can't pick more than one option in the same row). A point can be **saved indefinitely**
  (not forced to spend the turn it's earned) but stays scoped to its own row forever.
- **Track B — Universal Perks (content unchanged, cadence changed).** The 10 perks already designed
  and approved during the original Task 12 checkpoint (`might_boost`, `finesse_boost`, `vigor_boost`,
  `focus_boost`, `grit_boost`, `luck_boost`, `deep_reserves`, `sharp_reflexes`, `thick_skin`,
  `battle_hardened` — see §5 for the exact table, carried over verbatim) stay exactly as designed.
  What changes is the cadence: instead of "6 points, freely spent across L5-10," a character gets
  **one pick opportunity at each of L2, L4, L6, L8, L10** (5 total, starting well before Track A
  even begins at L5). Still **one-time-pick per perk id, non-stacking** — the existing rule carries
  over unchanged. Still swappable, town-only (§4).
- **Levels 6, 8, and 10 grant a pick in BOTH tracks simultaneously** (an Ability Talent row unlocks
  the same level as a Universal Perk opportunity). Levels 2 and 4 are Universal-Perk-only (Track A
  hasn't started yet). Levels 5, 7, and 9 are Ability-Talent-only.
- **The Ultimate's own gating is unchanged** — still usable at any level, gated only by the Bonus
  Meter filling (locked in the original 2026-07-23 spec §2/§8 and not reopened here). Only the
  Ultimate's **talent row** (its 3 flavor options) requires L10 — the Ultimate itself remains fully
  playable from L1 with an empty/unpicked Ultimate-talent row.
- **Respec: swappable, town-only, for BOTH tracks** — identical rule, identical mechanism (mirrors
  the Vault's `vault_available` safe-zone gating already used elsewhere in this project). In town, a
  spent point in either track can be freely re-picked; in the overworld/dungeon, already-spent picks
  are still visible (consistent with the "still presented as an option, just restricted" convention)
  but swapping is disabled.
- **Content authoring for the 126 Ability Talent options (6 rows × 3 options × 7 classes) is
  deferred to the implementation plan** — proposed in one batch, grouped by class for readability,
  for the player to review and approve before any of it is built. This mirrors exactly how the 7
  passive designs (Task 4) and the 10 universal perks (original Task 12) were each proposed as a
  checkpoint table rather than hand-designed during brainstorming. See §5.
- **UI: locked rows are shown, not hidden.** Unlike `AbilityMenuPanel`'s existing convention (locked
  abilities hidden entirely), the Ability Talent grid shows **all 6 rows for a class at once**,
  including ones the character hasn't reached yet — each locked row's 3 options are visible but
  disabled/grayed, labeled with its unlock level (e.g. "Unlocks at Level 8"). This is a deliberate
  departure from the Ability Menu's hide-when-locked rule: a talent TREE benefits from the player
  seeing the whole shape of it in advance, the way a grid/tree UI conventionally works. The Universal
  Perk section of the same panel is unaffected by this and keeps its existing shown-when-earned
  behavior (nothing to preview there — it's a flat list, not leveled rows).

## 3. Architecture — Ability Talents (Track A)

- New resource `AbilityTalentOption` (mirrors `TalentPerkDef`'s shape, kept as a separate class since
  its fields differ meaningfully — a stat-key/amount shape doesn't fit an ability-scoped effect):
  `id: StringName`, `display_name: String`, `description: String`, plus whatever a specific option's
  effect needs. A flat-percentage option (e.g. "Rend's bleed damage +20%") is data (a multiplier
  field read at the existing damage-calc site); an added-effect option needs a small bespoke method,
  same convention as passives (§4 of the 2026-07-23 spec) — this project does not build a generic
  rules/condition framework, per that spec's already-locked reasoning.
- New static `AbilityTalentLibrary` (mirrors `TalentPerkLibrary`/`ClassLibrary`'s registry
  convention): `options_for(class_id: StringName, row_id: StringName) -> Array[AbilityTalentOption]`
  — returns exactly 3 entries for a valid `(class_id, row_id)` pair. `row_id` is one of 6 fixed
  StringNames: `&"base_ability"`, `&"ability_l2"`, `&"ability_l3"`, `&"ability_l4"`, `&"passive"`,
  `&"ultimate"` — chosen as level-independent, ability-slot-shaped labels (not "l5_talent" etc.) so
  the row's identity doesn't depend on restating the level, which already lives in one place (§3.1
  below).
- New `Combatant` state: `ability_talent_picks: Dictionary` keyed by `row_id: StringName` →
  `option_id: StringName` (absent key = no pick yet in that row — a `Dictionary` fits better than a
  flat `Array[StringName]` here since a pick is inherently row-scoped, unlike `talent_perks`' flat
  list where order/identity alone is sufficient).
- New methods:
  - `func ability_talent_row_unlock_level(row_id: StringName) -> int` — the fixed mapping from §2's
    table (`base_ability`→5, `ability_l2`→6, `ability_l3`→7, `ability_l4`→8, `passive`→9,
    `ultimate`→10). A `match` over the 6 fixed ids, not derived from `AbilityDef.unlock_level` +
    offset — keeps the mapping legible as one static table rather than arithmetic a reader has to
    re-derive.
  - `func ability_talent_row_unlocked(row_id: StringName) -> bool` — `level >=
    ability_talent_row_unlock_level(row_id)`.
  - `func pick_ability_talent(row_id: StringName, option_id: StringName) -> bool` — rejects if the
    row isn't unlocked yet, if the row already has a pick (cap of 1), or if `option_id` isn't one of
    that row's 3 valid options (via `AbilityTalentLibrary.options_for(class_id, row_id)`). Returns
    `true` and records the pick on success.
  - `func unpick_ability_talent(row_id: StringName) -> bool` — clears an existing pick (the panel/
    caller is responsible for gating this to town-only, same convention as the existing
    `unpick_talent_perk()`).
- **Hook wiring is per-option, decided at content-authoring time** (§5) — a flat-percentage option
  hooks into whatever the underlying ability's existing damage/effect calculation reads from (e.g. a
  rider-effect magnitude field), the same way each of the 7 passives found its own hook point rather
  than this spec inventing one shared mechanism.

## 4. Architecture — Universal Perks (Track B) & shared UI/input wiring

- **Content is unchanged from the original Task 12 checkpoint** — carried forward verbatim:

  | id | Name | Effect |
  |---|---|---|
  | `might_boost` | Heavy Hands | +2 Might |
  | `finesse_boost` | Quick Hands | +2 Finesse |
  | `vigor_boost` | Iron Will | +2 Vigor |
  | `focus_boost` | Clear Mind | +2 Focus |
  | `grit_boost` | Stalwart | +2 Grit |
  | `luck_boost` | Lucky Charm | +2 Luck |
  | `deep_reserves` | Deep Reserves | +3 to whichever resource pool (Stamina or Mana) this character uses |
  | `sharp_reflexes` | Sharp Reflexes | +5 flat Initiative |
  | `thick_skin` | Thick Skin | −5% incoming damage, always |
  | `battle_hardened` | Battle Hardened | −10% incoming DoT damage (stacks with Vigor and Warden's Deep Roots) |

  All magnitudes remain `[ASSUMPTION]` per this project's convention (CLAUDE.md §4).
- `Combatant.talent_perks: Array[StringName]` (the flat one-time-pick list) and
  `TalentPerkDef`/`TalentPerkLibrary` keep their originally-planned shape from the 2026-07-23 spec
  §5 — **only the earned-points formula changes**:
  - OLD (superseded): `func talent_points_earned() -> int: return clampi(level - 4, 0, 6)`
  - NEW: `func universal_points_earned() -> int` — 1 point for each of the fixed milestone levels
    `[2, 4, 6, 8, 10]` that is `<= level` (a small fixed array checked with a loop/`filter`, not a
    single arithmetic formula — a formula risks over-counting the odd levels 3/5/7/9 in between).
    Renamed from `talent_points_earned()` to `universal_points_earned()` since Track A now has its
    own, differently-shaped "points earned" concept.
  - `func universal_points_available() -> int: return universal_points_earned() - talent_perks.size()`
    (renamed from `talent_points_available()`, same derivation pattern).
  - `pick_talent_perk()`/`unpick_talent_perk()` keep their existing names/signatures and one-time-
    pick/non-stacking enforcement — no behavior change, only the earned-count formula feeding
    `talent_points_available()`'s check changes.
- **No more per-class "class-flavored perk" concept in Track B.** The original spec's §5 "class-
  flavored perks (1-3 per class) mixed into the universal pool" idea is fully replaced by Track A's
  per-row system — Track B is now a pure shared/universal list with zero class-specific entries.
- **UI**: `TalentMenuPanel` (unchanged name/shape/input-wiring from the original spec §6 — still
  bound to `toggle_talents`/`N`, still wired into `town_demo.gd`/`overworld_demo.gd`/
  `dungeon_demo.gd` with the same pause/block/respec-gate pattern, still absent from `combat.tscn`)
  now shows **two sections**: the Ability Talent grid (6 rows × 3 columns for the viewed character's
  own class, per §2's locked-rows-shown-grayed rule) above or beside a Universal Perks section
  (a flat list/slot display showing the 5 milestone opportunities, spent/unspent, same shown-when-
  reached convention it already had).

## 5. Content authoring — deferred, not a placeholder

**Intentionally not designed in this spec**, proposed during the implementation plan for the
player's review before being built (same convention as the original spec's §7):

- All 126 Ability Talent options: 6 rows × 3 options × 7 classes. Proposed as one batch, **grouped
  by class** (7 sections of 18 options each) for readability, following the simple-scope rule from
  §2 ("a flat percentage bump or a small added effect" — not new mechanics, not multi-step
  interactions).

The Universal Perks table in §4 is **not** deferred — it was already designed, shown to, and
approved by the player during the original Task 12 checkpoint, and is carried over unchanged here.

## 6. Explicitly out of scope

- Everything the original 2026-07-23 spec's §8 already ruled out (the real XP curve, Ultimate
  gating changes, gear-rarity ladder changes, per-class ability reordering) remains out of scope
  and is not reopened by this revision.
- No cross-row point banking in Track A (a row's point is permanently scoped to that row, whether
  spent or saved).
- No stacking within a row (cap of exactly 1 pick per row) or within Track B (one-time-pick per
  perk id, unchanged).

## 7. Testing plan

- New `tests/test_ability_talents.gd`: row-unlock levels (5/6/7/8/9/10) per the fixed mapping,
  `pick_ability_talent()`'s rejection cases (row not yet unlocked, row already has a pick, invalid
  option id for that row), `unpick_ability_talent()` clearing a pick, and at least one flat-
  percentage option's effect actually reading through to its hook once content exists.
- Update the existing `tests/test_talent_perks.gd` (written against the original spec's §5-6, not
  yet implemented in code — this plan's Task 13 was still pending when this revision landed) so its
  earned/available assertions use the new L2/4/6/8/10 cadence (`universal_points_earned()`) instead
  of the old `clampi(level-4, 0, 6)` formula, and rename its `talent_points_earned()`/
  `talent_points_available()` references accordingly.
- New/updated `tests/test_talent_menu_panel.gd`: both grid sections render, locked Ability Talent
  rows show grayed with their unlock level rather than being hidden, Universal Perk milestones show
  in their existing shown-when-reached style, and the town-vs-overworld/dungeon respec gate applies
  to both tracks.
- Full headless suite re-run before this is marked shipped, per this project's standing convention.

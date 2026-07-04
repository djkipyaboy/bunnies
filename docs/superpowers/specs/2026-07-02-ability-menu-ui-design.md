# Ability Menu UI — Design (2026-07-02)

**Status:** Locked by player 2026-07-02 (approach A approved; hide-locked-abilities confirmed).
**Prereq:** the class-ability-expansion model layer (spec `2026-07-01-class-ability-expansion-design.md`),
shipped and test-green on branch `nvm-party-combat`. This feature is the missing PRESENTATION layer —
the final whole-branch review (CLAUDE.md §8) found no combat-scene way to use the 21 new L5/L7/L9
abilities. `MainPhasePlan` staging (`staged_extra_ability_id`, `toggle_extra_ability`,
`can_stage_extra_ability`), preview (`REEL_ADDING_EXTRA_IDS` in `preview_reels()`), commit dispatch,
and cooldown start all already exist and are unit-tested — **no model changes in this feature.**

## Player-locked decisions

1. **Locked (below-unlock-level) abilities are HIDDEN in combat** — not greyed. The player will learn
   future abilities in out-of-combat menus (a KOTOR/MMORPG-style character sheet with a talent
   section — future design-bible work, out of scope here).
2. **All of a character's available abilities live in ONE menu**, opened by an **"Abilities"** button
   on the combat UI. Inside the menu each ability is its own toggle showing name, resource cost,
   cooldown, description, and damage/effect numbers.
3. **The Ultimate keeps its own dedicated button** on the bar, unchanged.
4. This is prototype "bones" — the eventual build gets a full nature/fantasy-themed reskin. Build for
   function and legibility, not final aesthetics.

## 1. The Abilities button

The current base-ability button slot (`_splice_button`: row 1, column 1, next to the Ultimate) becomes
a single **Abilities** button that toggles the menu panel.

- Label: `Abilities` when nothing is staged; `Abilities: <Name> ✓` + staged-green modulate
  (`Color(0.6, 1.0, 0.6)`, the existing convention) when a base or extra ability is staged — the
  staged choice is legible without opening the menu.
- Gating: identical to today's base-ability button — enabled only during the player's own Main 1
  (`_awaiting_player_spin`); disabled on enemy turns, dummy turns, while stunned, and after SPIN.
- Tooltip: "Open your ability list — stage one ability for this turn."
- The `_splice_button` variable/handler is renamed/repurposed (`_abilities_button`,
  `_on_abilities_pressed`), not kept alongside — one button, one slot.

## 2. `AbilityMenuPanel`

New file `combat/ui/ability_menu_panel.gd` (`class_name AbilityMenuPanel`), following the
`TypeChartPanel` precedent: a non-modal panel floating over the reel area of the center band,
`visible = false` until opened, drawn over the strips while up (`move_child` to top).

- **Rebuilds every open** from the active combatant + current `MainPhasePlan` — never caches rows.
- **Rows, in unlock order:** the base L1 ability first, then `unlocked_extra_abilities()` in authored
  order. A level-1 fight shows 1 row; ENDGAME (level 9) shows 4. Locked abilities: no row at all.
- **Each row:** a toggle `Button` labeled `<Name> (<cost> <STA|MANA>)`, plus an info `Label` beside
  it: one-line description with the ability's actual numbers, and a cooldown line —
  `Ready` / `On cooldown: N turns` / `N-turn cooldown after use` (L9 abilities, when off cooldown).
- **Row states** (superset of everything the old single button rendered):

  | State | Enabled | Visual |
  |---|---|---|
  | normal | yes | plain |
  | staged | yes (press to unstage) | staged-green |
  | can't afford | no | plain, disabled |
  | on cooldown | no | disabled, cooldown line shows remaining turns |
  | base locked (staged Ultimate subsumes it) | no | grey, "locked — Ultimate staged" |
  | included free (Heft under staged Rampage) | no | staged-green, "included by Rampage — free" |

- **Special-case text:** Double or Nothing's dynamic cost renders as
  `Double or Nothing (all-in: spends ALL remaining Stamina)`.

## 3. Interaction flow

- Pressing a row dispatches to the EXISTING model, no new staging paths:
  - base ability id → the current `_on_splice_pressed` semantics: `plan.toggle_ability()`, with the
    Seer's `select_fate` opening the existing 6-type picker when not yet staged (same flow, launched
    from the row).
  - extra ability id → `plan.toggle_extra_ability(id)`.
  - Mutual exclusivity between the two slots is already model-enforced — the UI never polices it.
- **Close conditions:** any successful stage or unstage closes the panel and calls
  `_refresh_main1_preview()` (the reel/resource preview must be immediately visible — the panel
  floats over the strips, so it cannot stay open). Also closes on SPIN, turn end/turn change, and
  pressing Abilities again. A row press that stages nothing (e.g. can't afford — normally disabled
  anyway) leaves the panel open.
- **Commit path: untouched.** `_commit_main1` → `plan.commit()` already applies
  `staged_extra_ability_id` and starts cooldowns.

## 4. `AbilityCatalog` (data) + testing

- New static helper `combat/ui/ability_catalog.gd` (`class_name AbilityCatalog`), precedent
  `RoleVisuals`/`TypeVisuals`: maps ability id → display name + description text (with the ability's
  numbers written into the description) for **all 28 abilities** (7 base + 21 extra).
- Costs and cooldowns are **read live** from `AbilityDef`/class data at render time — never
  duplicated into the catalog (single source of truth; `[ASSUMPTION]` numbers get retuned
  post-playtest and the descriptions referencing them must be updated then too — the completeness
  test below is the greppable reminder hook).
- The existing `_ability_label`/`_ability_tooltip` helpers in `combat.gd` migrate to read from the
  catalog — one source of truth for base-ability names too.
- **Headless tests:**
  1. **Catalog completeness** — for every class in `ClassLibrary`, its `ability_id` and every
     `extra_abilities` id has a non-empty catalog name + description. Catches a forgotten
     description whenever a future ability is added.
  2. **Pure row-state function** — `AbilityMenuPanel.row_state(plan, combatant, id) -> RowState`
     (static, no scene tree), unit-tested across every state in §2's table.
- The panel's look/feel and whether the flow reads well in play is the **human's call** (CLAUDE.md
  §5 hard ceiling) — a playtest pass follows implementation, which then also unblocks the full
  ENDGAME-kit playtest deferred from the class-ability-expansion feature.

## Out of scope

- The character-sheet / talent-section menus where future abilities are previewed (design-bible work).
- Any reskin/theming (nature/fantasy aesthetic pass is a later, whole-UI effort).
- Any change to `MainPhasePlan`, `Combatant`, ability logic, or balance numbers.
- Enemy use of extra abilities (enemies have none — `EnemyLibrary` doesn't populate them).

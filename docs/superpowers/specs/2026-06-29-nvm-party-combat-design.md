# N-vs-M Party Combat — design spec (implementation-ready)

> **Date:** 2026-06-29 · **Status:** Approved — the player locked every open decision in their
> 2026-06-29 follow-up and authorized the full pipeline (brainstorm → spec → implement → commit →
> launch); [[combat-change-standard-procedure]].
> **Source of the captured decisions:** the player's 2026-06-29 direction ("next build is real N-vs-M
> party combat") + their follow-up locking the party/enemy selection menus, per-PC targeting, the
> button-bar placement, and party-order shifting; the **party-UI plan** (player request 2026-06-26,
> recorded in `CLAUDE.md §8`, `HANDOFF.md §6`, `DECISIONS-LOG.md` "Panel-width fix + N-vs-M party-UI
> plan"); and `CLAUDE.md §7` (party max **3 PCs**; architect N-vs-M from day one). Reconciled against
> the **as-built** code (every party path — turn order, AoE/splash, heal/shield broadcast,
> click-to-select targeting — is already written N-vs-M-correct; only the *scenario* and *layout*
> still run 1v1 + dummies).
> All balance numbers are `[ASSUMPTION]` placeholders — tuned by playtest, never balanced-by-fiat
> (`CLAUDE.md §4`).

### Locked decisions (player, 2026-06-29 follow-up)

1. **Enemy AI policy is a LATER iteration.** This build ships a **placeholder**: an enemy attacks the
   first living PC (party order). No threat/focus logic yet — kept in one swappable function.
2. **Default enemy count = 1**, but selectable **1–3** via an enemy-selection menu that **mirrors** the
   party-selection menu.
3. **Start-of-encounter selection screen** (replaces the single-class picker):
   - **Left side — "Choose your Party":** all **7 test characters** (the 7 classes) as small toggles,
     each showing **name and class**. Select **min 1, max 3**.
   - **Right side — "Enemy Combatants":** the **3 created enemy characters** as toggles. Select **min 1,
     max 3**.
4. **Per-PC targeting:** each PC's primary target is **adjustable on that PC's own turn** (click an enemy
   panel). Targets are remembered per PC across turns.
5. **Button/toggle bar:** the orientation previously proposed — a bar **above the combat log, centered**,
   its bottom **close to but not touching** the log's top.
6. **Party order = selection order.** First selected = first (top) panel, second below it, third below
   that. **Deselecting a higher-order member shifts the rest up** to fill the gap (e.g. with 3 selected,
   deselecting the 1st promotes the 2nd→1st and 3rd→2nd). Same rule for the enemy column.

---

## 0. Scope & ground rules

- **Goal:** turn the prototype from "1 PC vs 1 enemy (+ optional dummies)" into a real **N-vs-M party
  fight** — up to **3 PCs** on the player side vs **M enemies** — using the systems that are *already*
  party-ready. This is the build the prototype was architected toward since day one (`CLAUDE.md §7`).
- **This is mostly an integration + UI build, not new combat math.** The combat logic (turn order over
  arbitrary combatants, per-combatant effects, AoE/splash/heal/shield broadcast, the win check, and
  click-to-select targeting) already works for N-vs-M. The work is: (1) **build a party scenario**,
  (2) **lay it out in vertical columns**, (3) **let the player drive each PC's turn**, and (4) give the
  **enemy AI a target choice** (it currently always hits the lone PC).
- Keep it **campaign-first, fun-first** (`CLAUDE.md §3.5`). No roguelite systems. No new damage types,
  no 6th reel "just because" (`CLAUDE.md §7` YAGNI).
- All damage/heal math **rounds up** (`ceil`), project-wide ([[round-up-damage-healing]]).
- **TDD where it's logic** (`CLAUDE.md §5.3`): the enemy-AI target pick and any party-setup helpers get
  headless tests first. Layout/feel is the **human call** (`CLAUDE.md §5` hard ceiling) — the
  fun/fairness playtest is what closes this.

---

## 1. What already exists (reuse, don't rebuild)

Confirmed by reading the code — the party plumbing is **done**:

- **`TurnManager` is fully N-vs-M** (`turn_manager.gd`). `combatants: Array[Combatant]` takes any mix;
  `get_turn_order()` sorts the whole list by `current_initiative` desc (Finesse tie-break → stored d10);
  `is_combat_over()` / `winner_is_player()` test **each side** via `_living(is_player)`; `_announce_current()`
  skips fallen actors and rolls rounds. Adding more combatants to the array *just works*.
- **Broadcast helpers** in `combat.gd`: `_enemies_of(c)` / `_allies_of(c)` (side-relative, living-aware),
  `_targets_for(attacker)` (all enemies when AoE active, else the primary `_defender`), and
  `_splash_half_to_others(attacker, total, label)` (Collateral/Earthquake splash; returns who was hit).
- **Every multi-target ability is already written party-correct** and verified with synthetic 3-enemy /
  3-ally headless setups: Rampage/Big Bang AoE (loop `_targets_for`), Collateral/Earthquake splash, Big
  Bang heal-all + shield-all, Rallying Cry shield-all-allies, Inspirational buff-all-allies, Hunter's
  Mark cross-attacker accuracy. They degenerate to clean 1v1 no-ops today purely because there's one
  enemy and one ally.
- **Click-to-select targeting** (`_player_target`, `_select_target`, `_refresh_target_highlight`,
  `_build_target_click_catchers`, `CombatantPanel.set_targeted`). The player already picks a primary
  enemy by clicking its panel (red outline). This is the N-vs-M control surface — it just currently has
  one real enemy + dummies to choose from.
- **Per-combatant everything**: HP, effects, Bonus Meter, resource pools, stun flags, `min_hp`,
  `is_target_dummy` all live on `Combatant`. `_panels: Dictionary` maps any combatant → its
  `CombatantPanel` (300×238). The dummy path already proves N panels render and refresh.
- **Target dummies** (`is_target_dummy`, `_take_dummy_turn`, excluded from `_living`) — keep them as the
  testing toggle ([[difficulty-settings-deferred]] not relevant here; the dummy toggle is permanent per
  the 2026-06-26 decision). They remain valid in a party fight.

**What is NOT party-ready (the actual work):**

1. **Scenario build** (`_build_scenario`) hard-codes exactly `[_pc, _enemy]` (+ dummies).
2. **UI layout** (`_build_ui`) hard-codes positions: PC at `(40,80)`, enemy at `(1280,80)`, dummies in
   the center gap. The action-button column is pinned under the enemy panel at `BTN_X = 1280`.
3. **Player drives only one PC.** `_pc`, `_pc_panel`, `_pc_class_id` are singletons; the ability/Ultimate
   buttons always read `_pc`. On a multi-PC turn the controls must follow the **active** PC.
4. **Enemy AI has no target choice.** `_on_turn_started` sets `_defender = _pc` for any non-PC actor
   (`combat.gd:697`). With multiple PCs the enemy must *pick* one.
5. **Click-catchers are geometry-hard-coded** (`300×192` at each panel's old position) — they must follow
   the new column layout and the real panel height (238).

---

## 2. The locked party-UI layout (player request 2026-06-26)

> **Captured decision:** "arrange combatant panels as **vertical columns** — the player's party down
> the **LEFT** window edge, the enemy party down the **RIGHT** edge — replacing the current top-row
> strip. Frees the center for the reels/log. Carry the **300px** panel width into that layout."

### 2.1 Column geometry (window 1600×900, `[ASSUMPTION]` spacing)

- **Left column = player party** (1–3 PCs), stacked top-to-bottom. Panel `x = 24`.
- **Right column = enemy party** (1–M enemies + any dummies), stacked top-to-bottom. Panel
  `x = 1600 − 300 − 24 = 1276`.
- **Vertical stacking:** first panel `y = 80`; each subsequent panel `y += PANEL_H + GAP`, where
  `PANEL_H = 238` (the real `CombatantPanel` height) and `GAP = 12` `[ASSUMPTION]`. Three panels span
  `80 → 80 + 3×238 + 2×12 = 818` — fits under the 900px window. (4+ per side would overflow; the
  prototype caps PCs at 3 and should keep M small — see §6 open items.)
- **Center band is freed** for the action-reels block (banner → caption → strips → phase label → log)
  and the floating Type-Chart panel. The strips/log currently start at `x = 40`; **shift them right** to
  start clear of the left column (e.g. `x = 360`, ending before the right column at `x ≤ 1276 − margin`).
  The action-button column moves to the **bottom-center** (see §2.3) since it can no longer hang under a
  single enemy panel.

### 2.2 Replace hard-coded panel placement with a column builder

In `_build_ui`, replace the three hard-coded panel positions with a helper:

```gdscript
## Lays combatant panels in a vertical column. side_players=true → left edge, false → right edge.
func _build_party_column(members: Array[Combatant], side_players: bool) -> void:
    var x: float = 24.0 if side_players else (1600.0 - 300.0 - 24.0)
    var y: float = 80.0
    for c: Combatant in members:
        var p := CombatantPanel.new()
        p.position = Vector2(x, y)
        add_child(p)
        _panels[c] = p
        p.bind(c)
        y += 238.0 + 12.0
```

Call it once per side from the `TurnManager.combatants` split (players vs enemies, dummies appended to
the enemy column). This **subsumes** the current PC/enemy/dummy placement blocks and the separate
`bind()` loop.

### 2.3 Action controls move to a bottom-center bar

The right-hand button column (`BTN_X = 1280`, Ultimate/Splice/Spin/End/Paylines/Dummy/TypeChart) now
collides with the enemy column. **Relocate the buttons to a horizontal bar along the bottom-center**
(below the reels/log), or a fixed left-of-log column — `[ASSUMPTION]`, the player judges feel. They are
the **active PC's** controls (§3), not tied to any panel. `_relayout_action_block` already positions the
reels/log off the *measured* panel height; extend it (or a sibling) to also place this button bar so
nothing overlaps as panel counts change.

> **Deferred UI polish (player note 2026-06-29):** button hover-tooltips currently wrap off the window.
> Re-flow them in the full-demo phase, not here.

---

## 3. Multi-PC control: the active PC drives the turn

Today `_pc` / `_pc_panel` / `_pc_class_id` are singletons and the buttons always read `_pc`. For a party:

- **Replace the PC singletons with arrays:** `_pcs: Array[Combatant]`, and a per-PC class id list
  `_pc_class_ids: Array[StringName]` (static, survives `reload_current_scene()` like `_pc_class_id` does).
  Keep a helper `_is_player_actor(c) := c.is_player` rather than `c == _pc`.
- **`_on_turn_started(c)`** — when `c.is_player`, **that PC is the controller this turn.** Drive the
  ability/Ultimate/Splice buttons, the `MainPhasePlan`, the meter flash, and the preview **from `c`, not
  `_pc`**. Concretely, every `_pc.ability_id` / `_pc.ultimate_id` / `_panels[_pc]` reference in the
  Main-1 / preview / spin path becomes `_attacker.*` (the active PC). Audit: `_on_turn_started`,
  `_refresh_main1_preview`, `_on_spin_pressed`, `_on_splice_pressed`, `_on_ultimate_pressed`,
  `_ability_label`/`_ultimate_label` calls. (`_attacker` is already set to `c` at the top of
  `_on_turn_started`.)
- **Per-PC primary target (locked).** Replace the single global `_player_target` with
  `_player_targets: Dictionary` (PC → its chosen enemy). On a PC's turn, `_defender` = that PC's
  remembered target, defaulting to the **first living enemy** if unset/dead. Clicking an enemy panel
  during that PC's pre-spin window updates **that PC's** entry (`_select_target` writes
  `_player_targets[_attacker]`). Each PC keeps its own target across turns.
- **Enemy/dummy turns** stay automated (the existing `ENEMY_THINK_DELAY` → `_do_spin` path), now choosing
  a target via §4.

No change to `MainPhasePlan`, the resolver, paylines, or any ability — they already operate on whatever
`_attacker` / `_defender` / target list they're handed.

---

## 4. Enemy target AI (PLACEHOLDER — real policy is a later iteration)

`_on_turn_started` sets `_defender = _pc` for non-PC actors. With multiple PCs the enemy must pick one
of the **living PCs**. Per the player's locked decision, **the AI policy itself is deferred** — this
build ships the simplest correct placeholder, isolated in one swappable function so a future iteration
replaces only its body:

```gdscript
## Picks which living PC an enemy attacks this turn. PLACEHOLDER policy (real AI = later iteration):
## the first living PC in party order. Kept as one function so a future policy swaps only this body.
func _enemy_pick_target(attacker: Combatant) -> Combatant:
    return Combat.first_living(_enemies_of(attacker))   # _enemies_of(enemy) = living PCs

## Pure, headless-testable: first living combatant in the given order (null if none).
static func first_living(cands: Array[Combatant]) -> Combatant:
    for c: Combatant in cands:
        if c.is_alive():
            return c
    return null
```

- **Wire it:** in `_on_turn_started`, `else: _defender = _enemy_pick_target(c)` (if none, combat is
  already over — the win check fires).
- **No threat/focus/random logic yet** — that's the later iteration. `first_living` is a `static` so it's
  unit-tested without a scene.
- **AoE/splash enemies** (none ship yet) would already hit all PCs via `_targets_for`; the chooser only
  sets the **primary** `_defender`.
- **Dummies** keep `_take_dummy_turn` (heal + pass) — they never call the chooser.

---

## 5. Party scenario build + the 3 enemy characters

Replace the hard-coded `[_pc, _enemy]` in `_build_scenario` with a party-vs-party build driven by the
two ordered selection arrays:

- **Player party:** `_pcs = _pc_class_ids.map(id → ClassLibrary.make(id).build_combatant(true))`
  (1–3 entries, in selection order). The existing single-class path is the 1-PC case.
- **Enemy party:** `_enemies = _enemy_ids.map(id → EnemyLibrary.make(id))` (1–3 entries, selection
  order). **Default `_enemy_ids = [&"rat"]`** (count 1, the locked default).
- **`_turn_manager.combatants = _pcs + _enemies (+ dummies if the toggle is on)`** — the single source of
  truth the column builder, turn order, and win check all read. Dummies append to the enemy column.
- **Keep `_pc = _pcs[0]` / `_enemy = _enemies[0]`** as convenience anchors (defaults, first-panel
  references); all *control* paths read the **active** combatant, not these (§3).

### 5.1 `EnemyLibrary` — the 3 created enemy characters (`combat/enemy_library.gd`)

A code registry mirroring `ClassLibrary` (a Resource-free `Combatant` factory; enemies need no
abilities/Ultimate/Main-1 pool — the AI is later). `static IDS` + `static make(id) -> Combatant` (built
`is_player = false`, meter **hidden**) + `static label(id) -> String` (cheap name for the menu). All
values `[ASSUMPTION]`:

| id | display_name | weapon (type, base, reels) | defense | HP |
|---|---|---|---|---|
| `&"rat"` | "Cluny's Rat" | Crushing, 8, 2 | Earth | 300 |
| `&"ferret"` | "Redtooth (Ferret)" | Slashing, 7, 3 | Slashing | 260 |
| `&"stoat"` | "Killconey (Stoat)" | Piercing, 6, 4 | Piercing | 220 |

`&"rat"` is the existing matchup (preserves the demo). The varied types/reel-counts let the type chart
and focus-fire read clearly. **Meter hidden** (`meter_visible = false`) per `CLAUDE.md §4` (meter is for
PCs + Elite/Boss only); an Elite/Boss enemy with a visible meter is a later content call.

### 5.2 Start-of-encounter selection screen (replaces the single-class picker)

A full-window `_start_overlay` with **two mirrored roster lists** + BEGIN FIGHT:

- **Left — "Choose your Party":** 7 toggle buttons (one per `ClassLibrary.IDS`), label =
  `"<display_name> — <Class>"` (e.g. "Martin (Mouse) — Warrior"). Selecting writes `&id` into the ordered
  `_pc_class_ids` (max 3).
- **Right — "Enemy Combatants":** 3 toggle buttons (one per `EnemyLibrary.IDS`), label =
  `EnemyLibrary.label(id)`. Selecting writes into the ordered `_enemy_ids` (max 3).
- **BEGIN FIGHT** centered at the bottom, **disabled** until both lists have **1–3** members. A dummy
  toggle stays near it (the permanent testing aid).
- **Selection model** (the locked order/shift rule) lives in a pure helper **`RosterSelection.toggle`**
  so it's unit-testable away from the scene:
  ```gdscript
  ## Toggle membership of `id` in the ordered `selected` list (max `max_n`). Selecting appends (keeps
  ## selection order); deselecting removes and the remaining members shift up to fill the gap. No-op when
  ## trying to select past `max_n`.
  static func toggle(selected: Array, id: StringName, max_n: int) -> void:
      var i: int = selected.find(id)
      if i >= 0:
          selected.remove_at(i)            # deselect → array compaction shifts the rest up
      elif selected.size() < max_n:
          selected.append(id)              # select → appended at the tail (next order slot)
  ```
  After each toggle the overlay re-renders every button: selected buttons show `"<n>. <label>"` (1-based
  order) in green; unselected show the plain label. BEGIN's enabled state recomputes.

- **Static, survives reload:** both arrays are `static` (`_pc_class_ids`, `_enemy_ids`) so they persist
  across `reload_current_scene()` — the same trick the old `_pc_class_id` used. The end-card "Fight
  again" replays the same rosters; a full re-pick from the end card is optional polish `[ASSUMPTION]`.
- **Defaults on first load:** `_pc_class_ids = [&"warrior"]`, `_enemy_ids = [&"rat"]` (today's 1v1 if the
  player just presses BEGIN — nothing regresses).

---

## 6. New / changed code surfaces (for the plan)

| Area | Change |
|---|---|
| `combat/enemy_library.gd` (NEW) | `class_name EnemyLibrary` — `IDS` (rat/ferret/stoat), `make(id) -> Combatant` (is_player false, meter hidden), `label(id) -> String`. The 3 created enemies (§5.1). |
| `combat/roster_selection.gd` (NEW) | `class_name RosterSelection` — `static toggle(selected, id, max_n)` (ordered select/deselect + shift-up, max cap). The locked selection model (§5.2). |
| `combat/combat.gd` — scenario | `_build_scenario`: build `_pcs` from `_pc_class_ids`, `_enemies` from `_enemy_ids` via `EnemyLibrary`; `combatants = _pcs + _enemies + dummies`. Keep `_pc`/`_enemy` = `[0]` anchors. |
| `combat/combat.gd` — layout | Add a vertical-column panel placer (player party LEFT `x≈24`, enemy party RIGHT `x≈1276`, stacked at `y += 238+gap`). Move reels/banner/caption/phase/log into the freed center band; place the action buttons in a **centered bar just above the log** (§2.3). Simplify `_relayout_action_block` to fixed center coordinates (columns are on the edges, so no panel-height measuring needed). |
| `combat/combat.gd` — control | Route Main-1 / preview / spin / paylines button state off the **active** combatant (`_attacker`) instead of `_pc`. `_pcs`/`_enemies` arrays; `_pc_class_ids`/`_enemy_ids` static (survive reload). |
| `combat/combat.gd` — enemy AI | Add `_enemy_pick_target(c)` + `static first_living(...)`; call it for non-PC actors in `_on_turn_started` (replaces `_defender = _pc`). PLACEHOLDER policy (§4). |
| `combat/combat.gd` — targeting | `_player_targets: Dictionary` (per-PC, §3). `_build_target_click_catchers`: size catchers `300×238` at the column positions (already iterates non-player panels). `_select_target` gates on `_attacker.is_player` and writes the active PC's entry. |
| `combat/combat.gd` — selection UI | Rewrite `_build_start_overlay` as the two mirrored roster lists (§5.2) via a shared `_build_roster_list(...)` driven by `RosterSelection.toggle`; BEGIN gated on both lists 1–3; dummy toggle retained. |
| `tests/test_scene_load_seer.gd` | Update to set `Combat._pc_class_ids = [&"seer"]` (the singular static is gone). |
| `tests/` (NEW) | `test_roster_selection` (order, dedup, max cap, deselect shift-up), `test_enemy_library` (IDS, `make` fields, `label`), `test_party_combat` (build 2 PCs + 2 enemies via the libraries, run `TurnManager`, assert turn order spans all 4 and win-by-side when one side is cleared; `first_living` picks/ skips dead). Existing AoE/splash/heal/shield suites already cover the broadcast paths. |

> **No new architecture.** Every change rides existing hooks. The combat *logic* suites should stay green
> untouched; the new suites cover the AI pick and the party wiring.

---

## 7. Verification

- **Headless first** (`CLAUDE.md §5.3`): write `test_enemy_target_ai` + `test_party_turn_order` +
  `test_party_scenario_build` red, then green. Confirm the **full suite stays green** (currently 60
  suites) — the broadcast/AoE/heal/shield tests are the regression guard that party paths didn't break.
- **Run a suite:** `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  (use the `_console.exe` build to capture stdout; bound every run with `timeout`; refresh the class
  cache after adding a new `class_name`, per `HANDOFF.md §5`).
- **Then the human playtest** (the hard ceiling, `CLAUDE.md §5`): does a 3-vs-2 fight read clearly in the
  column layout? Is per-PC control legible? Does lowest-HP focus-fire feel fair or oppressive? This is
  also where the still-open **Seer/Ranger Ultimate** playtests can ride along (they shine with real
  allies/enemies present).

---

## 8. Open `[ASSUMPTION]`s / decisions to confirm in playtest

The product decisions are locked (see the header). What remains is balance/feel, judged at the playtest:

- **Enemy AI policy** — explicitly a **later iteration** (this build = first-living placeholder).
- **The 3 enemies' stats** (HP/weapon base/reels/types in §5.1) — placeholder numbers; tune after the
  party fight feels right.
- **Column spacing** (first `y`, inter-panel gap) and the **center-band coordinates** (reels / button bar
  / log) — tune for legibility on the 1600×900 window. ≤ 3 panels per side fit at 238px; 4+ would need a
  smaller panel or a scrollable column (not needed — both sides cap at 3).
- **Enemy meters/Elite** — rank-and-file meters hidden; an Elite/Boss with a visible meter + Ultimate is a
  later content call, not this build.
- **Still-open per-class playtests** (Seer/Ranger Ultimates) ride along now that real allies/enemies exist.

---

## 9. Explicitly NOT in this build (YAGNI — `CLAUDE.md §7`)

Roguelite/meta systems, `EncounterTable`/`RewardTable`, enemy classes/abilities beyond the existing
template, races + specialization branches, weapon riders, gear beyond the Padded Jerkin, and the future
UI polish in `ARCHITECTURE.md §9` (per-character initiative reel-strips, WoW-style buff-icon frames).
Tune `[ASSUMPTION]` balance numbers only **after** the party fight feels right (`CLAUDE.md §4`).

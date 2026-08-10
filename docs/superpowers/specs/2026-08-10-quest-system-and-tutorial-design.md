# Quest System, Tutorial, and Playtest Support — Design

**Status:** Locked, ready for planning.
**Context:** brainstormed 2026-08-09/10 while preparing a new playtest distro build. Supersedes
the "still open" quest-interaction-UI note in `CLAUDE.md` §8 / `HANDOFF.md`. The two previously
flagged bug/gap items (`give_material()` dropping `quality_tier`, potion display in
`InventoryMenuPanel`) were checked against current code during this session and are **already
fixed** (2026-08-02 and 2026-07-26 respectively) — no work needed, memory/docs corrected.

Ability/talent respec and the export/distro build are separate, later specs — not covered here.

---

## 1. Goal

Give the upcoming playtest build a real quest system (WoW-style: a Quest Log window, an on-screen
objective tracker, NPC accept/turn-in popups) and reuse that same system to deliver an in-game
tutorial for first-time players — so instructions like "press I to open your inventory" appear
as quest objectives instead of a separate hint system. Also adds two small playtest-support
pieces requested alongside it: an overworld interactable legend and a gathering-node respawn
debug utility.

## 2. Current state (what this builds on)

- `PartyInventory` (`economy/resources/party_inventory.gd`) only stores bare
  `accepted_quest_ids: Array[StringName]` / `completed_quest_ids: Array[StringName]` — no
  description, objectives, or reward data anywhere.
- `QuestTrackerPanel` (`world/ui/quest_tracker_panel.gd`) is a single `Label`, hardcoded to the
  `lost_cat` quest id with one hardcoded objective string.
- `QuestBoardEntry` (`world/resources/quest_board_entry.gd`) is presentation-only data for the
  town Adventuring Board; carries no objective/reward data.
- No accept/turn-in dialogue exists. `DialogueBox` (`world/ui/dialogue_box.gd`) is strictly
  linear (advance-to-next-line, no buttons) — insufficient for Accept/Decline or Complete actions.
- `CombatHandoff.mark_defeated(id)` / `is_defeated(id)` (`world/combat_handoff.gd`) gates whether
  a world node gets re-placed when a scene rebuilds. `GatheringNode`/`FishingSpot` both call
  `mark_defeated()` on interact and `queue_free()` — there is no respawn path today.
- Existing keybinds (`project.godot` `[input]`): move (WASD/arrows), `E` interact, `I` inventory,
  `C` stats, `L` event log, `N` talents, `P` professions. `Q` and `K` are free.
- `Villager` (`world/villager.gd`) supports one `DialogueSet` per NPC and emits `vendor_interacted`
  for shop NPCs (`is_vendor = true`) — used by the town Shopkeeper today.
- Placeholder visuals already distinguish overworld interactable types by color: Foraging node
  green, Fishing spot blue, `OverworldEnemy` red, `RandomEncounterNode` yellow "?", ground item
  pickup gray, `RewardPickup` gold glow.

## 3. Data model

New resources (`world/resources/`):

- **`Quest`** (`Resource`): `id: StringName`, `title: String`, `description: String`,
  `category: enum {CURRENT, SIDE, TUTORIAL}`, `objectives: Array[QuestObjective]` (ordered),
  `reward_amber: int` (placeholder `[ASSUMPTION]` value, not balanced).
- **`QuestObjective`** (`Resource`): `id: StringName` (unique within its quest),
  `display_text: String` (the on-screen instruction, e.g. "Press I to open your inventory").
  Completion is driven externally (see §6) — this resource is data only, no logic.
- **`QuestLibrary`** (static registry, mirrors `EnemyLibrary`/`ShopLibrary`): holds every
  authored `Quest`, including a re-authored `lost_cat` and the new `tutorial` quest.

`PartyInventory` changes (additive — existing `accepted_quest_ids`/`completed_quest_ids`/
`accept_quest()`/`complete_quest()`/`has_accepted_quest()`/`has_completed_quest()` are untouched
so Lost Cat's current call sites keep working):

- New `quest_progress: Dictionary` — `quest_id: StringName -> Array[StringName]` (completed
  objective ids for that quest).
- New `complete_objective(quest_id, objective_id)`, `is_objective_complete(quest_id, objective_id)`,
  `next_incomplete_objective(quest_id) -> QuestObjective` (or null if all done — caller then calls
  `complete_quest()`).
- New `tracked_quest_ids: Array[StringName]` — which accepted quests currently show on the
  on-screen tracker. Defaults to "every newly accepted quest" (append on `accept_quest()`);
  `QuestLogPanel`'s Track checkbox toggles membership.

## 4. Quest Log panel

New `QuestLogPanel` (`world/ui/quest_log_panel.gd`), built the same code-only-construction way as
`InventoryMenuPanel`/`ProfessionsMenuPanel`. Toggled by a new `toggle_quest_log` input action
bound to **Q**.

- Left: list of accepted quests (grouped or flat — flat is fine at this scale) plus a Completed
  section.
- Right: selected quest's description, its objectives with a checkmark per completed one, and
  the reward line.
- Each active row has a **Track** checkbox bound to `tracked_quest_ids` (this is the "untrack"
  ability — unticking hides it from the on-screen tracker without abandoning it).
- An **Abandon** button appears for `CURRENT`/`SIDE` quests only. `TUTORIAL`-category quests
  cannot be abandoned — letting a playtester skip the tutorial defeats its purpose for this build.

## 5. On-screen tracker

Rewrite `QuestTrackerPanel` from its current single-hardcoded-quest `Label` into a generic list:
one block per quest in `tracked_quest_ids` (that's accepted and not completed), showing that
quest's title plus its `next_incomplete_objective()`'s `display_text`. This is what actually
displays "Press I to open your inventory" on screen during the tutorial. Hidden entirely when
`tracked_quest_ids` is empty (same as today's "hidden when no quest active" behavior).

## 6. NPC accept/turn-in popups

New `QuestPopupPanel` (`world/ui/quest_popup_panel.gd`), built the same way as `DialogueBox` (code
construction, no scene file) since `DialogueBox` itself is strictly linear and has no buttons:

- **Offer mode**: quest title + description + objective preview, Accept / Decline buttons. Accept
  calls `PartyInventory.accept_quest()`.
- **Turn-in mode**: completion text + reward line, a single Complete button. No multi-option
  reward *choice* UI — no quest we have needs one, so it's not built (YAGNI over building for a
  hypothetical).

## 7. Objective completion wiring

Each `QuestObjective.id` maps to a real trigger, wired at the call site that already performs the
action (exact wiring is a plan-time detail; call sites below are the intended hooks):

| Objective | Hook |
|---|---|
| Move | `PCController`'s movement handling — first nonzero movement input |
| Open Inventory | `InventoryMenuPanel` open |
| Equip a piece of gear | The equip handler inside `InventoryMenuPanel` (no equip signal exists today — call `complete_objective()` directly from the handler) |
| Open Event Log | `EventLogPanel` open |
| Open Professions | `ProfessionsMenuPanel` open |
| Open Interactable Legend | `InteractableLegendPanel` open (new, §9) |
| Visit the shop / talk to Shopkeeper | `Villager.vendor_interacted` (already exists, `town_demo.gd:172`) |
| Win a first fight | `combat.gd`'s existing win-check (exact signal/call TBD at plan time) |

## 8. Tutorial quest content

One `TUTORIAL`-category quest (not a chain of several small quests — simpler to build, still
delivers the same on-screen guidance), ordered objectives:

1. Move (WASD)
2. Open Inventory (I) and equip a piece of gear
3. Open the Event Log (L)
4. Open Professions (P)
5. Open the Interactable Legend (K)
6. Visit the shop and speak with the Shopkeeper
7. Win a fight against an overworld enemy

**Auto-start:** the quest auto-accepts the first time `town_demo`/`overworld_demo` loads with no
accepted quests in `PartyInventory` (there's no save system, so in practice this means "every
fresh launch" — correct for a playtest build where every session starts clean).

**Reward:** a small placeholder Amber amount on completion (`[ASSUMPTION]`, not balanced — flagged
per `CLAUDE.md` §4 convention).

**Shopkeeper tutorial dialogue:** while objective 6 is active and incomplete, the Shopkeeper's
`vendor_interacted` plays a tutorial-specific `DialogueSet` (built the same way as the existing
`_make_dialogue()` greeting) explaining the Amber economy and item-rarity coloring, instead of the
normal greeting. Once the objective completes, later visits play the normal greeting again.

## 9. Overworld Interactable Legend

New `InteractableLegendPanel` (`world/ui/interactable_legend_panel.gd`), toggled by a new
`toggle_interactable_legend` input action bound to **K**. Static content — one row per existing
interactable type, a color swatch matching its real placeholder visual, and a one-line
description:

- Green — Foraging node ("Gather")
- Blue — Fishing spot ("Fish")
- Red — Enemy ("Fight")
- Yellow "?" — Random Encounter ("Investigate")
- Gray — Item pickup ("Pick up")
- Gold glow — Reward pickup ("Pick up — quest/dungeon reward")

No new art. This is a static glossary of *types*, distinct from §10's per-landmark hover tooltips.

## 10. World hover tooltips

No mouse-hover system exists in the world scenes today (only the proximity-triggered
`InteractPrompt`). Add:

- **`WorldTooltip`** (`world/ui/world_tooltip.gd`) — a small floating-label UI, shown/positioned
  by whichever scene owns it (mirrors `InteractPrompt`'s ownership pattern).
- An optional `hover_description: String` field on `Interactable` (`world/interactable.gd`),
  empty by default so every other interactable is unaffected. When non-empty, `_ready()` sets
  `input_pickable = true` on the Area2D and wires `mouse_entered`/`mouse_exited` to show/hide the
  tooltip — independent of the physics layer already used for proximity/movement detection, so no
  conflict with existing collision setup.
- Authored for three landmarks in `town_demo.gd`: `OldWell` ("Rest here to fully restore your
  party, once per visit — free and unlimited."), `AdventuringBoard` ("Town quest board — accept
  and turn in quests here."), `ShopFacade`/door ("General Store — spend Amber on gear, weapons,
  and consumables.").

## 11. Explicitly out of scope

- Multi-option reward choice UI (no quest needs it yet).
- Quest markers on NPCs ("!"/"?" over their heads) — not requested, would need new art anyway.
- Respawning enemies, random encounters, or reward pickups via the debug utility below — only
  gathering nodes were asked for.
- Any save/load system — the tutorial's "auto-start every launch" behavior is a direct consequence
  of there being none, not a workaround to build one.

## 12. Respawn Gathering Nodes (debug utility)

A visible button on the overworld debug harness (same placement pattern as the existing "Test:
Hollow Warden Fight" button in `town_demo.gd`), labeled "Respawn Gathering Nodes": clears
`CombatHandoff.is_defeated()` for the known Foraging/Fishing node ids (`WildBerries`,
`WildBerries2`, `FishingSpot`, `FishingSpot2`, …) and re-runs their placement so a playtester can
re-test those minigames repeatedly without relaunching the executable. Scoped to gathering nodes
only, per §11.

## 13. Testing

Standard project convention (`CLAUDE.md` §5): pure logic gets tests first.

- `PartyInventory` additions (`quest_progress`, `complete_objective()`, `next_incomplete_objective()`,
  `tracked_quest_ids`) are pure data/logic — unit test alongside existing `test_party_inventory.gd`
  coverage.
- `QuestTrackerPanel`'s multi-quest rendering and `QuestLogPanel`'s Track/Abandon behavior get
  headless tests following the existing `*_for_test()` hook convention (e.g. `AbilityMenuPanel`,
  `DialogueBox`).
- The tutorial's auto-start and full 7-step completion path gets an end-to-end test mirroring
  `test_lost_cat_board_flow.gd`'s shape.
- `WorldTooltip` show/hide on `mouse_entered`/`mouse_exited` gets a direct signal-driven test.

## 14. Open implementation-time decisions (not blocking, flagged for the plan)

- Exact signal/call used for "win a first fight" (combat.gd's win-check point).
- Exact call site for "equip a piece of gear" inside `InventoryMenuPanel`'s equip handler.
- Whether the Quest Log's Completed section needs its own scroll/filter at this quest count (2
  quests today) — likely not yet.

This spec covers enough ground (data model + 4 new UI panels + tutorial content + 2 small
support features) that it will likely need splitting into multiple plans rather than one — e.g.
data model + Quest Log + tracker as plan 1, popups + tutorial wiring as plan 2, legend + hover
tooltips + respawn debug as plan 3. That call belongs at plan time, not decided here.

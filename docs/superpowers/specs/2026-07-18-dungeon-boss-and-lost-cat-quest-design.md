# Dungeon Boss ("The Hollow Warden") + Lost Cat Quest — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally 2026-07-18. Step 4 of the dungeon milestone
> roadmap (memory `dungeon-milestone-roadmap-2026-07-17`) — the dungeon's boss encounter, folded
> together with the previously-deferred Lost Cat quest (memory `first-quest-lost-cat-idea-2026-07-18`)
> since "beat the boss" and "rescue the cat" are the same event from the player's perspective. This is
> the largest single feature this project has built — three real subsystems (a damage-type
> expansion, a multi-phase boss fight, and the game's first quest-tracking system) brainstormed
> together because they're tightly interdependent, but expected to be PLANNED and BUILT as a larger
> number of smaller tasks than usual.

## 1. Goal

Floor 4 of the dungeon holds The Hollow Warden, a multi-phase boss with real minions, a phase
transition, and the game's first enemy Ultimate. Defeating it frees a caged cat, which the player
carries back to town and turns in at the Adventuring Board — the game's first real quest, with a
proper accept → track → turn-in flow and an on-screen tracker, not just a flavor placeholder.

## 2. Decisions locked during brainstorming

### Damage types
- **Two new damage types, `LIGHT` and `DARK`, added to `DamageType.Type` now.** Both are neutral
  (1.0×) against/from all 6 existing types (the data model already defaults undefined matchups to
  neutral, so the 6 existing `.tres` files need NO changes). Light and Dark are mutually **super
  effective against each other, 1.5× both directions** — a rival pair, distinct from the existing
  gentle 6-type spread.
- **Both `.tres` files created now**, even though nothing uses Light yet ("we will add it in the
  future"). Cheap to do while already touching the enum/generator/chart in one pass.
- **The Hollow Warden deals Dark damage.** Its defense type is also Dark (a dark-attuned guardian).
- **Explicitly deferred, not touched this pass:** Seer's "Select your Fate" type-picker
  (`combat.gd`'s `_build_fate_picker()`) has its own hardcoded 6-button layout that would need
  extending to 8 — confirmed, deliberately out of scope until a later pass.

### The boss fight
- **550 max HP.** Normal attacks: 3 reels, 12 base damage on a HIT, standard 1.5× on a crit success.
- **Phase 1 (fight start):** two 30-HP minions, both **unstunnable** and **always act last** in turn
  order regardless of initiative roll. Minion A's turn: heals the boss +30 HP and applies the
  existing `guarded` effect to it. Minion B's turn: applies a NEW flat, stacking party-wide AoE DoT
  (4 / 7 / 10 damage per turn, 3-turn duration per stack, up to 3 stacks) — unrelated to any
  weapon's base damage, unlike every existing DoT in this codebase.
- **Both minion types keep a real (weak) weapon + always-fire their signature ability every turn**,
  reusing the exact existing "greedy ability use" AI pattern (ferret's Flurry, stoat's Hunter's Mark)
  — no new "abilityonly, no weapon" creature type needed.
- **Phase transition**, checked at the start of the boss's own turn: the FIRST time its HP drops
  below 40% (220 HP), three things happen at once:
  1. The boss gains **Indestructible** — all *direct* damage taken reduced to 0; DoT still applies in
     full (the existing damage-resolution pipeline already keeps these separate — no interaction
     risk). Lasts until both of THIS phase's two new minions are dead (not a turn-counted duration).
  2. Two new 90-HP minions spawn (same abilities as phase 1, same always-last/unstunnable rules).
  3. On every boss turn while Indestructible is active, its normal attack is replaced by **Darkness
     Rampage**: a 4-reel WILD (crit-biased) AoE hitting the whole party, 18 damage/hit, standard 1.5×
     crit, and the boss heals for half the total damage it deals.
  - Once both of that phase's minions are dead, Indestructible clears and the boss gains the
    **existing** `empowered` effect (1.4× outgoing damage, EffectLibrary — not a new effect; the
    player's originally-proposed "always Super Effective" idea was dropped once they remembered
    `empowered` already exists) for the **rest of combat**.
  - **10-turn cooldown, re-triggerable:** if the boss's HP is still below 40% after 10 of *its own*
    turns since the last trigger, the whole transition repeats (sacrifice check → Indestructible →
    2 new 90-HP minions → Darkness Rampage cycle again).
  - **Indestructible always supersedes Empowered.** A later re-trigger suspends Empowered while
    Indestructible is active again; finishing that cycle (minions dead) always re-applies Empowered,
    whether it's the first cycle or a later one. They never stack.
- **Ultimate: "Dark Reinforcements."** Fires once the boss's Bonus Meter is full (the boss has a
  real, **visible** `BonusMeter` — the first time this project's documented-but-unused "Elite/Boss
  meter is visible" rule is actually built). Summons two MORE 30-HP minions (phase-1 stats/behavior,
  always-last, unstunnable) — a pure escalation move, no direct damage. **If these Ultimate-summoned
  minions are still alive when the boss's next phase transition triggers, they are sacrificed** (an
  instant, no-reward removal — see §2's Lost Cat section for why "no reward" matters as a general
  principle) **and the boss heals for half their combined remaining HP** at that moment.
- **No other base ability.** The kit is exactly: normal attacks, phase-locked Darkness Rampage, and
  the Ultimate.
- **Sacrificed minions (of any kind) grant no Amber/XP/loot** — they're removed by the boss's own
  script, not defeated in battle; granting rewards would let players farm by ignoring reinforcements
  and waiting for a free sacrifice-heal cycle.

### The Lost Cat quest
- **Quest state lives on `PartyInventory`**, not `CombatHandoff` — confirmed `PartyInventory`/`Vault`
  are what actually travels with the party across every scene (`stash_party()`/`begin_encounter()`),
  while `CombatHandoff`'s own fields are explicitly session-lifetime bridging state only.
- **Accepted at the Adventuring Board.** The existing "Lost Cat" placeholder entry becomes real; its
  body text (regenerated fresh every board-open, matching the panel's existing convention) reads
  differently before/after acceptance — before: "a cat has gone missing, ask around" (flavor,
  pointing at the dungeon); after accepting: a reminder to bring the rescued cat back here.
- **The board's existing `entry_selected` signal** (already emitted on row click, currently
  unconsumed by `town_demo.gd` — confirmed via research) drives both accept and turn-in: clicking an
  unaccepted quest row accepts it; clicking an accepted row while the player holds the "Rescued Cat"
  `QuestItem` turns it in (removes that item, marks the quest completed, grants the Thank You Note).
- **The cat is a placeholder sprite always present on floor 4.** Built fresh each scene load (like
  every other dungeon placement), checking whether the boss's encounter is already marked defeated:
  not yet defeated → a plain "caged" flavor object (interact shows a locked/guarded message, grants
  nothing); already defeated → a real interactable that grants the "Rescued Cat" `QuestItem` once.
- **On-screen quest tracker**, same placement/refresh convention as the Amber HUD just shipped:
  shows the current accepted-but-not-completed quest's title + one-line objective, hidden entirely
  when nothing is active. Built generically enough for future quests, even though only this one
  exists as content today.
- **The Thank You Note** is a flavor-only `QuestItem`-adjacent item granted on turn-in; clicking its
  row in `InventoryMenuPanel`'s Quest Items tab opens the existing `DialogueBox` with its text,
  naming each current party member. No targeting flow needed (pure flavor, not the bigger
  out-of-combat item-use-targeting system still pending elsewhere).
- **Naming (flavor, freely changeable later):** the boss is "The Hollow Warden"; the cat is "Whiskers".

## 3. Architecture

### 3.1 Damage type expansion

`combat/resources/damage_type.gd`: extend the enum (additive, existing values keep their integer
identities):
```gdscript
enum Type { SLASHING, PIERCING, CRUSHING, STORM, MYSTIC, EARTH, LIGHT, DARK }
```

Update the authored source, `type_chart_6x6_labeled.html` (repo root): add `"Light"`/`"Dark"` to the
`types` array, add their rows to the `M` dictionary (only the Light↔Dark cross cells need explicit
`1.5` values — every other cell for the two new types is omitted/defaults neutral), and add the 2
new `<th>` column headers to the hand-written table markup.

Update `tests/gen_damage_types.gd` (a manual, hand-transcribed one-off tool script — NOT an
HTML parser despite the doc-comment's framing, confirmed by reading it) — add two new
`_save(_make(T.LIGHT, {T.DARK: 1.5}), "light.tres")` / `_save(_make(T.DARK, {T.LIGHT: 1.5}),
"dark.tres")` calls (following whatever the existing `_make()`/`_save()` helper signatures already
are in that file), then run it headless to regenerate/add the two new `.tres` files under
`combat/resources/types/`. The 6 existing `.tres` files are NOT touched — `DamageType.
multiplier_against()`'s `effectiveness.get(defender.type, default_multiplier)` already returns the
neutral `default_multiplier` (1.0) for any undefined matchup, so Light/Dark are automatically
neutral against all 6 existing types with zero edits to them.

`combat/ui/type_visuals.gd`: extend the hardcoded 6-entry `short_name()` array to 8 entries, and add
2 new `match` cases to `type_color()` for LIGHT/DARK (pick any placeholder colors — e.g. a pale
yellow-white for Light, a deep violet-black for Dark — tunable later).

`combat/ui/type_chart_panel.gd`: replace the hardcoded `6`s (the `TYPE_PATHS` array size, the
`CELL_W * 6.0`/`ROW_H * 6.0` sizing math, and the `range(6)` double loop) with `_types.size()`-driven
equivalents, and extend `TYPE_PATHS` to include `light.tres`/`dark.tres`, so the panel renders a full
8×8 grid instead of clipping to 6.

`tests/test_type_chart.gd`: extend the hardcoded 8-less `types` array and the hand-transcribed
expected-multiplier matrix to 8×8 (8 rows × 8 columns, with the new Light/Dark rows/columns mostly
1.0 except their mutual 1.5 cells), and extend the `range(6)` double-loop to `range(8)`.

### 3.2 New status effects

`combat/effect_library.gd` — one new effect (the flat stacking party-wide DoT the AoE minion
applies), following the exact existing `bleed`/`cursed` shape but with a FLAT (not weapon-derived)
magnitude:
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
Every existing DoT seeds `dot_base_damage` from `_attacker.weapon_effective_base_damage()` at apply
time in `combat/combat.gd` (confirmed the only two existing seed sites, lines ~1482/~1699) — this is
the ONE new orchestrator wrinkle needed: wherever this minion's ability applies `warden_curse`, seed
`dot_base_damage = 1.0` (a flat multiplier baseline) instead of deriving it from a weapon, so
`Effect.dot_damage()`'s existing `ceili(dot_base_damage * dot_fractions[idx])` formula produces
exactly 4/7/10 rather than a weapon-scaled number.

`Indestructible` (blocks direct damage, not DoT) reuses the EXISTING `MULTIPLIER_EDIT` mechanism with
zero new Effect kind needed:
```gdscript
&"indestructible":
    var e := Effect.new()
    e.id = &"indestructible"
    e.kind = Effect.Kind.MULTIPLIER_EDIT
    e.magnitude = 0.0
    e.affects_incoming = true
    e.duration = 99   # cleared explicitly by the orchestrator, not by turn-count expiry — see §3.4
    e.beneficial = true   # from the boss's perspective
    return e
```
Confirmed via research: `incoming_damage_multiplier()`'s only call site is inside the direct-attack
resolution path (`combat.gd` line ~1530); the DoT-tick path (`_apply_dot`) uses a completely separate
`dot_damage_multiplier()` hook and never reads `incoming_damage_multiplier()` — so this effect
blocking direct damage while leaving DoT untouched is automatic, no extra plumbing needed.

"Always acts last" and "cannot be stunned" reuse EXISTING mechanisms directly, no new Effect Kind:
- `Combatant` gains one new field: `var acts_last: bool = false`. `TurnManager.get_turn_order()`'s
  sort comparator (`turn_manager.gd` ~line 59) gets one new early check before the initiative
  compare: `if a.acts_last != b.acts_last: return b.acts_last` (a `false` sorts before `true`, i.e.
  acts-last combatants always sort to the bottom regardless of initiative).
- "Cannot be stunned" is just a permanent effect with `grants_stun_immunity = true` attached to the
  minion at spawn time — `Combatant.evaluate_stun()` already checks `active_effects` for this flag
  unconditionally and overrides even a forced stun (confirmed precedent: the existing `guard` object
  at `combat/combatant.gd:759`). No new mechanism needed.

### 3.3 The Hollow Warden — `EnemyLibrary` entry

`EnemyLibrary._build()` currently hardcodes `c.ultimate_id = &""` and `meter.is_visible = false` for
every enemy (this is the FIRST boss, so both need to become real, non-default values for this one
entry). Extend `_build()`'s signature with two new trailing optional params, defaulted so the 3
existing enemies (rat/ferret/stoat) are completely unaffected:
```gdscript
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int,
        defense: DamageType, hp: int, ability_id: StringName = &"", ability_cost: int = 0,
        loot_table_id: StringName = &"", amber_reward: int = 0,
        ultimate_id: StringName = &"", meter_visible: bool = false) -> Combatant:
    ...
    c.ultimate_id = ultimate_id
    ...
    meter.is_visible = meter_visible
    ...
```
New registry entry (id `&"hollow_warden"`), weapon type/defense both `dark.tres`, 3 reels, base
damage 12.0, HP 550, `ultimate_id = &"dark_reinforcements"`, `meter_visible = true`. Amber reward set
higher than any existing enemy (an `[ASSUMPTION]`, e.g. 50 — tunable by playtest like every other
placeholder magnitude in this project); no `loot_table_id` this pass (the dedicated Treasure Trove
reward is a separate, later roadmap step — the boss's own combat-loot stays minimal/default so it
doesn't compete with that future reward).

Two new minion registry entries: `&"warden_acolyte_lesser"` (30 HP, phase-1/Ultimate-summon variant)
and `&"warden_acolyte_greater"` (90 HP, phase-2-transition variant) — both weak weapons (1 reel, low
base damage, any existing type is fine, e.g. crushing), `acts_last = true` set post-construction, and
a permanent `grants_stun_immunity` effect attached at spawn. Their "signature ability" (heal+Guard
the boss, or apply `warden_curse` to the party) is driven by the SAME greedy always-fire AI pattern
`_enemy_stage_ability()` already uses for the ferret/stoat — this needs 2 new `match` branches added
to that function (not a new AI mechanism), each calling the appropriate existing apply-effect
plumbing (heal + `attach_effect(guarded)` for one; `attach_effect(warden_curse)`, seeded flat per
§3.2, on the whole party via the existing AoE-targeting path for the other).

### 3.4 Boss phase-transition orchestration

New per-Combatant state (used only by bosses; every other Combatant leaves these at their defaults):
```gdscript
var is_boss: bool = false
var boss_phase_two_active: bool = false
var boss_last_phase_trigger_turn: int = -1   # this boss's own turn counter, not a global round counter
var boss_phase_minion_ids: Array[Combatant] = []   # the CURRENT phase's minions, so we know when both are dead
```

A new orchestrator method in `combat/combat.gd`, `_check_boss_phase_transition(c: Combatant)`,
called once per turn for boss combatants — confirmed the natural hook point is either inside
`_on_phase_changed()`'s existing `PhaseManager.Phase.UPKEEP` branch (the same slot DoT/HoT ticks
already use, combat.gd ~line 1107-1123) or immediately inside `_on_turn_started()` right after the
existing `_apply_dot()`/panel-refresh call and before the stun check (~line 994-1035) — either is a
single new call plus this one new method, no restructuring of `PhaseManager`/the phase enum:

1. If `c.boss_phase_two_active` and both entries in `c.boss_phase_minion_ids` are dead: clear
   `indestructible` from `c.active_effects`, clear `boss_phase_two_active`, attach the existing
   `empowered` effect (long/permanent duration — "until end of combat" — rather than its normal
   2-turn expiry, since this is a one-off boss grant, not the player-facing ability that uses the
   normal 2-turn version).
2. If NOT `c.boss_phase_two_active` and `c.hp < c.max_hp * 0.4` and (`c.boss_last_phase_trigger_turn
   == -1` or `c.turns_taken - c.boss_last_phase_trigger_turn >= 10`): trigger the transition —
   sacrifice any surviving Ultimate-summoned minions (see below), attach `indestructible`, spawn 2
   new `warden_acolyte_greater` minions (see §3.5), set `boss_phase_two_active = true`, record
   `boss_last_phase_trigger_turn = c.turns_taken` (a per-combatant own-turn counter — confirm
   whether `Combatant` already tracks something equivalent, e.g. a turn-count field from an existing
   mechanic, or add one if not).

Enemy Ultimate-firing (needed for Dark Reinforcements to ever trigger) — confirmed there is
currently ZERO enemy-side Ultimate logic anywhere (every enemy hardcodes `ultimate_id = &""` today).
Extend `_enemy_stage_ability()` (combat.gd ~870-881, called from `_do_spin()` before the shared
`_commit_main1()` apply point) with a new check: if the attacker's `bonus_meter` is full/armed and
`ultimate_id != &""`, stage the Ultimate (mirrors the player-facing `_on_ultimate_pressed()` →
`MainPhasePlan.toggle_ultimate()` path) instead of/alongside the greedy ability check. Flows through
the existing `_commit_main1()` unchanged (it already logs "★ ... fires ULTIMATE").

### 3.5 Mid-fight minion spawning — the one genuinely new piece of plumbing

Confirmed via research: `_build_combatants()` already builds multiple enemy Combatants at FIGHT
START (existing, normal behavior — nothing new there), and `_enemies_of()`/`_allies_of()` compute
fresh from `_turn_manager.combatants` on every call rather than a cached snapshot, so once a new
Combatant is appended to `_turn_manager.combatants` (and to `_enemies`, for win-check/XP hookup),
targeting/AoE/win-check logic picks it up automatically with no further changes. What's genuinely
missing — confirmed no existing mechanism does this — is spawning a **new** Combatant mid-fight,
after `_build_combatants()` has already run once. This needs a new helper,
`_spawn_enemy_mid_combat(id: StringName, floor_index: int) -> Combatant` (or similar), extracting
the currently-inline panel-creation/layout logic from `_build_party_columns()` (~line 482) into a
reusable form, then:
- Building the Combatant via `EnemyLibrary.make(id)`.
- Appending it to `_turn_manager.combatants` and `_enemies` (mirroring `_build_combatants()`'s own
  append, ~line 222-227), including connecting its `defeated` signal for XP/Amber exactly like every
  other enemy.
- Building and registering its `CombatantPanel` (`_panels[c] = p`) with a real position in the
  existing enemy-column layout (extending the column instead of a fixed 1-3 slot count — reasonable
  since bosses reserve a slot pattern nothing else currently exercises).
- Inserting it into the CURRENT round's already-fixed `_order` array in `turn_manager.gd`
  (`_start_next_round()`, ~line 110-118, currently computed once via `get_turn_order()` per round) —
  since new minions must act THIS round (not wait for the next), not just be present for future
  rounds' `get_turn_order()` calls. Given `acts_last = true` (§3.2), a new minion's natural
  insertion point in the current round's remaining order is simply "append at the end of what's
  left," consistent with how `acts_last` combatants already sort in a fresh `get_turn_order()` call.

This is the one part of this spec too dependent on `combat.gd`'s exact current internals (which this
research pass sampled but didn't read in full) to hand the implementer fully-dictated code — the
plan should treat this as its own task with a clear behavioral contract (a Combatant this indicates
appears fully playable — targetable, panel-visible, acts this round — not just data-present) rather
than literal code, and the implementer should read the surrounding `_build_combatants()`/
`_build_party_columns()`/`turn_manager.gd` code directly before writing it.

### 3.6 Floor 4 placement

`world/dungeon_demo.gd` — floor 4 (index 3) currently has only a `StairsUp`, no enemy and no
`DungeonExit` (floor 1 owns that). Add:
- The boss encounter, placed via the same `OverworldEnemy` contact-trigger pattern already used on
  floors 1-3 (a single `enemy_ids = [&"hollow_warden"]`), with the same `is_defeated()`-gated
  placement-skip convention.
- A cat placeholder, always built (not gated on boss-defeated for PRESENCE — only for its
  INTERACTION behavior): if the boss encounter is not yet marked defeated, it's a plain visual
  (Interactable, non-functional interact — a flavor "the cage is guarded" message); once the boss
  IS marked defeated, its `interact()` grants a `QuestItem` (`item_id = &"rescued_cat"`, `display_name
  = "Whiskers, Rescued"`) into `_party_inventory.quest_items` and marks itself collected (mirrors the
  dungeon key's exact `is_defeated`-gated one-time-grant pattern) so it doesn't regrant on a later
  scene rebuild.

### 3.7 `PartyInventory` quest-state tracking

Mirrors the exact `mark_defeated`/`is_defeated` array-pair convention already used twice in this
codebase (`CombatHandoff.defeated_encounter_ids`, `CombatHandoff.unlocked_gate_ids`):
```gdscript
var accepted_quest_ids: Array[StringName] = []
var completed_quest_ids: Array[StringName] = []

func accept_quest(quest_id: StringName) -> void:
    if not accepted_quest_ids.has(quest_id):
        accepted_quest_ids.append(quest_id)

func has_accepted_quest(quest_id: StringName) -> bool:
    return accepted_quest_ids.has(quest_id)

func complete_quest(quest_id: StringName) -> void:
    if not completed_quest_ids.has(quest_id):
        completed_quest_ids.append(quest_id)

func has_completed_quest(quest_id: StringName) -> bool:
    return completed_quest_ids.has(quest_id)
```
This lives on `PartyInventory` (confirmed the correct home — it travels with the party across every
scene the same way `quest_items`/`amber` already do), not `CombatHandoff` (session-lifetime bridging
state only).

### 3.8 `QuestBoardEntry` + Adventuring Board interactivity

`world/resources/quest_board_entry.gd` gains one new field: `@export var id: StringName = &""`
(empty for the other 2 placeholder entries, which stay pure display — only the Lost Cat entry gets a
real id, `&"lost_cat"`).

`world/town_demo.gd`'s `_make_quest_entries()` (already rebuilt fresh every board-open, per its
existing convention) branches on `_party_inventory`'s quest state for the Lost Cat entry specifically:
not accepted → flavor pitch text, category SIDE; accepted but not completed → reminder-to-return
text, category CURRENT (moves it to the tracked section, matching the WoW-style "accepted quests
show as current" convention); completed → could simply stop appearing, or move to RECAP with a
resolved line (implementer's call, either is reasonable and low-risk).

`AdventuringBoardPanel`'s existing `entry_selected` signal (confirmed already emitted on row click,
currently connected to nothing in `town_demo.gd`) gets a new handler in `town_demo.gd`:
```gdscript
func _on_board_entry_selected(entry: QuestBoardEntry) -> void:
    if entry.id == &"":
        return   # the other 2 placeholder entries have no real quest behind them yet
    if not _party_inventory.has_accepted_quest(entry.id):
        _party_inventory.accept_quest(entry.id)
        _board_panel.open_for(_make_quest_entries())   # re-render with the new state
        return
    if _party_inventory.has_completed_quest(entry.id):
        return   # already turned in, nothing more to do
    if entry.id == &"lost_cat" and _party_inventory.has_quest_item(&"rescued_cat"):
        _party_inventory.consume_quest_item(&"rescued_cat")   # reuses the existing method (lock-and-key work)
        _party_inventory.complete_quest(&"lost_cat")
        _party_inventory.give_quest_item(_make_thank_you_note())
        _board_panel.open_for(_make_quest_entries())
```

### 3.9 On-screen quest tracker

A new small widget, `world/ui/quest_tracker_panel.gd` (or similar), mirroring the Amber HUD's
just-shipped placement/refresh convention (a persistent `Label`, refreshed every `_process()` tick,
added to `town_demo.gd`/`overworld_demo.gd`/`dungeon_demo.gd`'s `_build_ui()`): shows the title +
one-line objective of every quest that's accepted-but-not-completed (reading
`_party_inventory.accepted_quest_ids`/`completed_quest_ids`, filtered), hidden entirely (or showing
nothing) when that list is empty. For the Lost Cat quest specifically, the one-line objective text
itself should reflect progress (e.g. "Rescue the cat from the dungeon" before the boss is dead /
"Bring the rescued cat to the Adventuring Board" after) — the exact objective text per state is a
small piece of quest-specific display logic, reasonably placed alongside the board's own
`_make_quest_entries()` state branching (§3.8) so the two don't drift out of sync.

### 3.10 The Thank You Note

A `QuestItem` (existing resource, no new class needed) with `item_id = &"thank_you_note"`,
`display_name = "A Thank You Note"`, granted via `give_quest_item()` on turn-in (§3.8). Clicking its
row in `InventoryMenuPanel`'s Quest Items tab needs new interactivity — currently that tab renders
plain read-only `Label`s (`_build_list_row()`), unlike the Materials tab's already-selectable
`Button` rows (`_build_material_row()`). Give the Quest tab's rows the same `Button`-based treatment
Materials already has, and wire a click on the Thank You Note's specific row (matched by `item_id`,
not a generic "any quest item is clickable" rule — the Rusty Key/other quest items have no read
action) to open the existing `DialogueBox` with a single line naming each current party member, e.g.:
`"Thank you, %s! You saved my little Whiskers." % ", ".join(party_member_names)` — read from
whichever party is live at click time (PC + companions), not baked in at grant time.

## 4. Out of scope

- **Seer's "Select your Fate" type picker** extending to 8 buttons for Light/Dark — confirmed
  deliberately deferred.
- **Any use of the Light damage type** — created now, used by nothing this pass.
- **The Treasure Trove reward** (a separate, later roadmap step) — the boss's own combat-loot stays
  minimal/default, not the "real" floor-4 payoff.
- **Multiple simultaneous quests, a full quest-chain system, quest prerequisites/branching** — this
  pass builds a real but minimal tracker sized for exactly one quest, generically shaped enough to
  add more later without a rewrite, not a general quest-design system.
- **Any change to `docs/design-bible/28-encounter-design-framework.md`'s unapproved boss-parts/
  BossPhase architecture** — this boss is hand-built with bounded hooks into the existing turn/phase
  functions, not the seeded (but still unlocked) generic framework.

## 5. Testing plan

- **Damage types**: extend `tests/test_type_chart.gd` to the full 8×8 matrix; a focused test
  confirming `dark.tres`/`light.tres` load correctly and their mutual 1.5× matchup resolves via
  `multiplier_against()`, while every other cross-type matchup (old×new, new×old) reads the neutral
  default.
- **New effects**: a test for `warden_curse`'s flat 4/7/10 stacking DoT (seeded via a fixed
  `dot_base_damage`, not weapon-derived) and for `indestructible` (`incoming_damage_multiplier() ==
  0.0` for a direct hit, but a DoT tick on the same combatant is unaffected — proving the
  documented pipeline separation holds for this specific new effect, not just assumed).
- **Turn order**: a test proving an `acts_last = true` combatant always sorts after every
  `acts_last = false` combatant in `get_turn_order()`, regardless of initiative roll, and that stun
  immunity (permanent `grants_stun_immunity` effect) holds from turn 1 with no prior cast needed.
- **EnemyLibrary**: The Hollow Warden's stats/ultimate_id/meter_visible; both acolyte minion entries'
  stats/acts_last/stun-immunity.
- **Enemy Ultimate-firing**: a focused test proving `_enemy_stage_ability()` (or wherever the new
  check lands) stages an enemy's Ultimate once its meter is full, flowing through the existing
  `_commit_main1()` unchanged.
- **Mid-fight spawn**: an end-to-end combat test triggering the 40%-HP phase transition and
  confirming the 2 new minions are genuinely playable this same round — targetable, panel-visible,
  act their turn — not just present in a data array.
- **Full phase-transition sequence**: a scripted fight proving the whole cycle — phase 1 minions'
  scripted actions, the 40% trigger, Indestructible blocking a direct hit but not a DoT tick,
  Darkness Rampage's AoE + self-heal, Indestructible clearing once phase-2 minions die, Empowered
  applying, the 10-turn cooldown re-triggering correctly, and Ultimate-summoned minions being
  sacrificed (no reward) if still alive at a later trigger.
- **Quest system**: `PartyInventory.accept_quest`/`has_accepted_quest`/`complete_quest`/
  `has_completed_quest` round-trip; the board's `entry_selected` → accept → turn-in flow end to end
  (including the "must hold the rescued-cat item to turn in" gate); the cat interactable's
  boss-defeated-gated behavior switch; the on-screen tracker showing/hiding/updating correctly; the
  Thank You Note's dialogue naming the current live party.
- **End-to-end**: a full human playtest — descend to floor 4, fight The Hollow Warden through both
  the phase-1 minions and at least one full phase transition (including surviving long enough to see
  the 10-turn cooldown re-trigger, if feasible), fire the boss's Ultimate if the meter fills, win,
  interact with the freed cat, return to town, turn in at the board, read the Thank You Note.

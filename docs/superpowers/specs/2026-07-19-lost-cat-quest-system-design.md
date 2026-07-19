# Lost Cat Quest System — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Plan 3 of 3 for the combined dungeon-boss + Lost Cat feature brainstormed
> 2026-07-18 (`docs/superpowers/specs/2026-07-18-dungeon-boss-and-lost-cat-quest-design.md`). That
> combined document is the source of the design DECISIONS below — the player dictated the quest
> flow (accept at the board → rescue the cat by beating the boss → return the cat → get a Thank You
> Note) during that brainstorm, no new design ground is broken here. This document re-derives the
> quest-system architecture against the CURRENT codebase (re-verified 2026-07-19, after both
> Plan 1 — Light/Dark damage types — and **Plan 2 — The Hollow Warden boss fight — shipped**) so the
> implementation plan can be written with zero placeholders. This is the game's **first real quest**
> — everything the accept/track/turn-in flow needs (a `QuestBoardEntry.id` field, `PartyInventory`
> quest-state methods, an on-screen tracker) is being built for the first time in this pass, sized
> for exactly one quest but generically shaped enough to add more later without a rewrite.

## 1. Goal

The Adventuring Board's placeholder "Lost Cat" entry becomes a real quest: accept it in town, defeat
The Hollow Warden on dungeon floor 4 to free the caged cat ("Whiskers"), carry it back to town, and
turn it in at the board for a flavor-only "Thank You Note" that names the current party. This is also
the first WoW-style quest log/tracker infrastructure in the game — a proper accept → track → turn-in
flow, not just a bulletin-board placeholder.

## 2. Decisions locked during brainstorming (2026-07-18, restated for this document's scope)

- **Quest state lives on `PartyInventory`**, not `CombatHandoff` — `PartyInventory`/`Vault` are what
  actually travel with the party across every scene (`stash_party()`/`begin_encounter()`), while
  `CombatHandoff`'s own fields are explicitly session-lifetime bridging state only.
- **Accepted at the Adventuring Board.** The existing "Lost Cat" placeholder entry becomes real; its
  body text (already regenerated fresh every board-open) reads differently before/after acceptance —
  before: a flavor pitch pointing at the dungeon; after accepting: a reminder to bring the rescued cat
  back here.
- **The board's existing `entry_selected` signal** (already emitted on row click, confirmed still
  unconsumed by `town_demo.gd`) drives both accept and turn-in: clicking an unaccepted quest row
  accepts it; clicking an accepted row while the player holds the "Rescued Cat" `QuestItem` turns it
  in (removes that item, marks the quest completed, grants the Thank You Note).
- **The cat is a placeholder object always present on floor 4.** Built fresh each scene load,
  checking whether the boss's own encounter is already marked defeated: not yet defeated → a plain
  "caged" flavor object (interact shows a locked/guarded message, grants nothing); already defeated →
  a real interactable that grants the "Rescued Cat" `QuestItem` once.
- **On-screen quest tracker**, same placement/refresh convention as the Amber HUD: shows the current
  accepted-but-not-completed quest's title + one-line objective, hidden entirely when nothing is
  active. Built generically enough for future quests, even though only this one exists as content
  today.
- **The Thank You Note** is a flavor-only `QuestItem`-adjacent item granted on turn-in; clicking its
  row in `InventoryMenuPanel`'s Quest Items tab opens the existing `DialogueBox` with its text, naming
  each current party member. No targeting flow needed (pure flavor).
- **Naming (flavor, freely changeable later):** the cat is "Whiskers"; the boss is "The Hollow
  Warden" (already shipped in Plan 2).

## 3. Architecture

### 3.1 `PartyInventory` quest-state tracking

Confirmed current state of `economy/resources/party_inventory.gd` (2026-07-19): `quest_items:
Array[Resource]` plus `give_quest_item()`/`has_quest_item()`/`consume_quest_item()` already exist
(shipped with the dungeon lock-and-key work, first used for the Rusty Key). **What's missing** —
confirmed by reading the file in full — is any notion of "which quest ids has the player accepted or
completed." Add, mirroring the exact `mark_defeated`/`is_defeated` array-pair convention already used
twice elsewhere in this codebase (`CombatHandoff.defeated_encounter_ids`,
`CombatHandoff.unlocked_gate_ids`):
```gdscript
@export var accepted_quest_ids: Array[StringName] = []
@export var completed_quest_ids: Array[StringName] = []

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
This lives on `PartyInventory` (already carries `amber`/`quest_items`/`unlocked_companion_slots` the
same way, and already survives every scene transition via `stash_party()`/`begin_encounter()` — no
new persistence plumbing needed).

### 3.2 `QuestBoardEntry` gains a real id

Confirmed current `world/resources/quest_board_entry.gd` (full file, 12 lines): `title`, `category`
(`CURRENT`/`SIDE`/`RECAP` enum), `body_text` — **no `id` field exists yet**. Add:
```gdscript
@export var id: StringName = &""
```
Empty (`&""`) for the other 2 placeholder entries ("Clear the Cellar", "How We Got Here" — confirmed
still placeholders in `world/town_demo.gd`'s `_make_quest_entries()`, both `"Coming soon."`) — only
the Lost Cat entry gets a real id, `&"lost_cat"`.

### 3.3 `world/town_demo.gd` — quest-state-driven body text + board interactivity

`_make_quest_entries()` (confirmed current shape: builds 3 entries from a hardcoded `Array[Dictionary]`
literal, `"Lost Cat"` is the `SIDE`-category entry with body `"Coming soon."`) branches on
`_party_inventory`'s quest state for the Lost Cat entry specifically:
```gdscript
func _make_quest_entries() -> Array[QuestBoardEntry]:
	var lost_cat_body: String
	var lost_cat_category: QuestBoardEntry.Category
	if _party_inventory.has_completed_quest(&"lost_cat"):
		lost_cat_body = "Whiskers is home safe, thanks to you."
		lost_cat_category = QuestBoardEntry.Category.RECAP
	elif _party_inventory.has_accepted_quest(&"lost_cat"):
		lost_cat_body = "Bring the rescued cat back here to complete the quest."
		lost_cat_category = QuestBoardEntry.Category.CURRENT
	else:
		lost_cat_body = "A cat's gone missing — last seen near the old dungeon entrance. Whoever finds it should bring it back here."
		lost_cat_category = QuestBoardEntry.Category.SIDE
	var raw: Array[Dictionary] = [
		{"title": "Clear the Cellar", "category": QuestBoardEntry.Category.CURRENT, "body": "Coming soon.", "id": &""},
		{"title": "Lost Cat", "category": lost_cat_category, "body": lost_cat_body, "id": &"lost_cat"},
		{"title": "How We Got Here", "category": QuestBoardEntry.Category.RECAP, "body": "Coming soon.", "id": &""},
	]
	var entries: Array[QuestBoardEntry] = []
	for data in raw:
		var entry := QuestBoardEntry.new()
		entry.title = data["title"]
		entry.category = data["category"]
		entry.body_text = data["body"]
		entry.id = data["id"]
		entries.append(entry)
	return entries
```
(The completed-quest RECAP-with-resolved-line option from the combined spec's §3.8 is chosen here
outright — a plain "no longer appears" would make the board feel unresponsive to a real
accomplishment, and RECAP already exists as a category for exactly this "closed story beat" purpose.)

Confirmed via a fresh 2026-07-19 read: `AdventuringBoardPanel.entry_selected` (`world/ui/
adventuring_board_panel.gd:9`) is emitted by `_select_entry()` on every row click, and `world/
town_demo.gd` never connects to it (grepped the whole file — zero occurrences of `entry_selected`
outside the signal's own declaration). Wire it in `town_demo.gd`, at the same place `_board_panel`
is constructed (search for `_board_panel = AdventuringBoardPanel.new()`):
```gdscript
_board_panel.entry_selected.connect(_on_board_entry_selected)
```
New handler:
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
		_party_inventory.consume_quest_item(&"rescued_cat")
		_party_inventory.complete_quest(&"lost_cat")
		_party_inventory.give_quest_item(_make_thank_you_note())
		_board_panel.open_for(_make_quest_entries())
```
`_make_thank_you_note()` is a new small helper (§3.6).

### 3.4 The caged cat — floor 4 placement

Confirmed current `world/dungeon_demo.gd` (2026-07-19, post-Plan-2): floor 4 (index 3) now places
`DungeonFloor4Enemy` (the Hollow Warden encounter) at `floor_bounds(3).position + ENEMY_LOCAL`
(`ENEMY_LOCAL := Vector2(400, 300)`) and a `StairsUp` at `floor_bounds(3).position +
STAIRS_UP_LOCAL` (`STAIRS_UP_LOCAL := Vector2(100, 500)`). No cat placement exists yet. Add a new
constant clear of both: `const CAT_LOCAL := Vector2(650, 200)`.

The cat needs genuinely different INTERACT behavior depending on boss-defeated state (not just a
grant-vs-no-grant toggle) — before defeat, interacting should show a flavor "still caged" message,
not silently do nothing (matching this project's own "silent non-response reads as broken" lesson,
already applied to the dungeon key's unlock message and the Vault-unavailable message). This needs a
small new class rather than reusing `GroundItemPickup` as-is (that class's `interact()` always
attempts a grant — it has no "not yet available" branch). New file, `world/caged_cat.gd`:
```gdscript
class_name CagedCat
extends Interactable

## Floor 4's caged cat, "Whiskers" (spec 2026-07-19). Built fresh every scene load (like every other
## dungeon placement) — its INTERACT behavior branches on whether the Hollow Warden encounter is
## already marked defeated, checked by the driving scene at construction time (matching the existing
## defeated/no-respawn convention: dungeon_demo.gd decides what to build, this class doesn't reach
## into CombatHandoff itself). Pre-rescue: a flavor "still caged" message, grants nothing. Post-rescue:
## grants the "Rescued Cat" QuestItem once, then frees itself (mirrors GroundItemPickup's one-shot
## collect-then-vanish shape).

signal cat_rescued
signal locked_message_requested(text: String)

var party_inventory: PartyInventory
var boss_defeated: bool = false

func _init() -> void:
	prompt_text = "Free the cat"

func interact() -> void:
	if not boss_defeated:
		locked_message_requested.emit("The cage is still locked — something guards it.")
		return
	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	cat.display_name = "Whiskers, Rescued"
	party_inventory.give_quest_item(cat)
	cat_rescued.emit()
	queue_free()
```
`world/dungeon_demo.gd` gains a `_place_caged_cat()` (called once at scene build, alongside
`_place_dungeon_key()`/`_place_dungeon_enemies()`):
```gdscript
func _place_caged_cat() -> void:
	if _handoff().is_defeated(&"WhiskersPickup"):
		return   # already rescued and collected; don't respawn on a later scene rebuild
	var cat := CagedCat.new()
	cat.name = "WhiskersPickup"
	cat.party_inventory = _party_inventory
	cat.boss_defeated = _handoff().is_defeated(&"DungeonFloor4Enemy")
	cat.global_position = floor_bounds(3).position + CAT_LOCAL
	cat.locked_message_requested.connect(show_message)
	cat.cat_rescued.connect(func() -> void: _handoff().mark_defeated(&"WhiskersPickup"))
	_floors[3].add_child(cat)
```
**Correction from the original 2026-07-18 brainstorm's assumption**: confirmed by reading
`dungeon_demo.gd` directly (2026-07-19) that `show_locked_message()` takes **no parameters** — it's a
fixed, gate-specific string ("The way down is locked — you need a key.") written to the scene's
existing `_pickup_debug_label` (the same label already reused for encounter/pickup notifications).
Calling it verbatim for the cat would show the WRONG, gate-specific text. Add one new small shared
method instead — generalizing the existing fixed-text pattern into a parameterized one, without
touching `show_locked_message()`/`show_unlocked_message()` themselves:
```gdscript
## A general-purpose notification, alongside the existing fixed-text show_locked_message()/
## show_unlocked_message() (both about the dungeon-key gate specifically). Reuses the same
## _pickup_debug_label the scene already shows one-off notifications in.
func show_message(text: String) -> void:
	_pickup_debug_label.text = text
```
`CagedCat.locked_message_requested` connects to this new `show_message`, passing the cat's own
flavor text (`"The cage is still locked — something guards it."`, defined where `CagedCat.interact()`
emits the signal, §3.4's class body above) — not the gate's unrelated key text. `&"WhiskersPickup"`'s
`is_defeated`/`mark_defeated` tracking mirrors `RewardPickup`/`GatheringNode`'s exact "no respawn on
rebuild" convention (`CombatHandoff.defeated_encounter_ids` is a generic id-string set — reusing it
for a non-combat one-shot pickup is already established precedent, not a new use).

### 3.5 On-screen quest tracker

Mirrors the Amber HUD's exact placement/refresh convention (confirmed current shape in `world/
town_demo.gd`: a persistent `Label` at `Vector2(16, 100)`, built once, text refreshed every
`_process()` tick). New `world/ui/quest_tracker_panel.gd`:
```gdscript
class_name QuestTrackerPanel
extends Label

## On-screen quest tracker (spec 2026-07-19), same placement/refresh convention as the Amber HUD.
## Shows the current accepted-but-not-completed quest's title + one-line objective; hidden entirely
## when none is active. Sized for exactly one quest today, generic enough to extend later — a real
## multi-quest tracker (stacked lines, a scrollable log) is explicitly out of scope (§4).

func refresh(party_inventory: PartyInventory) -> void:
	if party_inventory.has_accepted_quest(&"lost_cat") and not party_inventory.has_completed_quest(&"lost_cat"):
		text = "Lost Cat\n%s" % _lost_cat_objective(party_inventory)
		show()
	else:
		hide()

## The Lost Cat quest's one-line objective, reflecting real progress — kept alongside the board's own
## _make_quest_entries() state branching (town_demo.gd) so the two texts don't drift out of sync; this
## function's THIRD branch (already holding the rescued cat) is the one case the board text doesn't
## need, since accepting/turning-in are both board-driven and the board is never open while carrying
## the item mid-dungeon.
static func _lost_cat_objective(party_inventory: PartyInventory) -> String:
	if party_inventory.has_quest_item(&"rescued_cat"):
		return "Bring Whiskers back to the Adventuring Board."
	return "Rescue the cat from the dungeon."
```
Wired into `world/town_demo.gd`, `world/overworld_demo.gd`, and `world/dungeon_demo.gd`'s `_build_ui()`
(all 3 already build the Amber HUD label the same way — add the tracker alongside it, refreshed every
`_process()` tick right next to the existing `_amber_label.text = ...` line):
```gdscript
_quest_tracker = QuestTrackerPanel.new()
_quest_tracker.position = Vector2(16, 140)   # just below the Amber HUD (16,100)
_ui_layer.add_child(_quest_tracker)   # (or `ui.add_child(...)` in dungeon_demo.gd's own naming)
...
# in _process():
_quest_tracker.refresh(_party_inventory)
```

### 3.6 The Thank You Note

A `QuestItem` (existing resource, no new class needed) with `item_id = &"thank_you_note"`,
`display_name = "A Thank You Note"`, built fresh at turn-in time (not baked in earlier) so its
dialogue text can read the live party. New helper in `world/town_demo.gd`:
```gdscript
func _make_thank_you_note() -> QuestItem:
	var note := QuestItem.new()
	note.item_id = &"thank_you_note"
	note.display_name = "A Thank You Note"
	return note
```
Clicking its row in `InventoryMenuPanel`'s Quest Items tab opens the existing `DialogueBox` with a
single line naming each current party member, read from whichever party is live at CLICK time (PC +
companions), not baked in at grant time.

Confirmed current `combat/ui/inventory_menu_panel.gd` (2026-07-19): `_build_quest_panel()` renders
plain read-only `Label`s via `_build_list_row()` — unlike the Materials tab's already-selectable
`Button` rows (`_build_material_row()`, confirmed same file). Give the Quest tab's rows the same
`Button`-based treatment:
```gdscript
func _build_quest_panel() -> void:
	if _party_inventory.quest_items.is_empty():
		_build_list_empty_message("No quest items yet.")
		return
	for i in range(_party_inventory.quest_items.size()):
		var entry: Resource = _party_inventory.quest_items[i]
		var label_text: String = entry.display_name if entry is QuestItem else "Quest item %d" % (i + 1)
		_build_quest_row(i, label_text, entry)

func _build_quest_row(index: int, text: String, entry: Resource) -> void:
	var btn := Button.new()
	btn.text = text
	btn.position = Vector2(PAD, GRID_TOP + float(index) * (SLOT_H + SLOT_GAP))
	btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	if entry is QuestItem and entry.item_id == &"thank_you_note":
		btn.pressed.connect(_on_thank_you_note_pressed)
	add_child(btn)
	_list_labels.append(btn)
```
Confirmed current `InventoryMenuPanel.open_for()` signature (`combat/ui/inventory_menu_panel.gd:284`):
```gdscript
func open_for(pc: Combatant, companions: Array, party_inventory: PartyInventory, vault: Vault, vault_available: bool = true, initial_tab: StringName = &"bag") -> void:
```
`pc`/`companions` are stored directly onto instance fields `_pc`/`_companions` (line 293-294) —
already exactly the live-party reference this feature needs, no new plumbing required.
`InventoryMenuPanel` doesn't yet own a `DialogueBox` reference — it needs one passed in (mirroring how
it already receives `party_inventory`/`vault`), OR simpler: emit a signal and let the driving scene
(which already owns a `DialogueBox`) open it, exactly like `AdventuringBoardPanel.entry_selected`'s
own "emit and let the caller act" convention. The signal approach needs no new cross-references and
matches this codebase's established pattern more closely — add:
```gdscript
signal thank_you_note_requested(dialogue_set: DialogueSet)
```
and:
```gdscript
func _on_thank_you_note_pressed() -> void:
	var names: Array[String] = [_pc.display_name]
	for c: Combatant in _companions:
		names.append(c.display_name)
	var line := DialogueLine.new()
	line.speaker_name = "Whiskers' Owner"
	line.text = "Thank you, %s! You saved my little Whiskers." % ", ".join(names)
	var set := DialogueSet.new()
	set.lines = [line]
	thank_you_note_requested.emit(set)
```
`world/town_demo.gd` (the only driving scene whose `InventoryMenuPanel` this needs to work from, per
§4 — turn-in only happens at the board, in town) connects this once, alongside its other
`InventoryMenuPanel` signal wiring. Confirmed the existing field name is `_inventory_panel`
(`world/town_demo.gd:31`), not a guessed name:
```gdscript
_inventory_panel.thank_you_note_requested.connect(_dialogue_box.open)
```
(`DialogueBox.open(dialogue_set: DialogueSet) -> void` — confirmed exact signature, `world/ui/
dialogue_box.gd:38` — matches this connect directly, no wrapper needed.) `DialogueSet.lines:
Array[DialogueLine]` and `DialogueLine.speaker_name`/`text` are both confirmed existing fields
(`world/resources/dialogue_set.gd`, `world/resources/dialogue_line.gd`) — no new dialogue
infrastructure needed anywhere.

## 4. Out of scope

- **Multiple simultaneous quests, a full quest-chain system, quest prerequisites/branching** — this
  pass builds a real but minimal tracker sized for exactly one quest, generically shaped enough to add
  more later (the `accepted_quest_ids`/`completed_quest_ids` arrays and the tracker's own structure
  don't assume single-quest, but nothing renders more than one line today) — not a general
  quest-design system.
- **A multi-line/scrollable on-screen tracker UI** — today's tracker shows exactly one quest's title +
  objective; a real multi-quest tracker (stacked lines, a toggleable full log) is future work once a
  second quest exists.
- **Any change to the Hollow Warden fight itself** — Plan 2 is done; this plan only reads its
  `is_defeated(&"DungeonFloor4Enemy")` state, never touches combat.
- **Any change to the dungeon's lock-and-key gate** — reused as-is (`show_locked_message()`/
  `_handoff()` helpers), not modified.
- **Balancing/renaming** — "Whiskers"/"The Hollow Warden"/exact flavor text are all freely changeable
  later; not the point of this pass.

## 5. Testing plan

- **`PartyInventory` quest state**: `accept_quest`/`has_accepted_quest`/`complete_quest`/
  `has_completed_quest` round-trip; confirm these fields survive a `stash_party()`/`begin_encounter()`
  round trip alongside the existing `quest_items`/`amber` fields (the established "test both
  CombatHandoff paths" lesson from this project's own history — a quest-state field only tested via
  one path has missed a real bug before).
- **`QuestBoardEntry.id`**: the 2 placeholder entries keep `id == &""`; the Lost Cat entry gets
  `&"lost_cat"`; extend `tests/test_quest_board_entry.gd` accordingly.
- **Board interactivity end to end**: clicking the unaccepted Lost Cat row accepts it and re-renders
  with CURRENT-category, "bring it back" text; clicking it again (already accepted, no rescued cat
  yet) does nothing; clicking it while holding `rescued_cat` consumes the item, completes the quest,
  grants the Thank You Note, and re-renders with RECAP-category, resolved text; clicking a completed
  quest a second time does nothing. Also confirm the other 2 placeholder rows (`id == &""`) are
  correctly no-ops regardless of click.
- **The caged cat**: pre-boss-defeat interact shows the locked message and grants nothing; post-defeat
  interact grants `rescued_cat` exactly once and the cat vanishes; a later scene rebuild doesn't
  re-place an already-collected cat (mirrors `RewardPickup`/`GatheringNode`'s existing no-respawn
  test pattern).
- **On-screen tracker**: hidden when the quest isn't accepted; shows "Rescue the cat from the dungeon"
  once accepted but before rescue; shows "Bring Whiskers back to the Adventuring Board" once the
  player holds `rescued_cat`; hidden again once completed. Test in at least town + dungeon (the 2
  scenes most relevant to this quest's actual flow); overworld inclusion is a straightforward
  same-pattern addition, lower-priority to verify exhaustively.
- **The Thank You Note**: clicking its Quest Items tab row opens `DialogueBox` with the correct live
  party names (test with a party of 1, and again with 1 PC + 2 companions, to confirm the name-list
  formatting is genuinely dynamic, not hardcoded); clicking any OTHER quest item's row (e.g. a
  still-in-testing Rusty Key on an earlier floor) does NOT open a dialogue.
- **End-to-end**: a full human playtest — accept Lost Cat at the board, descend to floor 4, interact
  with the caged cat before beating the boss (confirm the locked message), beat the boss, interact
  with the cat again (confirm the grant + on-screen tracker update), return to town, turn in at the
  board, read the Thank You Note with the real live party's names.

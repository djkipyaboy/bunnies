# The Old Well — Town Rest Point — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed 2026-07-23 in the same session as the second Hollow
> Warden/Lost Cat playtest fixes. Answers a request the player flagged during that playtest
> ("some way to heal outside of combat") and pays off a deferred design note from
> 2026-07-12 (`post-combat-recovery-deferred`): HP/Stamina/Mana/Bonus Meter currently carry over
> untouched between fights, and the player always intended SOME recovery mechanism to exist
> eventually — this is that mechanism, built as a deliberate opt-in player action rather than an
> automatic heal, so classes that benefit from missing HP (e.g. Vanguard's Bloodwrath) aren't
> punished by walking through a town.

## 1. Goal

Give the player a way to fully recover HP/Stamina/Mana for their whole roster (active party +
bench) without fighting, by interacting with a new town landmark: **the Old Well**. Free,
unlimited, town-only. Does not touch active effects (debuffs/buffs), the Bonus Meter, or XP.

## 2. Decisions locked during brainstorming

- **Naming/fiction: "The Old Well."** Pays off an already-existing, previously unplaced Villager
  flavor line in `town_demo.gd` ("Careful near the old well, stranger.") — the well's restorative
  property is explained the same way Amber already is (`docs/design-bible/10-storyline.md` §8):
  a trace of the old magic from the world's ancient Great Trees, carried in groundwater the same
  way Amber carries it in fossilized sap. No new lore document needed; this is a one-line
  extension of an already-locked idea.
- **Free and unlimited.** No Amber cost, no cooldown. It's a town amenity, not a shop transaction
  — matches the existing convention that Amber is spent at the General Store, not on utility
  actions.
- **Restores HP/Stamina/Mana only.** Does NOT cleanse active effects (buffs/debuffs) and does NOT
  drain/reset the Bonus Meter — the per-class `meter_floor` carryover rule is an intentional
  class-balance mechanic (CLAUDE.md §4) and isn't something a free town amenity should undercut.
  (Side note confirmed while researching this spec, not a scope change: `combat.gd`'s
  `_on_combat_ended()` never clears `active_effects` on any Combatant, so a debuff with remaining
  duration currently DOES survive a fight's end and follow the party back to town/overworld until
  it ticks out naturally or they fight again. The well does not touch this either way.)
- **Town-only.** No equivalent on the overworld or in the dungeon — preserves the tension of
  carrying your HP/resource state INTO a dungeon run, and matches the existing convention that the
  Vault is also safe-zone-gated (`InventoryMenuPanel`'s `vault_available` flag).
- **Restores the full roster, not just the active 2-companion party** — PC + every active
  companion + every benched companion. Avoids the edge case where a hurt companion gets benched,
  the player visits the well, and the companion is still hurt when swapped back in later with no
  way to heal them outside combat.
- **No confirmation menu.** Direct interact-and-resolve, like `Door`/`RewardPickup`/`CagedCat` —
  there's only one possible action (rest), so a Yes/No prompt (`VendorPromptPanel`'s Talk/Shop/
  Leave shape) would only exist to ask a question with one answer.

## 3. Architecture

### 3.1 `Combatant.restore_to_full()` (new, `combat/combatant.gd`)

A small pure-logic helper alongside the existing `heal()`/`cleanse()`, so it's independently
testable and reusable (e.g. if a future "rest at camp" system wants the same behavior):

```gdscript
## Restores HP to max and (if present) Stamina/Mana to their max — the Old Well's effect (spec
## 2026-07-23). Does NOT touch active_effects, bonus_meter, shield_hp, cooldowns, or xp; those are
## explicitly out of scope (see the spec's "Decisions locked" section).
func restore_to_full() -> void:
	if hp != max_hp and hp > 0:
		hp = max_hp
		hp_changed.emit(hp, max_hp)
	if resource_pool != null:
		if resource_pool.max_stamina > 0:
			resource_pool.stamina = resource_pool.max_stamina
		if resource_pool.max_mana > 0:
			resource_pool.mana = resource_pool.max_mana
```

`hp > 0` guards a defeated combatant the same way `heal()` already does (no-op on the dead) —
though in practice nothing currently benches/carries a combatant at 0 HP outside of an active
fight, so this is defense-in-depth, not a scenario this feature specifically produces.

### 3.2 `OldWell` (new, `world/old_well.gd`)

```gdscript
class_name OldWell
extends Interactable

## The town's Old Well landmark (spec 2026-07-23) — a free, unlimited, town-only full-party
## HP/Stamina/Mana restore. Built the same way AdventuringBoard is: a placeholder visual
## constructed in _init(), no _ready() override needed (Interactable's own _ready() already
## wires collision). Static landmark, no highlight_visual — same convention as AdventuringBoard,
## which also has no dim/bright indicator, just the InteractPrompt on proximity.

signal rest_message_requested(text: String)

var pc_combatant: Combatant
var companions: Array = []
var bench: Array = []

func _init() -> void:
	prompt_text = "Rest at the Old Well"

	var rim := ColorRect.new()
	rim.color = Color(0.5, 0.5, 0.55)
	rim.position = Vector2(-16, -10)
	rim.size = Vector2(32, 20)
	add_child(rim)

	var water := ColorRect.new()
	water.color = Color(0.3, 0.55, 0.7)
	water.position = Vector2(-11, -6)
	water.size = Vector2(22, 12)
	add_child(water)

func interact() -> void:
	if pc_combatant != null:
		pc_combatant.restore_to_full()
	for c: Combatant in companions:
		if c != null:
			c.restore_to_full()
	for c: Combatant in bench:
		if c != null:
			c.restore_to_full()
	rest_message_requested.emit("The old well's waters wash away your fatigue.")
```

Field-wiring convention (`pc_combatant`/`companions`/`bench` set externally after `.new()`,
before `add_child()`) mirrors `SceneExit`'s existing party fields exactly — not a new pattern.

### 3.3 `town_demo.gd` wiring

- New `func show_message(text: String) -> void: _pickup_debug_label.text = text` — mirrors
  `dungeon_demo.gd`'s existing identical method (currently town has no generic version, only
  ad-hoc direct `_pickup_debug_label.text = ...` assignments at 2 call sites). Both those call
  sites are left as-is (not a refactor this spec needs); this is purely adding the missing
  generic entry point for the well's signal to connect to.
- In the plaza-building function, alongside the existing `AdventuringBoard`/`Villager`
  construction: place an `OldWell` at `Vector2(300, 260)` — near, but NOT exactly on top of, the
  wandering Villager whose wander-center IS `Vector2(300, 300)` and whose line is "Careful near
  the old well, stranger." (paying off that line directly without visually overlapping that
  Villager's own sprite/collision). Also clear of the Adventuring Board (150,150), shop facade
  (450,80), and PC spawn (320,300).
- Wire `well.pc_combatant = _pc_combatant`, `well.companions = _companions`,
  `well.bench = _bench`, and `well.rest_message_requested.connect(show_message)`.

## 4. Out of scope (explicitly, per this brainstorm)

- No Amber cost, no cooldown, no debuff cleanse, no Bonus Meter change.
- No overworld or dungeon equivalent.
- No new confirmation-panel UI.
- Not a fix for `active_effects` surviving combat's end (a separate, pre-existing fact noted for
  awareness only — not this feature's problem to solve).

## 5. Testing plan

- `tests/test_combatant_restore_to_full.gd` (new): a combatant at partial HP + partial
  Stamina/Mana → full after `restore_to_full()`; a rail-less combatant (no `resource_pool`, e.g. a
  plain enemy) is unaffected and doesn't crash; an already-full combatant is a safe no-op (no
  spurious `hp_changed` emission — assert via a connected signal counter); a dead combatant
  (`hp == 0`) stays dead (not resurrected).
- `tests/test_old_well.gd` (new): mirrors `tests/test_caged_cat.gd`'s pattern — build a PC +
  1 active companion + 1 benched companion all at partial HP/resources, `interact()`, assert all
  three are now full and `rest_message_requested` fired with non-empty text.
- Existing `town_demo.gd` scene tests (`test_town_demo_inventory.gd` etc.) should be re-run to
  confirm the new landmark doesn't collide with or otherwise disturb existing plaza objects.

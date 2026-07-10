# Equipment / Inventory / Banking UI — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Builds the interaction layer on top of the data model locked in
> `2026-07-10-equipment-inventory-banking-design.md` (Gear/Weapon/rarity, `PartyInventory`, `Vault`,
> `Combatant.can_equip()`). That pass was explicitly data-only ("no UI screens... this pass makes the
> underlying model correct so that UI work later has real data to bind to") — this spec is that later
> UI work. All numeric magnitudes (placeholder item stats, seed counts) are `[ASSUMPTION]` per
> CLAUDE.md §4.

## 1. Goal

Make the equipment/inventory/banking data model actually playable: a paperdoll you can equip/unequip
gear and weapons on, a shared party Bag, and a Vault you can deposit to and withdraw from — all
driven by placeholder items, hung off the existing `town_demo.tscn` (no new scene/map needed). This
proves the same three interactions the data layer was built for (equip validation, bag capacity,
vault capacity) are actually usable, the same way `combat.tscn` proved the reel-spin loop was fun
before any real art existed.

Out of scope, deliberately: real authored items/loot tables, the character-select/multi-PC screen,
real companion recruitment, the escape/pause menu, and Materials/Quest/Gold/Reel-Mods UI (all noted
in the original data-layer spec's own out-of-scope list, or newly parked below in §7).

## 2. Data-layer gaps this pass closes

Two gaps in the locked data model block real equip/unequip and banking, closed here as small,
headlessly-testable additions before any UI is built:

### 2.1 `Combatant` gains real equip/unequip methods

Today `Combatant.gear` is a raw `Array[Gear]` — `can_equip()` validates, but nothing enforces one
item per slot, and nothing swaps a displaced item back to the bag. New methods:

```gdscript
## Equips [param g] if can_equip() allows it. Returns whatever was previously equipped in that
## slot (null if the slot was empty, or if the equip was rejected). Calls apply_stats() on success.
func equip_gear(g: Gear) -> Gear:
    if not can_equip(g):
        return null
    var displaced: Gear = null
    for existing: Gear in gear:
        if existing.slot == g.slot:
            displaced = existing
            break
    if displaced != null:
        gear.erase(displaced)
    gear.append(g)
    apply_stats()
    return displaced

## Removes and returns whatever is equipped in [param slot] (null if empty). Calls apply_stats().
func unequip_gear(slot: Gear.Slot) -> Gear:
    for existing: Gear in gear:
        if existing.slot == slot:
            gear.erase(existing)
            apply_stats()
            return existing
    return null

## Straight swap — Combatant.weapon is a single field, not a slotted array. Returns the previous weapon.
func equip_weapon(w: Weapon) -> Weapon:
    var previous: Weapon = weapon
    weapon = w
    apply_stats()
    return previous

func unequip_weapon() -> Weapon:
    var previous: Weapon = weapon
    weapon = null
    apply_stats()
    return previous
```

### 2.2 `PartyInventory`/`Vault` gain a `weapons` list + transfer methods

The locked spec designed a 6-slot loadout (Weapon + 5 Gear slots) but only gave `Gear` a storage
home. `PartyInventory` and `Vault` each gain:

```gdscript
@export var weapons: Array[Weapon] = []   # mirrors the existing `gear` list; uncapped like gear (only
                                           # the gear TAB's slot count is capped, per §4.1 of the data spec)
```

Both classes gain matching add/remove pairs, used by the UI to move items rather than touching the
arrays directly:

```gdscript
# PartyInventory — bag-side add/remove, no capacity check (equip/unequip never touches bag capacity)
func take_gear(g: Gear) -> void:
    gear.erase(g)
func give_gear(g: Gear) -> void:
    gear.append(g)
func take_weapon(w: Weapon) -> void:
    weapons.erase(w)
func give_weapon(w: Weapon) -> void:
    weapons.append(w)

# Vault — deposit/withdraw ARE capacity-checked (this is the actual bank-capacity gate)
func deposit_gear(g: Gear, from: PartyInventory) -> bool:
    if not can_add(&"gear", gear):
        return false
    from.take_gear(g)
    gear.append(g)
    return true
func withdraw_gear(g: Gear, to: PartyInventory) -> void:
    gear.erase(g)
    to.give_gear(g)
# ...same deposit_weapon/withdraw_weapon pair, keyed off a `&"weapons"` tab_capacity entry
```

`deposit_*` returns `false` (and does nothing) if the Vault tab is at capacity — the UI surfaces this
as a disabled button / inline message, not a silent no-op.

## 3. `InventoryMenuPanel` (`combat/ui/inventory_menu_panel.gd`)

A new `Panel`-extending Control, built the same way as the existing `AbilityMenuPanel`/
`TypeChartPanel`: manually positioned child Controls (no `.tscn`), pure state/logic exposed as
static methods for headless testing, `_for_test()` hooks that press buttons programmatically.
Opened/closed via `open_for(pc, companions, party_inventory, vault)` / `hide()`.

### 3.1 Layout

Three equal-size paperdoll columns across the top — **Companion 1 | PC | Companion 2** — PC always
center. A companion column with no companion assigned renders as a dim "— no companion —"
placeholder (the layout must not break with 0, 1, or 2 companions present). Each column shows 6 slot
boxes: Weapon, Headwear, Cloak, Chest, Hands, Charm — labeled with the equipped item's name in its
`RarityVisuals.color()`, or "— empty —".

Below the paperdoll row, one shared panel with two tabs, **Bag** (default) and **Vault**, each a grid
of Gear + Weapon entries. Per the locked scope, this pass shows **only Gear and Weapons** —
Materials/Quest Items/Gold/Reel-Mods are not represented in this panel at all (§7).

### 3.2 Interaction (click-to-equip, no drag-and-drop)

- Click an item in the **Bag** grid → selects it (highlighted).
- Click any slot on **any** of the 3 paperdolls → equips the selected item there via
  `equip_gear`/`equip_weapon`, moving it out of the bag (`PartyInventory.take_gear`/`take_weapon`) and
  putting whatever was displaced back into the bag (`give_gear`/`give_weapon`). Selection clears.
- Click an **already-equipped** slot with nothing selected → unequips it (`unequip_gear`/
  `unequip_weapon`) straight back into the Bag (`give_gear`/`give_weapon`).
- With a Bag item selected, a **"Send to Vault"** button appears → calls `Vault.deposit_gear`/
  `deposit_weapon`; if it returns `false` (tab at capacity), the button shows a brief "Vault full"
  message instead of transferring.
- Switching to the **Vault** tab shows the same grid for Vault contents. Selecting a Vault item shows
  a **"Withdraw to Bag"** button (calls `withdraw_gear`/`withdraw_weapon`) instead of paperdoll slots
  — Vault items are not directly equippable; they must be withdrawn to the Bag first. This avoids
  ambiguity about which of the 3 characters a bank item would equip to.

### 3.3 Hover tooltip + compare toggle

Hovering any item (Bag, Vault, or an equipped paperdoll slot) shows a tooltip: name (in its rarity
color), slot, and a `stat_bonuses`/reel-affix summary.

A **"Compare" checkbox** in the panel header, default ON: while enabled, hovering a Bag/Vault item
appends one comparison line per paperdoll column that currently has an item equipped in that same
slot — e.g. `vs PC: Might +2 (was +0)`, `vs Companion 1: Vigor −1 (was +3)`. A column with that slot
empty, or no companion assigned, is skipped (nothing to compare against). This keeps the comparison
in a single tooltip rather than annotating all three paperdoll columns simultaneously, and since any
Gear/Weapon can be equipped by any of the three characters (subject to `can_equip`'s level-gate),
comparing against all three avoids guessing which character the hover was "for."

## 4. `town_demo.tscn` integration

`town_demo.gd` currently has no `Combatant` references at all — it's pure movement/interaction. This
pass adds, in `_ready()`:

- A hardcoded PC `Combatant` (via `ClassLibrary`, any existing class — placeholder data, not real
  character-creation content) and one hardcoded companion `Combatant` (a second class, also
  placeholder — not the real companion-recruitment system, which doesn't exist in code yet).
- One shared `PartyInventory` and one `Vault`, each seeded with a small handful of placeholder
  `Gear`/`Weapon` instances spanning a few slots and rarities (enough to exercise the level-gate and
  the Resonance cap in play). A couple of items are pre-equipped on the PC/companion at start so
  unequip is testable immediately, not just equip into empty slots.
- The `I` key (in the existing `_unhandled_input`) toggles `InventoryMenuPanel.open_for(...)` /
  `hide()`. While the panel is open, PC movement is paused — the same pattern already used for
  `Villager.set_wander_paused()` during dialogue.

No new `.tscn` file, no new map — this reuses the existing town demo per the earlier direction to
"park the PC in our demo town."

## 5. Test plan

Headless suites under `tests/`, following the existing `extends SceneTree` + `_check()` pattern:

- `test_gear_equip_unequip.gd` — `equip_gear`/`unequip_gear` slot-swap behavior (displaced item
  returned correctly, `apply_stats()` refreshes derived values); `equip_weapon`/`unequip_weapon`
  straight-swap; rejected equips (`can_equip` false) leave state unchanged and return `null`.
- `test_inventory_vault_transfer.gd` — `deposit_gear`/`withdraw_gear`/`deposit_weapon`/
  `withdraw_weapon` move items between `PartyInventory` and `Vault` correctly; deposit blocked (no
  transfer occurs) when the relevant Vault tab is at capacity; bag-side `take_*`/`give_*` never
  capacity-check.
- `test_inventory_menu_panel.gd` — pure state/logic as static methods (which paperdoll columns render
  populated vs. "no companion"; which columns produce a compare line for a given hovered item vs.
  which are skipped), exercised via `_for_test()` hooks — same convention as
  `AbilityMenuPanel.press_row_for_test()`.
- Full regression: all existing suites (132 as of the equipment/inventory/banking data pass) must stay
  green — `Combatant.gear`/`weapon` are live fields read throughout combat resolution, untouched in
  shape by this pass (only new methods, no field removals/renames).

## 6. `world/town_demo.gd` file-size note

`town_demo.gd` currently owns movement, dialogue, doors, and NPC wandering. Adding
`Combatant`/inventory setup and the `I`-key toggle grows it further. If `_ready()` and the new setup
code push the file noticeably past its current size, split the new Combatant/inventory seeding into a
small helper (e.g. a static `_seed_demo_party()` free function or a tiny new
`world/inventory_demo_setup.gd`) rather than letting `town_demo.gd` keep absorbing unrelated
responsibilities — a targeted improvement in passing, not a speculative refactor.

## 7. Explicitly out of scope (this pass)

- **The escape/pause menu** (save/quit/settings) — parked for a later session; no save system exists
  yet either.
- **Materials, Quest Items, Gold, Reel-Mods** in the Bag/Vault UI — only Gear + Weapons are shown this
  pass, per direction. Reel-Mods has no defined shape yet (`27-crafting.md` undesigned).
- **Drag-and-drop** — click-to-select-then-click-target only, consistent with how targeting/ability
  staging already work in `combat.tscn`.
- **Real companion recruitment** — the companion in this demo is a hardcoded stub `Combatant`, not
  output of an actual recruitment system (none exists in code yet).
- **Character-select / multi-PC screen** — still not built, so true cross-character banking (handing
  an item to a *second* character) isn't end-to-end testable this pass, only the deposit/withdraw
  mechanics themselves are.
- **Real authored items/loot tables** — placeholder `Gear`/`Weapon` instances only, hand-placed in
  `town_demo.gd`'s seeding, not generated via `LootTable.roll()`.
- **Vault location-gating** — real in-game access will eventually be restricted to a bank location;
  this prototype's Vault tab is always reachable from the same menu, which is fine for proving the
  interaction, not the world-gating.

# General Store + Amber Economy — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally 2026-07-17. First step of the overworld-playtest
> arc's step 3 ("Shopkeepers" — memory `overworld-playtest-arc-2026-07-13`), which the player confirmed
> stays step 3 of the standing loot→items→shops→dungeon order. This spec covers ONE general store in
> the town's already-built shop building, the Amber currency it spends, and Amber's combat-drop source.
> Selling, multiple vendors, and a BG3-style simultaneous buy/sell screen are explicitly the "full game"
> version — **out of scope here**, researched and recorded below for later.

## 1. Goal

Turn the town's placeholder shop (a real `ShopDoor`/`ShopInterior` and a `Shopkeeper` NPC already in
`town_demo.gd`, whose dialogue literally says *"Nothing's actually for sale yet"*) into a working general
store: one stocked catalog of Gear/Weapon/Healing-Potion the player can buy with a new currency, **Amber**,
which vermin and woodlander combat encounters alike now drop. The store exists **specifically as a
playtesting tool** for this pass — cheap, plentiful stock lets the player freely re-gear every party member
in different combinations to stress-test stat-value balancing and Bag-capacity behavior, not to model a
real economy yet.

## 2. Decisions locked during brainstorming

- **Currency: Amber**, replacing the unused/placeholder `gold` field everywhere it already exists in code
  (see §3.1). Rejected alternatives considered: Acorns (too "low-value"-reading for the player), Shiny
  Bits/Trinkets, Teeth/Claws (fits vermin, not neutral encounters). **Lore direction (recorded for the
  storyline design-bible, not final prose):** Amber isn't wasted on vermin who can't personally use its
  mystical properties — it's the world's actual working currency, which is precisely why every faction
  fights over it. Warbands loot it from villages/travelers to fund themselves (buy weapons, bribe scouts,
  pay raiders); a given defeated grunt is carrying their cut of the spoils, the same way a real bandit
  carries stolen coin without personally "using" it. Underneath that ordinary-greed explanation sits a
  deeper hook: Amber is fossilized sap from the world's ancient Great Trees, carrying a trace of old magic
  — rare and potent enough that it became the recognized medium of trade in the first place, with room to
  matter again later (a certain golden Game Cartridge responding to it, etc.). Player-confirmed direction,
  not exact final wording.
- **One general store**, in the shop building that already exists in `town_demo.tscn`. No second vendor,
  no per-class shops, this pass.
- **Amber sources, this pass:** flat per-kill combat rewards only (§3.2), scaled by each enemy's size/
  power. Quest rewards and vendor-selling are real future sources the player named, but neither is a system
  that exists yet (no quest system at all; selling is explicitly the deferred "full game" feature below) —
  tracked, not built here.
- **Catalog scope (§3.4):** exactly one Gear item per (slot × rarity) combination for Headwear/Cloak/
  Chest/Hands (5 rarities × 4 slots = 20 items), **two** stat-differentiated Charm options per rarity (5 ×
  2 = 10 items, since Charm has 2 equip boxes and the player wants real stat-spread choice between them),
  and Weapons capped at **Common + Uncommon only** (2 items) — no Rare/Epic/Legendary weapons in this
  store. Every Gear/Weapon entry costs **1 Amber** and stocks **at least 3** units, so the player can fully
  re-gear multiple party members in different combinations. Healing Potions stock **99** units (also 1
  Amber each — cheap enough to buy in bulk and stress-test Bag behavior; not explicitly priced by the
  player, flagged as an assumption below).
- **The demo party starts with 30 Amber** (seeded, not earned) — this pass is specifically about
  exercising the shop and stat-value balancing, so the player shouldn't have to grind combat encounters
  first just to unlock the ability to test buying. Combat drops (§3.2) still work normally on top of this
  starting stockpile.
- **Purchase-only this pass** — no selling. The player's own framing separated "for the first playtest"
  (this spec) from "in the full game" (§7, researched below) — selling needs a sell-value system for
  arbitrary items that doesn't exist yet and isn't needed to unblock playtesting.
- **Vendor interaction: WoW-style 3-option menu** — interact with the Shopkeeper → a short line plays →
  **Talk / Shop / Leave**. Talk reuses the existing linear `DialogueBox`/`DialogueSet` flow unchanged (just
  real flavor text replacing the placeholder line). Shop opens the new `ShopPanel`. Leave closes the prompt
  with no further action. This is new, minimal scope — this project's dialogue system has no branching/
  choice mechanism at all yet, and a full choice-tree system is NOT being built here; this is a small,
  dedicated 3-button prompt that sits in front of the existing linear dialogue, not a rework of it.

## 3. Architecture

### 3.1 Currency rename: `gold` → `amber`

`gold` is not a dead placeholder — it's already wired into the Random Encounter ("?" node) system's
`good_gold_delta`/`neutral_gold_delta`/`bad_gold_delta` outcomes. Rename everywhere it appears:

- `economy/resources/party_inventory.gd`: `@export var gold: int = 0` → `@export var amber: int = 0`
  (update the doc comment above it to name Amber, not gold).
- `world/resources/encounter_option.gd`: `bad_gold_delta`/`neutral_gold_delta`/`good_gold_delta` →
  `bad_amber_delta`/`neutral_amber_delta`/`good_amber_delta`; `gold_delta_for()` → `amber_delta_for()`.
- `world/encounter_library.gd`: the 3 call sites (`o.good_gold_delta = 15`, `o.neutral_gold_delta = -5`,
  `o.bad_gold_delta = -10`) → the renamed fields, values unchanged.
- `world/ui/random_encounter_panel.gd`: `gold_delta_for` → `amber_delta_for`, `_party_inventory.gold` →
  `_party_inventory.amber`, the `"gold %+d"` display string → `"amber %+d"`.
- `tests/test_random_encounter_panel.gd`: `inv.gold` references → `inv.amber`.
- `docs/design-bible/25-inventory-and-storage.md` §8 "Party gold" → rename to "Party Amber", noting the
  currency is now named (was previously an open item).
- `docs/design-bible/10-storyline.md` §8 "Hooks into systems": append the lore paragraph from §2 above as
  a new ✅-tagged bullet, so the direction survives for whoever picks up the real storyline pass later.

### 3.1a Starting Amber

`world/inventory_demo_setup.gd`'s `seed_demo_party()` builds the `PartyInventory` returned in its
dictionary — add one line right after `var inv: PartyInventory = PartyInventory.new()`:
```gdscript
inv.amber = 30   # 2026-07-17 general store design: lets the player buy gear immediately, no combat grind required
```
This only affects a genuinely fresh seed (the very first town/overworld visit of a session) — a party
already carrying real, spent-and-earned Amber via `CombatHandoff.pc != null` reuse is never touched or
topped back up.

### 3.2 Combat Amber drops (mirrors the existing flat XP-per-kill pattern)

`Combat.ENEMY_XP_REWARD` is a single flat constant applied to every kill. Amber instead needs **per-enemy**
amounts (the player wants it scaled by size/power), so it's authored data, not one shared constant.

`combat/combatant.gd` — new field alongside `xp`/`loot_table`:
```gdscript
## Flat Amber reward this enemy grants the party on defeat (2026-07-17 general store design), scaled by
## the enemy's size/power. 0 for player-side combatants (never read for them). [ASSUMPTION] tuned by
## playtest, same convention as ENEMY_XP_REWARD.
var amber_reward: int = 0
```

`world/enemy_library.gd` — `_build()` gains a new trailing param `amber_reward: int = 0`, set
`c.amber_reward = amber_reward`; the 3 `make()` call sites pass concrete values:

```gdscript
&"rat":    return _build(label(id), crushing, 8.0, 2, earth, 300, &"", 0, &"overworld_trash", 5)
&"ferret": return _build(label(id), slashing, 7.0, 3, slashing, 260, &"flurry", 2, &"overworld_trash", 8)
&"stoat":  return _build(label(id), piercing, 6.0, 4, piercing, 220, &"hunters_mark", 3, &"overworld_trash", 12)
```
(rat = weakest kit, 2 reels/no ability → 5 Amber; ferret = 3 reels + an ability → 8; stoat = 4 reels + an
ability → 12 — scaled by kit strength, the closest proxy this codebase has to "power level." `[ASSUMPTION]`
exact numbers, tune by playtest like every other placeholder magnitude.)

`combat/combat.gd`'s `_on_enemy_defeated()` — add Amber alongside the existing XP/loot handling:
```gdscript
if _party_inventory != null and enemy.amber_reward > 0:
	_party_inventory.amber += enemy.amber_reward
	_fight_amber_gained += enemy.amber_reward
	CombatHandoff.log_event("%s defeated — party gains %d Amber." % [enemy.display_name, enemy.amber_reward], CombatHandoff.CATEGORY_COMBAT)
```
New `var _fight_amber_gained: int = 0` alongside `_fight_xp_gained`, reset in `_build_combatants()`
wherever `_fight_xp_gained` already resets. `_on_combat_ended()`'s result-card text gains a line matching
the existing `+N XP` pattern: `if _fight_amber_gained > 0: label.text += "\n+%d Amber" % _fight_amber_gained`.
Standalone launches (`_party_inventory == null`) skip this entirely, same guard already used for loot.

### 3.3 New resource: `ShopStockEntry`

`economy/resources/shop_stock_entry.gd`:
```gdscript
class_name ShopStockEntry
extends Resource

## One purchasable line in a vendor's catalog (2026-07-17 general store design). `item` is a Gear,
## Weapon, or ConsumableItem TEMPLATE — buying duplicates it (mirrors LootEntry's own
## duplicate-on-grant convention, so two purchases of the same line never alias the same Resource).
## `stock` decrements per purchase and does NOT replenish this pass (a fixed pool is fine for
## playtesting; a restock timer is future work, not built here).

@export var item: Resource
@export var price: int = 1
@export var stock: int = 3
```

### 3.4 New registry: `ShopLibrary`

`world/shop_library.gd` (mirrors `EnemyLibrary`/`LootTableLibrary`'s static-registry convention):
```gdscript
class_name ShopLibrary
extends RefCounted

## Code registry of vendor catalogs (2026-07-17 general store design). One store this pass:
## &"general_store", the town Shopkeeper's stock. Every entry is duplicated fresh per call so
## repeated openings never share Resource instances across scene reloads.

static func general_store() -> Array[ShopStockEntry]:
	return [
		# Headwear (Focus primary / Vigor secondary)
		_gear_entry("Cloth Cap", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.COMMON, _stats(0,0,0,1,0,0)),
		_gear_entry("Hunter's Hood", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.UNCOMMON, _stats(0,0,1,1,0,0)),
		_gear_entry("Owl-Eye Circlet", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.RARE, _stats(0,0,0,3,0,0)),
		_gear_entry("Sage's Coronet", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.EPIC, _stats(0,0,3,3,0,0)),
		_gear_entry("Crown of the Elder Oak", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.LEGENDARY, _stats(0,0,4,4,0,0)),
		# Cloak (Finesse primary / Luck secondary)
		_gear_entry("Traveler's Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.COMMON, _stats(0,1,0,0,0,0)),
		_gear_entry("Nimble Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.UNCOMMON, _stats(0,1,0,0,0,1)),
		_gear_entry("Shadowstep Cape", Gear.Slot.CLOAK, RarityVisuals.Rarity.RARE, _stats(0,3,0,0,0,0)),
		_gear_entry("Cloak of the Fleetfoot", Gear.Slot.CLOAK, RarityVisuals.Rarity.EPIC, _stats(0,3,0,0,0,3)),
		_gear_entry("Mantle of the Wind", Gear.Slot.CLOAK, RarityVisuals.Rarity.LEGENDARY, _stats(0,4,0,0,0,4)),
		# Chest (Vigor primary / Might secondary)
		_gear_entry("Padded Vest", Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, _stats(0,0,1,0,0,0)),
		_gear_entry("Riveted Jerkin", Gear.Slot.CHEST, RarityVisuals.Rarity.UNCOMMON, _stats(1,0,1,0,0,0)),
		_gear_entry("Bark-Plate Vest", Gear.Slot.CHEST, RarityVisuals.Rarity.RARE, _stats(0,0,3,0,0,0)),
		_gear_entry("Warden's Breastplate", Gear.Slot.CHEST, RarityVisuals.Rarity.EPIC, _stats(3,0,3,0,0,0)),
		_gear_entry("Heartwood Aegis", Gear.Slot.CHEST, RarityVisuals.Rarity.LEGENDARY, _stats(4,0,4,0,0,0)),
		# Hands (Might primary / Finesse secondary)
		_gear_entry("Worn Gloves", Gear.Slot.HANDS, RarityVisuals.Rarity.COMMON, _stats(1,0,0,0,0,0)),
		_gear_entry("Gripping Gauntlets", Gear.Slot.HANDS, RarityVisuals.Rarity.UNCOMMON, _stats(1,1,0,0,0,0)),
		_gear_entry("Ironclaw Fists", Gear.Slot.HANDS, RarityVisuals.Rarity.RARE, _stats(3,0,0,0,0,0)),
		_gear_entry("Gauntlets of the Vanguard", Gear.Slot.HANDS, RarityVisuals.Rarity.EPIC, _stats(3,3,0,0,0,0)),
		_gear_entry("Fists of the Ancient Oak", Gear.Slot.HANDS, RarityVisuals.Rarity.LEGENDARY, _stats(4,4,0,0,0,0)),
		# Charm variant A (Luck primary / Focus secondary) — both boxes accept either variant
		_gear_entry("Rabbit's Foot Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.COMMON, _stats(0,0,0,0,0,1)),
		_gear_entry("Four-Leaf Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.UNCOMMON, _stats(0,0,0,1,0,1)),
		_gear_entry("Gambler's Coin", Gear.Slot.CHARM, RarityVisuals.Rarity.RARE, _stats(0,0,0,0,0,3)),
		_gear_entry("Charm of Fortune's Favor", Gear.Slot.CHARM, RarityVisuals.Rarity.EPIC, _stats(0,0,0,3,0,3)),
		_gear_entry("The Wishing Amber", Gear.Slot.CHARM, RarityVisuals.Rarity.LEGENDARY, _stats(0,0,0,4,0,4)),
		# Charm variant B (Grit primary / Vigor secondary)
		_gear_entry("Sturdy Bead", Gear.Slot.CHARM, RarityVisuals.Rarity.COMMON, _stats(0,0,0,0,1,0)),
		_gear_entry("Ironwood Talisman", Gear.Slot.CHARM, RarityVisuals.Rarity.UNCOMMON, _stats(0,0,1,0,1,0)),
		_gear_entry("Bulwark Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.RARE, _stats(0,0,0,0,3,0)),
		_gear_entry("Charm of Unshakable Resolve", Gear.Slot.CHARM, RarityVisuals.Rarity.EPIC, _stats(0,0,3,0,3,0)),
		_gear_entry("Heart of the Mountain", Gear.Slot.CHARM, RarityVisuals.Rarity.LEGENDARY, _stats(0,0,4,0,4,0)),
		# Weapons (Common/Uncommon only, per player direction — no stat_bonuses field on Weapon)
		_weapon_entry("Journeyman's Blade", RarityVisuals.Rarity.COMMON, 6.0),
		_weapon_entry("Honed Shortsword", RarityVisuals.Rarity.UNCOMMON, 8.0),
		# Healing Potions
		_potion_entry(),
	]

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

static func _gear_entry(display_name: String, slot: int, rarity: int, stats: Stats) -> ShopStockEntry:
	var g: Gear = Gear.new()
	g.display_name = display_name
	g.slot = slot
	g.rarity = rarity
	g.stat_bonuses = stats
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = g
	e.price = 1
	e.stock = 3
	return e

static func _weapon_entry(display_name: String, rarity: int, base_damage: float) -> ShopStockEntry:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.display_name = display_name
	w.rarity = rarity
	w.base_damage = base_damage
	for i in range(3):
		w.reels.append(ActionReel.make_default(slashing))
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = w
	e.price = 1
	e.stock = 3
	return e

static func _potion_entry() -> ShopStockEntry:
	var p: ConsumableItem = ConsumableItem.new()
	p.item_type = &"healing_potion"
	p.display_name = "Healing Potion"
	p.heal_amount = 30
	p.quantity = 1   # per-unit template; ShopPanel buys one unit at a time (see §3.5)
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = p
	e.price = 1
	e.stock = 99
	return e
```

Every stat magnitude/name above is `[ASSUMPTION]`, tuned by playtest like every other authored number in
this codebase — the point of this pass is enabling that tuning, not pre-solving it. Total catalog: 20 (4
slots × 5 rarities) + 10 (Charm × 2 variants) + 2 weapons + 1 potion line = **33 stock entries.**

### 3.5 `ShopPanel` (new, `combat/ui/shop_panel.gd`)

Mirrors `ItemMenuPanel`'s non-modal floating-panel shape, but with `InventoryMenuPanel`'s tab convention
(`TAB_ROW`) since 33 entries don't fit one readable list — one tab per catalog group: **Headwear / Cloak /
Chest / Hands / Charms / Weapons / Potions** (7 tabs, each showing that group's rarity ladder as rows).

Each row: item name (rarity-colored via `RarityVisuals.color()`), a short stat-bonus summary (e.g. "Focus
+3"), price, remaining stock, and a Buy button. A header shows the party's current Amber balance
(`"Amber: %d" % _party_inventory.amber`), refreshed after every purchase.

`func open_for(party_inventory: PartyInventory, stock: Array[ShopStockEntry]) -> void` — rebuilds rows from
`stock` on every open (same "never cached" convention as every other menu panel in this codebase).

Buying (`_on_buy_pressed(entry: ShopStockEntry)`):
```gdscript
if entry.stock <= 0 or _party_inventory.amber < entry.price:
	return   # button is already disabled in this state; defensive no-op, mirrors other panels' guards
var granted: bool = false
if entry.item is Gear:
	granted = _party_inventory.try_give_gear((entry.item as Gear).duplicate(true))
elif entry.item is Weapon:
	granted = _party_inventory.try_give_weapon((entry.item as Weapon).duplicate(true))
elif entry.item is ConsumableItem:
	granted = _party_inventory.try_give_item((entry.item as ConsumableItem).duplicate(true))
if granted:
	_party_inventory.amber -= entry.price
	entry.stock -= 1
	_rebuild_row(entry)   # or full open_for() re-call — implementer's call, whichever is simpler here
else:
	_show_reject_message("Bag full")   # mirrors the existing "Requires level N"/"Vault full" convention
```
A full Bag legitimately blocks a Gear/Weapon purchase (this resolves the deferred lever the loot-drops
memory flagged: yes, a full Bag blocks acquiring more, same rule for a shop purchase as for combat loot).
Consumable stacks (Healing Potion) merge into the existing stack and never hit this rejection once the
first unit exists in the Bag, per `try_give_item()`'s existing behavior — buying up to 99 potions is always
possible regardless of Bag fullness; **Bag-full testing comes from the 32 individually-slotted Gear/Weapon
lines, not the potions** (worth knowing going in — the potions test unlimited-stack-quantity handling, the
gear tests Bag-capacity pressure; both were asked for, they just each stress a different mechanism).

### 3.6 Vendor interaction: `VendorPromptPanel` + `Villager.is_vendor`

`Villager` (`world/villager.gd`) gains:
```gdscript
@export var is_vendor: bool = false
signal vendor_interacted(dialogue_set: DialogueSet)
```
`_on_interacted()` branches:
```gdscript
func _on_interacted() -> void:
	if is_vendor:
		vendor_interacted.emit(dialogue)
	else:
		dialogue_requested.emit(dialogue)
```
Every other Villager is untouched (`is_vendor` defaults false, keeps emitting `dialogue_requested` exactly
as today).

New `world/ui/vendor_prompt_panel.gd` (`VendorPromptPanel`, mirrors the small single-purpose panel
convention already used for `ItemMenuPanel`): shows the Shopkeeper's greeting line (from its `DialogueSet`,
first line only) plus three buttons — **Talk** (closes the prompt, opens the existing `DialogueBox` with
the full `DialogueSet`, unchanged flow), **Shop** (closes the prompt, opens `ShopPanel`), **Leave** (closes
the prompt, no further action).

`town_demo.gd`: `shopkeeper.is_vendor = true`; connect `vendor_interacted` to a new `_on_vendor_interacted`
that pauses PC movement (`_pc.set_movement_paused(true)`, same as every other panel) and opens
`VendorPromptPanel`; each of the panel's three outcomes re-enables movement appropriately (Talk hands off
to the existing dialogue-close movement-resume path; Shop/Leave resume movement directly once their own
panel closes). Replace the Shopkeeper's placeholder dialogue line with real flavor text (no longer "nothing
for sale yet").

### 3.7 Shop stock survives a town↔overworld round trip

The store's `Array[ShopStockEntry]` is built once by `town_demo.gd` at `_ready()` (like `_party_inventory`)
and must persist across a `TownExit → overworld_demo.tscn → VillageEntrance → town_demo.tscn` round trip
inside one play session, or a purchase would silently "come back" next visit. `CombatHandoff.stash_party()`
gains a trailing param, mirroring `bench`'s exact precedent:
```gdscript
func stash_party(p: Combatant, comps: Array, inv: PartyInventory, v: Vault, b: Array = [], shop: Array = []) -> void:
	pc = p; companions = comps; bench = b; party_inventory = inv; vault = v; shop_stock = shop
```
New `var shop_stock: Array = []` field on `CombatHandoff`, cleared by `clear_party()` alongside
`party_inventory`/`vault`/`bench`. `town_demo.gd` checks `CombatHandoff.pc != null` (the same existing
reuse-vs-reseed branch that already handles `pc`/`companions`/`bench`/`party_inventory`/`vault`) and, when
reusing, also reuses `CombatHandoff.shop_stock` instead of calling `ShopLibrary.general_store()` fresh —
only a genuinely first-ever town visit builds a brand-new catalog. `overworld_demo.gd` never reads
`shop_stock` at all (a harmless passthrough field it doesn't own, same asymmetric-ownership pattern
`pending_ground_drops` already established the other direction).

### 3.8 Amber balance visibility

`InventoryMenuPanel`'s Stats tab (which already shows HP/Resource/Bonus Meter per character) gains one
line ABOVE the 3 character columns, since Amber is party-shared, not per-character:
`"Amber: %d" % party_inventory.amber`. This is the only place Amber is visible outside `ShopPanel` itself
this pass — keeps the player from being blind to their balance while wandering, at near-zero cost.

## 4. Out of scope

- **Selling items to vendors.** No sell-value system, no sell UI. Purchase-only this pass.
- **The full BG3-style simultaneous buy/sell trade screen** (researched for later): side-by-side player/
  merchant inventories, a middle staging area for items about to change hands, running totals of value
  displayed above each side as you add/remove items, one confirm action that resolves the whole net
  exchange, refusing an unbalanced offer. A persuasion/attitude-driven price modifier is part of BG3's
  system too but is its own later layer, not needed to make a first store functional.
- **Multiple vendors, per-class shops, restocking, or a shop that reads differently per character level.**
  One general store, fixed stock, this pass.
- **Quest-reward Amber and vendor-sale Amber** as actual sources — named by the player as real future
  sources, but neither a quest system nor selling exists yet to hang them on.
- **Reel affixes on shop Gear.** `ReelAffix` exists as a shape with no resolver wiring anywhere in the
  codebase yet (confirmed: no code reads a `Gear.reel_affixes` entry for any gameplay effect) — shop items
  carry `stat_bonuses` only, consistent with every other authored Gear item in the game so far.
- **Any change to Foresight/Regrowth/lowest-HP%-ally targeting**, dialogue branching as a general system,
  or anything about the dungeon (step 4 of the arc) — unrelated to this spec.

## 5. Testing plan

- **`tests/test_shop_library.gd` (new)** — `general_store()` returns exactly 33 entries; every Gear/Weapon
  entry has `price == 1` and `stock == 3`; the potion entry has `price == 1` and `stock == 99`; every
  rarity tier's `stat_bonuses` respects `RarityVisuals.max_stat_affixes()` (no entry sets more non-zero
  stats than its rarity allows); two calls to `general_store()` return DIFFERENT Resource instances (no
  aliasing across repeated calls, mirroring `LootTable.roll()`'s duplicate-on-grant precedent).
- **`tests/test_shop_panel.gd` (new)** — buying a Gear/Weapon entry decrements `stock`, decrements
  `party_inventory.amber` by `price`, and grants a DUPLICATE (not the template instance) into the Bag;
  buying with insufficient Amber or zero stock is a no-op (no deduction, no grant); a full Bag rejects a
  Gear/Weapon purchase (Amber unchanged, stock unchanged) and shows the reject message; buying a Healing
  Potion repeatedly past the point a Gear purchase would have been Bag-blocked still succeeds (stack
  merge, not a new slot).
- **`tests/test_villager_vendor.gd` (extend `test_overworld_npcs.gd`'s convention, or new file)** —
  `Villager.is_vendor = true` emits `vendor_interacted`, not `dialogue_requested`, on interact; a normal
  Villager (`is_vendor` default false) still emits only `dialogue_requested`, unchanged.
- **`tests/test_combat_amber.gd` (new, mirrors `test_combat_xp.gd`'s shape exactly)** — defeating an enemy
  with `amber_reward > 0` adds that amount to `_party_inventory.amber` and `_fight_amber_gained`; the
  result card shows `+N Amber`; a standalone launch (`_party_inventory == null`) never touches Amber.
- **`tests/test_shared_party_state.gd` (extend)** — `stash_party()`'s new `shop` param round-trips through
  a town→overworld→town cycle unchanged (a purchase's decremented stock is still decremented after the
  round trip), mirroring the existing bench-survival assertion in that same file.
- **`tests/test_inventory_demo_setup.gd` (extend)** — `seed_demo_party()`'s returned `party_inventory.amber
  == 30` on a fresh seed.
- **Existing test migration** — `tests/test_random_encounter_panel.gd`'s `inv.gold` references become
  `inv.amber`; no other file references the removed field names anywhere (grep-clean, matching the
  established convention from the 2026-07-16 field-rename work).
- **End-to-end** — drive a real `town_demo.tscn`, interact with the Shopkeeper, choose Shop, buy a piece of
  Gear and a Healing Potion, confirm Amber/Bag/stock all update correctly and the panel closes/reopens
  cleanly; separately confirm Talk still plays the (updated) dialogue and Leave does nothing.

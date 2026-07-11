# Equipment / Inventory / Banking — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Graduates the brainstorm captured across `docs/design-bible/21-stats-and-
> attributes.md`, `24-equipment.md`, `25-inventory-and-storage.md`, and `26-banking-cross-character.md`
> (all now marked ✅ LOCKED, kept for history/rationale). This is the source of truth for implementation.
> All numeric magnitudes are `[ASSUMPTION]` — data-driven, tuned post-playtest per CLAUDE.md §4, never
> hardcoded as "the" balance.
>
> **Correction (2026-07-11):** §3.1's `Gear.Slot` enum below shipped with only one Charm slot, but
> `docs/design-bible/24-equipment.md` §2 had already locked **two** independent Charm slots ("Charm
> x2") the same day this spec was written — a spec/design-bible mismatch, not a later design change.
> Found during the first human playtest of the equipment UI (a companion couldn't be given a second
> Charm). Fixed in `combat/resources/gear.gd` (`Gear.Slot` now has `CHARM` and `CHARM_2`) and
> `combat/ui/inventory_menu_panel.gd` (`SLOT_COUNT` 6→7). The code block and "5 non-weapon slots"
> text below are left as originally written for history.

## 1. Goal

Build the data layer and combat-math hooks for equipment, inventory, and cross-character banking:

- A 6-slot equipment loadout (Weapon + 5 armor/charm slots) with a shared 5-tier rarity ladder that
  doubles as a level-gate.
- A reworked stat→combat translation for Might/Vigor/Focus/Luck (WoW vanilla stat-scaling as the
  model), replacing the current flat 1:1 placeholders.
- A per-PC shared-party inventory (capped Gear tab, uncapped everything else) and an account-wide,
  finite, expandable cross-character Bank.
- The loot-generation *mechanism* (independent per-item drop-chance rolls, WoW-style) — not actual
  loot tables/items, which are explicitly deferred.

This is a **data + pure-logic** pass, headless-testable like every prior combat system. It does **not**
build any new UI screens (see §8 Explicitly Out of Scope) — there is no out-of-combat equipment/
inventory/bank screen in the game yet, and no companion-recruitment system in code yet to hang a
camp screen off of. This pass makes the underlying model correct so that UI work later has real data
to bind to.

## 2. New folder: `economy/`

Equipment (`Gear`, `Weapon`, rarity) stays in `combat/resources/` since combat directly consumes it.
Inventory/Bank/Loot are **not** turn-resolution concerns — they live in a new top-level `economy/`
folder (parallel to `combat/` and `world/`):

```
economy/
  resources/
    party_inventory.gd   (class_name PartyInventory)
    vault.gd             (class_name Vault)
    loot_entry.gd         (class_name LootEntry)
    loot_table.gd         (class_name LootTable)
```

## 3. Equipment data model (`combat/resources/`)

### 3.1 `Gear` (extend existing `combat/resources/gear.gd`)

```gdscript
enum Slot { HEADWEAR, CLOAK, CHEST, HANDS, CHARM }

@export var slot: Slot = Slot.CHEST
@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON
@export var stat_bonuses: Stats
@export var reel_affixes: Array[ReelAffix] = []
```

`Gear.Slot` covers only the 5 non-weapon slots — the equipped weapon lives on
`Combatant.weapon: Weapon` (unchanged) and never becomes a `Gear` instance, so it's deliberately not
in this enum. `Weapon` gets its own `rarity` field (§3.4) using the same `RarityVisuals.Rarity` enum
(defined once, §3.2, so neither `Gear` nor `Weapon` has to depend on the other just for a rarity
value) so the ladder stays shared. A future equipment-paperdoll UI showing all 6 slots together works
off `Weapon` + `Gear.Slot` as two separate sources, not one unified enum. Replaces the old
`ARMOR`/`TRINKET` slots.

`min_level` is **derived**, not stored, via `RarityVisuals.min_level_for(rarity)` — avoids the data
drifting out of sync with the tier table.

### 3.2 `RarityVisuals` (new static helper, `combat/rarity_visuals.gd`)

Owns the `Rarity` enum itself (`enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }`) plus every
lookup below, so both `Gear` and `Weapon` reference `RarityVisuals.Rarity` rather than duplicating or
cross-depending on each other. Mirrors the existing `TypeVisuals`/`RoleVisuals` pattern (name/color/
tier lookups consumed by both UI and validation logic):

| Rarity | `min_level_for()` | `display_name()` | `color()` | `max_stat_affixes()` | `max_reel_affixes()` |
|---|---|---|---|---|---|
| Common | 1 | "Common" | white `Color(1,1,1)` | 1 | 0 |
| Uncommon | 3 | "Uncommon" | green `Color(0.12,0.8,0.12)` | 2 | 0 |
| Rare | 5 | "Rare" | blue `Color(0.2,0.4,1.0)` | 1 | 1 |
| Epic | 7 | "Epic" | purple `Color(0.64,0.2,0.93)` | 2 | 1 |
| Legendary | 9 | "Legendary" | orange `Color(1.0,0.5,0.0)` | 2 | 2 |

(`[ASSUMPTION]` exact color values — approximating WoW's actual item-quality palette.) Also exposes
`static func rarity_for_level(level: int) -> Rarity` (the inverse lookup — highest tier whose
`min_level_for()` is `<= level`), used by the weapon empowerment layer (§3.4) and by the item-level
gate (§3.3).

### 3.3 `ReelAffix` (new, `combat/resources/reel_affix.gd`)

Thin descriptor — the shape the combat resolver already knows how to consume, just not yet
data-driven from an equipped item:

```gdscript
class_name ReelAffix
extends Resource

enum Kind { ADD_FACE, ADD_REEL, TIER_BIAS }

@export var kind: Kind = Kind.ADD_FACE
@export var damage_type_id: StringName = &""   # for ADD_FACE / ADD_REEL
@export var result_tier: ReelFace.ResultTier = ReelFace.ResultTier.SUCCESS  # for ADD_FACE
@export var multiplier: float = 1.0             # for ADD_FACE
@export var bias_pct: float = 0.0               # for TIER_BIAS
```

No resolver wiring in this pass (no items are authored yet) — this just locks the shape so
`27-crafting`/loot-table work later has a target to write into.

### 3.4 `Weapon` (extend existing `combat/resources/weapon.gd`)

```gdscript
@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON   # authored loot identity — sets affix budget, fixed
```

**Empowerment layer — "not item growth."** The weapon's own `base_damage`/`reels`/affixes are fixed
loot data (this is what the bank hands down and what stays interesting per-item). Separately,
`Combatant` computes a level-derived multiplier applied on top of *whichever* weapon is currently
equipped, recalculated every time `apply_stats()` runs (equip, level-up, or load):

```gdscript
# Combatant.gd
const WEAPON_LEVEL_DAMAGE_PCT: float = 0.03  # [ASSUMPTION] +3% weapon base damage per level

func weapon_effective_base_damage() -> float:
    if weapon == null:
        return 0.0
    return weapon.base_damage * (1.0 + level * WEAPON_LEVEL_DAMAGE_PCT)
```

`combat.gd`'s call into `resolve_combat_phase` switches from `_attacker.weapon.base_damage` to
`_attacker.weapon_effective_base_damage()`. This is recomputed from `level` directly (not
time-equipped), so swapping weapons is always safe and a banked high-rarity weapon handed to a
lower-level alt keeps its affixes but its damage layer rescales to the recipient's own level —
solving the bank's "does a hand-me-down trivialize a fresh alt" problem.

The **displayed** rarity-tier color for the weapon in UI is `RarityVisuals.rarity_for_level(level)`
(this is the "upgrades in rarity at L3/L5/L7/L9" the player sees), which is independent of the
weapon's own **authored** `rarity` (which only ever governs its affix budget, per §3.2's table, and
never changes). A Legendary-affix weapon on a level 1 character still shows/behaves as
level-appropriate in raw damage, while keeping its Legendary affixes.

### 3.5 Equip validation

New `Combatant` method, called by whatever UI eventually drives equipping:

```gdscript
func can_equip(g: Gear) -> bool:
    if level < RarityVisuals.min_level_for(g.rarity):
        return false
    if g.reel_affixes.size() > 0:
        var resonance_count: int = 0
        for existing: Gear in gear:
            if existing != g and existing.reel_affixes.size() > 0:
                resonance_count += 1
        if resonance_count >= 2:
            return false
    return true
```

Resonance cap is **per item**, not per affix — a Legendary item's 2 reel affixes still cost 1 slot.

## 4. Inventory & Bank data model (`economy/resources/`)

### 4.1 `PartyInventory` — one per PC (not per-companion)

```gdscript
class_name PartyInventory
extends Resource

@export var gear: Array[Gear] = []
@export var reel_mods: Array[Resource] = []   # uncapped; shape TBD when 27-crafting is designed
@export var materials: Array[Resource] = []   # uncapped, stacking
@export var quest_items: Array[Resource] = [] # uncapped; never banked (see Vault, §4.2)
@export var gold: int = 0
@export var unlocked_companion_slots: int = 0  # 0-2, story-gated (Rrrobert tutorial slot + ORG slot)

func gear_capacity() -> int:
    return 20 + 10 * unlocked_companion_slots

func can_add_gear() -> bool:
    return gear.size() < gear_capacity()
```

`unlocked_companion_slots` increments permanently at the relevant story beats regardless of whether
a companion currently occupies the slot (per the locked design — capacity is slot-unlock-driven, not
active-headcount-driven).

Companions' own **equipped** gear (their weapon/headwear/etc.) lives on their own `Combatant`
instance (`Companion extends Combatant`, per `12-companions-and-party.md`), not in
`PartyInventory` — only *carried, unequipped* gear is pooled. Access gating (benched companions'
equipped gear unusable in the field, freely manageable at a hub/rest point) is a **UI/scene-flow**
concern with no combat-math component, so it's noted here for the future camp screen rather than
built now (§8).

### 4.2 `Vault` — the account-wide bank

```gdscript
class_name Vault
extends Resource

@export var gear: Array[Gear] = []
@export var reel_mods: Array[Resource] = []
@export var materials: Array[Resource] = []
@export var tab_capacity: Dictionary = {}   # StringName tab -> int capacity, expandable

func capacity_for(tab: StringName) -> int:
    return tab_capacity.get(tab, 0)

func can_add(tab: StringName, list: Array) -> bool:
    return list.size() < capacity_for(tab)
```

No `quest_items` tab — quest items are per-playthrough and never cross the party↔bank boundary.
One `Vault` instance shared by every PC the player creates (loaded independently of any single PC's
save state). Expansion (dual sink: story/mastery-earned early tabs, gold-bought later tabs) is a
progression-content concern with the actual costs `[ASSUMPTION]` — this pass just needs
`tab_capacity` to be a live, mutable dictionary that content/UI can raise later.

### 4.3 Loot generation mechanism (shape only — no tables authored yet)

```gdscript
class_name LootEntry
extends Resource

@export var item: Resource       # a Gear (or a future item type)
@export var drop_chance: float = 0.0   # 0.0-1.0, rolled independently

class_name LootTable
extends Resource

@export var entries: Array[LootEntry] = []

static func roll(table: LootTable) -> Array:
    var drops: Array = []
    for e: LootEntry in table.entries:
        if randf() < e.drop_chance:
            drops.append(e.item)
    return drops
```

WoW-style: every entry is an **independent** roll, so a kill can drop zero, one, or several items —
not a single weighted pick. `EnemyLibrary` entries gain an optional `loot_table: LootTable` field
this pass (defaults to `null`/empty) so the hook exists; **no actual tables/items get authored** —
that's explicitly deferred to when more of the game's systems (and a real item catalog) exist.

## 5. Stat → combat rework (`combat/combatant.gd`, `combat/resource_pool.gd`, `combat/combat.gd`)

All four replace their current flat placeholder with a WoW-vanilla-inspired scaling model. Finesse
and Grit are unchanged (already shipped, not touched this pass).

### 5.1 Might — reel-count-normalized "Power" (WoW Strength→Attack Power analog)

```gdscript
# Combatant.gd
const MIGHT_TO_POWER_RATIO: float = 2.0  # [ASSUMPTION], mirrors WoW's 2 AP/Str

func might_damage_bonus_per_reel(active_reel_count: int) -> int:
    var power: float = effective_stats().might * MIGHT_TO_POWER_RATIO
    return ceili(power / maxf(active_reel_count, 1))
```

Replaces the current call at `combat.gd:1309`, which passes raw `effective_stats().might` straight
through as `flat_damage_bonus`. Change to
`_attacker.might_damage_bonus_per_reel(reels.size())`. Because the divisor is the *current* reel
count, a 2-reel heavy loadout gets a bigger per-reel bonus from the same Might than a 5-reel rapid
loadout — the reel-count analog of WoW's attack-power-normalized-by-weapon-speed, so the same total
Might-derived damage per turn holds roughly constant regardless of loadout shape (typical band = 3
reels, so at 3 reels the per-reel bonus × 3 ≈ `power` exactly).

### 5.2 Vigor — reduces incoming DoT damage (was: reduce enemy crit-success chance)

```gdscript
const VIGOR_DOT_RESIST_PER_POINT: float = 0.05  # [ASSUMPTION] 5%/point
const VIGOR_DOT_RESIST_FLOOR: float = 0.4        # [ASSUMPTION] never below 40% damage taken

func dot_damage_multiplier() -> float:
    return clampf(1.0 - effective_stats().vigor * VIGOR_DOT_RESIST_PER_POINT, VIGOR_DOT_RESIST_FLOOR, 1.0)
```

Hooked into `combat.gd:_apply_dot()` — only for non-beneficial ticks (Bleed/Cursed), not Regen/HoT:

```gdscript
if amount > 0:
    if e.beneficial:
        c.heal(amount)
        ...
    else:
        amount = ceili(amount * c.dot_damage_multiplier())
        c.take_damage(amount)
        ...
```

Vigor's existing max-HP contribution (`apply_stats()`) is unchanged.

### 5.3 Focus — adds to per-Upkeep resource regen (was: caster pool max only)

Needs a "base regen" seed field, mirroring the existing `base_max_hp`/`base_max_stamina` pattern
(currently `CharacterClass.stamina_regen`/`mana_regen` write straight into
`ResourcePool.regen_per_turn`/`mana_regen_per_turn` at build time — §5.3 needs a base to derive from
repeatedly, the same way `apply_stats()` re-derives `max_hp` from `base_max_hp` every call):

```gdscript
# Combatant.gd — new pre-stat seed fields, set at build time instead of writing pool fields directly
var base_stamina_regen: int = 0
var base_mana_regen: int = 0

const FOCUS_REGEN_PER_POINT: float = 0.5  # [ASSUMPTION]

# in apply_stats():
if resource_pool != null:
    ...
    if base_max_stamina > 0:
        resource_pool.regen_per_turn = base_stamina_regen + floori(s.focus * FOCUS_REGEN_PER_POINT)
    if base_max_mana > 0:
        resource_pool.mana_regen_per_turn = base_mana_regen + floori(s.focus * FOCUS_REGEN_PER_POINT)
```

`CharacterClass.build_combatant()` sets `base_stamina_regen`/`base_mana_regen` instead of writing
`pool.regen_per_turn`/`pool.mana_regen_per_turn` directly, then `apply_stats()` (already called right
after in both `character_class.gd` and `enemy_library.gd`) derives the live value — same call order
as today, just one indirection added.

### 5.4 Luck — threshold crit faces + the `extra_lines` payline hook

```gdscript
const LUCK_PER_CRIT_FACE: int = 3   # [ASSUMPTION] — was 1:1, now needs 3 points/face
const LUCK_PER_EXTRA_LINE: int = 4  # [ASSUMPTION]

func apply_luck() -> void:
    if weapon == null:
        return
    var n: int = effective_stats().luck / LUCK_PER_CRIT_FACE   # integer division floors
    if n <= 0:
        return
    ... # unchanged face-injection loop below

func luck_extra_lines(weapon_reel_count: int) -> Array:
    var n: int = effective_stats().luck / LUCK_PER_EXTRA_LINE
    var lines: Array = []
    for i in range(n):
        lines.append(PaylineLibrary.bonus_line(weapon_reel_count))
    return lines
```

`combat.gd`'s existing `extra_lines` construction (currently only Loaded Dice's bonus line, around
line 1306-1309) appends `_attacker.luck_extra_lines(weapon_count)` alongside whatever Loaded Dice
contributes — the two stack, both using the same `PaylineLibrary.bonus_line()` primitive already
shipped. This is the "reserved but never wired" `extra_lines`/Luck hook the codebase status notes
flagged — now used as intended.

## 6. Multi-character structure (context, not new code this pass)

The player creates multiple independent PCs (WoW-alt style) via a character-select screen. Each PC
gets its own full playthrough (story, companions, level, build) — the **only** thing shared across a
player's characters is the `Vault` (§4.2). No code this pass — noted so `PartyInventory` (§4.1, scoped
to one PC) and `Vault` (§4.2, scoped to the whole player) aren't accidentally conflated later.

## 7. Test plan

Headless suites under `tests/`, one per new subsystem, following the existing `extends SceneTree` +
`_check()` pattern:

- `test_rarity_visuals.gd` — min-level/name/color/affix-count table, `rarity_for_level()` inverse lookup.
- `test_gear_equip_validation.gd` — level-gate blocks under-level equip; Resonance cap blocks a 3rd
  reel-affix item but allows a 2-reel-affix Legendary as one slot; swapping/unequipping frees the slot.
- `test_might_scaling.gd` — per-reel bonus at 2/3/5 reel counts, confirms normalization (bigger
  per-reel bonus at low reel count, roughly-conserved total at the 3-reel baseline).
- `test_vigor_dot_resist.gd` — DoT tick reduced correctly at several Vigor values, floor never
  exceeded, beneficial DoTs (Regen) untouched.
- `test_focus_regen.gd` — regen_per_turn derives correctly from base + Focus, stays correct across
  repeated `apply_stats()` calls (idempotency — the base/derived split is exactly to guard this).
- `test_luck_threshold.gd` — crit faces only added at multiples of `LUCK_PER_CRIT_FACE`; extra lines
  granted at multiples of `LUCK_PER_EXTRA_LINE`; stacks correctly alongside Loaded Dice's line.
- `test_weapon_empowerment.gd` — `weapon_effective_base_damage()` scales with level; instant rescale
  on level change with no persisted "weapon level"; authored `rarity`/affix budget untouched by level.
- `test_party_inventory_cap.gd` — gear cap formula (20 + 10×slots) enforced; other tabs uncapped;
  cap persists regardless of whether unlocked slots are currently filled by an active companion.
- `test_vault.gd` — finite per-tab capacity; add blocked at cap; no quest-item tab exists.
- `test_loot_table.gd` — statistical check that entries roll independently (a table with two 100%
  entries always returns both; a table with one 0% and one 100% entry always returns exactly one).
- Full regression: all existing suites (107 as of the last playtest round) must stay green, since
  `flat_damage_bonus`/`_apply_dot`/`apply_stats`/`apply_luck`/`extra_lines` are all live, exercised
  call sites.

## 8. Explicitly out of scope (this pass)

- **Character-select screen** and any multi-save management — noted (§6), not built.
- **BG3-style camp/character-management screen** — no UI this pass; the data model (§4.1's
  `PartyInventory`, companion-owned equipped gear) is shaped to support it once it exists. No
  companion-recruitment system exists in code yet to hang this off of.
- **Actual authored items, loot tables, weapon/gear catalogs** — per player direction, content comes
  after more systems are built. This pass only locks the `LootTable`/`LootEntry` shape (§4.3).
- **Crafting / Reel-Mods mechanics** (`27-crafting.md`) — undesigned; `reel_mods` arrays are typed
  `Array[Resource]` placeholders.
- **Talents / Reel Points** (`23-talents-and-reel-points.md`) — separate system, not touched.
- **Set bonuses** — parked until the roguelite mode (CLAUDE.md §7).
- **In-combat item-use panel** — tracked separately per `25-inventory-and-storage.md` §9's existing
  backlog note.
- **Bind rules, Stow/junk tag, vendor selling** — carried-over proposals from the design bible, not
  re-litigated or built this pass.

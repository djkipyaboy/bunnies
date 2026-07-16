# Combat Item-Use Targeting + Item Reel — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally 2026-07-16. This is sub-project 1 of a
> 2-part follow-on to the items-out-of-combat expansion (memory
> `combat-items-out-of-combat-expansion-2026-07-14`): the player's original ask ("item-use targeting
> UI via the Stats tab") grew, during brainstorming, into replacing combat's item-targeting model
> entirely — this spec covers the **in-combat** half. Sub-project 2 (the out-of-combat
> `InventoryMenuPanel` Stats-tab targeting flow, for using items in town/overworld) is a separate
> spec, built after this one ships and is playtested. A third piece — a Thrown-Item success/fail
> reel — was raised during brainstorming and explicitly deferred; **not any part of this spec.**

## 1. Goal

Today, staging a Healing Potion in combat (`ItemMenuPanel`, shipped 2026-07-14) always heals the
party's lowest-HP%-living ally, deterministically, for a flat `heal_amount`. The player wants two
changes, requested together because the second depends on the first:

1. **Manual ally targeting**, replacing the auto-lowest-HP% pick. A green outline on the targeted
   ally's `CombatantPanel` — the same technique as the existing red enemy-target outline — defaults
   to the active combatant's own panel each turn (so by default you heal yourself), is
   click-adjustable at any point during that combatant's own Main Phase 1, and (since it's on by
   default every player turn, not just when an item is staged) doubles as an additional
   whose-turn-is-it indicator.
2. **An Item Reel.** When Spin is pressed with an item staged, a dedicated reel resolves the item's
   own outcome alongside the weapon reels: 90% Success, 10% Critical Success, **no failure tiers at
   all** — a potion should never simply fail. Critical Success multiplies the heal ×1.5.

## 2. Decisions locked during brainstorming

- **Scope: in-combat only.** This spec reworks `ItemMenuPanel`/`MainPhasePlan`/`combat.gd`'s existing
  combat item-use path. The separate out-of-combat flow (`InventoryMenuPanel`'s Stats tab, for using
  an item in town/overworld) is sub-project 2 — not touched here beyond both eventually sharing the
  same `ConsumableItem`/`PartyInventory` data.
- **Ally-target default and reset**: the active combatant's own panel, every turn, no
  cross-turn persistence (unlike the enemy-target system's per-PC `_player_targets` memory — the
  player was explicit that ally targeting always snaps back to self on a new turn, nothing to
  remember). Only relevant on a player-side (`is_player`) turn; an enemy's turn shows no ally
  outline at all (enemies never use items).
- **Adjustable only during that ally's own Main Phase 1** (the existing `_awaiting_player_spin`
  gate) — identical restriction to enemy targeting. The outline itself stays visible for the whole
  turn (Upkeep→End), same as the enemy outline today; only the click-to-reassign action is
  phase-gated.
- **Ally-target state is independent of item-staging state.** Clicking a different ally doesn't
  require an item to be staged first, and un-staging/re-staging the item doesn't reset the chosen
  target — only a new turn does.
- **Item Reel composition**: 9 SUCCESS + 1 CRIT_SUCCESS faces (10-face strip, exact 90/10), zero
  multiplier on every face (the reel's own damage-pipeline output is irrelevant — the orchestrator
  computes the real payoff from the landed tier, same convention as the Warden's Rallying Cry reel).
  `is_weapon_attack = false` (out of paylines, tail of the loadout). **`charges_meter = false`**
  (player's call — the heal is the payoff, same reasoning already on record for Rallying Cry).
- **The item reel is NOT subject to the 5-reel loadout cap** (player's call) — staging an item
  always adds its reel regardless of how many weapon/ability reels are already loaded. `_strips_box`
  already lays out reel strips dynamically per `reels.size()` (`combat.gd:_prepare_strips`), so a
  turn temporarily showing 6 strips instead of 5 needs no layout change.
- **Critical Success = ×1.5 the potion's `heal_amount`**, rounded up (project-wide
  round-up-damage-and-healing convention, memory `round-up-damage-healing`). Plain Success = the
  base amount, unchanged.
- **Foresight/Regrowth are untouched.** They're abilities (not items) with their own
  `_lowest_hp_pct_ally()` auto-targeting, kept exactly as-is — this spec only changes the
  **item**-use path.
- **A full visual reel**, not a quiet/log-only resolution — a real `ReelStrip` scrolls and lands on
  Success/Crit-Success like every other reel, per the project's "the reel IS the dice, always
  visible" pillar.

## 3. Architecture

### 3.1 `ActionReel.make_item_use()` (new, `combat/resources/action_reel.gd`)

Mirrors `make_rallying_cry()`'s shape (a no-damage, no-fail, out-of-paylines utility reel) with a
different tier split:

```gdscript
## Builds the item-use reel (2026-07-16 combat item-use targeting design §2): a no-damage utility
## reel with NO failure tiers at all — a potion should never simply fail. 9 SUCCESS + 1 CRIT_SUCCESS
## (90%/10%). Every face has multiplier 0; the orchestrator reads the landed tier post-spin and
## applies the item's real effect (e.g. a heal, ×1.5 on crit) itself, same convention as
## make_rallying_cry(). is_weapon_attack = false (out of paylines); charges_meter = false (the item's
## effect IS the payoff — same reasoning already used for Rallying Cry).
static func make_item_use(type: DamageType = null) -> ActionReel:
    var reel: ActionReel = ActionReel.new()
    reel.damage_type = type
    reel.is_weapon_attack = false
    reel.charges_meter = false
    reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
    for i in range(9):
        reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
    reel.faces.shuffle()
    return reel
```

### 3.2 `Combatant` fields (`combat/combatant.gd`)

Replace today's `healing_potion_pending: bool` / `pending_heal_amount: int` with a shape that
mirrors `rallying_cry_reel` — the reel reference itself doubles as the "is something pending" flag,
so no separate boolean is needed:

```gdscript
## The reel recording an in-progress item use this turn (2026-07-16 design), or null if no item is
## staged. Mirrors rallying_cry_reel — its presence IS the "an item use is pending" signal.
var item_use_reel: ActionReel = null

## The staged item's un-multiplied heal amount, read alongside item_use_reel once the reel resolves.
var pending_item_base_heal: int = 0
```

`begin_turn()` resets both (`item_use_reel = null`, `pending_item_base_heal = 0`), same place
`rallying_cry_reel = null` is already reset.

### 3.3 `MainPhasePlan` (`combat/main_phase_plan.gd`)

`preview_reels()` — append the item-use reel whenever an item is staged, **unconditional on
`reel_cap`** (unlike every other reel-adding branch in this function):

```gdscript
if staged_item_type != &"":
    reels.append(ActionReel.make_item_use(combatant.weapon_type()))
```

`commit()` — replace the existing block (today at combat.gd's commit-time application — see §3.5
for what moves out of there) with reel-construction + bookkeeping only, no immediate heal:

```gdscript
if staged_item_type != &"" and party_inventory != null:
    var item: ConsumableItem = party_inventory.find_item(staged_item_type)
    if item != null:
        var reel: ActionReel = ActionReel.make_item_use(combatant.weapon_type())
        combatant.turn_reels.append(reel)
        combatant.item_use_reel = reel
        combatant.pending_item_base_heal = item.heal_amount
        party_inventory.consume_item(staged_item_type)
```

### 3.4 Ally targeting (`combat/combat.gd`)

New state, alongside the existing `_player_targets`/`_defender`:

```gdscript
var _ally_target: Combatant = null
```

New click-catchers over party-side panels, built from `_build_party_columns()` alongside the
existing `_build_target_click_catchers()` call:

```gdscript
## Mirrors _build_target_click_catchers() for the party side: clicking a living ally panel sets it
## as the acting combatant's item-use target (design §2/§3.4).
func _build_ally_target_click_catchers() -> void:
    for c: Combatant in _turn_manager.combatants:
        if not c.is_player or not _panels.has(c):
            continue
        var panel: CombatantPanel = _panels[c]
        var hit := Button.new()
        hit.flat = true
        hit.modulate = Color(1, 1, 1, 0)
        hit.position = panel.position
        hit.custom_minimum_size = Vector2(300, 278)
        hit.size = Vector2(300, 278)
        hit.tooltip_text = "Click to make %s the active ally's item-use target." % c.display_name
        hit.pressed.connect(_select_ally_target.bind(c))
        add_child(hit)

## Selects [param ally] as the ACTIVE combatant's item-use target — only during that combatant's own
## pre-spin window (mirrors _select_target). Independent of whether an item is currently staged.
func _select_ally_target(ally: Combatant) -> void:
    if ally == null or not ally.is_alive():
        return
    if not (_awaiting_player_spin and _attacker != null and _attacker.is_player):
        return
    _ally_target = ally
    _refresh_ally_target_highlight()

## Outlines the current ally-target panel (green) and clears the others. No-op (all clear) when
## _ally_target is null — the state during an enemy's turn.
func _refresh_ally_target_highlight() -> void:
    for c: Combatant in _turn_manager.combatants:
        if _panels.has(c):
            (_panels[c] as CombatantPanel).set_ally_targeted(c == _ally_target)
```

`_on_turn_started(c)` gains, alongside the existing enemy-target default logic:

```gdscript
if c.is_player:
    _ally_target = c
else:
    _ally_target = null
_refresh_ally_target_highlight()
```

(placed next to the existing `_refresh_target_highlight()` call in that function)

Both click-catcher builders are called from `_build_party_columns()`:

```gdscript
_build_target_click_catchers()
_build_ally_target_click_catchers()
```

### 3.5 Post-spin resolution (`combat/combat.gd`)

Remove the commit-time healing block (today's lines ~1391-1396, which applies the heal
immediately on Spin-press rather than after the reel resolves). Capture the item reel's landed tier
in the same pass that captures `_rallying_cry_tier` (~line 1522):

```gdscript
var _item_use_tier: int = -1   # new var alongside _rallying_cry_tier

...
_item_use_tier = -1
if _attacker.item_use_reel != null:
    var iu_idx: int = reels.find(_attacker.item_use_reel)
    if iu_idx >= 0 and iu_idx < attacks.size():
        _item_use_tier = attacks[iu_idx].face.result_tier
```

Apply the heal in the same pass that applies the Rallying Cry shield (~line 1832), reading
`_ally_target` instead of a lowest-HP% lookup:

```gdscript
if _attacker.item_use_reel != null and _item_use_tier != -1 and _ally_target != null and _ally_target.is_alive():
    var crit: bool = _item_use_tier == ReelFace.ResultTier.CRIT_SUCCESS
    var amount: int = ceili(_attacker.pending_item_base_heal * (1.5 if crit else 1.0))
    _ally_target.heal(amount)
    var tier_text: String = " — CRITICAL SUCCESS!" if crit else ""
    _log("  ✚ %s uses an item%s — %s heals %d HP (%d/%d)." % [_attacker.display_name, tier_text, _ally_target.display_name, amount, _ally_target.hp, _ally_target.max_hp])
    if _panels.has(_ally_target):
        (_panels[_ally_target] as CombatantPanel).refresh_status()
```

The `is_alive()` guard is defensive-only (§4 — nothing can kill an off-turn ally between selection
and resolution in this synchronous single-actor-per-turn flow), matching the same style of guard
already used for enemy-target validity.

### 3.6 `CombatantPanel.set_ally_targeted()` (new, `combat/ui/combatant_panel.gd`)

Same technique as the existing `set_targeted()`, a different border color so the two never look
alike even if (hypothetically) both were ever true on the same panel:

```gdscript
## Outlines this panel when it's the active combatant's item-use target (2026-07-16 design) — a
## green border, distinct from set_targeted()'s red enemy-target border. Also serves as a whose-
## turn-is-it indicator, since it defaults to (and is visible for the whole turn of) the active
## combatant.
func set_ally_targeted(on: bool) -> void:
    if on:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.12, 0.17, 0.12)
        sb.border_color = Color(0.4, 0.85, 0.4)
        sb.set_border_width_all(3)
        add_theme_stylebox_override("panel", sb)
    else:
        remove_theme_stylebox_override("panel")
```

### 3.7 `ItemMenuPanel` live description (`combat/ui/item_menu_panel.gd`)

`_build_row()`'s info label currently reads `"Heals the party's lowest-HP%% ally for %d HP."` —
replace with a target-aware description reflecting both the new targeting and the reel odds. This
needs the current `_ally_target`, so `open_for()` gains a parameter:

```gdscript
func open_for(plan: MainPhasePlan, inventory: PartyInventory, ally_target: Combatant) -> void:
    ...
    info.text = "Heals %s for %d HP (90%% success / 10%% critical success ×1.5)." % [ally_target.display_name if ally_target != null else "your target", item.heal_amount]
```

All three existing `_item_menu.open_for(_plan, _party_inventory)` call sites in `combat.gd`
(`_on_items_pressed` at line ~1191, the no-op re-render at line ~1205, and the "keep an open menu's
row states live" refresh inside `_on_phase_changed` at line ~1286) pass `_ally_target` as the third
argument. So the description stays live when the ally target changes, `_select_ally_target` (§3.4)
gets one more line at the end: `if _item_menu.visible: _item_menu.open_for(_plan, _party_inventory,
_ally_target)` — the same "re-render an open menu after a state change" convention the codebase
already uses for ability/ultimate staging.

## 4. Out of scope

- **Sub-project 2**: the out-of-combat `InventoryMenuPanel` Stats-tab item-use targeting flow
  (click a column to target, Confirm/Cancel, live description) — separate spec, built after this one.
- **Thrown items** and their own success/fail reel — explicitly raised and explicitly deferred by
  the player during brainstorming. Not designed, not stubbed.
- Any change to Foresight/Regrowth's existing `_lowest_hp_pct_ally()` auto-targeting.
- Any change to how abilities/Ultimates stage or resolve — only the item-staging path is reworked.
- A manual/debug way to fill the Bag to capacity for testing loot overflow — raised in the same
  conversation but is an unrelated, independent, much smaller piece with no dependency on anything
  in this spec. Handled as its own tiny separate addition, not part of this spec.
- Balancing `heal_amount`, the 90/10 split, or the ×1.5 multiplier — all `[ASSUMPTION]` per CLAUDE.md
  §4, tuned by playtest after the mechanic itself is confirmed working.

## 5. Testing plan

- **`tests/test_action_reel.gd` (extend)** — `make_item_use()` produces exactly 9 SUCCESS + 1
  CRIT_SUCCESS faces, every face multiplier 0.0, `is_weapon_attack == false`, `charges_meter == false`.
- **`tests/test_main_phase_plan.gd` (extend)** — staging an item appends the item-use reel to
  `preview_reels()` even when `combatant.turn_reels.size() >= reel_cap` (the one case exempt from
  the cap check every other reel-adding branch enforces); un-staging removes it from the preview;
  `commit()` sets `item_use_reel`/`pending_item_base_heal` and consumes exactly one unit of the item;
  `begin_turn()` resets both fields to null/0.
- **New `tests/test_item_use_heal.gd`** — pure formula test (no reel spin involved), mirroring
  `test_rallying_cry.gd`'s style: given a known tier, `ceili(base_heal * 1.5)` for CRIT_SUCCESS vs
  `base_heal` unchanged for SUCCESS, checked against concrete numbers.
- **New `tests/test_ally_targeting.gd`** — `_ally_target` defaults to the active combatant on
  `_on_turn_started` for a player-side turn, stays null on an enemy's turn; `_select_ally_target`
  only takes effect while `_awaiting_player_spin` on that combatant's own turn, rejects a dead or
  null ally, and is unaffected by whether an item is currently staged; a new turn resets the target
  regardless of what was previously selected.
- **`tests/test_combatant_panel.gd` (extend, or new coverage)** — `set_ally_targeted(true)` applies
  a stylebox override distinct from `set_targeted(true)`'s; `set_ally_targeted(false)` removes it.
- **End-to-end** (extends the existing combat-items-menu test coverage) — stage Healing Potion,
  retarget to a companion via the ally-target selection hook, spin with a forced/rigged item-use
  tier, confirm: (a) SUCCESS heals the companion for exactly `heal_amount`, (b) CRIT_SUCCESS heals
  for `ceili(heal_amount * 1.5)`, (c) the PC's own HP is unchanged in both cases, (d) the potion is
  consumed exactly once, (e) the log names the actual healed ally, not always the caster.
- **Existing test-name migration** — any existing test referencing `healing_potion_pending` or
  `pending_heal_amount` by name is updated to the new `item_use_reel`/`pending_item_base_heal` shape,
  not left referencing removed fields.

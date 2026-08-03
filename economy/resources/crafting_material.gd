class_name CraftingMaterial
extends Resource

## A stacking crafting material (design-bible 27-crafting.md §6/§11) — gathered from environmental
## nodes (Foraging/Fishing) or salvaged from Gear via Salvaging's Break Down (2026-08-02
## salvaging-and-cooking professions design, SalvageSystem.break_down()) into rarity-tagged Scrap.
## Stacking key is (material_type, rarity, quality_tier) — see PartyInventory.give_material().
##
## Named CraftingMaterial, not the shorter "Material" the design bible uses in prose — Godot 4 has
## a built-in engine class literally called `Material` (the shader/rendering base class), and
## `class_name Material` collides with it: `Material.new()` silently resolves to the ENGINE class
## instead of this script, so `.display_name`/`.material_type` assignments fail at runtime with a
## confusing "Invalid assignment ... on a base object of type 'Material'" error. Caught by this
## session's own test run, not by inspection.

@export var display_name: String = ""
@export var material_type: StringName = &""
@export var quantity: int = 1

## Set by a gathering mini-game's bonus outcome (2026-08-01 gathering-profession-minigames spec
## sections 2/3) -- 0 = no bonus. Undesigned content: nothing downstream interprets different
## nonzero values differently yet (mirrors how Combatant.loot_table shipped as a hook before real
## loot tables existed) -- that belongs to the deferred materials/items pass.
@export var quality_tier: int = 0

## Set by Salvaging (2026-08-02 salvaging-and-cooking professions design section 2.1) — mirrors the
## salvaged Gear's own rarity. Defaults COMMON so every pre-existing gathered material (which never
## sets this) is unaffected.
@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON

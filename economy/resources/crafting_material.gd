class_name CraftingMaterial
extends Resource

## A stacking crafting material (design-bible 27-crafting.md §6/§11) — gathered from environmental
## nodes (Foraging/Fishing) or, later, salvaged from Gear into typed Reel-Essence. Shape is
## deliberately minimal for the current playtest: a typed, stacking quantity, no rarity/affix data
## yet (that's the profession-mini-game-reel work, not designed/built — see §11).
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

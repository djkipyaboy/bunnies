class_name Weapon
extends Resource

## A weapon: the base damage and the Action-reel loadout it spins (DESIGN.md §8, §4.3).
## The reel count is the weapon's baseline band (2–5); Main-Phase abilities add/subtract from it
## (deferred for the prototype). Each reel carries its own damage type (see [ActionReel]).

## Base damage each landed reel multiplies by its face multiplier (DESIGN.md §4.5).
@export var base_damage: float = 1.0

## The Action reels this weapon spins in the Combat Phase. Size = the baseline reel band (2–5).
@export var reels: Array[ActionReel] = []

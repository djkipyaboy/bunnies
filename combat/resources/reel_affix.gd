class_name ReelAffix
extends Resource

## A reel-editing affix an equipped item can carry (spec 2026-07-10 §3.3). Shape only this pass —
## no resolver wiring, since no items are authored yet (loot tables are explicitly deferred).

enum Kind { ADD_FACE, ADD_REEL, TIER_BIAS }

@export var kind: Kind = Kind.ADD_FACE
@export var damage_type_id: StringName = &""                                    # ADD_FACE / ADD_REEL
@export var result_tier: ReelFace.ResultTier = ReelFace.ResultTier.SUCCESS       # ADD_FACE
@export var multiplier: float = 1.0                                             # ADD_FACE
@export var bias_pct: float = 0.0                                               # TIER_BIAS

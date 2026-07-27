class_name ConsumableEffects
extends RefCounted

## Static-only dispatch for ConsumableItem.effect_type (2026-07-26 out-of-combat item-use design §3),
## mirroring the TypeVisuals/RarityVisuals convention — no instance state, pure functions. Only
## "heal" is implemented; a second effect_type (cleanse, buff, ...) adds one more match branch to
## both functions below, no other code needs to change. This is deliberately separate from combat's
## own item-reel resolution (ItemMenuPanel/MainPhasePlan), which stays heal-specific until a real
## second in-combat effect type is needed.

## Applies [param item]'s effect to [param target] and returns a player-facing result string.
## Out-of-combat item use is flat/deterministic — no reel, no crit/fail roll (unlike combat's 90/10
## Item Reel), consistent with the Old Well's no-RNG convention for non-combat actions.
static func apply(item: ConsumableItem, target: Combatant) -> String:
	match item.effect_type:
		&"heal":
			target.heal(item.heal_amount)
			return "Healed %s for %d HP." % [target.display_name, item.heal_amount]
		_:
			return "Nothing happens."

## Whether [param item]'s effect would actually do anything to [param target] — used to warn the
## player and block Confirm before a wasted, zero-effect use (2026-07-26 no-effect-warning design).
## A second effect_type adds its own branch here alongside apply()/description(); an unrecognized
## effect_type is conservatively false (can't be proven to do anything).
static func has_effect(item: ConsumableItem, target: Combatant) -> bool:
	match item.effect_type:
		&"heal":
			return target != null and target.hp > 0 and target.hp < target.max_hp
		_:
			return false

## The live "what will this do" text shown while targeting, before Confirm is pressed. [param target]
## may be null (no target picked yet) — falls back to a generic phrase, mirroring ItemMenuPanel's
## existing null-ally_target convention.
static func description(item: ConsumableItem, target: Combatant) -> String:
	var target_name: String = target.display_name if target != null else "your target"
	match item.effect_type:
		&"heal":
			return "Heals %s for %d HP." % [target_name, item.heal_amount]
		_:
			return "Unknown effect."

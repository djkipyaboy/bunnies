extends SceneTree

## ConsumableItem's effect_type field (2026-07-26 out-of-combat item-use design §3) — the field
## that lets ConsumableEffects dispatch on effect kind. Defaults to &"heal" so every pre-existing
## caller (ItemMenuPanel, MainPhasePlan) that never sets it keeps working unchanged.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var item: ConsumableItem = ConsumableItem.new()
	_check(item.effect_type == &"heal", "effect_type defaults to &\"heal\"")

	item.effect_type = &"cleanse"
	_check(item.effect_type == &"cleanse", "effect_type is settable")

	quit()

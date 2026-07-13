extends SceneTree

## EncounterOption: pure bucket-classification + per-outcome text/delta lookups (player direction
## 2026-07-12, "?" random encounters). No CombatHandoff/tree dependency — runs entirely in _init().

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_check(EncounterOption.bucket_for(ReelFace.ResultTier.CRIT_FAILURE) == EncounterOption.Outcome.BAD, "CRIT_FAILURE buckets to BAD")
	_check(EncounterOption.bucket_for(ReelFace.ResultTier.FAILURE) == EncounterOption.Outcome.BAD, "FAILURE buckets to BAD")
	_check(EncounterOption.bucket_for(ReelFace.ResultTier.NEUTRAL) == EncounterOption.Outcome.NEUTRAL, "NEUTRAL buckets to NEUTRAL")
	_check(EncounterOption.bucket_for(ReelFace.ResultTier.SUCCESS) == EncounterOption.Outcome.GOOD, "SUCCESS buckets to GOOD")
	_check(EncounterOption.bucket_for(ReelFace.ResultTier.CRIT_SUCCESS) == EncounterOption.Outcome.GOOD, "CRIT_SUCCESS buckets to GOOD")

	var o: EncounterOption = EncounterOption.new()
	o.bad_text = "bad"; o.neutral_text = "neutral"; o.good_text = "good"
	o.bad_gold_delta = -10; o.neutral_gold_delta = -1; o.good_gold_delta = 15
	o.bad_hp_delta = -20; o.neutral_hp_delta = -5; o.good_hp_delta = 0

	_check(o.text_for(EncounterOption.Outcome.BAD) == "bad", "text_for(BAD) reads bad_text")
	_check(o.text_for(EncounterOption.Outcome.NEUTRAL) == "neutral", "text_for(NEUTRAL) reads neutral_text")
	_check(o.text_for(EncounterOption.Outcome.GOOD) == "good", "text_for(GOOD) reads good_text")

	_check(o.gold_delta_for(EncounterOption.Outcome.BAD) == -10, "gold_delta_for(BAD) reads bad_gold_delta")
	_check(o.gold_delta_for(EncounterOption.Outcome.NEUTRAL) == -1, "gold_delta_for(NEUTRAL) reads neutral_gold_delta")
	_check(o.gold_delta_for(EncounterOption.Outcome.GOOD) == 15, "gold_delta_for(GOOD) reads good_gold_delta")

	_check(o.hp_delta_for(EncounterOption.Outcome.BAD) == -20, "hp_delta_for(BAD) reads bad_hp_delta")
	_check(o.hp_delta_for(EncounterOption.Outcome.NEUTRAL) == -5, "hp_delta_for(NEUTRAL) reads neutral_hp_delta")
	_check(o.hp_delta_for(EncounterOption.Outcome.GOOD) == 0, "hp_delta_for(GOOD) reads good_hp_delta")

	quit()

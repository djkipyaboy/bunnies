extends SceneTree

## Beneficial-DoT data + math (spec 2026-07-01, task 26). Task 26 adds a beneficial branch to
## combat.gd's shared _apply_dot(): a DAMAGE_OVER_TIME effect flagged beneficial HEALS its bearer
## (via Combatant.heal) instead of damaging it (via take_damage) — building the plumbing Task 27's
## Warden Regrowth (&"regen") will consume.
##
## The _apply_dot BRANCHING itself is orchestrator-level: it lives in combat.gd and needs the running
## Combat scene's _panels dictionary (refresh_status), so it is NOT headlessly testable here —
## consistent with prior tasks' precedent (e.g. test_crippling_shot's combat.gd bonus-damage note).
## What CAN be tested headlessly, and is covered below: the DATA property Effect.beneficial for the two
## DoTs this plan uses (&"cursed" harmful, &"regen" beneficial), the shared dot_damage() amount math on
## Effect itself, and that Combatant.heal() applies that amount (the branch's beneficial payload).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# --- Data property: &"cursed" (Hex's rider) is a harmful DoT ---
	var cursed: Effect = EffectLibrary.make(&"cursed")
	_check(cursed != null and cursed.kind == Effect.Kind.DAMAGE_OVER_TIME, "cursed is a DAMAGE_OVER_TIME effect")
	_check(cursed.beneficial == false, "cursed is a debuff (beneficial == false → _apply_dot damages)")

	# --- Data property: &"regen" (Task 27's Regrowth rider, already authored in Task 7) is beneficial ---
	var regen: Effect = EffectLibrary.make(&"regen")
	_check(regen != null and regen.kind == Effect.Kind.DAMAGE_OVER_TIME, "regen is a DAMAGE_OVER_TIME effect")
	_check(regen.beneficial == true, "regen is a buff (beneficial == true → _apply_dot heals)")

	# --- Shared dot_damage() amount math (the value _apply_dot feeds to take_damage/heal) ---
	# Both cursed and regen use the 50/80/115% fractions, rounding UP (project convention).
	cursed.dot_base_damage = 8.0
	cursed.stacks = 1
	_check(cursed.dot_damage() == 4, "cursed 1 stack @ base 8 = ceil(4.0) = 4 (got %d)" % cursed.dot_damage())
	cursed.stacks = 3
	_check(cursed.dot_damage() == 10, "cursed 3 stacks @ base 8 = ceil(9.2) = 10 (got %d)" % cursed.dot_damage())

	regen.dot_base_damage = 10.0
	regen.stacks = 1
	_check(regen.dot_damage() == 5, "regen 1 stack @ base 10 = ceil(5.0) = 5 (got %d)" % regen.dot_damage())
	regen.stacks = 2
	_check(regen.dot_damage() == 8, "regen 2 stacks @ base 10 = ceil(8.0) = 8 (got %d)" % regen.dot_damage())

	# --- Beneficial payload: Combatant.heal() applies the DoT amount (the branch's action) ---
	# Mirror _apply_dot's beneficial branch (c.heal(amount)) on a wounded combatant to confirm the
	# amount the orchestrator would compute actually restores HP up to max_hp (heal clamps + returns overflow).
	var c: Combatant = Combatant.new()
	c.max_hp = 100
	c.hp = 90
	var healed_amount: int = regen.dot_damage()  # regen still at 2 stacks / base 10 = 8
	var overflow: int = c.heal(healed_amount)
	_check(c.hp == 98, "heal(8) on 90/100 → hp 98 (got %d)" % c.hp)
	_check(overflow == 0, "heal(8) on 90/100 has no overflow (got %d)" % overflow)
	# Overflow path (Big-Bang-style clamp) — a beneficial tick past max returns the excess.
	c.hp = 98
	var overflow2: int = c.heal(10)
	_check(c.hp == 100, "heal(10) on 98/100 clamps hp to max 100 (got %d)" % c.hp)
	_check(overflow2 == 8, "heal(10) on 98/100 returns 8 overflow (got %d)" % overflow2)

	print(("DOT-BENEFICIAL TEST PASSED" if _failures == 0 else "DOT-BENEFICIAL TEST FAILED: %d" % _failures))
	quit(_failures)

# Harvester Reflavor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the Summoner class to Harvester, retune its weapon (Warden's Staff → Scythe,
`weapon_base_damage` 6.0 → 14.0), and reflavor its 4 minions and Ultimate with plant/nature-spirit
names — closing out every "placeholder — naming still open" flag left by the 2026-08-16
minion-summoning-class work.

**Architecture:** This is a display-string and single-numeric-constant change, no mechanism
changes. Three independent edit sites in the codebase (`combat/class_library.gd`,
`combat/minion_library.gd` + `combat/ui/ability_catalog.gd` together, `combat/ui/ultimate_catalog.gd`),
each with its own existing test file to update. `class_id`, `minion_type`, and every ability/
Ultimate StringName id (`&"summoner"`, `&"ember"`, `&"ember_minion"`, `&"grand_sacrifice"`, etc.)
are internal keys and stay unchanged — only what a player actually reads changes.

**Tech Stack:** Godot 4.6.3-stable, GDScript. Tests run headless via
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/<file>.gd` from
the `bunnies/` directory (the exe lives one directory above the repo, per CLAUDE.md). A test file
prints `<NAME> TEST PASSED` or `<NAME> TEST FAILED: N` and pushes a `push_error` per failed
assertion — grep the output for `FAIL` or `SCRIPT ERROR`, don't trust exit codes alone (this
project has known exit-code-blind test files).

**Spec:** `docs/superpowers/specs/2026-08-23-harvester-reflavor-design.md`

## Global Constraints

- `class_id`, `minion_type` StringName keys, and ability/Ultimate StringName ids are **never**
  renamed — only `display_name`/`description` string literals change (spec §1, §3, §4, Open
  Questions).
- Damage type stays `earth` — do not add a new damage type (spec §5).
- No mechanism/behavior changes — minion stage effects, costs, cooldowns, the summon-reel
  mechanism, and the meter economy are all unchanged (spec intro).
- `weapon_base_damage` for `&"summoner"` changes from `6.0` to exactly `14.0`; `reel_count` stays
  `2` (spec §2).

---

### Task 1: Harvester class identity — rename + Scythe weapon retune

**Files:**
- Modify: `combat/class_library.gd:203-207`
- Modify: `tests/test_summoner_class.gd`

**Interfaces:**
- Consumes: nothing new — `CharacterClass.display_name`, `weapon_display_name`,
  `weapon_base_damage`, `reel_count` are all existing `CharacterClass` fields.
- Produces: `ClassLibrary.make(&"summoner").display_name == "Harvester"`,
  `.weapon_display_name == "Scythe"`, `.weapon_base_damage == 14.0` — later tasks don't depend on
  these values, but keep them consistent with the spec table if referenced.

- [ ] **Step 1: Write the failing assertions**

Add to the end of `tests/test_summoner_class.gd`, just before the final `print(...)`/`quit(...)`
lines (i.e. after the existing `hasty` block, before line 43):

```gdscript
	_check(cls.display_name == "Harvester", "summoner class display_name is now Harvester (got %s)" % cls.display_name)
	_check(cls.weapon_display_name == "Scythe", "summoner weapon_display_name is now Scythe (got %s)" % cls.weapon_display_name)
	_check(is_equal_approx(cls.weapon_base_damage, 14.0), "summoner weapon_base_damage retuned to 14.0 (got %f)" % cls.weapon_base_damage)
	_check(cls.reel_count == 2, "summoner keeps its 2-reel baseline (got %d)" % cls.reel_count)
```

- [ ] **Step 2: Run it to verify it fails**

Run from `bunnies/`:
```
"../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_summoner_class.gd
```
Expected: `FAIL` lines for the 2 renamed-string checks and the damage check (reel_count check
passes already, since that's unchanged).

- [ ] **Step 3: Apply the rename + retune**

In `combat/class_library.gd`, replace:
```gdscript
			c.class_id = &"summoner"
			c.display_name = "Summoner"   # placeholder — naming still open
			c.base_stats = _stats(0, 1, 2, 5, 1, 0)
			c.weapon_base_damage = 6.0; c.weapon_type = earth; c.reel_count = 2
			c.weapon_display_name = "Warden's Staff"
```
with:
```gdscript
			c.class_id = &"summoner"
			c.display_name = "Harvester"
			c.base_stats = _stats(0, 1, 2, 5, 1, 0)
			# Retuned from 6.0 (2026-08-24 harvester-reflavor spec §2) — the old value was under
			# half the expected dmg/turn of every other class's weapon, including the other two
			# 2-reel "heavy hitters" (Vanguard 18.0, Seer 15.6 expected dmg/turn). 14.0 lands this
			# class at ~16.8 expected dmg/turn, in line with its peers.
			c.weapon_base_damage = 14.0; c.weapon_type = earth; c.reel_count = 2
			c.weapon_display_name = "Scythe"
```
(`class_id` stays `&"summoner"` — spec Open Questions: internal key, no player-facing surface.)

- [ ] **Step 4: Run it to verify it passes**

Run the same command as Step 2. Expected: `SUMMONER CLASS TEST PASSED`.

- [ ] **Step 5: Commit**

```bash
git add combat/class_library.gd tests/test_summoner_class.gd
git commit -m "feat(harvester): rename Summoner->Harvester, retune weapon to Scythe (14.0 dmg)"
```

---

### Task 2: Plant minion names (minion nameplate + ability menu copy)

Two places show a minion's name to the player: the minion's own on-panel nameplate
(`MinionLibrary.DISPLAY_NAMES`, set on the `Combatant` when summoned) and the ability button that
summons it (`AbilityCatalog.display_name()`/`description()` for the 4 `*_minion` ability ids).
Both must change together so a player never sees two different names for the same minion.

**Files:**
- Modify: `combat/minion_library.gd:18-23`
- Modify: `combat/ui/ability_catalog.gd:21-24` (display_name) and `:73-76` (description)
- Modify: `tests/test_minion_library.gd:26,31,35,41`

**Interfaces:**
- Consumes: `MinionLibrary.DISPLAY_NAMES: Dictionary` (existing), `AbilityCatalog.display_name(id)`/
  `description(id)` (existing static functions, unchanged signatures).
- Produces: `MinionLibrary.make(false, &"dew").display_name == "Lotus"` (and equivalent for the
  other 3 types) — no later task depends on this.

- [ ] **Step 1: Write the failing assertions**

In `tests/test_minion_library.gd`, replace the 4 display-name assertions:
```gdscript
	_check(dew.display_name == "Dew Minion", "dew minion display name is 'Dew Minion' (got %s)" % dew.display_name)
```
→
```gdscript
	_check(dew.display_name == "Lotus", "dew minion display name is now 'Lotus' (got %s)" % dew.display_name)
```
```gdscript
	_check(misfortune.display_name == "Misfortune Minion", "misfortune display name correct (got %s)" % misfortune.display_name)
```
→
```gdscript
	_check(misfortune.display_name == "Nightshade", "misfortune minion display name is now 'Nightshade' (got %s)" % misfortune.display_name)
```
```gdscript
	_check(hasty.display_name == "Hasty Minion", "hasty display name correct (got %s)" % hasty.display_name)
```
→
```gdscript
	_check(hasty.display_name == "Wheat", "hasty minion display name is now 'Wheat' (got %s)" % hasty.display_name)
```
```gdscript
	_check(default_call.display_name == "Ember Minion", "default-call display name unchanged (got %s)" % default_call.display_name)
```
→
```gdscript
	_check(default_call.display_name == "Touch-Me-Not", "default-call (ember) display name is now 'Touch-Me-Not' (got %s)" % default_call.display_name)
```

- [ ] **Step 2: Run it to verify it fails**

```
"../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_minion_library.gd
```
Expected: 4 `FAIL` lines, one per renamed assertion.

- [ ] **Step 3: Apply the minion nameplate rename**

In `combat/minion_library.gd`, replace:
```gdscript
const DISPLAY_NAMES: Dictionary = {
	&"ember": "Ember Minion",
	&"dew": "Dew Minion",
	&"misfortune": "Misfortune Minion",
	&"hasty": "Hasty Minion",
}
```
with:
```gdscript
const DISPLAY_NAMES: Dictionary = {
	&"ember": "Touch-Me-Not",
	&"dew": "Lotus",
	&"misfortune": "Nightshade",
	&"hasty": "Wheat",
}
```
(Update the `## Display name per minion type.` doc comment immediately above if it quotes the old
names literally — it currently doesn't, so no change needed there.)

- [ ] **Step 4: Apply the ability-menu copy rename**

In `combat/ui/ability_catalog.gd`, in `display_name()`, replace:
```gdscript
		&"ember_minion": return "Ember Minion"
		&"dew_minion": return "Dew Minion"
		&"misfortune_minion": return "Misfortune Minion"
		&"hasty_minion": return "Hasty Minion"
```
with:
```gdscript
		&"ember_minion": return "Touch-Me-Not"
		&"dew_minion": return "Lotus"
		&"misfortune_minion": return "Nightshade"
		&"hasty_minion": return "Wheat"
```

In `description()`, replace:
```gdscript
		&"ember_minion": return "Summon a minion that pulses AoE damage, escalating each round it survives."
		&"dew_minion": return "Summon a minion that heals the party, cleansing the oldest debuff and granting Thorns as it escalates."
		&"misfortune_minion": return "Summon a minion that debuffs every enemy, escalating from Weakened to Weakened+Sundered to a Curse."
		&"hasty_minion": return "Summon a minion that hastens the party, escalating from +20 Initiative to also granting resource regen to also granting Empowered and an extra reel."
```
with:
```gdscript
		&"ember_minion": return "Summon a Touch-Me-Not that pulses AoE damage, escalating each round it survives."
		&"dew_minion": return "Summon a Lotus that heals the party, cleansing the oldest debuff and granting Thorns as it escalates."
		&"misfortune_minion": return "Summon a Nightshade that debuffs every enemy, escalating from Weakened to Weakened+Sundered to a Curse."
		&"hasty_minion": return "Summon Wheat that hastens the party, escalating from +20 Initiative to also granting resource regen to also granting Empowered and an extra reel."
```

- [ ] **Step 5: Run it to verify it passes**

```
"../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_minion_library.gd
```
Expected: `MINION LIBRARY TEST PASSED`.

Also run the ability-catalog completeness test as a regression check (it asserts every ability id
has a non-empty display_name/description — content changes shouldn't break it, but confirm):
```
"../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ability_catalog.gd
```
Expected: no `FAIL`/`SCRIPT ERROR` lines.

- [ ] **Step 6: Commit**

```bash
git add combat/minion_library.gd combat/ui/ability_catalog.gd tests/test_minion_library.gd
git commit -m "feat(harvester): rename the 4 minions to their plant identities"
```

---

### Task 3: Strawfellow's Due (Grand Sacrifice rename)

**Files:**
- Modify: `combat/ui/ultimate_catalog.gd:20,33`

**Interfaces:**
- Consumes: `UltimateCatalog.display_name(id)`/`description(id)` (existing static functions).
- Produces: `UltimateCatalog.display_name(&"grand_sacrifice")` now contains "STRAWFELLOW'S DUE"
  instead of "GRAND SACRIFICE". Nothing else depends on this string's exact contents (confirmed —
  no test in `tests/test_grand_sacrifice.gd` or `tests/test_summoner_meter_economy.gd` asserts on
  this catalog string, only on the ability id `&"grand_sacrifice"` and the
  `Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS` constant, both unchanged).

There's no existing test asserting this exact string, so this task is verified by manual read +
the full regression sweep in Task 4 rather than its own red/green cycle — still write the change
as its own commit since it's an independently reviewable, self-contained edit.

- [ ] **Step 1: Apply the rename**

In `combat/ui/ultimate_catalog.gd`, in `display_name()`, replace:
```gdscript
		&"grand_sacrifice": return "GRAND SACRIFICE (sacrifice your minion)"
```
with:
```gdscript
		&"grand_sacrifice": return "STRAWFELLOW'S DUE (sacrifice your minion)"
```

In `description()`, replace:
```gdscript
		&"grand_sacrifice": return "Grand Sacrifice (full meter, requires an active minion): sacrifices your minion for an effect that depends on its type — Ember bursts + splashes the enemies, Dew heals the party and grants Thorns + a repeating cleanse, Misfortune curses every enemy, Hasty hastens the whole party."
```
with:
```gdscript
		&"grand_sacrifice": return "Strawfellow's Due (full meter, requires an active minion): sacrifices your minion for an effect that depends on its type — Touch-Me-Not bursts + splashes the enemies, Lotus heals the party and grants Thorns + a repeating cleanse, Nightshade curses every enemy, Wheat hastens the whole party."
```

- [ ] **Step 2: Manually verify via the character-creation class-info panel**

`UltimateCatalog` is shared by `combat.gd` and the character-creation screen's class-info panel
(per its own header comment). Run the game (`../Godot_v4.6.3-stable_win64.exe --path .` from
`bunnies/`), start a New Game, and check the Harvester's class-info panel shows "STRAWFELLOW'S DUE"
for its Ultimate. This is a player-facing UI string with no existing automated assertion — eyeball
it once rather than skip verification entirely.

- [ ] **Step 3: Commit**

```bash
git add combat/ui/ultimate_catalog.gd
git commit -m "feat(harvester): rename Grand Sacrifice to Strawfellow's Due"
```

---

### Task 4: Full regression sweep

**Files:** none (verification only)

- [ ] **Step 1: Re-run every test touched by this plan**

```bash
for f in test_summoner_class test_minion_library test_ability_catalog test_grand_sacrifice test_summoner_meter_economy test_dew_minion test_misfortune_minion test_hasty_minion test_minion_lifecycle; do
  echo "=== $f ==="
  "../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://tests/$f.gd" 2>&1 | grep -iE "FAIL|SCRIPT ERROR|TEST PASSED"
done
```
Expected: every file prints its own `... TEST PASSED` line and zero `FAIL`/`SCRIPT ERROR` lines.
These 9 files are exactly the ones that reference the renamed strings/ids from Tasks 1-3 (via
`Grep` during planning) — a clean sweep here means nothing outside this plan's edits broke.

- [ ] **Step 2: Grep for any remaining old display strings**

```bash
grep -rn '"Summoner"\|Warden'"'"'s Staff\|Ember Minion\|Dew Minion\|Misfortune Minion\|Hasty Minion\|GRAND SACRIFICE\|Grand Sacrifice' combat/ tests/
```
Expected: no matches in `combat/` (only historical references in `docs/superpowers/plans/` and
`docs/superpowers/specs/` are acceptable — those are dated design history, not live code, and are
never edited retroactively).

- [ ] **Step 3: No commit needed for this task** (verification only — if Step 1 or 2 surfaces a
miss, fix it as part of the task that should have caught it, and re-run this sweep).

---

### Task 5 (added during execution — ruling, see SDD ledger): combat.gd player-facing log-line rename

**Why this exists:** Task 4's grep sweep surfaced 13 `_log()` calls in `combat/combat.gd` that
narrate combat events into the player-facing Event Log using the OLD minion/Ultimate names — a
real gap the original plan's file list missed (it only covered the ability/minion catalog files,
not combat.gd's own hardcoded log narration). This is genuinely player-visible text (the project
has a persistent, always-open Event Log), so it must match the renamed catalog entries. Ember's own
stage-effect log (`combat.gd:898`) already reads `minion.display_name` dynamically and needs no
change — it automatically picked up "Touch-Me-Not" from Task 2's `DISPLAY_NAMES` rename. Only the
13 lines below, which hardcode a literal old name string, need editing.

**Files:**
- Modify: `combat/combat.gd` (13 line-level string edits, listed below)

**Interfaces:** none — pure string-literal edits inside existing `_log()` calls, no signature or
behavior changes.

No existing test asserts on this exact log text (confirmed via
`grep -rn "Dew Minion cleanses\|Dew Minion wraps\|Dew Minion (stage\|Misfortune Minion (stage\|Hasty Minion grants\|Hasty Minion (stage\|Grand Sacrifice (Ember)\|Grand Sacrifice (Dew)\|Grand Sacrifice (Misfortune)\|Grand Sacrifice (Hasty)\|Grand Sacrifice's repeating cleanse\|Grand Sacrifice's consumption bonus" tests/`
— zero matches), so there is no red/green cycle for this task. Verify instead by re-running the 5
tests that exercise these exact code paths and confirming they still pass (format-string argument
counts are unchanged, only literal words inside the strings change).

- [ ] **Step 1: Apply the 13 line edits**

In `combat/combat.gd`, make these exact replacements (old → new), each a same-line literal-text
swap with no other changes to the line:

```gdscript
_log("  💧 Dew Minion cleanses %s's %s." % [ally.display_name, String(cleansed.id).to_upper()])
```
→
```gdscript
_log("  💧 Lotus cleanses %s's %s." % [ally.display_name, String(cleansed.id).to_upper()])
```

```gdscript
_log("  🛡 Dew Minion wraps %s in Thorns (%d%% reflected, %d turns)." % [ally.display_name, roundi(DEW_THORNS_PCT * 100), DEW_THORNS_TURNS])
```
→
```gdscript
_log("  🛡 Lotus wraps %s in Thorns (%d%% reflected, %d turns)." % [ally.display_name, roundi(DEW_THORNS_PCT * 100), DEW_THORNS_TURNS])
```

```gdscript
_log("  💧 Dew Minion (stage %d) heals the party for %d." % [stage, heal_amount])
```
→
```gdscript
_log("  💧 Lotus (stage %d) heals the party for %d." % [stage, heal_amount])
```

```gdscript
_log("  🌑 Misfortune Minion (stage %d) afflicts every enemy." % stage)
```
→
```gdscript
_log("  🌑 Nightshade (stage %d) afflicts every enemy." % stage)
```

```gdscript
_log("  💨 Hasty Minion grants %s +%d resource regen (%d turns)." % [ally.display_name, HASTY_REGEN_BONUS, HASTY_REGEN_TURNS])
```
→
```gdscript
_log("  💨 Wheat grants %s +%d resource regen (%d turns)." % [ally.display_name, HASTY_REGEN_BONUS, HASTY_REGEN_TURNS])
```

```gdscript
_log("  💨 Hasty Minion (stage %d) buffs the party." % stage)
```
→
```gdscript
_log("  💨 Wheat (stage %d) buffs the party." % stage)
```

```gdscript
_log("  🔥 Grand Sacrifice (Ember): %d burst damage, splashed to %d other enemies." % [GRAND_SACRIFICE_EMBER_BURST, splashed.size()])
```
→
```gdscript
_log("  🔥 Strawfellow's Due (Touch-Me-Not): %d burst damage, splashed to %d other enemies." % [GRAND_SACRIFICE_EMBER_BURST, splashed.size()])
```

```gdscript
_log("  🔥 Grand Sacrifice (Ember) whiffs: no living enemy to burst.")
```
→
```gdscript
_log("  🔥 Strawfellow's Due (Touch-Me-Not) whiffs: no living enemy to burst.")
```

```gdscript
_log("  💧 Grand Sacrifice (Dew): large party heal + improved Thorns + repeating cleanse.")
```
→
```gdscript
_log("  💧 Strawfellow's Due (Lotus): large party heal + improved Thorns + repeating cleanse.")
```

```gdscript
_log("  🌑 Grand Sacrifice (Misfortune): Jinxed + improved Curse on every enemy.")
```
→
```gdscript
_log("  🌑 Strawfellow's Due (Nightshade): Jinxed + improved Curse on every enemy.")
```

```gdscript
_log("  💨 Grand Sacrifice (Hasty): party-wide regen + Empowered + reel surge, 2 turns.")
```
→
```gdscript
_log("  💨 Strawfellow's Due (Wheat): party-wide regen + Empowered + reel surge, 2 turns.")
```

```gdscript
_log("  💧 Grand Sacrifice's repeating cleanse removes %s's %s." % [c.display_name, String(cleansed.id).to_upper()])
```
→
```gdscript
_log("  💧 Strawfellow's Due's repeating cleanse removes %s's %s." % [c.display_name, String(cleansed.id).to_upper()])
```

```gdscript
_log("    BM +%d  (%d/%d)  — Grand Sacrifice's consumption bonus" % [Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
```
→
```gdscript
_log("    BM +%d  (%d/%d)  — Strawfellow's Due's consumption bonus" % [Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
```

**Explicitly out of scope for this task:** do NOT touch `combat.gd:898`'s Ember stage log (already
dynamic via `minion.display_name`, needs no change), do NOT touch any `##`/`#` doc-comment
referencing the old names (comments are not player-facing — e.g. `combat.gd:889`, `:900`, `:932`,
`:954`, `:1004`, `:1921`, `:2407`, `combat/combatant.gd`'s many doc comments, `combat/main_phase_plan.gd`'s
comments, `combat/resources/effect.gd`'s comments — all fine as historical/internal references,
consistent with how Tasks 1-3 treated comments), and do NOT rename any `&"..."` StringName id or
constant name (e.g. `GRAND_SACRIFICE_EMBER_BURST`, `DEW_THORNS_PCT` stay as-is — only the quoted
log-message text changes).

- [ ] **Step 2: Run the 5 tests that exercise these code paths**

From `bunnies/`:
```
"../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_dew_minion.gd
"../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_misfortune_minion.gd
"../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_hasty_minion.gd
"../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_grand_sacrifice.gd
"../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_summoner_meter_economy.gd
```
Expected: all 5 print their own `... TEST PASSED` line, no `FAIL`/`SCRIPT ERROR`. None of these
tests assert on the exact log text, so this is a plain regression check, not a red/green cycle.

- [ ] **Step 3: Grep to confirm no old names remain in combat.gd's log strings**

```bash
grep -n '_log(' combat/combat.gd | grep -E "Dew Minion|Misfortune Minion|Hasty Minion|Grand Sacrifice \(|Grand Sacrifice's"
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add combat/combat.gd
git commit -m "fix(harvester): rename player-facing combat-log lines to match the renamed minions/Ultimate"
```

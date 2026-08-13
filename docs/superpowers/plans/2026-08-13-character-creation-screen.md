# Character Creation Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pre-story `CharacterCreationScreen` — Species → Class (tentative) → Background
→ Name, with free back/forth navigation, a live reel-preview panel, and a `Finalize` step that
builds a real player `Combatant` and emits it via signal — plus the two new placeholder-content
resource types (`Heritage`, `Background`) it draws from.

**Architecture:** `CharacterCreationScreen` (a `Control`-rooted scene, content built entirely in
code per this project's existing panel convention) owns a `CharacterCreationDraft` (plain
`RefCounted`, not persisted) and swaps visibility among four child step `Control`s
(`SpeciesStep`/`ClassStep`/`BackgroundStep`/`NameStep`), each a thin button-list or `LineEdit`
wrapper emitting a `selected`/`name_changed` signal. A persistent `ReelPreviewPanel` re-renders on
every draft change. `Heritage`/`Background` are new `Resource` subclasses with code-registry
factories (`HeritageLibrary`/`BackgroundLibrary`), mirroring the existing `ClassLibrary` pattern
exactly. `Finalize` calls `ClassLibrary.make(draft.class_id).build_combatant(true)`, then layers the
chosen `Heritage`'s passive onto `base_stats` and the chosen `Background`'s signature `ReelFace`
onto the starting weapon's first reel, before emitting `character_created(pc)`.

**Tech Stack:** Godot 4.6 / GDScript, headless test suite
(`Godot_v4.6.3-stable_win64_console.exe --headless --path <repo> --script res://tests/test_<name>.gd`).

**Spec:** `docs/superpowers/specs/2026-08-13-character-creation-design.md`

## Global Constraints

- GDScript only, static typing throughout (typed vars/params/returns) — CLAUDE.md §2.
- `PascalCase` classes, `snake_case` script files/methods — CLAUDE.md §2.
- No placeholder/TBD code; every step below is complete, runnable GDScript.
- Species list is locked to the First 9 (Hare/Otter/Badger/Mouse/Frog/Turtle/Fox/Weasel/Wildcat) —
  `docs/design-bible/10-storyline.md` §6. All 9 must be selectable; only passive *values* are
  `[ASSUMPTION]` placeholders.
- Background list is NOT locked — only 2 placeholder entries are authored in this plan, enough to
  prove the pipeline (spec, Scope section).
- Step order is fixed: Species → Class → Background → Name. Free back/forth navigation between
  already-reached steps (spec, "Navigation & validation").
- Name validation: max 20 characters; letters/spaces/apostrophes/hyphens only (spec, "Name
  validation").
- Placeholder visuals throughout (plain `Button`/`Label` controls, no art assets) — spec, Scope.
- Class pick made here is TENTATIVE — this plan only reserves `Combatant.class_is_locked: bool`
  for a future Class Trial & Lock-In spec; it does not implement that mechanic.
- The Godot executable lives ONE DIRECTORY ABOVE this repo:
  `C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe` (repo root is
  `C:/bunnies/bunnies-main/bunnies`). Run tests with:
  `"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_<name>.gd`
  Exit code `0` = pass. Harmless `RID allocations leaked` / `ObjectDB instances leaked` warnings at
  process exit are pre-existing noise in this project's headless runs, not failures.
- Never delete `.godot/` to troubleshoot a test failure (gitignored, but wipes the project-wide
  `class_name` registry). If a new `class_name` can't be resolved by `--script`, refresh it with:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
- Stage and commit only the files each task actually touches — this repo currently has several
  unrelated pre-existing untracked files sitting in the working tree; do not sweep them into a
  commit with a broad `git add`.

---

### Task 1: `Heritage` resource + `HeritageLibrary`

**Files:**
- Create: `combat/resources/heritage.gd`
- Create: `combat/heritage_library.gd`
- Test: `tests/test_heritage_library.gd`

**Interfaces:**
- Consumes: `Stats` (pre-existing, fields `might`/`finesse`/`vigor`/`focus`/`grit`/`luck: int`).
- Produces: `Heritage` (`species_name: String`, `passive_description: String`,
  `passive_stat: StringName`, `passive_stat_bonus: int`, `apply_passive(base_stats: Stats) -> void`),
  `HeritageLibrary.IDS: Array[StringName]` (9 entries), `HeritageLibrary.make(id: StringName) -> Heritage`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_heritage_library.gd`:

```gdscript
extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	_check(HeritageLibrary.IDS.size() == 9, "HeritageLibrary registers exactly 9 species (got %d)" % HeritageLibrary.IDS.size())

	var seen_names: Dictionary = {}
	for id: StringName in HeritageLibrary.IDS:
		var h: Heritage = HeritageLibrary.make(id)
		_check(h != null, "HeritageLibrary.make(&\"%s\") returns a Heritage" % id)
		_check(not h.species_name.is_empty(), "%s has a non-empty species_name" % id)
		_check(not (h.species_name in seen_names), "%s's species_name '%s' is distinct from every other species" % [id, h.species_name])
		seen_names[h.species_name] = true
		_check(h.passive_stat != &"", "%s has a passive_stat assigned" % id)

	_check(HeritageLibrary.make(&"not_a_real_species") == null, "an unknown id returns null")

	var stats: Stats = Stats.new()
	stats.might = 1; stats.finesse = 1; stats.vigor = 1; stats.focus = 1; stats.grit = 1; stats.luck = 1
	var hare: Heritage = HeritageLibrary.make(&"hare")
	hare.apply_passive(stats)
	_check(stats.finesse == 2, "Hare's passive adds its bonus to Finesse (got %d)" % stats.finesse)
	_check(stats.might == 1, "Hare's passive leaves Might untouched")

	print(("HERITAGE LIBRARY TEST PASSED" if _failures == 0 else "HERITAGE LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_heritage_library.gd
```
Expected: a parse error (`Heritage`/`HeritageLibrary` don't exist yet) — non-zero exit code.

- [ ] **Step 3: Create `combat/resources/heritage.gd`**

```gdscript
class_name Heritage
extends Resource

## One of the First 9 playable species (docs/design-bible/10-storyline.md §6), selectable in
## CharacterCreationScreen's Species step. Grants exactly one passive stat bump (docs/design-bible/
## 20-character-creation.md §4). See [HeritageLibrary] for the 9 registered instances -- passive
## VALUES are [ASSUMPTION] placeholders, pending a later design-bible content session (spec
## 2026-08-13-character-creation-design.md).

@export var species_name: String = ""
@export var passive_description: String = ""

## Which [Stats] field [member passive_stat_bonus] is added to: one of
## &"might"/&"finesse"/&"vigor"/&"focus"/&"grit"/&"luck".
@export var passive_stat: StringName = &""
@export var passive_stat_bonus: int = 0

## Applies this species' passive directly to a Combatant's base_stats (called once, at Finalize).
func apply_passive(base_stats: Stats) -> void:
	match passive_stat:
		&"might": base_stats.might += passive_stat_bonus
		&"finesse": base_stats.finesse += passive_stat_bonus
		&"vigor": base_stats.vigor += passive_stat_bonus
		&"focus": base_stats.focus += passive_stat_bonus
		&"grit": base_stats.grit += passive_stat_bonus
		&"luck": base_stats.luck += passive_stat_bonus
```

- [ ] **Step 4: Create `combat/heritage_library.gd`**

```gdscript
class_name HeritageLibrary
extends RefCounted

## Code registry of the First 9 playable species (docs/design-bible/10-storyline.md §6). Mirrors
## ClassLibrary: returns a FRESH Heritage each call. Passive stat/amount values are [ASSUMPTION]
## placeholders -- tune by a later design-bible content session (spec
## 2026-08-13-character-creation-design.md).

const IDS: Array[StringName] = [&"hare", &"otter", &"badger", &"mouse", &"frog", &"turtle", &"fox", &"weasel", &"wildcat"]

static func _make(species_name: String, passive_description: String, passive_stat: StringName, passive_stat_bonus: int) -> Heritage:
	var h: Heritage = Heritage.new()
	h.species_name = species_name
	h.passive_description = passive_description
	h.passive_stat = passive_stat
	h.passive_stat_bonus = passive_stat_bonus
	return h

static func make(id: StringName) -> Heritage:
	match id:
		&"hare": return _make("Hare", "+1 Finesse", &"finesse", 1)
		&"otter": return _make("Otter", "+1 Vigor", &"vigor", 1)
		&"badger": return _make("Badger", "+1 Might", &"might", 1)
		&"mouse": return _make("Mouse", "+1 Grit", &"grit", 1)
		&"frog": return _make("Frog", "+1 Focus", &"focus", 1)
		&"turtle": return _make("Turtle", "+1 Grit", &"grit", 1)
		&"fox": return _make("Fox", "+1 Luck", &"luck", 1)
		&"weasel": return _make("Weasel", "+1 Finesse", &"finesse", 1)
		&"wildcat": return _make("Wildcat", "+1 Might", &"might", 1)
		_: return null
```

- [ ] **Step 5: Run the test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`, `HERITAGE LIBRARY TEST PASSED`, no `FAIL:` lines.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/heritage.gd combat/heritage_library.gd tests/test_heritage_library.gd
git commit -m "feat(creation): add Heritage resource + HeritageLibrary (First 9 species)"
```

---

### Task 2: `Background` resource + `BackgroundLibrary`

**Files:**
- Create: `combat/resources/background.gd`
- Create: `combat/background_library.gd`
- Test: `tests/test_background_library.gd`

**Interfaces:**
- Consumes: `ReelFace` (pre-existing, `result_tier: ReelFace.ResultTier`, `multiplier: float`).
- Produces: `Background` (`background_name: String`, `flavor_text: String`, `signature_face: ReelFace`),
  `BackgroundLibrary.IDS: Array[StringName]` (2 entries), `BackgroundLibrary.make(id: StringName) -> Background`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_background_library.gd`:

```gdscript
extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	_check(BackgroundLibrary.IDS.size() == 2, "BackgroundLibrary registers exactly 2 placeholder entries (got %d)" % BackgroundLibrary.IDS.size())

	var seen_names: Dictionary = {}
	for id: StringName in BackgroundLibrary.IDS:
		var b: Background = BackgroundLibrary.make(id)
		_check(b != null, "BackgroundLibrary.make(&\"%s\") returns a Background" % id)
		_check(not b.background_name.is_empty(), "%s has a non-empty background_name" % id)
		_check(not (b.background_name in seen_names), "%s's background_name '%s' is distinct from every other background" % [id, b.background_name])
		seen_names[b.background_name] = true
		_check(b.signature_face != null, "%s carries exactly one signature_face" % id)

	_check(BackgroundLibrary.make(&"not_a_real_background") == null, "an unknown id returns null")

	var rv: Background = BackgroundLibrary.make(&"reformed_vermin")
	_check(rv.signature_face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS, "Reformed Vermin's signature face is a CRIT_SUCCESS tier")

	print(("BACKGROUND LIBRARY TEST PASSED" if _failures == 0 else "BACKGROUND LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_background_library.gd
```
Expected: a parse error (`Background`/`BackgroundLibrary` don't exist yet) — non-zero exit code.

- [ ] **Step 3: Create `combat/resources/background.gd`**

```gdscript
class_name Background
extends Resource

## A player-authored backstory grant, selectable in CharacterCreationScreen's Background step.
## Grants exactly one signature ReelFace (docs/design-bible/20-character-creation.md §5). See
## [BackgroundLibrary] for the 2 registered placeholder instances -- the full roster is deferred to
## a later design-bible content session (spec 2026-08-13-character-creation-design.md).

@export var background_name: String = ""
@export var flavor_text: String = ""
@export var signature_face: ReelFace
```

- [ ] **Step 4: Create `combat/background_library.gd`**

```gdscript
class_name BackgroundLibrary
extends RefCounted

## Code registry of placeholder Backgrounds (spec 2026-08-13-character-creation-design.md). Mirrors
## ClassLibrary: returns a FRESH Background each call. Only 2 entries exist -- enough to prove the
## creation-screen pipeline, not a full roster (deferred to a later design-bible content session).

const IDS: Array[StringName] = [&"reformed_vermin", &"abbey_cook"]

static func make(id: StringName) -> Background:
	match id:
		&"reformed_vermin":
			var b: Background = Background.new()
			b.background_name = "Reformed Vermin"
			b.flavor_text = "Once one of the Wildcat's own -- now fighting for the other side."
			var face: ReelFace = ReelFace.new()
			face.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
			face.multiplier = 1.5
			b.signature_face = face
			return b
		&"abbey_cook":
			var b: Background = Background.new()
			b.background_name = "Abbey-Cook"
			b.flavor_text = "Years at the hearth taught patience, and a knack for a well-timed breather."
			var face: ReelFace = ReelFace.new()
			face.result_tier = ReelFace.ResultTier.NEUTRAL
			face.multiplier = 1.0
			b.signature_face = face
			return b
		_:
			return null
```

- [ ] **Step 5: Run the test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`, `BACKGROUND LIBRARY TEST PASSED`, no `FAIL:` lines.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/background.gd combat/background_library.gd tests/test_background_library.gd
git commit -m "feat(creation): add Background resource + BackgroundLibrary (2 placeholder entries)"
```

---

### Task 3: `Combatant` creation fields

**Files:**
- Modify: `combat/combatant.gd:58` (immediately after the existing `var is_player: bool = false`)
- Test: `tests/test_combatant_creation_fields.gd`

**Interfaces:**
- Consumes: `ClassLibrary.make(id: StringName) -> CharacterClass`,
  `CharacterClass.build_combatant(is_player: bool) -> Combatant` (both pre-existing),
  `HeritageLibrary.make()` (Task 1), `BackgroundLibrary.make()` (Task 2).
- Produces: `Combatant.heritage: Heritage`, `Combatant.background: Background`,
  `Combatant.class_is_locked: bool` (all default to unset/`false`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_combatant_creation_fields.gd`:

```gdscript
extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	var c: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	_check(c.heritage == null, "a Combatant built directly via ClassLibrary has no heritage by default")
	_check(c.background == null, "a Combatant built directly via ClassLibrary has no background by default")
	_check(c.class_is_locked == false, "class_is_locked defaults to false")

	c.heritage = HeritageLibrary.make(&"hare")
	c.background = BackgroundLibrary.make(&"abbey_cook")
	c.class_is_locked = true
	_check(c.heritage.species_name == "Hare", "heritage can be assigned and read back")
	_check(c.background.background_name == "Abbey-Cook", "background can be assigned and read back")
	_check(c.class_is_locked, "class_is_locked can be assigned and read back")

	print(("COMBATANT CREATION FIELDS TEST PASSED" if _failures == 0 else "COMBATANT CREATION FIELDS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_combatant_creation_fields.gd
```
Expected: a parse error (`Combatant` has no `heritage`/`background`/`class_is_locked` members yet) —
non-zero exit code.

- [ ] **Step 3: Add the 3 fields to `combat/combatant.gd`**

Immediately after the existing line `var is_player: bool = false` (line 58), insert:

```gdscript

## The player's chosen species (CharacterCreationScreen) -- null for every enemy/companion built
## directly via ClassLibrary, since only a player-created PC goes through creation (spec
## 2026-08-13-character-creation-design.md).
var heritage: Heritage

## The player's chosen backstory grant (CharacterCreationScreen) -- null for every enemy/companion
## built directly via ClassLibrary, same rule as [member heritage].
var background: Background

## True once the player's tentative class choice (made in CharacterCreationScreen) has been locked
## permanently by the Class Trial & Lock-In mechanic (its own future spec). This plan always leaves
## it false; nothing else in this plan reads it yet.
var class_is_locked: bool = false
```

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`, `COMBATANT CREATION FIELDS TEST PASSED`, no `FAIL:` lines.

- [ ] **Step 5: Run the full existing combatant test suite for regressions**

```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_combatant.gd
```
Expected: exit code `0` (adding 3 new default-valued fields must not change any existing behavior).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd tests/test_combatant_creation_fields.gd
git commit -m "feat(creation): add heritage/background/class_is_locked fields to Combatant"
```

---

### Task 4: `CharacterCreationDraft`

**Files:**
- Create: `world/character_creation/character_creation_draft.gd`
- Test: `tests/test_character_creation_draft.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `CharacterCreationDraft` — fields `heritage_id: StringName`, `class_id: StringName`,
  `background_id: StringName`, `character_name: String`; methods `has_heritage() -> bool`,
  `has_class() -> bool`, `has_background() -> bool`, `is_name_valid() -> bool`,
  `is_complete() -> bool`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_character_creation_draft.gd`:

```gdscript
extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	var draft: CharacterCreationDraft = CharacterCreationDraft.new()
	_check(not draft.has_heritage(), "a fresh draft has no heritage")
	_check(not draft.has_class(), "a fresh draft has no class")
	_check(not draft.has_background(), "a fresh draft has no background")
	_check(not draft.is_name_valid(), "a fresh draft's empty name is invalid")
	_check(not draft.is_complete(), "a fresh draft is not complete")

	draft.heritage_id = &"hare"
	draft.class_id = &"warrior"
	draft.background_id = &"abbey_cook"
	_check(draft.has_heritage() and draft.has_class() and draft.has_background(), "picks register once assigned")
	_check(not draft.is_complete(), "still incomplete without a valid name")

	draft.character_name = "Martin"
	_check(draft.is_name_valid(), "a plain name is valid")
	_check(draft.is_complete(), "a fully-filled draft is complete")

	draft.character_name = "O'Malley-Anne"
	_check(draft.is_name_valid(), "apostrophes and hyphens are allowed")

	draft.character_name = "   "
	_check(not draft.is_name_valid(), "a whitespace-only name is invalid")

	draft.character_name = "Martin3"
	_check(not draft.is_name_valid(), "digits are rejected")

	draft.character_name = "Martin!"
	_check(not draft.is_name_valid(), "symbols are rejected")

	draft.character_name = "A".repeat(21)
	_check(not draft.is_name_valid(), "a 21-character name exceeds the 20-character cap")

	draft.character_name = "A".repeat(20)
	_check(draft.is_name_valid(), "a 20-character name is exactly at the cap and valid")

	print(("CHARACTER CREATION DRAFT TEST PASSED" if _failures == 0 else "CHARACTER CREATION DRAFT TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_character_creation_draft.gd
```
Expected: a parse error (`CharacterCreationDraft` doesn't exist yet) — non-zero exit code.

- [ ] **Step 3: Create `world/character_creation/character_creation_draft.gd`**

```gdscript
class_name CharacterCreationDraft
extends RefCounted

## In-progress state for CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## Nothing here is a real save -- it's discarded if creation is abandoned; only
## CharacterCreationScreen._build_pc() turns a complete draft into a real Combatant.

const NAME_MAX_LENGTH: int = 20
const NAME_PATTERN: String = "^[A-Za-z '-]+$"

var heritage_id: StringName = &""
var class_id: StringName = &""
var background_id: StringName = &""
var character_name: String = ""

func has_heritage() -> bool:
	return heritage_id != &""

func has_class() -> bool:
	return class_id != &""

func has_background() -> bool:
	return background_id != &""

## True only if the trimmed name is 1-20 characters and contains nothing but letters, spaces,
## apostrophes, and hyphens (player-requested restriction, spec section "Name validation").
func is_name_valid() -> bool:
	var trimmed: String = character_name.strip_edges()
	if trimmed.is_empty() or trimmed.length() > NAME_MAX_LENGTH:
		return false
	var regex: RegEx = RegEx.create_from_string(NAME_PATTERN)
	return regex.search(trimmed) != null

func is_complete() -> bool:
	return has_heritage() and has_class() and has_background() and is_name_valid()
```

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`, `CHARACTER CREATION DRAFT TEST PASSED`, no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add world/character_creation/character_creation_draft.gd tests/test_character_creation_draft.gd
git commit -m "feat(creation): add CharacterCreationDraft with name validation"
```

---

### Task 5: The four step panels

**Files:**
- Create: `world/character_creation/species_step.gd`
- Create: `world/character_creation/class_step.gd`
- Create: `world/character_creation/background_step.gd`
- Create: `world/character_creation/name_step.gd`
- Test: `tests/test_character_creation_steps.gd`

**Interfaces:**
- Consumes: `HeritageLibrary.IDS`/`.make()` (Task 1), `BackgroundLibrary.IDS`/`.make()` (Task 2),
  `ClassLibrary.IDS`/`.make()` (pre-existing), `CharacterCreationDraft` (Task 4, used only by
  `NameStep` for inline validation).
- Produces: `SpeciesStep`/`ClassStep`/`BackgroundStep` — each with `signal selected(id: StringName)`,
  `select_for_test(id: StringName) -> void`, `selected_id_for_test() -> StringName`. `NameStep` —
  `signal name_changed(new_name: String)`, `enter_name_for_test(new_name: String) -> void`,
  `error_visible_for_test() -> bool`, `text_for_test() -> String`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_character_creation_steps.gd`:

```gdscript
extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	var species: SpeciesStep = SpeciesStep.new()
	var got_species_id: StringName = &""
	species.selected.connect(func(id: StringName) -> void: got_species_id = id)
	species.select_for_test(&"otter")
	_check(got_species_id == &"otter", "selecting Otter emits selected(&\"otter\") through a real button press")
	_check(species.selected_id_for_test() == &"otter", "the step tracks the selection internally")

	var class_step: ClassStep = ClassStep.new()
	var got_class_id: StringName = &""
	class_step.selected.connect(func(id: StringName) -> void: got_class_id = id)
	class_step.select_for_test(&"chancer")
	_check(got_class_id == &"chancer", "selecting Chancer emits selected(&\"chancer\") through a real button press")

	var background_step: BackgroundStep = BackgroundStep.new()
	var got_background_id: StringName = &""
	background_step.selected.connect(func(id: StringName) -> void: got_background_id = id)
	background_step.select_for_test(&"reformed_vermin")
	_check(got_background_id == &"reformed_vermin", "selecting Reformed Vermin emits selected(&\"reformed_vermin\") through a real button press")

	var name_step: NameStep = NameStep.new()
	var got_name: String = ""
	name_step.name_changed.connect(func(new_name: String) -> void: got_name = new_name)
	name_step.enter_name_for_test("Martin")
	_check(got_name == "Martin", "typing a name emits name_changed through the real LineEdit path")
	_check(not name_step.error_visible_for_test(), "a valid name shows no error")
	name_step.enter_name_for_test("Martin3")
	_check(name_step.error_visible_for_test(), "an invalid name (digit) shows the inline error")
	name_step.enter_name_for_test("")
	_check(not name_step.error_visible_for_test(), "an empty (not-yet-typed) name shows no error, only a disabled Next")

	print(("CHARACTER CREATION STEPS TEST PASSED" if _failures == 0 else "CHARACTER CREATION STEPS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_character_creation_steps.gd
```
Expected: a parse error (none of the 4 step classes exist yet) — non-zero exit code.

- [ ] **Step 3: Create `world/character_creation/species_step.gd`**

```gdscript
class_name SpeciesStep
extends Control

## Species-picker step of CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## One button per HeritageLibrary entry; placeholder visuals (plain labeled buttons), matching the
## project's placeholder-rectangle art direction. Buttons are built in _init(), not _ready(), so
## this step is fully testable via .new() alone -- no scene-tree insertion required, matching this
## project's InventoryMenuPanel/ProfessionsMenuPanel/TalentMenuPanel convention.

const BUTTON_H: float = 32.0

signal selected(id: StringName)

var _buttons: Dictionary = {}   # StringName -> Button
var _selected_id: StringName = &""

func _init() -> void:
	var y: float = 0.0
	for id: StringName in HeritageLibrary.IDS:
		var heritage: Heritage = HeritageLibrary.make(id)
		var btn: Button = Button.new()
		btn.text = "%s (%s)" % [heritage.species_name, heritage.passive_description]
		btn.position = Vector2(0.0, y)
		btn.pressed.connect(_on_pressed.bind(id))
		add_child(btn)
		_buttons[id] = btn
		y += BUTTON_H

func _on_pressed(id: StringName) -> void:
	_selected_id = id
	for key: StringName in _buttons:
		var btn: Button = _buttons[key]
		btn.modulate = Color(0.6, 1.0, 0.6) if key == id else Color.WHITE
	selected.emit(id)

func select_for_test(id: StringName) -> void:
	(_buttons[id] as Button).pressed.emit()

func selected_id_for_test() -> StringName:
	return _selected_id
```

- [ ] **Step 4: Create `world/character_creation/class_step.gd`**

```gdscript
class_name ClassStep
extends Control

## Class-picker step of CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## The pick made here is TENTATIVE -- a future Class Trial & Lock-In mechanic lets the player try
## other classes post-tutorial before it becomes permanent (Combatant.class_is_locked, Task 3).
## One button per ClassLibrary entry; placeholder visuals; built in _init() like SpeciesStep.

const BUTTON_H: float = 32.0

signal selected(id: StringName)

var _buttons: Dictionary = {}   # StringName -> Button
var _selected_id: StringName = &""

func _init() -> void:
	var y: float = 0.0
	for id: StringName in ClassLibrary.IDS:
		var character_class: CharacterClass = ClassLibrary.make(id)
		var btn: Button = Button.new()
		btn.text = "%s (%d reels)" % [character_class.display_name, character_class.reel_count]
		btn.position = Vector2(0.0, y)
		btn.pressed.connect(_on_pressed.bind(id))
		add_child(btn)
		_buttons[id] = btn
		y += BUTTON_H

func _on_pressed(id: StringName) -> void:
	_selected_id = id
	for key: StringName in _buttons:
		var btn: Button = _buttons[key]
		btn.modulate = Color(0.6, 1.0, 0.6) if key == id else Color.WHITE
	selected.emit(id)

func select_for_test(id: StringName) -> void:
	(_buttons[id] as Button).pressed.emit()

func selected_id_for_test() -> StringName:
	return _selected_id
```

- [ ] **Step 5: Create `world/character_creation/background_step.gd`**

```gdscript
class_name BackgroundStep
extends Control

## Background-picker step of CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## One button per BackgroundLibrary entry; placeholder visuals; built in _init() like SpeciesStep.

const BUTTON_H: float = 32.0

signal selected(id: StringName)

var _buttons: Dictionary = {}   # StringName -> Button
var _selected_id: StringName = &""

func _init() -> void:
	var y: float = 0.0
	for id: StringName in BackgroundLibrary.IDS:
		var background: Background = BackgroundLibrary.make(id)
		var btn: Button = Button.new()
		btn.text = "%s -- %s" % [background.background_name, background.flavor_text]
		btn.position = Vector2(0.0, y)
		btn.pressed.connect(_on_pressed.bind(id))
		add_child(btn)
		_buttons[id] = btn
		y += BUTTON_H

func _on_pressed(id: StringName) -> void:
	_selected_id = id
	for key: StringName in _buttons:
		var btn: Button = _buttons[key]
		btn.modulate = Color(0.6, 1.0, 0.6) if key == id else Color.WHITE
	selected.emit(id)

func select_for_test(id: StringName) -> void:
	(_buttons[id] as Button).pressed.emit()

func selected_id_for_test() -> StringName:
	return _selected_id
```

- [ ] **Step 6: Create `world/character_creation/name_step.gd`**

```gdscript
class_name NameStep
extends Control

## Name-entry step of CharacterCreationScreen (spec 2026-08-13-character-creation-design.md) --
## always last, per the player's explicit preference. Validation (length cap, allowed characters)
## lives on CharacterCreationDraft; this panel just surfaces it inline, never as a modal, and only
## once the player has actually typed something (an empty field shows no error, just a disabled
## Next button -- CharacterCreationScreen owns that gating).

signal name_changed(new_name: String)

var _line_edit: LineEdit
var _error_label: Label
var _validity_check: CharacterCreationDraft = CharacterCreationDraft.new()

func _init() -> void:
	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = "Enter your name"
	_line_edit.text_changed.connect(_on_text_changed)
	add_child(_line_edit)

	_error_label = Label.new()
	_error_label.position = Vector2(0.0, 32.0)
	_error_label.text = "Name must be 1-20 characters, letters/spaces/'/- only"
	_error_label.visible = false
	add_child(_error_label)

func _on_text_changed(new_text: String) -> void:
	_validity_check.character_name = new_text
	_error_label.visible = not new_text.is_empty() and not _validity_check.is_name_valid()
	name_changed.emit(new_text)

func enter_name_for_test(new_name: String) -> void:
	_line_edit.text = new_name
	_on_text_changed(new_name)

func error_visible_for_test() -> bool:
	return _error_label.visible

func text_for_test() -> String:
	return _line_edit.text
```

- [ ] **Step 7: Run the test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`, `CHARACTER CREATION STEPS TEST PASSED`, no `FAIL:` lines.

- [ ] **Step 8: Commit**

```bash
git add world/character_creation/species_step.gd world/character_creation/class_step.gd world/character_creation/background_step.gd world/character_creation/name_step.gd tests/test_character_creation_steps.gd
git commit -m "feat(creation): add the four Species/Class/Background/Name step panels"
```

---

### Task 6: `ReelPreviewPanel`

**Files:**
- Create: `world/character_creation/reel_preview_panel.gd`
- Test: `tests/test_reel_preview_panel.gd`

**Interfaces:**
- Consumes: `CharacterCreationDraft` (Task 4), `HeritageLibrary.make()` (Task 1),
  `BackgroundLibrary.make()` (Task 2), `ClassLibrary.make()` (pre-existing),
  `ReelFace.ResultTier` (pre-existing enum).
- Produces: `ReelPreviewPanel.refresh(draft: CharacterCreationDraft) -> void`,
  `ReelPreviewPanel.text_for_test() -> String`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_reel_preview_panel.gd`:

```gdscript
extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	var panel: ReelPreviewPanel = ReelPreviewPanel.new()
	var draft: CharacterCreationDraft = CharacterCreationDraft.new()

	panel.refresh(draft)
	_check(panel.text_for_test() == "Make a selection to preview your reels.", "an empty draft shows the placeholder prompt")

	draft.class_id = &"warrior"
	panel.refresh(draft)
	_check(panel.text_for_test().find("Martin (Mouse)") != -1, "picking a class shows its display name in the preview")
	_check(panel.text_for_test().find("3 reels") != -1, "picking a class shows its reel_count in the preview")

	draft.heritage_id = &"hare"
	panel.refresh(draft)
	_check(panel.text_for_test().find("Hare") != -1, "picking a heritage adds its species name to the preview")
	_check(panel.text_for_test().find("Finesse") != -1, "picking a heritage adds its passive description to the preview")

	draft.background_id = &"reformed_vermin"
	panel.refresh(draft)
	_check(panel.text_for_test().find("Reformed Vermin") != -1, "picking a background adds its name to the preview")
	_check(panel.text_for_test().find("CRIT_SUCCESS") != -1, "picking a background adds its signature face's tier to the preview")

	print(("REEL PREVIEW PANEL TEST PASSED" if _failures == 0 else "REEL PREVIEW PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_reel_preview_panel.gd
```
Expected: a parse error (`ReelPreviewPanel` doesn't exist yet) — non-zero exit code.

- [ ] **Step 3: Create `world/character_creation/reel_preview_panel.gd`**

```gdscript
class_name ReelPreviewPanel
extends Control

## Persistent side panel in CharacterCreationScreen showing the in-progress draft's derived reel
## info (spec 2026-08-13-character-creation-design.md) -- refreshed on every draft change, not just
## the current step's, per the design bible's "reel preview at creation" requirement. A plain text
## summary, not a full visual reel-strip widget, matching the project's placeholder-art decision for
## this screen.

var _label: Label

func _init() -> void:
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_label)

func refresh(draft: CharacterCreationDraft) -> void:
	var lines: Array[String] = []
	if draft.has_class():
		var character_class: CharacterClass = ClassLibrary.make(draft.class_id)
		lines.append("%s -- %d reels (%s)" % [character_class.display_name, character_class.reel_count, character_class.weapon_display_name])
	if draft.has_heritage():
		var heritage: Heritage = HeritageLibrary.make(draft.heritage_id)
		lines.append("%s passive: %s" % [heritage.species_name, heritage.passive_description])
	if draft.has_background():
		var background: Background = BackgroundLibrary.make(draft.background_id)
		var tier_name: String = ReelFace.ResultTier.keys()[background.signature_face.result_tier]
		lines.append("%s signature face: %s (x%.2f)" % [background.background_name, tier_name, background.signature_face.multiplier])
	_label.text = "\n".join(lines) if not lines.is_empty() else "Make a selection to preview your reels."

func text_for_test() -> String:
	return _label.text
```

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`, `REEL PREVIEW PANEL TEST PASSED`, no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add world/character_creation/reel_preview_panel.gd tests/test_reel_preview_panel.gd
git commit -m "feat(creation): add ReelPreviewPanel"
```

---

### Task 7: `CharacterCreationScreen` assembly, navigation, and Finalize

**Files:**
- Create: `world/character_creation_screen.gd`
- Create: `world/character_creation_screen.tscn`
- Test: `tests/test_character_creation_screen.gd`

**Interfaces:**
- Consumes: `CharacterCreationDraft` (Task 4), `SpeciesStep`/`ClassStep`/`BackgroundStep`/`NameStep`
  (Task 5), `ReelPreviewPanel` (Task 6), `HeritageLibrary.make()` (Task 1),
  `BackgroundLibrary.make()` (Task 2), `ClassLibrary.make()` +
  `CharacterClass.build_combatant(is_player: bool) -> Combatant` (pre-existing),
  `Combatant.heritage`/`.background`/`.class_is_locked`/`.base_stats`/`.weapon`/`.apply_stats()`/
  `.apply_luck()` (pre-existing + Task 3), `Weapon.reels: Array[ActionReel]` and
  `Reel.faces: Array[ReelFace]` (pre-existing).
- Produces: `CharacterCreationScreen.character_created(pc: Combatant)` signal;
  `current_step_for_test() -> StringName`, `select_species_for_test(id)`, `select_class_for_test(id)`,
  `select_background_for_test(id)`, `enter_name_for_test(text)`, `press_next_for_test()`,
  `press_back_for_test()`, `can_advance_for_test() -> bool`,
  `reel_preview_text_for_test() -> String` (test hooks; nothing later consumes them since this is
  the plan's final task).

- [ ] **Step 1: Write the failing test**

Create `tests/test_character_creation_screen.gd`:

```gdscript
extends SceneTree

## Scene-level test for CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## Drives it through all 4 steps via the actual panel signals/button presses -- never calling any
## private build/finalize method directly -- per the project's "a test that calls signal.emit()
## directly proves nothing about a real UI path" lesson (memory
## godot-toggle-button-and-test-bypass-gotchas).

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/character_creation_screen.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var screen: CharacterCreationScreen = _instance

		_check(screen.current_step_for_test() == &"species", "screen opens on the Species step")
		_check(not screen.can_advance_for_test(), "Next is disabled with nothing picked yet")

		screen.select_species_for_test(&"hare")
		_check(screen.can_advance_for_test(), "Next enables once Species is picked")
		screen.press_next_for_test()
		_check(screen.current_step_for_test() == &"class", "Next advances to the Class step")
		_check(not screen.can_advance_for_test(), "Next is disabled again on the new step with nothing picked")

		screen.select_class_for_test(&"warrior")
		screen.press_next_for_test()
		_check(screen.current_step_for_test() == &"background", "Next advances to the Background step")

		screen.select_background_for_test(&"reformed_vermin")
		screen.press_next_for_test()
		_check(screen.current_step_for_test() == &"name", "Next advances to the Name step")

		# Back-and-forth navigation preserves earlier picks (spec, "Navigation & validation").
		screen.press_back_for_test()
		_check(screen.current_step_for_test() == &"background", "Back returns to the Background step")
		screen.press_back_for_test()
		_check(screen.current_step_for_test() == &"class", "Back returns to the Class step")
		_check(screen.can_advance_for_test(), "the earlier Class pick is still there after navigating back")
		screen.press_next_for_test()
		screen.press_next_for_test()
		_check(screen.current_step_for_test() == &"name", "forward navigation returns to the Name step with every earlier pick intact")

		_check(not screen.can_advance_for_test(), "Finalize is disabled with no name entered")
		screen.enter_name_for_test("Martin")
		_check(screen.can_advance_for_test(), "Finalize enables once a valid name is entered")
		_check(screen.reel_preview_text_for_test().find("Reformed Vermin") != -1, "the reel preview reflects the Background pick made 2 steps ago, not just the current step")

		var created_pc: Combatant = null
		screen.character_created.connect(func(pc: Combatant) -> void: created_pc = pc)
		screen.press_next_for_test()

		_check(created_pc != null, "pressing Finalize on the Name step emits character_created with a real Combatant")
		_check(created_pc.display_name == "Martin", "the finalized Combatant carries the entered name")
		_check(created_pc.heritage != null and created_pc.heritage.species_name == "Hare", "the finalized Combatant carries the chosen heritage")
		_check(created_pc.background != null and created_pc.background.background_name == "Reformed Vermin", "the finalized Combatant carries the chosen background")
		_check(created_pc.class_id == &"warrior", "the finalized Combatant carries the chosen (tentative) class")
		_check(not created_pc.class_is_locked, "the finalized Combatant's class starts unlocked, pending the future Class Trial & Lock-In mechanic")
		_check(created_pc.background.signature_face in created_pc.weapon.reels[0].faces, "the background's signature face is inserted into the PC's starting reel strip")

	if _frames >= 2:
		print("ok character-creation-screen scene test complete")
		_instance.free()
		return true
	return false
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_character_creation_screen.gd
```
Expected: a load error (`res://world/character_creation_screen.tscn` doesn't exist yet) — non-zero exit code.

- [ ] **Step 3: Create `world/character_creation_screen.gd`**

```gdscript
class_name CharacterCreationScreen
extends Control

## The pre-story character creation screen (spec 2026-08-13-character-creation-design.md). Species
## -> Class(tentative) -> Background -> Name, free back/forth between steps, a persistent reel
## preview, then Finalize builds a real Combatant and emits character_created. Built entirely in
## code (only the root Control lives in character_creation_screen.tscn), matching this project's
## InventoryMenuPanel/ProfessionsMenuPanel/TalentMenuPanel convention.
##
## Out of scope here (spec, "Explicitly not built here"): the start-menu entry point that launches
## this screen, and the Class Trial & Lock-In mechanic that later locks class_is_locked -- this
## screen only reserves that field and leaves it false.

signal character_created(pc: Combatant)

const STEP_IDS: Array[StringName] = [&"species", &"class", &"background", &"name"]

var draft: CharacterCreationDraft = CharacterCreationDraft.new()
var _step_index: int = 0

var _species_step: SpeciesStep
var _class_step: ClassStep
var _background_step: BackgroundStep
var _name_step: NameStep
var _reel_preview: ReelPreviewPanel
var _back_button: Button
var _next_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_species_step = SpeciesStep.new()
	_species_step.selected.connect(_on_species_selected)
	add_child(_species_step)

	_class_step = ClassStep.new()
	_class_step.selected.connect(_on_class_selected)
	add_child(_class_step)

	_background_step = BackgroundStep.new()
	_background_step.selected.connect(_on_background_selected)
	add_child(_background_step)

	_name_step = NameStep.new()
	_name_step.name_changed.connect(_on_name_changed)
	add_child(_name_step)

	_reel_preview = ReelPreviewPanel.new()
	add_child(_reel_preview)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.pressed.connect(_on_back_pressed)
	add_child(_back_button)

	_next_button = Button.new()
	_next_button.text = "Next"
	_next_button.pressed.connect(_on_next_pressed)
	add_child(_next_button)

	_rebuild()

func _rebuild() -> void:
	_species_step.visible = _step_index == 0
	_class_step.visible = _step_index == 1
	_background_step.visible = _step_index == 2
	_name_step.visible = _step_index == 3
	_back_button.visible = _step_index > 0
	_next_button.text = "Finalize" if _step_index == STEP_IDS.size() - 1 else "Next"
	_next_button.disabled = not _current_step_complete()
	_reel_preview.refresh(draft)

func _current_step_complete() -> bool:
	match STEP_IDS[_step_index]:
		&"species": return draft.has_heritage()
		&"class": return draft.has_class()
		&"background": return draft.has_background()
		&"name": return draft.is_name_valid()
		_: return false

func _on_species_selected(id: StringName) -> void:
	draft.heritage_id = id
	_rebuild()

func _on_class_selected(id: StringName) -> void:
	draft.class_id = id
	_rebuild()

func _on_background_selected(id: StringName) -> void:
	draft.background_id = id
	_rebuild()

func _on_name_changed(new_name: String) -> void:
	draft.character_name = new_name
	_rebuild()

func _on_back_pressed() -> void:
	if _step_index > 0:
		_step_index -= 1
		_rebuild()

func _on_next_pressed() -> void:
	if not _current_step_complete():
		return
	if _step_index == STEP_IDS.size() - 1:
		character_created.emit(_build_pc())
	else:
		_step_index += 1
		_rebuild()

## Builds the real PC Combatant from the completed draft: the tentative CharacterClass's baseline,
## the chosen Heritage's passive layered onto base_stats (then re-derives stats/luck so the bump
## actually takes effect), and the chosen Background's signature face inserted into the first
## weapon reel's strip ("the signature face literally appears on the strip" -- design bible §5).
func _build_pc() -> Combatant:
	var character_class: CharacterClass = ClassLibrary.make(draft.class_id)
	var pc: Combatant = character_class.build_combatant(true)
	pc.display_name = draft.character_name.strip_edges()
	pc.heritage = HeritageLibrary.make(draft.heritage_id)
	pc.heritage.apply_passive(pc.base_stats)
	pc.apply_stats()
	pc.apply_luck()
	pc.background = BackgroundLibrary.make(draft.background_id)
	pc.weapon.reels[0].faces.append(pc.background.signature_face)
	pc.class_is_locked = false
	return pc

# --- headless test hooks ---

func current_step_for_test() -> StringName:
	return STEP_IDS[_step_index]

func select_species_for_test(id: StringName) -> void:
	_species_step.select_for_test(id)

func select_class_for_test(id: StringName) -> void:
	_class_step.select_for_test(id)

func select_background_for_test(id: StringName) -> void:
	_background_step.select_for_test(id)

func enter_name_for_test(new_name: String) -> void:
	_name_step.enter_name_for_test(new_name)

func press_next_for_test() -> void:
	_next_button.pressed.emit()

func press_back_for_test() -> void:
	_back_button.pressed.emit()

func can_advance_for_test() -> bool:
	return not _next_button.disabled

func reel_preview_text_for_test() -> String:
	return _reel_preview.text_for_test()
```

- [ ] **Step 4: Create `world/character_creation_screen.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://world/character_creation_screen.gd" id="1_character_creation_screen"]

[node name="CharacterCreationScreen" type="Control"]
script = ExtResource("1_character_creation_screen")
```

- [ ] **Step 5: Run the test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`, `ok character-creation-screen scene test complete`, no `FAIL` lines.

- [ ] **Step 6: Run every test file created or touched by this plan, together, for regressions**

```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_heritage_library.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_background_library.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_combatant_creation_fields.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_character_creation_draft.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_character_creation_steps.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_reel_preview_panel.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_character_creation_screen.gd
```
Expected: exit code `0` on all 7.

- [ ] **Step 7: Commit**

```bash
git add world/character_creation_screen.gd world/character_creation_screen.tscn tests/test_character_creation_screen.gd
git commit -m "feat(creation): assemble CharacterCreationScreen with navigation and Finalize"
```

---

## Plan Self-Review Notes

- **Spec coverage:** Scene structure & data model (Tasks 1, 2, 4, 5, 6, 7) — `Heritage`/
  `HeritageLibrary` (Task 1), `Background`/`BackgroundLibrary` (Task 2), `class_is_locked`
  reservation (Task 3), `CharacterCreationDraft` (Task 4), all 4 step panels (Task 5),
  `ReelPreviewPanel` (Task 6), screen assembly (Task 7). Navigation & validation (Task 7's
  `_rebuild()`/`_current_step_complete()` + Task 4's `is_name_valid()`). Name length cap + character
  restriction (Task 4). Finalize & handoff (Task 7's `_build_pc()` + `character_created` signal —
  the actual scene→scene wiring is explicitly the start-menu spec's job, not this plan's). Testing
  section's 4 bullets are covered 1:1 by Tasks 1/2 (resource loading), Task 4 (draft validation),
  and Task 7 (scene-level, real-signal-driven, back-nav-preserves-picks).
- **Placeholder scan:** no TBD/TODO markers; every code block is complete and runnable.
- **Type consistency:** `HeritageLibrary.make()`/`BackgroundLibrary.make()` signatures (Tasks 1-2)
  match their use in Task 5's steps, Task 6's preview panel, and Task 7's `_build_pc()`.
  `CharacterCreationDraft`'s field names (`heritage_id`/`class_id`/`background_id`/`character_name`)
  are defined once in Task 4 and used identically in Tasks 5, 6, 7. `Combatant.heritage`/
  `.background`/`.class_is_locked` (Task 3) are consumed with matching names/types only in Task 7.
- **Out of scope, confirmed untouched by any task:** the start-menu "New Game" entry point, the
  Class Trial & Lock-In mechanic, full species-passive/background content authoring beyond the
  agreed placeholders, and any save/persistence system.

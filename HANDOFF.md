# SESSION HANDOFF — Bunnies (Redwall-style slot-reel RPG, working title TBD)

> **Purpose of this file:** a short, self-contained briefing so a *new* chat session (or a new
> collaborator) can pick up instantly, without reading the full history. Read this first, then
> `CLAUDE.md` (conventions + rules), `DESIGN.md` (full design, source of truth if anything
> disagrees), and `ARCHITECTURE.md` (as-built code map). The complete, unabridged chronological
> ship/playtest log lives in `docs/DEVLOG.md` — read it on demand, not every session.
>
> **This is a CURRENT snapshot, rewritten 2026-08-09** (replacing a version that had gone stale
> since 2026-06-27 — its old dated "START HERE NEXT SESSION" blocks had turned into a second,
> out-of-date copy of the ship log; that content is superseded by `docs/DEVLOG.md`, which has the
> real, complete record).

---

## 1. What the game is (10-second version)

A 2D, Godot-built, turn-based RPG in the *Redwall* tradition (anthropomorphic woodlanders vs.
vermin, all-ages with real stakes). **The hook: every random resolution in combat is a SLOT-REEL
SPIN, not a dice roll — and your build edits the reels** (which symbols, how many reels, what each
symbol does). Campaign mode is built first; a roguelite mode comes post-1.0 and reuses the same
systems.

---

## 2. Where we are right now

The combat prototype, out-of-combat world, and four gathering/crafting professions are all
built, code-complete, and have been through multiple rounds of human playtesting with fixes
applied. At a glance:

- **Combat:** all 7 classes (Warrior/Vanguard/Skirmisher/Chancer/Ranger/Seer/Warden), each with a
  full 4-ability + Ultimate kit and a talent/perk tree (L1–10); 8 damage types; N-vs-M party
  combat; a multi-phase boss fight (the Hollow Warden); the Team-Up! jackpot minigame.
- **Out-of-combat:** town, overworld, and a 4-floor dungeon (lock-and-key gate, boss, Treasure
  Trove); equipment/inventory/banking UI; a real quest (Lost Cat); companion recruitment/bench;
  shops (Amber economy); a rest point (the Old Well); a persistent cross-scene event log.
- **Professions:** Foraging, Fishing, Salvaging, Cooking — each with an opt-in bonus mini-game
  (Shake the Bush / claw-machine reel catch / Tempering Reels / Second Helping).

**Most recent ship:** 2026-08-12, Plan 3 (quest-system-and-tutorial design) is now FULLY
playtest-confirmed end to end. Its human playtest found 3 issues, all fixed and re-confirmed same
day: the tutorial's objective order was reworked (Adventuring Board -> Shopkeeper -> leave town
[new `leave_town` objective] -> Legend -> win a fight); accepting a quest now logs an Event Log
entry (`PartyInventory.quest_accepted`, mirrors `quest_completed`); and world hover tooltips
(which never fired with a real mouse even after fixing `Viewport.physics_object_picking`) were
replaced outright with a descriptive `InteractPrompt` line on proximity — the same already-working
mechanism every other interactable uses — which playtested cleanly. Full 328-file suite clean (see
CLAUDE.md's gotchas for the two known unrelated exceptions). See `CLAUDE.md` §8 for a condensed
status summary, or `docs/DEVLOG.md` for the full entry.

**Next open items** (not started, no session currently in flight):
- **Nothing is known to block the next export/distro build** — the entire quest-system-and-
  tutorial thread (all 3 plans) is shipped and playtest-confirmed.
- A test-fixture staleness gap surfaced during the Plan 3 verification sweep:
  `tests/test_professions_menu_panel.gd`'s "over-tall panel" case was calibrated for
  `ProfessionsMenuPanel`'s old 2x scale; the 2026-08-10 panel-centering fix dropped that panel to
  1x, so the fixture's 4-Gear-item case (614px) no longer exceeds the 900px viewport it's meant to
  test against. Not a functional bug (the TOP_MARGIN anchoring code itself is untouched) — the test
  fixture just needs re-engineering (its material/gear row caps mean simply adding more demo items
  won't reproduce the case). Deferred, not blocking export.
- Ability-level redistribution / talent tuning, post-combat recovery, PC↔companion level parity —
  each explicitly deferred to its own dedicated design session.
- Design-bible settlement/roster content is still seeded proposals, not locked.

---

## 3. The combat loop in one breath

Each combatant rolls **Initiative once** (2-reel d100, `00`=100 high; + Finesse, with a Finesse →
d10-reel tie-break) → combat runs in **rounds**, acting in descending `current_initiative` order
(effects shove that value up/down with a duration; deeply-negative init → STUNNED gate). A turn
runs **MTG phases**: Upkeep → **Main 1** (stage abilities/items — SPIN commits) → Combat (spin
2–5 Action reels, *each an independent attack*) → Main 2 → End. Each Action reel lands on one of
five tiers (crit-fail / fail / **neutral=utility** / success / crit-success); damage =
`ceil(base × multiplier × type-chart) + Might`. The weapon grid is then scored for **paylines**
(extra rewards on matched lines). Results charge a **Bonus Meter**; a full meter arms the class's
Ultimate.

---

## 4. The non-negotiable pillars (don't let these drift)

1. The slot reel **is** the dice — protect the spin as the core fantasy.
2. Builds **edit the reels** — that's the depth.
3. **Legibility over realism** — show reel contents, turn order, staged previews; hidden math
   kills the fun.
4. **Every choice is a trade-off.**
5. **Campaign first, fun first.**

(Full detail: `CLAUDE.md` §3.)

---

## 5. How to run it

**Godot 4.6.3-stable**, GDScript (no C#). Project root = `bunnies/` (this repo); `main_scene` is
`res://world/start_menu.tscn` (changed 2026-08-13 per the start-menu spec, reversing the
2026-08-10 decision this same sentence used to describe). The start menu's "New Game" path goes
through `CharacterCreationScreen` -> `InventoryDemoSetup.seed_demo_party(pc)` -> `CombatHandoff`
-> `town_demo.tscn` — `town_demo.gd` already seeds a fresh party via
`InventoryDemoSetup.seed_demo_party()` when no `CombatHandoff` state exists, and the full
Town⇄Overworld⇄Dungeon⇄Combat loop is reachable from there, now reached via the start menu's New
Game rather than being the literal boot scene; locked in by
`tests/test_main_scene_is_start_menu.gd`. The Godot executable lives **one directory above this
repo**: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`.

- **Play the loop:** open the project in Godot and press play, or launch a specific scene:
  `Godot_v4.6.3-stable_win64_console.exe --path bunnies res://world/<scene>.tscn`. Judging
  whether the spin is *fun* is the human call (CLAUDE.md §5 hard ceiling) — no computer-use tool
  exists in this harness to drive a live GUI, so this always needs a human.
- **Headless test suite — 300+ test files, all green as of the last full sweep (2026-08-08).**
  To run one:
  ```bash
  Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd
  ```
  **Gotchas:**
  1. Use the `_console.exe` build to capture output — the plain `.exe` is GUI-subsystem and
     writes nothing to a redirected stream.
  2. A parse error hangs the run forever (never reaches `quit()`) — always bound a run with a
     timeout.
  3. After adding a new `class_name`, refresh the class cache or `--script` can't resolve it:
     `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`. Never delete
     `.godot/` to troubleshoot — it wipes the class-name registry project-wide; use the above
     refresh instead.
  4. **"Silent script-error-exits-zero":** a thrown error mid-`_process()`/`_init()` kills the
     rest of that frame's checks but the process still exits 0. At least 3 known exit-code-blind
     files exist (`tests/test_adventuring_board_panel.gd`, `tests/test_dungeon_demo.gd`, and one
     more documented in memory `silent-script-error-exits-zero-gotcha`) — grep actual output for
     `SCRIPT ERROR`/`FAIL`, don't trust exit codes alone on a full sweep.
  5. A rare intermittent teardown-only SIGSEGV flake class has recurred across many different
     test files over the project's history — always confirmed clean on immediate retry; not a
     regression signal by itself.

---

## 6. Detailed record — where to read more

- **Full chronological ship/playtest history:** `docs/DEVLOG.md` (moved out of `CLAUDE.md` on
  2026-08-09 to keep that file lean).
- **Per-feature design specs:** `docs/superpowers/specs/`. **Plans:** `docs/superpowers/plans/`.
- **Autonomous balance/design calls + `[ASSUMPTION]` values:** `docs/superpowers/DECISIONS-LOG.md`.
- **As-built code map:** `ARCHITECTURE.md`. **Conventions/rules:** `CLAUDE.md`. **Full design /
  source of truth:** `DESIGN.md`. **Out-of-combat systems:** `docs/design-bible/` (start at
  `00-index.md`).
- **Session-to-session context that doesn't belong in a doc** (what was surprising, what's still
  open, why a decision was made): the assistant's persistent memory system — ask it to check
  memory if picking up a thread that isn't reflected above.

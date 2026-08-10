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

**Most recent ship:** 2026-08-08, professions playtest round 2 (panel overflow/centering fixes,
per-profession inventory scoping, layout fixes for Second Helping/Fishing/the event log) —
human-playtested and confirmed working across the board. See `CLAUDE.md` §8 for a condensed
status summary, or `docs/DEVLOG.md` for the full entry.

**Next open items** (not started, no session currently in flight):
- Ability-level redistribution / talent tuning, post-combat recovery, PC↔companion level parity —
  each explicitly deferred to its own dedicated design session.
- Design-bible settlement/roster content is still seeded proposals, not locked.
- **Pre-export checklist:** the Professions panel's scaling reads noticeably too large — flagged
  during the 2026-08-10 Quest Log playtest, not fixed yet, check before cutting an export build.

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
`res://combat/combat.tscn`. The Godot executable lives **one directory above this repo**:
`C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`.

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

# SESSION HANDOFF — Redwall slot-RPG (working title TBD)

> **Purpose of this file:** a short, self-contained briefing so a *new* chat session (or a new collaborator) can pick up instantly without re-reading the whole `DESIGN.md`. Read this first, then open `DESIGN.md` for full detail. This file is a snapshot — `DESIGN.md` is the source of truth if they ever disagree.

---

## 1. What the game is (10-second version)

A 2D, Godot-built, turn-based RPG in the *Redwall* tradition (anthropomorphic woodlanders vs vermin, all-ages with real stakes). **The hook: every random resolution in combat is a SLOT-REEL SPIN, not a dice roll — and your build edits the reels** (which symbols, how many reels, what each symbol does). Campaign mode is built first; a roguelite mode comes post-1.0 and reuses the same systems.

---

## 2. Where we are in the process

Two full design sessions are complete. The result: **all previously-open decisions and designer questions are resolved**, and the first two content deliverables (type chart + starter roster) are drafted.

**Locked this session:**
- All six **§10 decisions** (multi-reel = independent attacks; party = max 3 PCs, prototype 1v1; 6 types; 2–5 reel band; neutral = utility result; Stamina/Focus/Mana + MTG phase turn + separate Bonus-Meter economy).
- All fourteen **§11 designer answers** (HP, enemy symmetry, defense, status layer, talents, level-up, gear slots, world structure, tone, platforms, audio, team).
- The **MTG-style phase turn** (§4.8) and the **Bonus Meter / Ultimate** system (§4.9), including the per-class `meter_floor` carryover rule.
- The **6×6 type chart first pass** (§5.1) — values done, ×1.5 tier reserved for playtest.
- The **race/class/specialization roster** (§5B) — soft-coupled model, vermin playable in the post-1.0 roguelite, MMO-style class specializations living in the talent layer.

---

## 3. The combat loop in one breath

Each combatant rolls **Initiative once** (2-reel d100, `00`=100 high) → combat runs in **rounds**, acting in descending current-Initiative order (effects shove that value up/down with a duration). A turn runs **MTG phases**: Upkeep → Main 1 (spend resources, set reel loadout) → Combat (spin 2–5 Action reels, *each an independent attack*) → Main 2 → End. Each Action reel lands on one of five tiers (crit-fail / fail / **neutral=utility** / success / crit-success); damage = `base × symbol multiplier`, modified by the 6-type chart. Results charge a **Bonus Meter**; full meter arms a class-defining **Ultimate** (costs only the meter).

---

## 4. The non-negotiable pillars (don't let these drift)

1. The slot reel **is** the dice — protect the spin as the core fantasy.
2. Builds **edit the reels** — that's the depth.
3. **Legibility over realism** — show reel contents and turn order; hidden math kills the fun.
4. **Every choice is a trade-off** (Slay the Spire lesson).
5. **Campaign first, fun first** — prove the loop with placeholder art before anything else.

---

## 5. Engine & tooling (already decided)

- **Godot 4.4+, GDScript** (2D-first, MIT, fast iteration).
- **Claude Code** = agentic coding; **`Coding-Solo/godot-mcp`** to let it read the live scene tree.
- Living context docs Claude Code reads each session: `DESIGN.md` (this design), a planned `CLAUDE.md` (conventions), a planned `ARCHITECTURE.md` (data structures).
- **Known ceiling:** MCP can't press play and judge feel — *the human* decides "is the spin fun." Delegate implementation, not fun.

---

## 6. EXACT next actions (in order) — start here next session

1. **`ARCHITECTURE.md`** — turn the §8 data sketch into concrete GDScript `Resource` stubs. Key classes: `ReelFace`, `Reel` (abstract base) + its subclasses `InitiativeReel` (shared constant) and `ActionReel` (build-variable), `Weapon`, `DamageType`, `Effect`, `Class`, `BonusMeter`, `Ultimate`, `ResourcePool`, `Combatant`, `EncounterTable`, `RewardTable`, `TurnManager`, `PhaseManager`. Naming convention (signals = `spin_resolved`-style past-tense, etc.) is locked in `CLAUDE.md §2`. (Race affinities and class specializations ride on `Class` + talent data — **no new engine classes needed**.)
2. **`CLAUDE.md`** — root conventions for Claude Code (GDScript not C#, node-naming, engine version, done/next).
3. **Stand up the project** — repo + Godot 4.4 project + Git + Coding-Solo MCP.
4. **Vertical-slice prototype** — 1 PC vs 1 enemy, placeholder rectangles: Initiative spin → fixed-order round → MTG phase turn → Action-reel attack (independent resolution) → damage via type chart → meter charges → win/lose. **This is the moment the game becomes real.**

**Parallel design tasks (not blocking the prototype):**
- Spec the **talent system** (Fellowship-style UI, WoW-style effects) and define each class's **specialization branches**; decide Warrior shape (a) three weapon branches vs (b) one weapon-adaptive talent.
- Confirm the **Archer Ultimate** (shifting wild vs Pick'em).
- **Playtest** the type chart; decide whether the ×1.5 tier is warranted.

---

## 7. Things still deliberately open (and that's fine)

- Balance placeholders flagged `[ASSUMPTION]` in `DESIGN.md`: the damage multiplier values (§4.5), Bonus-Meter charge weights + cap (§4.9). Tune *after* the spin is fun.
- The one soft decision left: Pick'em was double-assigned to Archer + Healer; leaning Healer = Pick'em, Archer = shifting wild. Confirm at class-design time.
- Final game/working title is still TBD.

---

*Snapshot taken at end of session 2. Open `DESIGN.md` for the authoritative detail behind every line above.*

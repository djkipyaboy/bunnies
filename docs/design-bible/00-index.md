# Design Bible — Index & How To Use It

> **What this is.** A parallel companion to `DESIGN.md` (which stays the **combat** source of truth).
> The Design Bible is where every **out-of-combat** system gets captured, shaped, and locked before it
> becomes a real spec → plan → build. Created 2026-06-28.

---

## The one principle that governs everything here

> **Every out-of-combat system FEEDS THE REELS.** It grants or edits reel faces, unlocks reel-slots,
> spends a build budget, or gates the world — but it never becomes a *second* power-build axis that
> competes with reel-editing. (This is the unanimous conclusion of the Persona/FF/D&D, BG3/Diablo, and
> Paper Mario research. Where a famous system — Sphere Grid, Materia, Persona Fusion — tries to *be* the
> build, we reskin its **verb onto the reels** or reject it.)

The four combat pillars still rule (`DESIGN.md`/`CLAUDE.md §3`): the slot reel IS the dice · builds edit
the reels · legibility over realism · every choice is a trade-off · campaign-first, fun-first.

---

## How we work these docs (the hybrid loop)

Each system is **one file** with two zones:

1. **💬 BRAIN DUMP (yours)** — frictionless. Optional starter prompts, then open space. Dump however it
   comes out — fragments, contradictions, "what if". You can also just *talk* and I'll paste/structure it.
2. **📋 STRUCTURED BRIEF (mine)** — I fill this from your dump + research + proposals. You **react/edit**,
   you don't author from a blank page.

Lifecycle per system: **dump → I structure → you react/edit → ✅ lock → graduate to a real spec → plan →
build** (exactly how combat features ship). Status is tracked in the table below.

## Marker legend (scan for what needs you)

| Marker | Meaning |
|---|---|
| 🟦 **YOUR INPUT** | A blank waiting on your decision/creativity |
| 💡 **PROPOSAL** | My suggestion — accept / reject / tweak |
| 🔬 **REFERENCE** | Grounded in the research (names the game it's borrowed from) |
| ❓ **OPEN QUESTION** | A fork we need to resolve together |
| ✅ **LOCKED** | Decided — ready to graduate to a spec |
| ⏳ **DEFERRED** | Post-1.0 / YAGNI — parked on purpose |

## Three document styles

- **⚙️ Systems Brief** — mechanics (companions, creation, stats, leveling, talents, equipment, inventory,
  banking, crafting, encounters). *Proposals here are aggressive* — react and veto.
- **📖 Narrative/World Brief** — storyline, world, tone. *Proposals here are light* — these are yours;
  mostly 🟦 blanks + ❓ with proposals only where I have a real view.
- **🗂️ Content Catalog** — enumerable content (enemies, NPCs, companions, later: items/areas). Define the
  *fields* once, fill *rows* over time. Built out after the parent system brief locks.

---

## System status board

| File | Style | System | Status |
|---|---|---|---|
| `10-storyline` | 📖 | Storyline & narrative | 🔲 awaiting your dump |
| `11-world-and-overworld` | 📖 | World structure, out-of-combat loop, collectibles | 🔲 awaiting your dump |
| `12-companions-and-party` | ⚙️ | KOTOR-style recruitable companions + party management | 📝 seeded |
| `20-character-creation` | ⚙️ | PC creation flow | 📝 seeded |
| `21-stats-and-attributes` | ⚙️ | The 5+1 stats out of combat | 📝 seeded |
| `22-leveling-and-progression` | ⚙️ | XP/levels → reel edits | 📝 seeded |
| `23-talents-and-reel-points` | ⚙️ | Talent system + the "Reel Points" budget | 📝 seeded |
| `24-equipment` | ⚙️ | Gear that edits reels/stats | 📝 seeded |
| `25-inventory-and-storage` | ⚙️ | Personal + cross-character inventory | 📝 seeded |
| `26-banking-cross-character` | ⚙️ | The cross-character vault (replayability spine) | 📝 seeded |
| `27-crafting` | ⚙️ | Reel-mod crafting + salvage | 📝 seeded |
| `28-encounter-design-framework` | ⚙️ | Boss parts/phases, multi-target, encounter variety | 📝 seeded |
| `40-enemy-roster` | 🗂️ | Hundreds of designed enemies | 🔲 schema only |
| `41-npc-roster` | 🗂️ | Static merchants / townsfolk / quest-givers | 🔲 schema only |
| `42-companion-roster` | 🗂️ | Recruitable allies | 🔲 schema only |
| `99-parking-lot` | — | Stray ideas + systems you may have left off | 💡 my proposals |

**Suggested first three to work** (highest leverage, everything else hangs off them):
`10-storyline` (sets tone/cast/stakes), `23-talents-and-reel-points` (the meta-progression spine), and
`12-companions-and-party` (the KOTOR structure that reshapes creation/leveling/roster).

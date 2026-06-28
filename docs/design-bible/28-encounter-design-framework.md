# Encounter Design Framework (boss parts, phases, multi-target, variety) — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** 📝 seeded
> **Related:** `DESIGN.md`/`ARCHITECTURE.md` (combat) · [[11-world-and-overworld]] · [[40-enemy-roster]]
> **Your direction:** *fluctuating enemy counts; combat scenarios designed as uniquely as possible — single
> bosses with multiple targetable elements, multi-phase bosses, etc.*

---

## 💬 BRAIN DUMP (yours)

- 🟦 Any **specific boss fights** you can already picture? (a giant adder with separate coils? a vermin warlord + bodyguards?)
- 🟦 How **hard** should standard fights feel vs. bosses? Any flee/retreat option?
- 🟦 Do you want **environmental hazards / terrain** in fights, or pure combatant-vs-combatant?

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. The unifying primitive: a "boss part" IS a Combatant
💡🔬 **The cleanest architecture — and it makes your fluctuating counts and bosses the SAME system.** Add
`boss_group_id`, `is_part: bool`, `core: bool` to `Combatant`. The win-check ignores `is_part`; victory =
the `core` dies (or all-parts-dead for "no core" bosses). Then:
- "3 rats" · "1 boss + 2 arms + 1 core" · "warlord + 2 bodyguard adds" are all one fluctuating-count system.
- Reuses the shipped per-combatant panels, per-PC targeting, AoE/splash, and the type-effectiveness AI **for free.**
`[ASSUMPTION]` part HP ≈ 40% of core.

### 2. Phases as DATA, not code
💡🔬 A `BossPhase` resource: `{ trigger (HP%/turn/event), reel_loadout, type_override, resist_override,
on_enter_effects[], persists_debuffs: true }`. `PhaseManager` emits `phase_changed`; the panel shows
`Phase 2/3`. Authors build multi-phase bosses **without** `if boss == "Hooktail"` special-casing.

### 3. The six encounter archetypes (the variety menu)
🔬 *From Paper Mario / FF / MMO research — each poses a different tactical question and maps onto shipped systems:*
1. **Adds / summons** (TTYD Magnus, Smorg) — *focus vs. spread*; cap spawn rate; clearing them visibly helps. Pairs with our AoE Ultimates.
2. **Multi-part body w/ gated weak point** (FFX arms, TTYD Cortez) — break a part → weakens the boss; needs readable per-part HP (we have it).
3. **Telegraphed counter-state** (FFVII Guard Scorpion "tail up") — a `GUARDED` turn where crit/success *rebounds*; teaches reading the reel result in context. 💡 *Reflect = 50% (`[ASSUMPTION]`), hard-telegraphed icon + log.*
4. **HP-threshold phase shift** (genre standard) — new type/resist/summon/heal at 50%/25%; announce *why*; persist broken parts/debuffs through it.
5. **Regenerating weak-node shield** (TTYD Grodus) — core invulnerable until N nodes die; 1 regrows/turn. *Tempo race* rewarding wide reel loadouts/splice over single-target burst. 💡 *Tune so a focused party out-paces regen.*
6. **Build-keyed weakness** (TTYD Hooktail's cricket fear; type-chart exploit) — the "answer" is a build/damage-type you bring **in** (Pillar 2 as an encounter mechanic). **Telegraph it in the world** (NPC/lore) so it's a puzzle, not a wall.

### 4. Legibility guardrails (Pillar 3)
✅ Every phase change is a **named, logged event**; every regenerating node and counter-state shows a **panel
icon**; persistent debuffs/broken parts **survive transitions and say so**. Boss mechanics change *what a
result means* — they never replace the spin.

### 5. The Encounter Design template (per-encounter doc, used in [[11-world-and-overworld]] chapters)
```
# Encounter: <Name>   (version / changelog)
1. Identity & Fantasy — pitch · campaign slot · player-feeling target
2. Roster & Board — combatants (PC-facing count) · parts vs core (boss_group_id/is_part/core)
                   · types · reel loadouts (2–5) · resist/weakness · initiative spread
3. The Core Decision — the ONE tactical question (focus/spread, race regen, read counter, bring type)
4. Phases (each) — trigger · what changes · what PERSISTS · announce line · panel change
5. Special Mechanics — adds (rate/cap/payoff) · parts/nodes (HP/regen/break-effect/drop)
                     · counter states · meta-resource attacks
6. Build Hooks — which reel-edits/types this rewards or punishes · where the weakness is telegraphed
7. Tuning Levers [ASSUMPTION] — part HP, regen, thresholds, add cap, soft-timer; define "BROKEN/stalemate"
8. Legibility Checklist — states visible? phases announced? no hidden timer? counters telegraphed?
9. Win / Lose / Flee · Rewards (coins, collectibles, Reel Points, recipes)
```

### 6. Data model sketch (→ Godot)
💡 *`Combatant` gains `boss_group_id/is_part/core`; an `Encounter` resource = `{ combatants[], phases{}, special_mechanics[], rewards }`.* The combat scene already accepts arbitrary combatant lists.

### 7. Open questions
- ❓ Flee/retreat allowed? ❓ Environmental hazards/terrain in scope? ❓ Difficulty band targets (deferred-difficulty memory: build one default now).

### Scope / phase
✅ Boss-part primitive + data phases + archetypes 1–4 for early chapters; 5–6 as the framework matures.
⏳ Terrain/hazards, the post-campaign max-tuning gauntlet ([[11-world-and-overworld]] §5) = later.

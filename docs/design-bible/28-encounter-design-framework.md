# Encounter Design Framework (boss parts, phases, multi-target, variety) — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** 🟨 first worked example (ch.1 combat tutorial) added — awaiting your reaction
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

### 7. Worked example — Ch.1 Combat Tutorial encounter (locked shape, 2026-07-09)

The first encounter authored against the template above, doubling as the game's mechanics tutorial. Roster =
**Wildcat's Talon** ([[40-enemy-roster]]); companion = **Rrrobert** ([[42-companion-roster]]).

1. **Identity & Fantasy** — the player's very first fight; teaches the spin, abilities, item use, targeting,
   and (briefly) an Ultimate — all before any class exists. Campaign slot: ch.1 opening, right after character
   creation. Feeling target: *"I can already do cool things, and this game has depth."*
2. **Roster & Board** —
   - **Phase 1 (2v2):** PC (starting weapon = **sword / bow / staff, player's choice** — weapon type only, no
     class) + **Rrrobert** (Skirmisher, L1 kit) vs. **Talon Scout** + **Talon Archer**.
   - **Phase 2 (2v3):** **Talon Leader** arrives, revitalizes the Scout & Archer → same PC + Rrrobert now
     face all three.
   - No boss parts/core here — straightforward roster, not a multi-part fight.
3. **The Core Decision** — Phase 1 is pure onboarding (no real tactical question yet); Phase 2 introduces the
   first real one: **focus the Talon Leader** (tutorial explicitly nudges the player to target him), teaching
   that targeting is a deliberate choice, not automatic.
4. **Phases** —
   - **Phase 1, turns 1–3 (kept short by design):**
     - **Turn 1 (PC):** only option is a **plain weapon spin** — no abilities/items yet. Teaches the base spin.
     - **Turn 2 (Rrrobert, AI-scripted):** uses a **level-1 Skirmisher ability**, teaching the player what an
       ability turn looks like before they're asked to use one themselves.
     - **Turn 3 (PC):** a dedicated **"use an item" turn** — opens the (new, see below) in-combat item panel
       and uses a consumable. 🟦 *Which item is TBD — player's call later; needs only to demo the panel.*
     - Announce line: none needed — Talon Scout/Archer are simple enough Phase 1 has no phase-change event.
   - **Transition:** short in-fiction beat — Talon Leader arrives and roars **"Fight for Your Lives!"**
     ([[40-enemy-roster]] on-enter effect) — an intimidation-driven command, not encouragement, that bullies
     the Scout & Archer back to full fighting shape → phase changes to 2v3. This IS a `BossPhase`-style
     trigger even though Talon Leader isn't a boss — reuse the same `phase_changed` signal/UI treatment (§2)
     for the free legibility win.
   - **Phase 2:** the Bonus Meter is **pre-filled for tutorial purposes only** (not earned through play) so
     the PC can immediately use a **temporary Ultimate** — see Special Mechanics below. Tutorial UI explicitly
     encourages targeting the **Talon Leader**, teaching the click-to-target system from §-shipped conventions.
5. **Special Mechanics** —
   - **The "Classless Outlander" temp Ultimate** `[ASSUMPTION]` — a one-time, tutorial-only grant explained
     in-fiction by the Outlander trait ([[10-storyline]] §4), NOT a real class Ultimate (PC hasn't picked a
     class yet). Spec: **5 action reels total**, **all WILD**, **crit-biased** (reuse the shipped sticky-wild
     crit-bias convention, e.g. Skirmisher/Warden precedent), **full damage to the targeted enemy** (steered
     toward the Talon Leader) **+ half damage (`ceil`, per CLAUDE.md round-up convention) to every other
     enemy struck** — i.e. Collateral Damage/Earthquake's splash shape, reused rather than reinvented. This
     never recurs after the tutorial (no other "classless" Ultimate exists in the real kit).
   - **Talon Leader's on-enter "Fight for Your Lives!"** — an intimidation-based forced rally (heals Scout &
     Archer + a short Empowered buff, see [[40-enemy-roster]] `[ASSUMPTION]`) — his minions fear HIM, not PC.
6. **Build Hooks** — none yet (PC is classless) — this encounter's job is to demo mechanics that recur all
   game (abilities, items, targeting, Ultimates), not to reward a build.
7. **Tuning Levers** `[ASSUMPTION]` — Talon Scout/Archer/Leader HP, rally heal/buff magnitude, temp-Ultimate
   splash %, how full the pre-filled meter needs to be, whether Phase 1 can be lost (probably not — it's a
   tutorial; a loss state here would need its own design pass).
8. **Legibility Checklist** — item hover-tooltip (new UI, below), ability-turn framing for Rrrobert, the
   phase-change announce beat for the Leader's arrival, target-highlight during the temp Ultimate — all reuse
   shipped conventions except the new item panel.
9. **Win / Lose / Flee / Rewards** — win = Talon Leader defeated (Scout/Archer are trash, don't gate the win);
   no flee (tutorial); rewards are narrative only (leads into §1 step 4 aftermath), no loot — starter gear was
   already chosen as the weapon pick in step 2.

**New combat-UI requirement this encounter surfaces (not yet built):** an in-combat **item-use panel** —
open-able inventory list, one row per item: small icon, item name, hover-over description, and a compact
effect indicator (e.g. *[bottle icon]  Minor Healing Draught  +4–10 HP*). This is real future combat-code
work, tracked in [[25-inventory-and-storage]] §9 — **not built yet**, deferred until combat-side work resumes.

### 8. Open questions
- ❓ Flee/retreat allowed? ❓ Environmental hazards/terrain in scope? ❓ Difficulty band targets (deferred-difficulty memory: build one default now).
- ❓ Ch.1 tutorial: exact item for the "use an item" turn (§7 above); final Talon Leader name; exact rally/temp-Ultimate numbers.

### Scope / phase
✅ Boss-part primitive + data phases + archetypes 1–4 for early chapters; 5–6 as the framework matures.
⏳ Terrain/hazards, the post-campaign max-tuning gauntlet ([[11-world-and-overworld]] §5) = later.

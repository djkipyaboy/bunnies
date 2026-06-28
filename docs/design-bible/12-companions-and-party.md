# Companions & Party System (KOTOR-style) — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** 📝 seeded
> **Related:** [[10-storyline]] · [[20-character-creation]] · [[22-leveling-and-progression]] · [[42-companion-roster]]
> **Your direction (2026-06-28):** *"Party works like KOTOR 1 & 2 — recruitable allied characters with
> story ties to the world and the PC's party. When in the active party they are as fully fleshed out as the
> PC: class, level, talents, equipment, etc. Plus hundreds of designed enemy combatants and static NPCs."*

---

## 💬 BRAIN DUMP (yours)

- 🟦 How big is the **active party**? (combat is architected for **up to 3 PCs** today — is the active party 3, or larger with a bench?)
- 🟦 How many **total recruitable companions** across the campaign (ballpark)?
- 🟦 Are companions **class-fixed** (this otter is always a Skirmisher) or do they level/spec like the PC with freedom?
- 🟦 Can companions **die / leave permanently** based on story choices (KOTOR)? 
- 🟦 Does the PC's **alignment / influence** with a companion change their story, powers, or loyalty?

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. Design goal & fantasy
Build a party from allies you meet and earn through the world; each is a real character with a stake, not a
stat-block. The combat layer already runs **N PCs vs M enemies** and treats every combatant uniformly, so a
companion in the active party is mechanically a full PC. 🔬 *KOTOR 1/2: ~9 recruitable companions, each with
a personal quest, banter, and world ties; a subset are active at once.*

### 2. The three character tiers (this is the unifying model)
🔬 *The encounter research concluded the cleanest architecture is "everyone is a Combatant; tiers differ by
data."* Applied to your direction:
- **PC** — the created hero ([[20-character-creation]]). Full class/level/talents/gear.
- **Companion** — recruitable ally. **Identical depth to the PC** when active (class, level, talents,
  equipment, Reel Points). Carries a story arc ([[10-storyline]]) + the data row in [[42-companion-roster]].
- **NPC / Enemy** — designed content, NOT player-built. Static NPCs (merchants/townsfolk/quest-givers,
  [[41-npc-roster]]) and the hundreds of enemies ([[40-enemy-roster]]). Enemies reuse the combat
  `Combatant` + the type-effectiveness AI already shipped.
💡 *In data terms: PC and Companion are both "a `CharacterClass`-stamped `Combatant` with a progression
profile"; the only difference is who authored the starting build and the story metadata.*

### 3. Recruitment
🟦 *How are companions recruited?* 💡 *Story-gated encounters (KOTOR): meet → a beat/quest → they join the
roster.* ❓ *Are any **missable** (choice-locked)? — ties to the alignment question and the deferred-difficulty stance.*

### 4. Party management
- 💡 **Active party = up to 3** (matches the shipped combat ceiling; revisit only if you want a bigger board).
- 💡 **Bench/roster** of all recruited companions; swap at the **Rest/Abbey workbench** ([[11-world-and-overworld]] §2).
- 🟦 *Do benched companions still earn XP (FF "everyone levels") or only the active 3 (KOTOR)?* 💡 *Recommend
  benched companions earn **reduced/partial** XP so the bench stays viable without trivializing choice.*

### 5. Companion progression parity
✅ *Companions use the SAME systems as the PC:* [[22-leveling-and-progression]] (reel-edits on level),
[[23-talents-and-reel-points]] (the budget), [[24-equipment]], [[21-stats-and-attributes]]. 🟦 *Open: are
companions **free-spec** (player chooses their reel edits) or do they have **guided/signature** builds that
nudge their identity (KOTOR companions had defined-but-flexible classes)?* 💡 *Recommend signature starting
build + free growth — keeps identity but respects player agency.*

### 6. Influence / loyalty (KOTOR's signature)
💡🔬 **Adopt a light "Influence" track per companion** (KOTOR 2): the PC's choices raise/lower influence;
high influence unlocks that companion's **personal quest, extra reel faces, or an Ultimate upgrade**
(mirrors Persona Confidant→combat-unlock, reel-shaped). Keep it **non-punishing** (no permanent lockouts) per
the deferred-difficulty memory. ❓ *In for 1.0, or parked?*

### 7. Data model sketch (→ Godot Resources)
💡 *A `Companion` resource = `{ id, display_name, species, class_id, signature_build, story_arc_id,
recruit_condition, influence_track, portrait }` wrapping the existing `CharacterClass`/`Combatant` stamp.*
Reuses `ClassLibrary.build_combatant`. The active party is just the `_pcs` array the combat scene already
consumes. Enemies/NPCs stay in their libraries ([[40-enemy-roster]]/[[41-npc-roster]]).

### 8. Cross-system hooks
Recruitment & arcs ← [[10-storyline]]; swapping/leveling ← [[11-world-and-overworld]] rest beats; shared bank
& gold across the whole roster ← [[26-banking-cross-character]] (the replayability spine literally hands gear
between characters).

### 9. Open questions
- ❓ Active-party size (3 vs. larger). ❓ Bench XP rule. ❓ Free-spec vs. signature companions.
- ❓ Influence/loyalty in for 1.0? ❓ Permanent companion loss/missability?

### Scope / phase
✅ *Recruit + active-party-of-3 + parity progression is the 1.0 core.* ⏳ *Deep influence trees, romance-style
arcs, permadeath companions = scope after the spine locks.*

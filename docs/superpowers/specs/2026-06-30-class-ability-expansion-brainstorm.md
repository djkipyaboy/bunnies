# Class Ability Expansion — BRAINSTORM MENU (awaiting player picks)

> **STATUS: 🟨 brainstorm menu — NOT yet a locked spec.** This captures the 2026-06-30 brainstorm so the
> next session can resume instantly. **Next action: the player reacts to these 21 options** (confirm/swap
> the ⭐ recommended pairs, veto anything off-fantasy, cut any unwanted new effect). Once picks settle,
> THIS becomes a proper design spec (the chosen 2 new abilities/class + unlock cadence + new effects + the
> ENDGAME combat tester), then → writing-plans.

---

## Goal (locked this session)

Grow each class from **1 base ability + 1 Ultimate** (the current prototype = "early-game" kits) to
**3 base abilities + 1 Ultimate**, on this unlock cadence:

| Level | Unlock |
|---|---|
| **L1** | Base ability #1 (the class's *current* base ability) |
| **L3** | Ultimate (bonus-meter spender — the class's *current* Ultimate) |
| **L5** | Base ability #2 *(NEW)* |
| **L7** | Base ability #3 *(NEW)* |

So we design **2 NEW base abilities per class** (14 total), develop the **new buffs/debuffs** they apply,
and build an **ENDGAME combat tester** with every ability unlocked for each class.

### Design philosophy (locked)
**Option A — differentiated kit — with the hardest possible class-fantasy lean.** The three base abilities
of a class each fill a *distinct tactical role* (so each turn's choice is a real trade-off, pillar #4), but
every ability is unmistakably *that class's*.

**Why this won't create a rigid "optimal trio" (the player's concern):**
1. Differentiation lives *inside* each class; every class is a complete, self-sufficient kit owning a
   fantasy no other replicates — so no class is strictly-better and there's no "best 3."
2. The new buffs/debuffs are *shared, overlapping infrastructure* — e.g. **Sundered** raises *everyone's*
   damage into a target. Many trios synergize, not one dominant chain.
3. Talents (later) personalize within a class.
4. Numbers stay playtest-tuned; the design rule is "no strictly-best option."

---

## Shared new-effect vocabulary

A small reusable set (not 14 one-offs) so the ENDGAME tester integrates cleanly. NEW effects:

| Effect | Kind | What it does |
|---|---|---|
| **Sundered** (debuff) | `MULTIPLIER_EDIT` | Target takes more damage from *all* sources (uses the currently-unused kind) |
| **Weakened** (debuff) | `MULTIPLIER_EDIT` | Target's *outgoing* damage reduced |
| **Jinxed** (debuff) | `REEL_FACE_EDIT` | Enemy reels: success→neutral / crit→fail (inverse of Luck) |
| **Rooted** (debuff) | `INITIATIVE_MOD` + flag | Hard slow / control (Earth, traps) |
| **Guarded / Braced** (buff) | new | Incoming damage reduced for N turns |
| **Empowered** (buff) | `MULTIPLIER_EDIT` | Next spin's weapon reels hit harder |
| **Evasion** (buff) | `REEL_FACE_EDIT` | Incoming attacker's hit faces → miss |
| **Regen** (buff) | `DAMAGE_OVER_TIME` (beneficial) | Heal-over-time (mirror of Bleed) |
| **Cursed** (debuff) | `DAMAGE_OVER_TIME` | Mystic DoT |
| **Taunt** (marker) | marker | EnemyAI prefers to target the taunter |

Already exist: Bleed, Slow, Stunned, Hunter's Mark, Inspirational, Shielded.

---

## The 21 options — 3 per class, pick ~2 (⭐ = my recommended pair)

Costs intentionally unstated — `[ASSUMPTION]` numbers tuned in playtest. Each new ability costs the class's
existing resource (Stamina or Mana, per `class_library.gd`).

### ⚔️ Warrior — *Martin, the legendary hero-blade: relentless, courageous, leads from the front*
*Has: Rend (sustained Bleed), Wild Ult (burst). Missing: protection & damage-amp.*
- ⭐ **Sundering Strike** *(control/amp)* — Slashing blow leaves the foe **Sundered**; the whole party hits it harder.
- ⭐ **Heroic Guard** *(defense)* — braces: gains **Guarded** + **Taunt**, pulling fire off fragile allies.
- **Second Wind** *(sustain)* — heals a chunk and **Cleanses** a debuff off himself.

### 🛡️ Vanguard — *Sunflash, the immovable mountain: slow, overwhelming, badger battle-fury*
*Has: Heft (reliability), Rampage Ult (AoE). Missing: an offense identity & control.*
- ⭐ **Bloodwrath** *(offense ramp)* — gains **Empowered** that grows as his own HP drops (high-risk juggernaut).
- ⭐ **Quake Slam** *(control)* — Crushing overhead that reliably **Slows** (or stun-chance).
- **Mountain Stance** *(defense)* — heavy **Guarded** + immune to Slow/Stun; an unkillable anchor.

### 🗡️ Skirmisher — *Basil Stag Hare, the dashing duelist: blinding speed, foppish bravado*
*Has: Flurry (extra swing), Sticky-Wild Ult. Missing: defense & tempo.*
- ⭐ **Feint & Riposte** *(defense/counter)* — gains **Evasion** (incoming hits whiff).
- ⭐ **Quickstep** *(tempo)* — **Haste** (acts earlier / +1 reel next turn).
- **Hamstring** *(control)* — crippling cut that **Slows**.

### 🎲 Chancer — *Cheek the Otter, the storm-slinging gambler: turns chaos into fortune*
*Has: Re-roll, Wildcard Gamble Ult, Luck, casino paylines. Missing: an enemy-facing tool & a payline play.*
- ⭐ **Loaded Dice** *(luck/payline)* — adds crit faces **and** lights an **extra payline** this spin (uses the reserved `extra_lines` hook).
- ⭐ **Jinx the Odds** *(debuff)* — curses a foe with **Jinxed** (their good faces turn bad).
- **Double or Nothing** *(risk amp)* — huge **Empowered** next spin, but crit-fails recoil onto him.

### 🏹 Ranger — *the patient marksman: marks prey, controls range*
*Has: Hunter's Mark (party accuracy vs target), Collateral Ult (AoE). Missing: single-target burst & zoning.*
- ⭐ **Aimed Shot** *(precision burst)* — **Empowered** shot; bonus vs a **Marked** target (own-kit synergy).
- ⭐ **Snare Trap** *(control)* — trap that **Roots** an enemy.
- **Crippling Shot** *(debuff)* — shot to the limb that **Weakens** the foe's damage.

### 🔮 Seer — *the oracle: bends fate, channels raw Mystic power*
*Has: Select your Fate! (type-pick), Big Bang Ult (AoE+heal). Missing: a DoT & focused support.*
- ⭐ **Hex** *(debuff DoT)* — lays a **Curse** (Mystic DoT).
- ⭐ **Foresight** *(support)* — grants an ally **Evasion** or a small shield.
- **Mana Surge** *(amp)* — channels deep mana into a massive **Empowered** on his heavy 2-reel hit.

### 🪨 Warden — *the earthen guardian: shields, roots, steadfast protector*
*Has: Rallying Cry (party shield, no meter), Earthquake Ult (AoE stun). Missing: control & recovery.*
- ⭐ **Entangle** *(control)* — roots erupt: **Rooted** on an enemy.
- ⭐ **Regrowth** *(sustain)* — **Regen** (heal-over-time) on an ally.
- **Bastion** *(defense)* — heavy self-**Guarded** + **Taunt**, the wall the party hides behind.

---

## What's needed next session (player action)
1. React to the 21 options — confirm/swap the ⭐ pairs, veto off-fantasy ideas, cut any unwanted effect.
2. (Optional) we can go class-by-class instead of all at once.
3. Then: promote this to a locked spec → writing-plans → implement + ENDGAME tester.

### Open threads to resolve when specced
- Exact resource costs / cooldowns (all `[ASSUMPTION]`).
- Whether **Taunt** needs EnemyAI changes (currently AI targets by type-effectiveness then lowest-HP).
- Whether **Empowered/Sundered** (`MULTIPLIER_EDIT`) apply pre- or post-type-chart.
- Species-vs-First-9 note (classes currently labelled Squirrel/Vole/Mole, not on the First 9 roster) — a
  cross-system tidy-up for the race system, NOT part of this ability work.

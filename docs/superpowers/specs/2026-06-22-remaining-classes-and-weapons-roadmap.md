# Remaining Work Roadmap — finishing the 1v1 combat prototype

> **Date:** 2026-06-22 · **Status:** Preliminary, for the designer to edit offline before implementation.
> **Purpose:** Track the classes/weapons still to build and the recommended build order. This is a
> *living planning doc* — edit the `[TO DECIDE]` markers and tweak numbers freely; nothing here is locked.
> **Companion docs:** full class design in `2026-06-21-class-system-v1-design.md` (§2 roster, §4A
> abilities, §4B BLEED, §5 weapons); autonomous calls in `../DECISIONS-LOG.md`.

---

## 0. Definition of "complete 1v1 prototype"

All **7 classes fully expressed** — each with: stat spread · starting weapon · a **base Main-1 ability**
· a **real Ultimate** (its own archetype, not the sticky-wild placeholder) — plus the supporting
**Effects** those classes need (heal / cleanse / etc.). Wiring weapon **riders** (Bleed/Root/…) and a
**gear** layer is a natural final polish pass. **Party / N-vs-M is explicitly OUT** of the 1v1 goal.

**Built so far (3/7):** Warrior (Rend→BLEED), Vanguard (Heft + Rampage Ultimate, AoE-ready),
Skirmisher (Flurry + Sticky-Wild). 30 headless suites green; shareable Windows `.exe` produced.

---

## 1. Classes still to build (4 of 7)

All four are designed in the roster but **not implemented**. Each still needs a **base ability chosen**
(only the built three have one; "Rallying Cry" was shelved and could be repurposed below) **and** its
**Ultimate** (none of these four are built).

| Class | Species / test char | Type · reels | Ultimate (unbuilt) | New system it forces | Base ability `[TO DECIDE]` |
|---|---|---|---|---|---|
| **Ranger** | Squirrel · Jess | Piercing · 4 | **Hold & Win Respins** | Per-reel **lock + respin UI** (heaviest UI lift) | e.g. "Take Aim" — add crit faces / a guaranteed hit reel |
| **Seer** | Owl · Sir Harry the Muse | Mystic · 2 | **Multiplier-on-Cascade** | **Cascade/chain resolver loop** + growing multiplier | e.g. "Focus" — set up next-spin damage multiplier |
| **Warden** | Mole · Foremole | Earth · 3 | **Pick'em Bonus** | **Choose-1-of-N modal** + new **heal & cleanse Effects** | e.g. "Rallying Cry" (shelved buff) or a shield |
| **Chancer** | Otter · Cheek | Storm · 4 | **Wildcard Gamble** (Luck) | Post-spin **reroll pass** (+ reserved extra-paylines, deferred) | e.g. "Reroll one reel" (cheap single-reel version) |

> **Stat spreads** (from the design spec §3, `[ASSUMPTION]` — edit freely):
> Ranger 2/4/2/2/1/1 · Seer 0/2/1/6/1/2 · Warden 1/1/3/4/2/1 · Chancer 2/3/2/1/0/4
> (order: Might / Finesse / Vigor / Focus / Grit / Luck).
>
> **HP note:** all classes are currently a flat **300** (testing knob for long fights). Re-differentiate
> per class before "complete" if desired (e.g. Vanguard tankier).

---

## 2. Weapon types so far (the §5 starter menu)

**3 are wired** today (as inline class weapon profiles, *not yet* a reusable `Weapon`/`.tres` library);
the rest are design-only. **Riders:** **Slow** is built + wired (Crushing). **Bleed effect now exists**
(built via the Warrior's Rend) but is **not yet attached as a weapon's inherent rider** — a small step.
Others are design intent.

| Weapon | Type | base · reels | Status |
|---|---|---|---|
| One-Handed Sword | Slashing | 8 · 3 | **wired** (Warrior) |
| Great Maul | Crushing | 15 · 2 | **wired** (Vanguard) · Slow ✓ |
| Sabre (dual-wield) | Slashing | 6 · 4 | **wired** (Skirmisher) |
| Greatsword | Slashing | 14 · 2 | design · Bleed* |
| Battle Axe | Slashing | 12 · 2 | design · Bleed* |
| Dagger | Piercing | 5 · 5 | design · armor-pierce |
| War Spear | Piercing | 10 · 3 | design · reach |
| Hunting Bow | Piercing | 7 · 4 | design |
| War Mace | Crushing | 9 · 3 | design · Slow ✓ |
| Storm Sling | Storm | 6 · 4 | design · knockback |
| War Staff | Mystic | 13 · 2 | design · focus-drain |
| Talisman | Mystic | 7 · 3 | design |
| Earthstave | Earth | 9 · 3 | design · root/poison |

(*Bleed effect exists; wiring it as an inherent weapon rider is a small step.)

**Suggested class → starting weapon for the unbuilt four:** Ranger → Hunting Bow (Piercing 4) ·
Seer → War Staff (Mystic 2) · Warden → Earthstave (Earth 3) · Chancer → Storm Sling (Storm 4).

---

## 3. Build strategy: one class at a time (not batched)

**Why the first batch worked batched:** Warrior/Vanguard/Skirmisher **shared infrastructure** (the
ability-dispatch, the sticky-wild placeholder, reel-editing) and differed mostly in *data* + small
helpers — low marginal cost per class, so three-at-once was efficient.

**Why the remaining four shouldn't be:** each carries a **distinct, largely independent new system**
(lock-respin UI, cascade loop, pick'em + heal/cleanse, reroll). Batching all four means building four
new mechanics before any play-test → high regression surface and **muddy feel feedback** (can't tell
which mechanic feels off). Since "is it fun" is a per-mechanic human call (the hard ceiling), tight
isolated loops win.

**Recommendation:** build them **one at a time**, each a full *design → implement (TDD) → play-test*
loop. Keep the *cheap* parts batched **inside** each class (stats/weapon/base-ability via existing
hooks go fast); spend the focus on the one new Ultimate system.

**Suggested order** (reusable-systems-first, ascending UI cost, de-risking):

1. **Chancer** — reroll pass; reuses Luck + resolver; least new UI; proves a reusable "reroll" capability.
2. **Seer** — cascade loop (reusable for any future cascade idea); Mystic already in the type chart.
3. **Warden** — heal/cleanse Effects (needed game-wide) + pick'em modal; self-heal testable in 1v1.
4. **Ranger** — the lock-and-respin reel UI is the biggest interface job; do it last when reel-UI
   patterns are mature.

---

## 4. Cross-cutting work uncovered along the way (not class-specific)

- **Effect system fill-out:** `Effect.Kind` still has stubs (`MULTIPLIER_EDIT`, `REEL_FACE_EDIT`);
  Warden needs **heal** and **cleanse/dispel** kinds. (Built so far: INITIATIVE_MOD, DAMAGE_OVER_TIME.)
- **Weapon riders:** wire Bleed (exists) + design Armor-pierce / Root / Focus-drain / knockback.
- **Reusable Weapon library:** promote the 3 inline class weapons into authorable `.tres` weapons
  (the §5 menu) so classes pick from a shared list.
- **Gear layer:** `Gear` resource exists (stat bonuses); a real gear pass (Weapon/Armor/Trinket) is a
  post-class polish item.
- **`extra_lines` payline hook:** reserved for the Chancer's Luck "+paylines"; deferred until grids
  larger than 3×3 exist.

---

## 5. `[TO DECIDE]` checklist for the designer (offline)

- [ ] Base ability for each of the 4 remaining classes (see table col 6 for starting ideas).
- [ ] Exact Ultimate tuning per class (cascade cap, reroll odds, pick'em menu contents, respin attempts).
- [ ] Re-differentiate per-class HP (currently flat 300 for testing) — or keep flat for now.
- [ ] Confirm class → starting weapon picks (§2 suggestions).
- [ ] Whether weapon riders + gear are in-scope for "complete 1v1" or a follow-up milestone.

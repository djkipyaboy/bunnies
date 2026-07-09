# World Atlas & Regions (continents, regions, towns, races-per-place) — Design Bible

> **Style:** 📖 Narrative/World Brief (proposals LIGHT–MEDIUM) · **Status:** 🟨 template + first region/town
> (the port town + Pirate Faction) drafted — awaiting your reaction
> **Related:** [[10-storyline]] · [[11-world-and-overworld]] · [[40-enemy-roster]] · [[41-npc-roster]] ·
> [[42-companion-roster]] · [[20-character-creation]] (race passives / reel-hook pass, later)

---

## 💬 BRAIN DUMP (yours)

*What you've already given me: two continents (a primary landmass hosting most of the campaign, and a
"dark continent" where the big bad guys reside and the story likely climaxes), and at least one large port
town on the primary continent, home to a friendly-but-morally-grey Pirate Faction (name TBD) that PC's
Chancer companion comes from. Add more here whenever — new regions, towns, races-per-place, or corrections
to what's below.*

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. How this file works

✅ **Three-tier hierarchy, locked 2026-07-09: Continent → Region → Town.** Chapters map onto regions
(Option A) — a chapter is "set in" one (occasionally two) regions; a region can span multiple chapters if
the story lingers there. **The overworld stays backtracking-friendly** (per your note) — regions/towns list
their neighbors so travel/backtracking has a real map to move through, this doesn't need a hard chapter-gate.
Each tier below has a reusable field template (shown once) — fill dossiers in over time, same
dump→structure→react→lock loop as every other design-bible file.

**Special info boxes** (free-form blockquotes attached to any tier) capture lore/spells/abilities that don't
fit the table columns. Tag one with `🎰 reel hook` when it looks like eventual race/region reel-face material
— **no mechanical follow-through yet**; per your call, we finish populating locations/races/story first, then
do one dedicated pass presenting racial-bonus options off everything tagged this way.

### 2. Chapter Map

| Ch. | Title | Primary region(s) | Beat |
|---|---|---|---|
| 1 | [TBD] | The Frogmire *(🟦 name placeholder — the marsh/wetlands region, primary continent)* | Frogadier camp under siege by Wildcat's Talon; combat tutorial ([[28-encounter-design-framework]] §7); ends with PC + Rrrobert setting out for [ORG]'s hub. |
| 2–?? | 🟦 TBD | 🟦 TBD | *(Author as regions get filled in below — includes wherever the port town/Pirate Faction chapter lands.)* |

### 3. Continents

**Template:**

| Field | Meaning |
|---|---|
| `id` / `name` | placeholder ok |
| `role` | its job in the story (e.g. "primary landmass, hosts most of the campaign" / "the dark continent — antagonist seat, climax setting") |
| `tone` | overall mood |
| `dominant_biomes` | list, → §6 |
| `races_present` | which peoples commonly live here |
| `notable_factions` | major groups based here |

**Dossiers:**

| id | name | role | tone | dominant_biomes | races_present | notable_factions |
|---|---|---|---|---|---|---|
| `continent_primary` | [Primary Continent — name TBD] | Hosts most of the campaign; the "beautiful wilderness fairytale" per [[10-storyline]] §2 | Varied, mostly gentle/hopeful with real danger at the margins | Old-growth forest, tall-grass sea, river/marsh wetlands, farmland/hedgerow, coastal cliffs + port towns, burrow-warrens, alpine highlands, ancient ruins, inland lake/lagoon, orchard hill-country (§6) | All First-9 + the widened non-First-9 list ([[10-storyline]] §6 — Bat-folk etc.) | [ORG] (the militia), the Frogadiers, the Pirate Faction (§5) |
| `continent_dark` | [The Dark Continent — name TBD] | Wildcat's seat of power; forced-labor relic excavation; likely climax setting | Corrupted, harsh — 💡 each biome a twisted mirror of a primary-continent one (§6) | Petrified forest, ashen wasteland, volcanic badlands + excavation pits, a fortress-crater/sunken citadel, toxic bog, storm-wracked shipwreck coast, slave-labor tunnels (§6) | Enslaved/forced-labor populations of many races under the 3's/Wildcat's rule ([[10-storyline]] §6) | The Wildcat's main army; **Wildcat's Talon** ([[40-enemy-roster]], a raiding cell operating out from here); 🟦 the "Tainted Fleet" (§5) |

### 4. Regions

**Template:**

| Field | Meaning |
|---|---|
| `id` / `name` | placeholder ok |
| `continent` | which one |
| `biome` | → §6 |
| `tone` | mood |
| `chapters` | which chapter(s) are set here (Chapter Map §2, reverse-lookup) |
| `races_good` / `races_bad` | who lives here, split by which side they lean (race ≠ alignment overall, but a given region can skew) |
| `dangers_resources` | notable threats + what's craftable/collectible here |
| `adjacent_regions` | for backtracking/overworld travel |

**Dossiers so far:**

| id | name | continent | biome | tone | chapters | races_good | races_bad | dangers_resources | adjacent_regions |
|---|---|---|---|---|---|---|---|---|---|
| `region_frogmire` | The Frogmire *(name TBD)* | Primary | River/marsh wetlands | Humble, close-knit, wary of outsiders | Ch.1 | Frog (Frogadiers) | — (Wildcat's Talon raids in, doesn't live here) | The opening siege; 🟦 resources TBD | 🟦 TBD |
| `region_saltmere` | The Saltmere Coast *(name TBD)* | Primary | Coastal cliffs + port town | Bustling, mercantile, lawless-but-fair | 🟦 TBD — later chapter, not ch.1 | Otter/Hare-leaning seafaring population + the widened non-First-9 list (bird-folk, Bat-folk, merfolk dockhands — a natural home for that variety direction) | — | The Pirate Faction's turf; offshore skirmishes vs. the Tainted Fleet (§5); 🟦 craft resources TBD (shipwright materials? pearls/salvage?) | 🟦 TBD |

🟦 *Next regions get authored as chapters get planned — same "author by chapter, don't front-load" cadence as [[40-enemy-roster]].*

### 5. Towns & Factions

**Template:**

| Field | Meaning |
|---|---|
| `id` / `name` | placeholder ok |
| `region` | which one |
| `size_type` | village / port / city / hidden enclave |
| `population_races` | who lives/works here |
| `factions_present` | groups based here |
| `services` | shop / rest / quest-board / recruit ([[11-world-and-overworld]] §2) |
| `special_info_box` | free-form lore/spells/abilities; `🎰` tag if reel-hook candidate |

**Dossier — the port town (worked example):**

| Field | Value |
|---|---|
| `id` | `town_saltmere_port` |
| `name` | [Port Town — name TBD] |
| `region` | The Saltmere Coast |
| `size_type` | Port city — the primary continent's largest coastal hub |
| `population_races` | Sailors/dockworkers drawn from across the widened species list — Otters and Hares are common, but Bat-folk, bird-folk, and merfolk dockhands give it the most racially varied population on the primary continent so far |
| `factions_present` | **The Pirate Faction** (name TBD, below); common merchants/shipwrights; 🟦 possibly an [ORG] customs/liaison presence — open question |
| `services` | Shop (exotic/imported goods — a natural spot for rare crafting materials, [[27-crafting]]); quest-board (bounties against the Tainted Fleet); 🟦 recruit — this is where the Chancer companion joins (race TBD, [[42-companion-roster]]) |
| `special_info_box` | *(see Pirate Faction write-up below — shared, since the faction defines the town)* |

> **The Pirate Faction** (name TBD) — ✅ **morally grey, not evil: opportunists with their own code**, wary of
> outsiders and [ORG] alike at first. **Friendly to PC and party once trust/favor is earned through story
> actions** *(🟦 open question: this implies a lightweight faction-reputation mechanic — not designed yet;
> parking-lot candidate, see [[99-parking-lot]])*. Their real enemy: the **Tainted Fleet** — sailors and sea
> creatures corrupted under the Wildcat's dominion, raiding the shipping lanes the Pirate Faction depends on.
> This shared enemy is the natural bridge from "grey and guarded" to "allied" — no redemption arc needed,
> they were never on the Wildcat's side. **The Chancer companion** ([[42-companion-roster]] — race still
> TBD among the remaining open slots) comes from this faction; their gambler/luck flavor (cutlass work, dice,
> nerve) is a `🎰 reel hook` candidate for the later racial-bonus pass.

🟦 **The Tainted Fleet** — a new enemy faction implied by the above (corrupted sailors/sea creatures serving
the Wildcat, opposing the Pirate Faction). Not authored yet — flagged in [[40-enemy-roster]] as a future
batch, likely a later/climax-adjacent chapter given it's tied to the dark continent.

### 6. Biome reference list (a menu to pull from when authoring new regions)

**Primary continent** — old-growth hollow-tree forest · tall-grass "sea" · river/marsh wetlands (Frogadier
territory) · rolling farmland/hedgerow country · coastal cliffs + port towns · underground burrow-warrens ·
alpine highlands · ancient First-9 ruins · inland lake/lagoon (merfolk) · orchard/terraced hill-country.

💡 **Dark continent — each a corrupted mirror of a primary-continent biome:** petrified dead forest (↔
old-growth forest) · ashen/blighted wasteland · volcanic badlands + forced-labor excavation pits (↔ farmland/
ruins, and straight from the Schism lore) · a fortress-crater or sunken citadel (the Wildcat's seat) · toxic
bog (↔ wetlands) · storm-wracked shipwreck coast (↔ the port town) · slave-labor tunnels (↔ burrow-warrens).

### 7. Open questions
- ❓ Port town / Pirate Faction / Tainted Fleet names — all placeholder.
- ❓ Faction reputation/favor mechanic (how the Pirate Faction's trust is earned) — undesigned; candidate for [[99-parking-lot]] until a system brief is warranted.
- ❓ Which of the remaining open companion race slots (Hare/Otter/Badger/Mouse/Turtle) is the Chancer from the Pirate Faction?
- ❓ Does the port town double as the [ORG] hub town from [[10-storyline]] step 6, or is it a separate, later-chapter location? *(Leaning separate — the hub reads like an early, inland/central location, the port a later coastal one — but not decided.)*
- ❓ Region count/pacing per continent — how many regions before the dark continent is reached?

### Scope / phase
✅ Three-tier template + Chapter Map shape locked. The Frogmire (ch.1) and Saltmere Coast/port town/Pirate
Faction dossiers are first-pass content, reactable like every other draft in this bible. ⏳ Full continent
authoring, the Tainted Fleet, and the faction-reputation mechanic wait on later passes.

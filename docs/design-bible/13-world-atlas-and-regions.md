# World Atlas & Regions (continents, regions, towns, races-per-place) — Design Bible

> **Style:** 📖 Narrative/World Brief (proposals LIGHT–MEDIUM) · **Status:** 🟨 template + first region/town
> (the port town + Pirate Faction) drafted; primary-continent shape + full 12-slot biome chain LOCKED
> 2026-08-25/26 (§4, §6); both First-9 ruins now locked (frost-forest + old-growth's Towering Spire-Tree,
> 2026-08-26); wild coast given real shape + a Turtle export port town + the Canal + Yak (2026-08-27); the
> Northern Icecap's secret passage now cross-referenced to the Icecap Reveal story beat (2026-08-28,
> → [[10-storyline]] §6) — awaiting your reaction on the rest
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
| 1 | [TBD] | The Frogmire *(🟦 name placeholder — the marsh/wetlands region, primary continent)* | Frogadier camp under siege by a Returned raiding cell led by Wildcat's Talon; combat tutorial ([[28-encounter-design-framework]] §7); ends with PC + Rrrobert setting out for The Vigilant's hub. |
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
| `continent_primary` | [Primary Continent — name TBD] | Hosts most of the campaign; the "beautiful wilderness fairytale" per [[10-storyline]] §2 | Varied, mostly gentle/hopeful with real danger at the margins | 12-slot north-to-south chain on the populated coast — icecap, peaks, frost-forest, old-growth forest, tall-grass sea, farmland/hedgerow, wetlands (Frogmire), coastal cliffs (Saltmere), inland lake, orchard hill-country, peaks, icecap (full detail + whimsy → §6) | All First-9 + the widened non-First-9 list ([[10-storyline]] §6 — Bat-folk etc.) | [ORG] (the militia), the Frogadiers, the Pirate Faction (§5) |
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
| `region_frogmire` | The Frogmire *(name TBD)* | Primary | River/marsh wetlands | Humble, close-knit, wary of outsiders | Ch.1 | Frog (Frogadiers) | — (a Returned raiding cell hits it, doesn't live here) | The opening siege; 🟦 resources TBD | 🟦 TBD |
| `region_saltmere` | The Saltmere Coast *(name TBD)* | Primary | Coastal cliffs + port town | Bustling, mercantile, lawless-but-fair | 🟦 TBD — later chapter, not ch.1 | Otter/Hare-leaning seafaring population + the widened non-First-9 list (bird-folk, Bat-folk, merfolk dockhands — a natural home for that variety direction) | — | The Pirate Faction's turf; offshore skirmishes vs. the Tainted Fleet (§5); 🟦 craft resources TBD (shipwright materials? pearls/salvage?) | 🟦 TBD |

🟦 *Next regions get authored as chapters get planned — same "author by chapter, don't front-load" cadence as [[40-enemy-roster]].*

> **Primary continent shape — LOCKED 2026-08-25.** An A-width **Hourglass** silhouette carrying an
> off-center **Dogleg** mountain spine that runs the continent's length (deliberately *not* a centered
> range). Exact width doesn't matter much — the world scales to fit within it. The off-center spine splits
> the continent into two long coastlines, which is the in-fiction reason coastal towns and sailing matter
> here: crossing the divide needs boats, not just reaching open ocean. One coast is the **populated coast**
> (Frogmire, Saltmere, and the full biome chain in §6 all live here); the other is a deliberately sparse,
> lightly-detailed **wild coast** — a frontier held in reserve for a later "beyond the passes" arc, given
> real shape but only loose terrain concepts so far (§6). **Rivers run the spine's full length, feeding both
> coasts** — mountain runoff threads every biome in the §6 chain into one watershed.

> **The Canal — LOCKED 2026-08-27.** A magical waterway crosses the spine at a low point on the border
> between the Saltmere Cliffs (#8) and the Inland Lake (#9), running off innate magic with **no upkeep
> needed** — the only crossing between the two coasts that doesn't require sailing around the continent.
> Built as a joint work between the **First-9 and the naturally magical merfolk of the Inland Lake**,
> sharing knowledge toward the shared goal of bettering the world — this is what originally connected the
> populated and wild coasts, before the two grew estranged. It's the trade route the wild coast's exports
> (§6) travel through today. Exact era/timing relative to the Schism and War of the First-9 not pinned down
> yet. Many expeditions have tried going around/through the northern or southern icecaps instead — none
> have succeeded, and some crews have been stranded in those biomes, potentially found dead or alive by the
> PC party on a future icecap expedition.

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
> actions.** 🟦 **2026-08-24 player direction: NOT a numerical reputation track** — trust is earned through a
> dedicated narrative quest/sequence/dungeon (content, not a meter). Rewards for earning it: **Pirate Faction
> crafting recipes** ([[27-crafting]] account-wide unlock) and a **race-unique Pirate cosmetic outfit** (ties
> to the parking-lot Cosmetics item, [[99-parking-lot]] §C — "do my characters look cool?" is expected to be
> a load-bearing part of the game's appeal). Not designed in detail yet — no quest beats, no recipe list, no
> outfit specifics. Their real enemy: the **Tainted Fleet** — sailors and sea
> creatures corrupted under the Wildcat's dominion, raiding the shipping lanes the Pirate Faction depends on.
> This shared enemy is the natural bridge from "grey and guarded" to "allied" — no redemption arc needed,
> they were never on the Wildcat's side. **The Chancer companion** ([[42-companion-roster]] — race still
> TBD among the remaining open slots) comes from this faction; their gambler/luck flavor (cutlass work, dice,
> nerve) is a `🎰 reel hook` candidate for the later racial-bonus pass.

🟦 **The Tainted Fleet** — a new enemy faction implied by the above (corrupted sailors/sea creatures serving
the Wildcat, opposing the Pirate Faction). Not authored yet — flagged in [[40-enemy-roster]] as a future
batch, likely a later/climax-adjacent chapter given it's tied to the dark continent.

**Dossier — the wild-coast export port (LOCKED 2026-08-27, name TBD):**

| Field | Value |
|---|---|
| `id` | `town_wildcoast_port` |
| `name` | [Export Port — name TBD] |
| `region` | Wild coast, at the Canal's western mouth (§4) |
| `size_type` | Port town — the wild coast's one real settlement so far |
| `population_races` | **Turtle-majority** population; **Yak** traders/haulers come down from the southern icecaps and spine mountain range to sell/ship through here, though they're NPC-population flavor, not a designed playable or companion race yet ([[10-storyline]] §6) |
| `factions_present` | 🟦 not yet named — presumably a merchant/shipping guild running the Canal trade; open question |
| `services` | Shop (wild-coast exports, below); the Canal itself is the town's reason to exist — goods gathered across the wild coast funnel here before sailing through to the populated coast |
| `special_info_box` | *(see exports list below)* |

> **Wild-coast exports (LOCKED 2026-08-27, flavor/background detail — no mechanical items required yet):**
> tropical fruit and vegetation, plus a **propensity for magical herbs/teas** in high demand worldwide,
> straight from the port's own surrounding terrain; **wind-scoured highlands** (Yak country) — yak-wool
> textiles, cured/preserved meats, a resonant highland mineral/crystal that hums or carries sound (an
> acoustic-magic cousin to the frost-forest's singing icicles, §6 #3); **deep old forest, unmapped** — dense
> near-petrified timber (ship masts, weapon hafts), pelts from whatever keeps this forest unmapped, a rare
> bioluminescent fungus or shadow-dye plant; **fog-bound moor** — peat/turf fuel, moor-berries for dye or a
> potent liquor, a foraged fungus with mild visionary properties; **black-sand shore** — iron-rich black sand
> for smithing (a wild-coast counterpart to Saltmere's amber-as-currency angle), volcanic-glass tool/jewelry
> stock, shipwreck salvage; **wild salt marsh** — coarse wild-harvested salt, medicinal reeds, an exotic
> eel/fish catch; **southern icecap** (Yak country) — **Ice** as a luxury/refrigeration export, rare
> cold-adapted furs, "frozen delicacies" preserved well enough to ship as a novelty.

### 6. Biome reference list (a menu to pull from when authoring new regions)

**Primary continent, populated coast — 12-slot chain, north to south, LOCKED 2026-08-25/26.** Follows the
spine's own length (see the shape callout in §4); the spine's two ends are the northern/southern peaks, so
the chain runs pole to pole. Rivers run the whole chain, spine to both coasts (§4). The **wild coast** on
the spine's other side now has real shape and a first pass of loose terrain concepts, listed after the main
chain below.

1. **Northern icecap.** Its far interior holds the aurora's true wellspring (§2's visible glow is only the
   surface of it) — a First-9 song-magic pocket dense enough to still carry a First-9-era imprint. Reachable
   only via the secret passage from the frost-forest ruin (§7 #1) — payoff for that passage LOCKED
   2026-08-28 as **the Icecap Reveal**, a mid/late-campaign story beat → [[10-storyline]] §6.
2. **Northern peaks** *(top of the spine).* Aurora reads in-fiction as First-9 song-magic residue.
3. **Frost-forest transition** *(thin band).* "Singing icicles" — wind through frost-laced branches rings
   out chime-tones that shift pitch ahead of a storm. Hosts a **First-9 ruin** at its border with #2/#4 —
   **explicitly the 6's destroyed settlement** from [[10-storyline]] §6 (the Final Skirmish & the Elders'
   Sacrifice) — a present-day explorable ruin, not just flavor.
4. **Old-growth hollow-tree forest.** Firefly streetlights in the tree-towns. Hosts a **second First-9
   ruin, LOCKED 2026-08-26** — the **Towering Spire-Tree**, a distinct site and incident from the
   frost-forest ruin (§3 above). Originally a **stone spire built by a small discovering group from the 6**
   (which member is undecided — a placeholder, but definitely one of the 6, likely whichever is native to
   this biome) to reach a **powerful natural magic source** found at this location; the steep earthen slope
   that spirals the site was carved by that same group as their access path to the source. The site was
   **remote and deliberately undefended** — First-9 hubris, believing beings of their power faced no real
   danger — and its caretaker(s) used the tapped source to empower their creations, the **Hayforged** (§5
   below), studying and caring for them here. During the **War of the First-9**, Wildcat's forces caught the
   site unaware while marching toward the Final Skirmish at the 6's main settlement — a separate battle from
   that Final Skirmish, defeating the few defenders and wrecking the spire. The site's caretaker released the
   Hayforged before they could be captured or harmed. As the source was tapped and later left to run wild
   after the attack, **roots and moss slowly enveloped the stone spire, transforming it over time into the
   massive living tree that stands today** — ruin and living thing fused into one. **Present-day access is
   SE-only**: the player path swirls in from the biome's southeast, spiraling around the tree as it climbs
   the original earthen slope, ending at a clifftop overlook at the tree's crown — the only way in. Full
   dungeon/encounter layout is a later pass, → [[28-encounter-design-framework]].
5. **Tall-grass "sea."** Home to the **Hayforged** — First-9-made, golem-like grass-whale constructs, a
   lingering display of First-9 power/prowess whose slow wakes are visible for miles. **Origin LOCKED
   2026-08-26**: grown/given life at the Towering Spire-Tree site (§4) as their caretaker's own display of
   craft, then **released into the wild during that site's fall** in the War of the First-9 — they fled here
   specifically because this field of tall grass is the very hay they were grown from before being given
   life. Their residual innate magic is now read as the cause of the biome's own unnaturally **exponential
   growth**, not just their own continued existence. At dusk, pollen drifts glow faintly and locals read
   weather by which way they stream — this is where the **day/night cycle** open question first came up, see
   §8. The underground burrow-warrens (below) surface most visibly here, poking through the grass like a
   second landscape — now confirmed as an inhabited community and the planned home of the fast-travel
   system, see §7.
6. **Rolling farmland/hedgerow country.** Self-trimming hedge-mazes + scarecrow guardians (ties to the
   Harvester's "Old Strawfellow" lore, `docs/superpowers/specs/2026-08-24-harvester-talent-tree-design.md`);
   hedges that have grown into odd shapes mark old disputes — a living record of local history.
7. **River/marsh wetlands — Frogmire.** Will-o'-wisp lanterns and lily-pad hamlets; frog-folk lantern-boats
   ferry the wisp-light around at night, giving the region a visible nightlife/economy beat.
8. **Coastal cliffs + port towns — Saltmere.** Amber-fossil cliffs (ties to Amber-as-currency lore); tide
   pools occasionally strand tiny bits of living, still-forming amber — a visual seed for how the currency
   is harvested before it fully hardens. Its border with #9 is where **the Canal** (§4) crosses the spine.
9. **Inland lake/lagoon** *(mountain-runoff fed, not coast-fed).* A merfolk town that fully surfaces only
   once a season, for a festival/trade event, rather than being visible year-round. Its border with #8 is
   where **the Canal** (§4) crosses the spine — the merfolk here co-built it with the First-9.
10. **Orchard/terraced hill-country.** Spiraling jeweled-fruit terraces.
11. **Southern peaks** *(bottom of the spine).* An inverted counterpart to the northern Aurora — a
    permanent, dim twilight-glow gap in the sky where the lights never reach. Home territory for the
    **Yak** (§9, [[10-storyline]] §6), alongside the southern icecap (#12).
12. **Southern icecap.** Yak home territory (#11); also exports **Ice** as a luxury/refrigeration good via
    the wild-coast export port (§5, §6 wild-coast list below).

**Wild coast — real shape, loose terrain concepts, LOCKED 2026-08-27 (not full biome dossiers):**
wind-scoured highlands (Yak country, north-mid) · deep old forest, unmapped (mid-upper) · fog-bound moor
(mid) · black-sand shore (mid-lower, home to the wild-coast export port, §5) · wild salt marsh (south).
See the port's dossier in §5 for what each exports.

**Non-latitude extras** (don't own a chain slot): **underground burrow-warrens** thread beneath farmland,
hills, and forest, surfacing most visibly in the tall-grass sea (#5); **First-9 ruins** are a droppable
special-interest location type — the frost-forest one (#3) is locked as the 6's settlement, and the
old-growth one (#4) is now locked as the Towering Spire-Tree, the Hayforged's origin site.

💡 **Dark continent — each a corrupted mirror of a primary-continent biome:** petrified dead forest (↔
old-growth forest) · ashen/blighted wasteland · volcanic badlands + forced-labor excavation pits (↔ farmland/
ruins, and straight from the Schism lore) · a fortress-crater or sunken citadel (the Wildcat's seat) · toxic
bog (↔ wetlands) · storm-wracked shipwreck coast (↔ the port town) · slave-labor tunnels (↔ burrow-warrens).

### 7. Overworld path design (rough pass, LOCKED 2026-08-27)

**Purpose:** a first pass at *how a player actually travels* through each of the 12 populated-coast
biome slots (§6) — not just the abstract north-to-south adjacency already locked there. Built to find
natural drop points for towns/settlements along the campaign route, one zone at a time, top (north
icecap) to bottom (south icecap). Style reference: **WoW-style organic paths** — routes read as worn in
by generations of foot/cart traffic finding the natural line, not laid out efficiently the way a modern
engineer would. Every zone also gets **sporadic smaller settlements/compounds** (single-family or small-
group scale) scattered along its route, separate from the two anchor towns below — those aren't
individually authored yet, just confirmed as a standing rule for every zone.

**Two anchor town candidates locked from this pass:** the farmland/hedgerow zone (#6) and the orchard/
terrace zone (#10) — both sit at a natural crossroads/hub point their own path design produces (a lane
crossroads and a switchback loading-platform level, respectively). Neither is a chapter-authored dossier
yet (§5 pattern still applies: full town dossiers get written up as chapters reach them).

1. **Northern icecap.** No built road — ice doesn't hold generations of wear. A fading line of cairns +
   expedition wreckage marks the one entry from #2, petering out into nothing. One hand-authored offshoot:
   a stranded expedition camp (survivors or remains). No dwellings — confirmed too hostile for permanent
   settlement. **New:** the frost-forest ruin (#3, the 6's destroyed settlement) hides a First-9-built
   secret passage straight through to this icecap — the real reason no *conventional* crossing has ever
   succeeded; the only real way across is through the ruin. **2026-08-28:** that passage's destination is
   now locked — it leads to the aurora's true wellspring, deep in the icecap's interior, the site of **the
   Icecap Reveal** story beat (a vision of the War of the First-9's final clash, the Reality Tear, and the
   dark continent's discovery) → [[10-storyline]] §6.
2. **Northern peaks.** Foot-only switchback trail (too steep for carts) with worn-smooth First-9-era
   waystations at the switchbacks — this is the first sign the eventual cart route doesn't start until the
   terrain flattens further south. One offshoot scramble to an aurora-watch perch, tended by a hermit/
   small-order watch-post (the zone's one dwelling).
3. **Frost-forest transition.** A quick, still foot-only corridor — travelers navigate the "safe line"
   through frost-laced trees by *ear*, following the singing icicles' chime pattern rather than sight (a
   blind/low-vision traveler could out-navigate a sighted one here). The 6's ruined settlement sits just
   off the corridor at the #2/#4 border — now confirmed as a hub connecting the surface corridor, its own
   dungeon, and the secret icecap passage (#1, above). A trapper/woodcutter camp sits at the warm southern
   edge, working both biomes.
4. **Old-growth hollow-tree forest.** The chain's **first real cart road** — a track that weaves between
   the hollow trees' surface roots rather than cutting through them, worn in by generations detouring
   around the same roots. The biome's existing "firefly streetlight tree-towns" (plural) are this zone's
   dwellings, linked to each other by a separate rope-and-plank canopy walkway network *above* the ground
   road, not along it. The Towering Spire-Tree ruin stays its own dead-end offshoot (SE-entry spiral,
   already locked, §6 #4).
5. **Tall-grass "sea."** No built road survives the grass's own exponential regrowth — the only through-
   route is the Hayforged's own migration wakes (the same giants retracing similar routes since this is
   where they were grown; elephant-path logic), making this the one real break in the cart route for
   anyone who can't time a fresh wake. **Underground burrow-warrens are made a real inhabited community
   here** (not just flavor text) — warren-dwelling family groups, living beneath the grass, whose tunnel
   network is a reliable (if cramped, non-cart) alternate route between #4 and #6. **This tunnel network is
   also the planned home of the game's eventual fast-travel system** (discovered in an incomplete state on
   first meeting the warren-dwellers, completed by campaign progress) and doubles narratively as a hidden
   retreat/stealth route even before fast travel unlocks — cross-ref [[99-parking-lot]]'s existing "fast
   travel / overworld navigation" item, don't design that system twice.
6. **Rolling farmland/hedgerow.** ⭐ **Town candidate.** The chain's first *true* cart road — wide, worked
   lanes that bend around whoever's field came first (old farm-country logic, not a grid), a deliberate
   human-built road (unlike #4's root-road). The self-trimming hedge-maze branches off the main lanes as a
   puzzle/exploration pocket (existing Old Strawfellow lore); some hedge-shapes mark old boundary disputes.
   The candidate town sits at a natural lane crossroads; individual farmsteads scatter along the approach
   lanes.
7. **River/marsh wetlands — Frogmire.** 🏘 Town (Ch.1). The cart road continues south as a narrow raised
   timber causeway on stilts — built to let water/wildlife pass underneath rather than damming the marsh;
   also the in-fiction reason a raiding force could march on Frogmire at all for the opening siege (real
   but exposed infrastructure, a natural chokepoint). Frog-folk lantern-boats run the actual water channels
   as a parallel local-only transport layer, invisible/unusable to an outsider without a guide — this is
   the layer that ferries wisp-light at night (existing flavor). Lily-pad hamlets sit off the channels, not
   the causeway.
8. **Coastal cliffs — Saltmere.** 🏘 Port town + Pirate Faction. The road upgrades into a real maintained
   coastal highway here, befitting the continent's biggest port. Two offshoots: a cliffside scramble down
   to the tide-pool amber flats (foraging, dangerous at high tide), and a second, unofficial network of
   smugglers' cliff paths/sea caves that bypasses the official highway and port checkpoints — Pirate
   Faction only shows this to the party once trust is earned. **The Pirate Faction also runs legitimate
   sea-lane trade** up and down the coastline (Frogmire, Saltmere, and further reach), shipping higher-
   value/faster cargo by boat as a real parallel to the overland cart road — the smuggling is their side
   business, not their whole one. Small fishing hamlets dot the highway outside the port proper.
9. **Inland lake/lagoon.** 🏘 Merfolk town + the Canal (crosses the spine at the #8/#9 border, co-built by
   the merfolk and First-9). The highway continues as a shore-hugging ring-road (nothing to cross to most
   of the year). **The merfolk town is large** — breaching to cover 70-80% of the lake's surface during its
   once-a-season festival, and maintaining a magical breathable-air barrier that lets merfolk and surface-
   dwellers move freely inside it during that window. The shoreline docks and their ferry fleet (varying
   sizes) are themselves part of that submerge/surface cycle — invisible and unusable outside the festival,
   rising only when the town does. Lakeside fishing/boating hamlets are the sporadic dwellings.
10. **Orchard/terraced hill-country.** ⭐ **Town candidate.** The ring-road climbs the terraces via a
    switchback cart road cut generations ago to move fruit carts to the lake trade; each switchback landing
    doubles as a small harvest-staging platform. Above where carts stop climbing, narrow foot-only paths
    continue up to the rarer high-terrace fruit. **Not every terrace is cultivated** — some sections sit
    wild/abandoned, overgrown and reclaimed by wildlife, alongside the working farmland. The candidate town
    sits at the busiest switchback level; farmer family plots scatter up and down the slope.
11. **Southern peaks.** Mirrors #2: a foot/pack-animal switchback trail (no cart access) — this is the
    actual origin point of the Yak trade route already referenced in the wild-coast export port's dossier
    (§5). A twilight-gap overlook offshoot mirrors the aurora-watch perch, with its own local
    superstition rather than a First-9 tie-in. **Sparsely populated by the other races, but genuinely lived-
    in Yak home territory** — real generational Yak herding/family compounds along the trail, bigger and
    more numerous than #2's single hermit-post, even though the zone reads as remote/empty to an outside
    traveler.
12. **Southern icecap.** Mirrors #1's no-built-road logic, but **Yak-inhabited**: a real, maintained
    network of cairns/waypoints between the southern-peaks Yak settlements and their icecap herding/
    hunting grounds, fading into the same fainter, untouched, no-successful-crossing interior further in.
    A mirrored stranded-expedition offshoot exists, though the Yak likely already have their own oral
    history about it. Yak edge-camps (closer and more numerous than #1's total absence of dwellings) are
    the zone's settlements.

**Wild coast — deferred, out of this pass's scope.** Paths there will only branch a short distance out
from the export port town (§5) — just enough for goods to reach it — with the rest of that side of the
continent left untouched/unmapped, traversable only through dense foliage and harsh terrain. Full wild-
coast path design waits for its own later session alongside the rest of that coast's biome dossiers.

### 8. Open questions
- ❓ **Day/night cycle** — raised 2026-08-26 during the biome pass (dusk pollen drifts in the tall-grass
  sea, §6). Direction set: Pokémon-style time-of-day **encounter tables** (combat encounters, profession
  minigames like fishing, NPC availability/locations) — explicitly NOT meant to touch combat mechanics.
  Full system undesigned; tracked as its own item in [[99-parking-lot]] (also spun off a future light/dark
  time-of-day class idea, same parking-lot entry).
- ❓ Wild coast terrain — 5 loose concepts + the export port and Canal are now locked (§4/§5/§6), but none
  of it is full biome-dossier detail yet (realistic, less-banded shapes; actual vegetation/waterways) —
  deferred, not urgent.
- ❓ Which of the 6 cared for the Towering Spire-Tree site (§6 #4) — locked as one of the 6, likely whichever
  is native to the old-growth forest biome; the specific member is still a placeholder.
- ❓ Port town / Pirate Faction / Tainted Fleet / wild-coast export port / the Canal — all names placeholder.
- ❓ The wild-coast export port's faction (the merchant/shipping guild presumably running the Canal trade)
  is unnamed.
- ❓ Faction TRUST mechanic (how the Pirate Faction's trust is earned) — direction now set 2026-08-24: a
  narrative quest/sequence/dungeon, NOT a numerical reputation stat, rewarding recipes + a race-unique
  cosmetic outfit (see §5 above). Still needs: the actual quest content, which recipes, what the outfit
  looks like.
- ❓ Which of the remaining open companion race slots (Hare/Otter/Badger/Mouse/Turtle) is the Chancer from the Pirate Faction?
- ❓ Does the port town double as the [ORG] hub town from [[10-storyline]] step 6, or is it a separate, later-chapter location? *(Leaning separate — the hub reads like an early, inland/central location, the port a later coastal one — but not decided.)*
- ❓ Region count/pacing per continent — how many regions before the dark continent is reached?
- ❓ **Fast-travel system** (§7) — direction set 2026-08-27: built on the tall-grass sea's burrow-warren
  tunnel network, discovered incomplete on first meeting the warren-dwellers, completed by campaign
  progress; also usable earlier as a narrative retreat/stealth route. Not designed yet — no unlock beats,
  no UI/travel-node model. Tracked in [[99-parking-lot]]'s existing fast-travel item; don't re-scope there.

### Scope / phase
✅ Three-tier template + Chapter Map shape locked. The Frogmire (ch.1) and Saltmere Coast/port town/Pirate
Faction dossiers are first-pass content, reactable like every other draft in this bible. ✅ Primary-continent
shape (§4) and the full 12-slot biome chain + whimsy pass (§6) are locked. ✅ **Overworld path design** (§7)
— a full rough pass across all 12 populated-coast biome slots, locked 2026-08-27; the wild coast's own path
pass is deferred (§7 closing note). ⏳ Full region-by-region authoring (regions are still just 2 of the 12
biome slots), the wild coast, the Tainted Fleet, and the faction-trust mechanic content all wait on later
passes.

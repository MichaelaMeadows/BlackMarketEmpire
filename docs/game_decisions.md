# Black Market Empire: Game Decisions

This document is the source of truth for design choices. Update it when a mechanic, fantasy, scope, or technical direction changes.

## Core Pillars

- **Code-first Godot development:** gameplay systems should be understandable from scripts and data. Scenes should stay lightweight and composable.
- **Top-down immediacy:** the early game should feel physical and tense, with direct movement, readable spaces, and fast decisions inspired by top-down action games.
- **Rising base power:** the game starts in one small owned building and grows through larger bases, staff, facilities, raids, and eventually wider strategic control.
- **Fictionalized economy:** goods, organizations, and places are fictional. The game should avoid real-world operational detail and focus on risk, logistics, reputation, and pressure.
- **Pressure creates decisions:** heat, scarcity, debt, territory, rival attention, and trust should push the player into tradeoffs.

## Progression Scale

1. **House:** direct player movement inside a small owned base, basic crew, storage, and starter facilities.
2. **Industrial building:** larger rooms, more staff slots, production/storage facilities, and repeatable raid planning.
3. **Compound:** layered defenses, multiple specialized facilities, larger squads, and stronger rival bases.
4. **Network:** multiple holdings, regional pressure, supply lines, market shocks, and strategic delegation.

Each scale should preserve the fantasy of growth while reducing direct micromanagement. The player should still be able to zoom down into important incidents.

## Prototype Loop

The current scaffold implements:

- Move around a top-down starter house.
- Start with $100, unemployment benefits, 20 KG of base inventory capacity, and Benji as a $10/week runner.
- Inspect rooms, slots, starter facilities, crew, storage, weekly cashflow, and raid targets through the phone.
- Send crew to raid abstractly or join a separate raid map.
- Grow toward larger bases by accumulating cash, crew, facilities, and raid results.
- Track district-level fictional markets with diverse goods, local prices, production recipes, consumer willingness bands, habit pressure, and slow trade between connected districts.
- Track unlocks and triggered events through data-driven progression rules fed by gameplay facts like sales, item movement, days, production, and kills.
- Follow a short introductory mission chain through buying, delivery, selling, hiring muscle, squad commands, and the first depot raid; after that raid, guidance ends and play becomes open-ended.
- Completing the introductory depot raid opens intermediate suppliers and starter workbench production. Player production consumes physical base inventory and creates sellable output over game time.

This is deliberately small. It exists to prove input, state, interaction, and HUD flow.

## Near-Term Mechanics

- Replace generic stock with fictional product categories.
- Add larger base tiers such as industrial buildings and compounds.
- Add rival crews with territory influence.
- Add day/night cycles and timed market changes.
- Add heat sources that respond to player behavior.
- Expand or refine the short introductory missions only when a new core mechanic needs teaching; missions are onboarding, not a permanent linear campaign.
- Expand tactical action scenes for raids, ambushes, and escapes.

## Technical Direction

- Use Godot 4.x.
- Keep core game state in autoloads or small resource-like classes.
- Prefer typed GDScript where it improves clarity.
- Keep input bindings close to code while prototyping.
- Build systems behind simple interfaces so later AI passes can extend them safely.
- Add tests or simulation scripts once the economy has enough rules to regress.
- Store maps as JSON data under `maps/` and load them through `MapLoader`.
- Map files should stay schema-light while prototyping: `base`, `buildings`, `walls`, `zones`, `props`, `facilities`, `npcs`, `contacts`, `raid_targets`, and `triggers` are top-level data so new maps can add content without scene edits.
- Enterable buildings are floor records plus separate wall records. This keeps collision flexible enough for doors, rooms, and interiors without making a unique scene for every building.
- Use `zones` for large area materials like roads and woods, and `props` for repeated small objects like trees.
- Triggers are included in the map schema before they are fully active; future passes can attach gameplay behavior to those data records.
- The in-game phone is the main expandable player interface. The base-first loop emphasizes Base, Crew, Raids, Map, Bank, and Market apps.
- The phone Map app must render from the same active map data as the playable world rather than maintaining a separate minimap layout.
- The market simulation should stay abstract and fictionalized. Goods, recipes, consumer segments, districts, and trade routes live in JSON under `data/economy/` so price movement creates strategic signals without becoming real-world instruction.
- Trade source availability, order/trip lifecycle, inventory reservations, manifests, and transporter dispatch live in `TradeState`. `GameState` remains the stable facade that supplies cross-domain context, emits global state changes, and forwards progression effects; world movement must report transitions through that facade rather than mutate trade records directly.
- Local markets advance in daily ticks: anchor supply, production, consumer demand, route trade, price recalculation, trend updates, and habit/desire updates.
- Progression rules live in JSON under `data/progression/` and should consume generic events/metrics instead of being hardcoded into individual gameplay systems.
- Intro missions live in `data/progression/intro_missions.json`, advance sequentially from successful gameplay events, and explicitly end in open play rather than becoming an endless quest log.
- Player production recipes live in `data/production/base_recipes.json`. `BaseProductionState` owns facility jobs, input reservation/refunds, worker requirements, timers, output-space waiting, and completion; `GameState` remains the facade that supplies base context and forwards crafted progression events.
- AI squad intent must yield to explicit world jobs such as raid departure. Departure paths choose a reachable navigation exit instead of the geometrically nearest map edge.
- Newly hired crew use a short arrival job that temporarily owns movement, settles within a practical radius, and clears on stalled or excessive travel time. Squad AI resumes immediately afterward so arrival never becomes a permanent hidden assignment.
- Character health and weapons are component-style scripts. Keep combat simple and data-driven until there is a clear need for richer AI or weapon inheritance.
- Projectiles are the first weapon delivery type. Future weapons should extend data first, then specialized scripts only when behavior meaningfully differs.
- Combat AI is component-style and opt-in from unit data. Units use explicit factions and hostile faction lists, then make decisions for sight, weapon-range engagement, reaction timing, target memory, shooting, chasing, scored cover, suppression response, squad target sharing, squad spacing, and optional follow-anchor cohesion.
- Player combat crew accepts persistent whole-squad Follow, Attack, and Hold intent. Orders constrain or prioritize the reactive combat states rather than replacing them: Attack prioritizes a chosen hostile, Hold defends per-unit anchors within a limited engagement area, and Follow restores player-anchor cohesion.
- Gunplay remains data-first: weapon type, accuracy, movement spread, recoil, magazines, reloads, bursts, projectile count, projectile arc, and effective/preferred range should be tuned through weapon dictionaries before adding specialized weapon scripts.

## Tone

The tone should be stylish, tense, and strategic rather than instructional. The player is building a fictional criminal empire inside a pressure-driven game system, not learning real-world procedures.

## Street-Level Visual Direction

- The neighborhood view targets gritty pixel art: dark asphalt, worn interiors, dirty brick, muted greens, cold streetlights, warm window light, and small neon accents.
- The first vertical slice keeps maps JSON-driven and code-first, but visual data can include `visual_id`, `variant`, material hints, prop scale, and prop z-order hints so later authored assets can replace procedural fallbacks.
- Characters should use animated sprite-style presentation with readable facing, walking, aiming, firing, hurt, and death states. Gameplay state remains in controllers and components.
- World labels and health bars should be subdued. Labels should feel like a temporary affordance, while health bars should appear only when useful.
- The phone map should stay abstract and readable rather than reusing detailed world art.

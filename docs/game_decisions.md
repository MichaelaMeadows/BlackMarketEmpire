# Black Market Empire: Game Decisions

This document is the source of truth for design choices. Update it when a mechanic, fantasy, scope, or technical direction changes.

## Core Pillars

- **Code-first Godot development:** gameplay systems should be understandable from scripts and data. Scenes should stay lightweight and composable.
- **Top-down immediacy:** the early game should feel physical and tense, with direct movement, readable spaces, and fast decisions inspired by top-down action games.
- **Rising abstraction:** the game starts at street level and gradually turns into a strategic empire simulator.
- **Fictionalized economy:** goods, organizations, and places are fictional. The game should avoid real-world operational detail and focus on risk, logistics, reputation, and pressure.
- **Pressure creates decisions:** heat, scarcity, debt, territory, rival attention, and trust should push the player into tradeoffs.

## Progression Scale

1. **Neighborhood:** direct player movement, individual contacts, hand-to-hand deals, local heat.
2. **City:** crews, vehicles, stash houses, districts, rival territory, police pressure by borough.
3. **Nation:** supply lines, laundering fronts, political influence, multi-city operations.
4. **Global:** ports, shell companies, international risk, market shocks, diplomatic and enforcement pressure.

Each scale should preserve the fantasy of growth while reducing direct micromanagement. The player should still be able to zoom down into important incidents.

## Prototype Loop

The current scaffold implements:

- Move around a top-down neighborhood.
- Buy stock from a supplier.
- Sell stock to a buyer.
- Pay a fixer to lower heat.
- Grow from neighborhood scale to larger scopes by accumulating cash.

This is deliberately small. It exists to prove input, state, interaction, and HUD flow.

## Near-Term Mechanics

- Replace generic stock with fictional product categories.
- Add procedural neighborhood blocks and interiors.
- Add rival crews with territory influence.
- Add day/night cycles and timed market changes.
- Add heat sources that respond to player behavior.
- Add missions that introduce mechanics one at a time.
- Add tactical action scenes for raids, ambushes, and escapes.

## Technical Direction

- Use Godot 4.x.
- Keep core game state in autoloads or small resource-like classes.
- Prefer typed GDScript where it improves clarity.
- Keep input bindings close to code while prototyping.
- Build systems behind simple interfaces so later AI passes can extend them safely.
- Add tests or simulation scripts once the economy has enough rules to regress.

## Tone

The tone should be stylish, tense, and strategic rather than instructional. The player is building a fictional criminal empire inside a pressure-driven game system, not learning real-world procedures.

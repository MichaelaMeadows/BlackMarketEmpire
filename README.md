# Black Market Empire

A code-first Godot 4 prototype for a top-down 2D base-building and tactical empire game.

You start in a single owned house with $100, unemployment benefits, one runner named Benji, and 20 KG of base inventory capacity. Over time you grow into larger bases: industrial buildings, compounds, and eventually broader operational hubs. The current scaffold focuses on a physical home base, crew, storage, facilities, and separate raid targets.

The opening uses a short six-step mission chain to introduce trade orders, deliveries, sales, hiring, squad commands, and raids. Completing the Abandoned Depot mission ends the guided introduction; from that point the prototype is deliberately open-ended.

Completing that introduction also opens legal intermediate suppliers and the Production phone app. The starter workbench can reserve delivered inputs, run timed batches, return inputs when canceled, and store finished Plain Wraps, Clean Labels, or Burner Parts for sale.

## Run

1. Open this folder in Godot 4.3 or newer.
2. Press Play.
3. Move with `WASD` or arrow keys.
4. Open the phone with `Tab` to inspect Base, Crew, Raids, Map, Bank, and Market apps.
5. In raids or combat spaces, use:
   - `E` to use the contact's default action
   - `B` to buy from a supplier
   - `X` to sell to a buyer
   - `F` to pay a fixer to reduce heat
   - Mouse to aim and `Space` to fire your equipped weapon
   - `1` to order combat crew to follow and regroup
   - `2`, then left-click a hostile, to order the squad to attack it
   - `3` to order combat crew to hold and defend their current positions
   - `Tab` to open or close your phone

## Structure

- `project.godot` configures the project and the `GameState` autoload.
- `maps/` contains JSON map definitions that can be saved and loaded by `MapLoader`.
- `assets/` contains the pixel-art folder structure and visual direction notes for character, prop, tile, effect, and UI art.
- `data/economy/` contains JSON definitions for fictional goods, recipes, district markets, consumer segments, and trade routes.
- `data/progression/` contains JSON unlock and event rules driven by gameplay facts.
- `data/progression/intro_missions.json` contains the short sequential onboarding chain.
- `data/production/base_recipes.json` contains player-operated base production recipes and batch timings.
- `scenes/` contains lightweight scene entry points.
- `scripts/` contains the behavior. Most gameplay is meant to live here.
- `docs/game_decisions.md` records design decisions and future direction.

## Maps

The default map is `maps/starter_house.json`. It defines bounds, player start, an owned base, buildings, walls, zones, props, facilities, crew NPCs, raid targets, and placeholder triggers. `maps/neighborhood_basic.json` remains as legacy/reference content.

The phone's Map app reads from the same loaded map data as the playable world, so buildings, walls, NPCs, contacts, and the player marker stay tied to the active map file.

Enterable buildings should use `buildings` as floor/outline data with `collides: false`, then use `walls` for exterior walls, doors, and room dividers. `tools/map_authoring_helper.gd` has small static helpers for generating exterior wall records with door gaps, room dividers, and trees.

New maps can instead declare `building_layouts`. These accept local room rectangles (`rooms_are_local: true`) and `room_connections`; `MapCompiler` expands them into the existing runtime `buildings` and `walls` records when the map loads. A connection generates the separating wall and a clearance-safe centered doorway, so room geometry and door geometry come from the same definition. `maps/raid_abandoned_depot.json` is the working example.

`MapValidator` checks map identity and geometry, duplicate IDs, room containment, facility-to-room/slot references, raid map paths, walkability, inferred doorways, and room reachability. The test suite validates every shipped map; schema-version 2 maps receive strict navigation validation, while the schema-version 1 neighborhood remains legacy reference content.

NPC map entries can include `health`, `faction`, optional `weapon` data, and optional `ai` data. Weapons support `weapon_type`, damage/projectile timing, `accuracy`, movement/recoil spread, magazines/reload, bursts, multi-projectile shots, and effective/preferred ranges. AI data can opt a unit into combat behavior with `enabled`, `hostile_factions`, `role`, `detection_radius`, weapon range overrides, reaction/memory timing, cover/suppression settings, squad settings, and follow settings that can be assigned at runtime.

Combat crew can receive whole-squad Follow, Attack, and Hold orders through the HUD or the `1`, `2`, and `3` keys. Attack uses a hostile selected with the mouse. Hold gives each unit its own anchor and limits autonomous pursuit to the defended area while preserving cover, reload, and suppression behavior.

When crew are sent on a raid, departure movement temporarily owns them and routes them through the shortest reachable map exit. Their persistent squad Follow order resumes only when they return home.

New hires briefly walk in from the base entrance. This arrival job settles once they are close to their assigned spot and gives up if movement stalls, then restores normal squad AI; sending them on a raid cancels the arrival immediately.

Base maps can include a `base` dictionary, room `slot_ids`, `facilities`, staff NPCs, and `raid_targets`. The Base, Crew, and Raids phone apps read that data through `GameState`. The starter house stores 20 KG, pays unemployment benefits weekly, and starts with Benji as a $10/week runner who can take simple transport assignments.

## Economy

The background economy is district-based. `scripts/market_simulation.gd` loads economy data from `data/economy/`, advances markets in daily ticks, and exposes local buy/sell prices through `GameState`.

The player-facing production foundation is separate from the background district simulation. Intermediate goods travel through normal trade orders and storage; `BaseProductionState` reserves recipe inputs, advances one batch per facility with game time, checks worker requirements and output space, and deposits finished goods into the shared base inventory.

## Progression

`scripts/progression_tracker.gd` tracks flexible unlock rules for cumulative metrics, item-specific metrics, event counts, and random interval checks. `GameState` records current facts such as sales, kills, days, and active-market production.

## Tests

Run all Godot test scripts with:

```powershell
.\tools\run_all_tests.cmd
```

The runner discovers `*test.gd` scripts in `tools/`, runs them with Godot headless, and stops on the first failure.

Run the broader combat profile simulation with:

```powershell
godot --headless --script tools/combat_ai_simulation.gd
```

## Code-First Notes

The project favors small scripts, explicit state, and simple scenes so AI agents can safely extend behavior over time. Prefer adding gameplay through scripts and data structures before introducing complex editor-only scene work.

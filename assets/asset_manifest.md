# Visual Asset Manifest

This is the production backlog and source of truth for visual files. Work one category at a time; approve silhouettes and palette before expanding a category.

## Batch 01 — Phone navigation icons (first production batch)

Destination: `assets/ui/icons/`. Each final icon is a 32 x 32 transparent PNG.

| ID | Filename | Readable silhouette | Accent |
|---|---|---|---|
| base | `nav_base.png` | Safehouse with door | Cyan door |
| crew | `nav_crew.png` | Two busts | Cyan shoulder mark |
| raids | `nav_raids.png` | Crosshair over warehouse | Heat red target |
| map | `nav_map.png` | Folded street map | Cyan route |
| bank | `nav_bank.png` | Cash bundle | Cash amber band |
| market | `nav_market.png` | Crate with swap arrows | Cash amber arrows |
| orders | `nav_orders.png` | Clipboard with route tick | Cyan tick |
| hire | `nav_hire.png` | ID card with plus | Success green plus |

Status: generated, palette-normalized, alpha-validated, integrated. Source contact sheets live under `assets/source/ui/` and game-ready icons under `assets/ui/icons/`.

## Batch 02 — Market good icons

Destination: `assets/ui/goods/`. Each final icon is a 32 x 32 transparent PNG.

| Family | Filename | Primary goods covered |
|---|---|---|
| Food | `good_food.png` | Fast food, grocery supplies |
| Industrial | `good_industrial.png` | Industrial/growing/packaging supplies, repair parts, storage |
| Medical | `good_medical.png` | Rare meds, night vials, hush tabs, glimmer drops |
| Electronics | `good_electronics.png` | Burner parts, encrypted devices, ledger keys |
| Chemicals | `good_chemicals.png` | Fuel chits and future chemical inputs |
| Documents | `good_documents.png` | Paper forms, labels, wraps, route/access papers, forged papers |
| Luxury | `good_luxury.png` | Counterfeit luxuries, mirror silk, art fakes |
| Street parcel | `good_street.png` | Bootleg media, street goods, generic fallback |

Selected, unavailable, risky, and seized states are expressed by UI styling and badges rather than duplicate icon files. All 28 current goods must resolve to an icon through the visual asset catalog.

Status: generated, normalized, integrated into Market and Orders, and mapped across every current economy good.

## Batch 03 — Core terrain tiles

Destination: `assets/tiles/core/`. Each final texture is a seamless 32 x 32 opaque PNG.

| Material | Filename | Runtime mappings |
|---|---|---|
| Worn asphalt | `tile_asphalt.png` | Asphalt road and alley zones |
| Stained concrete | `tile_concrete.png` | Concrete courts, yards, paths, bare/store concrete |
| Packed dirt | `tile_dirt.png` | Dirt zones and fallback outdoor earth |
| Sparse grass | `tile_grass.png` | Woods and grass zones |
| Worn wood planks | `tile_wood.png` | House and apartment floors |
| Worn carpet | `tile_carpet.png` | Worn and faded carpet rooms |
| Old ceramic tile | `tile_ceramic.png` | Old, bath, and cold tile rooms |
| Dirty brick | `tile_brick.png` | Reserved for the structural wall batch and authoring previews |

Every tile requires a generated 3 x 3 seam-test image under `assets/source/tiles/seam_tests/`. Runtime rectangles retain code-drawn borders, road markings, room boundaries, and semantic overlays above these base textures.

Status: generated, palette-normalized, seam-validated, and integrated into map zones plus building and room floors.

## Batch 04 — Interior props

32 or 64 px transparent sprites: crate, stacked boxes, shelf, worktable, chair, sofa, bed, sink, toilet, cheap refrigerator, stove, filing cabinet, safe, packing station, and production bench. Each needs a fixed footprint in metadata.

## Batch 05 — Contacts and pickups

32 x 32 markers and 48 x 48 world sprites: supplier, buyer, fixer, mission lead, cash pickup, goods pickup, weapon pickup, locked interaction, and unknown contact.

## Batch 06 — Character sheets

Use the exact 576 x 144 sheet specification in `docs/visual_style_guide.md`. First set: player streetwear, runner, muscle, production worker, rival thug, and law officer. Approve the player sheet before generating variants.

### Batch 06A — Player proof sheet

- Destination: `assets/sprites/characters/player_streetwear.png`.
- Canvas: 576 x 144 px, transparent PNG.
- Grid: 12 columns x 3 rows; each frame 48 x 48 px.
- Rows: down, up, right; left uses horizontal flip.
- Columns: idle 0–1, walk 2–5, aim 6–7, fire 8–9, hurt 10, downed 11.
- Visual: dark charcoal street jacket, muted trousers, cyan shoulder stripe, warm skin, compact dark handgun only in aim/fire frames.
- Engine anchor: feet at local `(24, 40)`.

NPC sheets remain on the procedural fallback until Batch 06A animation and alignment are verified in play.

Status: player proof sheet generated, normalized, and wired into all player animation states; procedural fallback retained for NPCs.

## Batch 07 — Combat effects

Transparent pixel sheets: muzzle flash (16 x 16, 4 frames), bullet impact (16 x 16, 4), melee arc (32 x 32, 4), smoke puff (32 x 32, 6), alert ping (32 x 32, 6), and bloodless damage spark (16 x 16, 3).

## Batch 08 — UI feedback and status

16 x 16 status glyphs: ready, traveling, producing, injured, downed, seized, delayed, hot, protected, locked, warning, success. Bars and panel backgrounds remain code-native theme resources.

## Shared 16-color world palette

`#080B0C`, `#111616`, `#1B2322`, `#283331`, `#43504C`, `#707D76`, `#A4B0A8`, `#E4EBE5`, `#214E50`, `#36C7C9`, `#6B4D24`, `#D9A441`, `#285B3A`, `#4FC47A`, `#7D302D`, `#D7564E`.

## Naming and import rules

- Lowercase snake_case filenames with category prefix when ambiguity is possible.
- PNG color mode RGBA, no embedded color profile, no padding outside the fixed canvas.
- Godot import: nearest filtering, mipmaps off, lossless compression.
- Keep generated source/contact sheets under `assets/source/`; only validated game-ready files belong in runtime folders.
- Asset data should reference `res://assets/...`; gameplay scripts must not depend on generated-image cache paths.

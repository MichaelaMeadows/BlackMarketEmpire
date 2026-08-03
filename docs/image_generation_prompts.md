# Strict Image Generation Prompts

These prompts are production specifications. Do not broaden them with extra objects, text, lighting, texture, or decorative framing.

## Batch 01 contact sheet prompt — phone navigation icons

Use case: stylized-concept
Asset type: pixel-art game UI icon source sheet
Primary request: Create exactly eight distinct phone navigation icons in a 4-column by 2-row contact sheet, in this exact order: safehouse, two-person crew, crosshair over warehouse, folded street map, cash bundle, shipping crate with opposing arrows, clipboard with route check, identification card with plus.
Scene/backdrop: perfectly flat solid `#FF00FF` chroma-key background for later removal; every cell has the same background.
Style/medium: crisp hand-placed 32 x 32 pixel art, industrial crime-management game UI, orthographic symbols, limited palette.
Composition/framing: 4 by 2 regular grid; each icon centered in an equal square cell with generous clear separation; no grid lines; glyph footprint approximately 22 x 22 logical pixels.
Color palette: only `#080B0C`, `#1B2322`, `#43504C`, `#A4B0A8`, `#E4EBE5`, `#36C7C9`, `#D9A441`, `#4FC47A`, `#D7564E`; do not use `#FF00FF` in any icon.
Constraints: exactly eight icons; thick 2-logical-pixel dark outline; maximum six colors in each icon; hard pixel edges; no antialiasing; no gradients; no lighting; no texture; no cast shadows; no text; no letters; no numbers; no watermark; no outer border; no rounded-square containers; no extra symbols. Background must be one uniform color with no shadows, variation, or floor plane.
Avoid: painterly rendering, vector smoothing, 3D, isometric perspective, tiny detail, glow, bevels, realistic materials, icon overlap, inconsistent scale.

Post-process by removing the chroma key, then sample each cell into a separate 32 x 32 canvas using nearest-neighbor only. Each result must pass the acceptance checklist before integration.

## Batch 02 contact sheet prompt — market good families

Use case: stylized-concept
Asset type: pixel-art economy item icons for a game UI
Primary request: Create exactly eight distinct market-good icons in a 4-column by 2-row contact sheet, in this exact order: wrapped fast-food meal, industrial supply crate with a metal gear, small medicine bottle with one capsule, rugged encrypted handheld device, sealed fuel or chemical drum, stack of restricted documents with a folded corner, compact luxury gift box with a gemstone clasp, anonymous taped street parcel.
Scene/backdrop: perfectly flat solid `#FF00FF` chroma-key background for later removal; every cell has the same background.
Style/medium: crisp hand-placed 32 x 32 pixel art matching an industrial crime-management game UI; orthographic symbols; limited palette.
Composition/framing: 4 by 2 regular grid; each object centered in an equal square cell; no grid lines; identical visual scale; glyph footprint approximately 22 x 22 logical pixels.
Color palette: only `#080B0C`, `#1B2322`, `#43504C`, `#A4B0A8`, `#E4EBE5`, `#36C7C9`, `#D9A441`, `#4FC47A`, `#D7564E`; do not use `#FF00FF` in an icon.
Constraints: exactly eight icons; each icon is a single isolated object; thick 2-logical-pixel dark outline; maximum six colors per icon; hard pixel edges; no antialiasing; no gradients; no lighting; no texture noise; no cast shadows; no text; no letters; no numbers; no logos; no watermark; no outer border; no rounded-square containers; no extra symbols. Background must be perfectly uniform with no shadows, variation, texture, or floor plane.
Avoid: characters, hands, scenery, painterly rendering, vector smoothing, 3D, isometric perspective, tiny detail, glow, bevels, realistic materials, icon overlap, inconsistent scale.

Post-process with the same chroma removal, nearest-neighbor sampling, palette quantization, and hard-alpha validation used by Batch 01.

## Batch 03 contact sheet prompt — core terrain tiles

Use case: stylized-concept
Asset type: seamless top-down pixel-art terrain textures for a game
Primary request: Create exactly eight square terrain texture samples in a 4-column by 2-row contact sheet, in this exact order: worn dark asphalt, stained gray concrete, compacted brown dirt, sparse dark grass, worn brown wood floor planks, faded charcoal-green carpet, old gray ceramic floor tile, dirty dark red-brown brickwork.
Scene/backdrop: every cell is completely filled edge-to-edge by its material; no background is visible.
Style/medium: strict top-down orthographic 32 x 32 pixel-art material tiles for a gritty urban strategy game; limited 16-color palette; low-frequency texture.
Composition/framing: exact 4 by 2 grid of equal square cells; one flat material per cell; clear cell boundaries; no perspective; no objects.
Color palette: derive only from the shared 16-color world palette in `assets/asset_manifest.md`; dark value range; navigable floors remain quieter than units and interactables.
Constraints: exactly eight material samples; tileable/seamless on all four edges; hard pixel edges; no antialiasing; no gradients; no directional light; no shadows; no text; no labels; no symbols; no objects; no plants on grass; no debris larger than 3 logical pixels; texture marks cover no more than 15 percent of a tile.
Avoid: isometric perspective, horizon, rooms, borders around the whole sheet, photorealism, glossy surfaces, high-frequency noise, large cracks, large stones, dramatic highlights, vignette, watermark.

Post-process by extracting each cell, reducing it with nearest-neighbor sampling, quantizing to the world palette, enforcing mirrored edge continuity, and producing a 3 x 3 seam test before runtime integration.

## Batch 06A prompt — player streetwear sprite sheet

Use case: stylized-concept
Asset type: animated top-down pixel-art player sprite sheet
Primary request: Create one consistent human player character sprite sheet with exactly 36 frames arranged in 12 columns and 3 rows. The character wears a dark charcoal street jacket, muted trousers, a cyan shoulder stripe, and has warm medium skin. A compact dark handgun appears only in aim and fire frames.
Scene/backdrop: perfectly flat solid `#FF00FF` chroma-key background in every frame.
Style/medium: strict 48 x 48 pixel-art frames, top-down three-quarter game view, chunky readable silhouette, limited shared 16-color palette, gritty modern urban setting.
Composition/framing: exact 12-column x 3-row uniform grid; rows are facing down, facing up, facing right. Columns 0–1 idle, 2–5 walk cycle, 6–7 aim, 8–9 fire, 10 hurt, 11 downed. Center every standing frame on the same feet anchor. Left-facing animation is not included.
Constraints: exactly one character per frame; consistent identity, clothing, proportions, scale, and anchor across all frames; hard pixel edges; no antialiasing; no gradients; no cast shadows; no frame borders; no grid lines; no text; no labels; no numbers; no watermark. Keep all pixels within each logical cell. Do not use `#FF00FF` on the character.
Avoid: extra characters, alternate outfits, changing skin tone, changing weapon, perspective changes, isometric view, oversized head, detailed face, scenery, glow, motion blur, smooth vector edges.

Post-process by chroma removal, fixed 12 x 3 cell extraction, nearest-neighbor resizing into exact 48 x 48 frames, palette quantization, hard alpha, and reassembly into a 576 x 144 sheet.

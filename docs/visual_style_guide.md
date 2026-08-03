# Black Market Empire Visual Style Guide

## Art direction: Quiet Criminal Infrastructure

Black Market Empire should feel like an illicit operation managed through battered practical tools: a dim safehouse, a cheap encrypted phone, shipping labels, cash ledgers, sodium streetlights, and improvised tactical maps. The game is dark, but the interface must never be murky. Information is the player's main weapon.

The target is restrained pixel art with strong silhouettes and an industrial UI. Detail is earned at focal points. Empty space, clear grouping, and one bright signal color should do more work than decoration.

### Visual pillars

1. **Readable under pressure.** Gameplay actors, interactables, threats, and buttons must be identifiable by silhouette and value before hue.
2. **Systemic, not ornamental.** Reusable tokens and components create the look. Avoid one-off colors, margins, borders, and button treatments.
3. **Worn but controlled.** The world may be stained and uneven; UI geometry stays crisp and aligned.
4. **Sparse signals.** Cyan means player/control, amber means money/opportunity, red means danger/loss, and green means confirmed success. Never use these accents as general decoration.
5. **Pixel discipline.** World sprites use hard edges, integer placement, nearest-neighbor filtering, and a limited shared palette.

## Palette

| Token | Hex | Use |
|---|---:|---|
| Ink | `#080B0C` | Deepest background, outlines |
| Asphalt | `#111616` | App and HUD backgrounds |
| Steel | `#1B2322` | Raised surfaces |
| Steel Light | `#283331` | Hovered surfaces |
| Rule | `#43504C` | Borders and dividers |
| Paper | `#E4EBE5` | Primary text |
| Dust | `#A4B0A8` | Secondary text |
| Muted | `#707D76` | Disabled and tertiary text |
| Signal Cyan | `#36C7C9` | Player, selection, interactive focus |
| Cash Amber | `#D9A441` | Currency, opportunity, contacts |
| Success Green | `#4FC47A` | Confirmed positive state |
| Heat Red | `#D7564E` | Damage, heat, destructive action |
| Warning Orange | `#E3813B` | Pending risk and warnings |

Use Paper on Asphalt or Steel for body copy. Dust is acceptable for secondary copy at 14 px or larger. Muted is not suitable for essential information. Accent-colored text should be short and bold; use a neutral label beside it.

## Typography and numbers

- Use the project default sans-serif until a licensed pixel UI font is selected. Consistent metrics matter more than novelty.
- Display/page title: 22 px, semibold impression, one line.
- Section title: 18 px.
- Body and controls: 16 px.
- Supporting labels: 14 px minimum.
- Use tabular-looking aligned columns for prices, quantities, timers, capacity, and percentages.
- Use sentence case. Reserve all caps for short state stamps such as `READY`, `SEIZED`, or `HOT`.

## Spacing and layout

The base unit is 4 px. Preferred spacing is 8, 12, 16, 24, and 32 px.

- Minimum control height: 40 px; primary actions: 44 px.
- Minimum icon target: 40 x 40 px even when the drawn icon is 20 x 20 px.
- Panel padding: 16 px standard, 12 px compact.
- Screen gutter: 24 px desktop, 16 px at narrow layouts.
- Section gap: 16 px. Related-row gap: 8 px.
- Align labels to a shared left edge and numbers to a shared right edge.
- Do not encode a state with color alone. Pair color with an icon, label, pattern, or value change.

## Shape, borders, and depth

- UI corners: 2 px standard, 4 px for modal containers. Avoid pill shapes except compact status badges.
- Borders: 1 px Rule; focused controls use a 2 px Signal Cyan border.
- Depth is represented by surface value and a small lower shadow, not blur or glass effects.
- World shadows are short, dark, and offset down-right. No soft cinematic bloom on ordinary objects.

## Interaction states

| State | Treatment |
|---|---|
| Normal | Steel surface, Rule border, Paper text |
| Hover | Steel Light surface, brighter border |
| Pressed/selected | Cyan-dark surface, 2 px Signal Cyan border |
| Focused | Cyan outline plus normal state; visible for keyboard/gamepad |
| Disabled | Asphalt surface, Muted text, low-contrast border |
| Destructive | Neutral surface by default; Heat Red on hover/confirmation |

Navigation must show the current app persistently. Tooltips supplement visible labels; they do not replace them.

## Icon language

- Master grid: 32 x 32 px; visible glyph occupies roughly 22 x 22 px.
- Orthographic front/top view, no perspective.
- 2 px dark outline, 1 px internal highlights, no antialiasing.
- One primary neutral mass plus one semantic accent. Maximum six colors per icon, all drawn from the shared palette.
- Transparent background. No text, numbers, borders, containers, drop shadows, or glow.
- At 1x scale each icon must remain recognizable. Validate in grayscale and at 50% UI opacity.

## World tiles and props

- Tile module: 32 x 32 px. Build terrain from seamless 2 x 2 and 3 x 3 neighborhood tests.
- Keep navigable ground in the darkest two value bands. Walls and blocking props must be at least one band brighter or have a strong outline.
- Texture frequency stays low: at most 10–15% of a tile may contain noise pixels.
- Doors, pickups, contacts, and hazards receive semantic accent pixels. Background clutter does not.
- World sprites may use the shared 16-color world palette defined in the asset list; per-sprite ramps should reuse those colors.

## Character sprite-sheet specification

Characters use 48 x 48 px frames on a transparent background. The source sheet is 576 x 144 px: 12 columns by 3 rows.

- Rows: down, up, right. Left is produced by horizontal flip.
- Columns 0–1: idle, 2 frames at 3 fps, loop.
- Columns 2–5: walk, 4 frames at 8 fps, loop.
- Columns 6–7: aim, 2 frames at 4 fps, loop.
- Columns 8–9: fire, 2 frames at 10 fps, no loop.
- Column 10: hurt, 1 frame, 0.12 s.
- Column 11: downed/death, 1 frame, hold.

Feet align to local pixel `(24, 40)` in every standing frame. The character silhouette must fit within x=8–39 and y=5–43. Weapons may extend to x=45. No frame may include a cast shadow; the engine draws shadows separately.

## Asset acceptance checklist

- Reads at native size and at 2x nearest-neighbor scale.
- Uses only approved palette colors, aside from alpha.
- Has no accidental semitransparent edge pixels.
- Maintains the category's fixed canvas and anchor.
- Communicates state without relying on hue alone.
- Matches naming, import, and directory rules in `assets/asset_manifest.md`.


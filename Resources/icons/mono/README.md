# AgentMeter monochrome About-dialog icons

Watchful Agent, based on the selected original icon portfolio.

## Contents

- Three styles: solid, outline, badge.
- Each style in black and white, with a transparent background.
- `png/`: 48 PNG exports, at 16, 24, 32, 48, 64, 128, 256 and 512 pixels.
- `masters/`: six full-resolution image-generated PNG masters.
- `preview.png`: labeled comparison on light/dark backgrounds, including small sizes.
- `AgentMeterMonochrome.xcassets`: three macOS template image assets, each at 128 pt with 1x and 2x representations.
- `generation-prompts.json`: prompts used by the built-in image-generation tool.

## Recommended use

For an About dialog, start with Solid at 64 pt (use the 128 px file on a Retina display), or Outline at 96–128 pt. Badge provides more framing. Solid is the strongest option at small sizes; Outline and Badge are better suited to larger display sizes.

Pixel sizes are physical pixels, not points. Select a PNG at twice the desired point size for a 2x display.

Import the asset catalog, or copy its individual imagesets into your existing catalog. Asset names: AgentMeterSolid, AgentMeterOutline, AgentMeterBadge. They are marked as template images so the UI can tint their alpha silhouette. The template catalog uses the same black master in both appearances, ensuring identical geometry when the system tint changes.

The separate black and white PNG designs were generated individually and have small geometric differences. Use the template assets when exact shape consistency across appearances matters. These are raster assets, not SVGs.

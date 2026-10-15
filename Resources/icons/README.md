# AgentMeter: Watchful Agent icon set

Selected proposal: 5 (Watchful Agent). Transparent PNG artwork.

## Files

- `masters/`: original selected concept and refined app/web master PNGs (1254 × 1254).
- `macos/AgentMeter.icns`: multi-resolution macOS app icon.
- `macos/AgentMeter.png`: 1024 × 1024 app PNG.
- `macos/AgentMeter.iconset/`: standard 16 to 512 point PNGs at 1× and 2× resolution.
- `web/favicon.ico`: 16, 32, 48, 64, 128 and 256 pixel favicon entries.
- `web/favicon-*.png`: individual website icons.
- `web/apple-touch-icon.png`: 180 × 180 website icon.
- `mono/`: monochrome icon set in three styles (solid, outline, badge), each in black and white, with masters, PNG exports from 16 to 512 px, a template asset catalog and a preview (see `mono/README.md`).

## Mono icon (About tab)

The About tab in Settings shows `mono/AgentMeter-mono.png` as its hero image: the solid black style at 512 px (a copy of `mono/png/solid-black/agentmeter-solid-black-512.png`). Solid reads best at the hero size of 96 pt and stays closest to the colored app icon; outline looks thin there, and the badge repeats the app icon's rounded square.

The app loads it as a template image, so only the alpha channel matters and macOS tints it for light and dark mode. `make app` copies it into `Contents/Resources/`; without it the About tab falls back to the regular app icon.

## Website example

Copy `web/` contents to your website's public asset directory:

```html
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">
<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
```

## macOS

Include `AgentMeter.icns` in the app bundle's `Contents/Resources/` directory and set `CFBundleIconFile` to `AgentMeter` in its `Info.plist`.

The iconset can also be compiled on macOS with:

```sh
iconutil -c icns macos/AgentMeter.iconset -o macos/AgentMeter.icns
```

App artwork retains subtle depth. Website artwork has simplified shading and larger features for small sizes. These are raster assets, not editable vectors. Artwork was created with the built-in image generator and packaged into standard icon formats. No repository changes are included.

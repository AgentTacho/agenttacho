# Contract: capture.sh and the site's screenshot set

## Invocation

```text
capture.sh <target-dir>
```

`--first-run` is gone; any other argument shape prints the usage line and exits 2 (as today for wrong shapes).

## Output

On success: exactly these 14 files in `<target-dir>`, one line each on stdout as `<file> <width>x<height>`:

```text
menubar budget harnesses prices menubar-settings glance same-provider
× light, dark → <stem>-<appearance>.webp (lossless)
```

Files of other names in `<target-dir>` are never touched.

On failure: exit 1, `could not capture: <stem>-<appearance> ...` (or a preflight message), and the target folder unchanged.

## Image rules for `glance` and `same-provider`

- Uniform margin on all sides, taken from the dropdown pixels, at least 4 px, at most 4% of the shorter side.
- Aspect `width:height` between 3:4 and 4:3.
- `glance`: the first Claude Max section (header to expanded details, models view).
- `same-provider`: both Claude Max sections, details collapsed.

## Consumer

The site (`src/assets/agenttacho/`, `Shot.astro`) references stems by name; its phase-2 pull request maps card 1 to `glance` and card 3 to `same-provider` and removes `plan-limits`, `pace`, `details`, `groups`, `alert` and `dropdown`.

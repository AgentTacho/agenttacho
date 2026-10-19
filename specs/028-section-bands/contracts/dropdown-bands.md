# Contract: Dropdown bands

Replaces the "Dividers" section of `specs/025-minimal-dropdown/contracts/dropdown-ui.md`.

```
┌ panel, 360 pt, always dark ─────────────────┐
│  12 pt top inset (2 pt container + 10 pt band padding)
│  [config / demo error lines, no band]       │
│  Section 1                         plain    │
│░░Section 2░░░░░░░░░░░░░░░░░░░░░░░ tinted ░░░│
│  Section 3                         plain    │
│░░Unassigned (if shown)░░░░░░░░░░░ tinted ░░░│   <- scroll view ends here
│▒▒errors / update line / status row  footer ▒│   <- pinned
└─────────────────────────────────────────────┘
```

| Element | Fill | Edges | Padding inside |
|---|---|---|---|
| plain section | none | n/a | 12 pt left/right, 10 pt top/bottom |
| tinted section | `Color.primary` at 0.04 (0.08 Increase contrast) | full width, hard, no corners, no line | 12 pt left/right, 10 pt top/bottom |
| footer | `Color.primary` at 0.07 (0.12 Increase contrast) | full width down to the panel's bottom | 12 pt left/right, 10 pt top, 12 pt bottom |
| error lines and "No accounts configured" at the top | none | n/a | 12 pt left/right, 10 pt top/bottom, 10 pt between lines |

- No `Divider` anywhere in the dropdown.
- The row hover highlight (`Color.primary` at 0.06, rounded 4 pt) and the `○` marker are drawn above the band; bar track and pace marker keep their colors.
- Bands add no accessibility elements and do not change the reading order.
- Stripes come from `SectionBands.stripes(arrangedCount:unassignedShown:)`; strengths from `BandStyle.opacity(increasedContrast:)`.

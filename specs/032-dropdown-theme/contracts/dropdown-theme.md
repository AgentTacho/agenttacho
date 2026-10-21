# Contract: Dropdown Theme

## Configuration file

```json
{ "dropdownTheme": "light" }
```

- Optional global key. Values `auto`, `dark`, `light`; missing means `auto`.
- AgentTacho writes it only for `dark` and `light`.
- Unknown or unreadable values fall back to `auto` with one load note in the diagnostic log (see data-model.md).

## Settings > General > Display

```
Display
  Show usage as     [ Used | Remaining ]
  Remaining counts down from 100% ...
  Dropdown theme    [ Auto | Dark | Light ]
  Auto follows the system appearance. Settings and the menu bar always do.
```

- Segmented picker, applied through the draft like every other General setting (no save button).
- VoiceOver reads "Dropdown theme, Auto" (the picker label and the selected segment).

## Dropdown

| Theme | System light | System dark |
|---|---|---|
| Auto | light panel | dark panel |
| Dark | dark panel | dark panel |
| Light | light panel | light panel |

- The panel is opaque in every cell. Layout, sizes, bands, scroll behavior and footer are the same in both panels; only colors differ.
- A change of the system appearance (Auto) or of the setting switches an open dropdown, within one second.
- Unchanged by the theme: the menu bar item, the Settings window, the Settings bar preview (dark capsule), notifications.

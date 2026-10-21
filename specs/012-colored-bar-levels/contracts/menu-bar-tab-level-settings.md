# Contract: Level settings in the Menu Bar tab

Placement: in the Menu Bar tab (spec 008), directly below the bar preview and above the entry list.

| Control | Kind | Values | Bound to |
|---|---|---|---|
| Level color | segmented picker, label "Level color" | Text, Pill, Off | `draft.levelColor` |
| Mark levels with ⚠ / ‼ | checkbox | on, off | `draft.showLevelSymbols` |

Behavior:

- Changes go to the Settings draft and are applied and undone like every other settings change (spec 008); they never trigger a refresh.
- The preview (above) renders from the draft's settings with dark-appearance colors (research R5) and updates on every change.

Threshold help text in the account and group editors (FR-006), replacing the sentence about `⚠` and `‼`:

"The lower value also marks the entry as a warning in the menu bar (80% when both are empty). At 100% it is marked as over the limit. The Menu Bar tab sets how levels look."

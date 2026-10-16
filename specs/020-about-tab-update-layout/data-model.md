# Data Model: About Tab Update Layout

No new or changed data. The feature moves the control for an existing stored setting and removes the Signing row from About.

- **`checksForUpdates`** (configuration, Bool, default `true`): unchanged in name, default and format. Its control moves from Settings > About to Settings > General (FR-008, FR-009).
- **`AppVersionInfo.Signing`** (from the `AgentMeterSigning` and `AgentMeterNotarized` bundle stamps): unchanged; still read by the update policy to choose the install action, and `Signing.text` still names it in the diagnostic log (research R2).

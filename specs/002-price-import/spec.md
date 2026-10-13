# Feature Specification: Price Import

**Feature Branch**: `002-price-import`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "docs/superpowers/specs/2026-10-13-price-import-design.md: buttons on the Prices tab that import the latest prices for Anthropic models, the same for OpenAI and possibly other providers (from LiteLLM's public price list), and an 'Import from CSV' that imports or overwrites prices from a downloaded CSV file. Imported prices form their own layer below manual overrides, are stored separately from the main configuration, are shown in a preview before they apply, and can be removed again. Prices can also be exported as CSV."

## Clarifications

### Session 2026-10-13

- Q: When a newer app build ships updated built-in prices, should an older import still override them? → A: Yes. Imports always win over built-in prices regardless of age; the Prices tab status line shows each import's age.
- Q: After an import is applied or removed, should the app fetch subscription usage again or only recalculate spend from local session logs? → A: Only recalculate token-based spend from local session logs; the subscription usage endpoint is not called.
- Q: How should the preview show new models when an import brings in many models never used? → A: New models that appear in current usage are listed in full; the remaining new models are collapsed into a count that can be expanded.
- Q: Should removing an import ask for confirmation first? → A: Yes, always; the confirmation names the import and how many models fall back to another price or become unpriced.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Update a provider's prices with one action (Priority: P1)

A developer tracks Claude Code spend through Vertex against a weekly budget. A provider changes its prices or releases a new model, and the built-in price table no longer matches. Instead of typing prices by hand or waiting for a new app build, the developer opens the Prices tab, chooses "Anthropic prices" from the Import menu, reviews what would change, and applies it. Spend figures are recomputed with the new prices right away. The same works for OpenAI models (direct and on Vertex) and for Google Gemini models.

**Why this priority**: This is the core value of the feature: keeping spend figures accurate without manual price editing. It matters most for the Vertex budget group, where OpenAI models are about to appear next to Claude models and have no built-in prices.

**Independent Test**: With network access, choose "Anthropic prices" from the Import menu. A preview appears listing new, changed, unchanged and shadowed models. Apply it, and confirm that a model whose price changed now shows the new price in the Prices tab and that the group's spend in the dropdown reflects it after the recomputation.

**Acceptance Scenarios**:

1. **Given** network access and no imported prices, **When** the user chooses a provider import, **Then** a preview shows a one-line summary (counts of new, changed, removed, unchanged and shadowed models), lists the changed models with old and new values for each changed price field, lists new models that appear in current usage, and collapses the remaining new models into an expandable count.
2. **Given** the preview is open, **When** the user chooses Apply, **Then** the imported prices take effect immediately, spend figures are recomputed, and the Prices tab shows the provider's import with today's date.
3. **Given** the preview is open, **When** the user chooses Cancel, **Then** nothing changes.
4. **Given** the user has a manual override for a model, **When** an import contains a different price for that model, **Then** the preview lists the model as shadowed with "your override stays in effect", and after Apply the override still determines the price.
5. **Given** a model has a CSV price, **When** a provider import contains a different price for that model, **Then** the preview lists the model as shadowed by the CSV price, not as changed.
6. **Given** a provider import was applied earlier, **When** the user imports the same provider again, **Then** the new import replaces the earlier one for that provider only, imports of other providers are unaffected, and models that were in the earlier import but not in the new one, and whose effective price therefore changes, are listed in the preview as removed with the price they fall back to (or "unpriced").
7. **Given** no network access, a timeout, or an unusable response, **When** the user starts a provider import, **Then** the preview shows an error naming the reason and no prices change.

---

### User Story 2 - Import prices from a CSV file (Priority: P2)

The developer has prices that the public price list does not have or gets wrong (for example a negotiated rate, or a model the list does not cover yet). They keep these in a spreadsheet, save it as CSV, and choose "From CSV file…" in the Import menu. The app reads the file, shows the same preview as a provider import, reports any rows it could not read with line number and reason, and applies the valid rows on confirmation. CSV prices win over provider imports but not over manual overrides.

**Why this priority**: It covers the gaps of the public price list and allows bulk edits without retyping prices row by row. It depends on the same preview and layering as Story 1 but not on network access.

**Independent Test**: Create a CSV file with a header and three rows, one of them invalid. Import it, confirm the preview lists two models and one skipped row with its line number and reason, apply it, and confirm the two models show CSV as their source.

**Acceptance Scenarios**:

1. **Given** a CSV file with a header row containing model, input and output columns, **When** the user imports it, **Then** the preview lists each valid row as new, changed, unchanged or shadowed.
2. **Given** a CSV row omits the cache price columns, **When** it is imported, **Then** the missing cache prices are derived from the input price (5-minute cache write 1.25 times, 1-hour cache write 2 times, cache read 0.1 times) and the preview marks these values as derived.
3. **Given** some rows are invalid (missing model, unparsable or negative number, wrong column count), **When** the file is imported, **Then** each invalid row is listed with its line number and reason, and the valid rows can still be applied.
4. **Given** a CSV file uses semicolons as separators and decimal commas (for example `2,50`), **When** it is imported, **Then** the values are read correctly.
5. **Given** a CSV import was applied earlier, **When** the user imports a new CSV file, **Then** the new file replaces the earlier CSV prices entirely; models absent from the new file lose their CSV price, and those whose effective price therefore changes are listed in the preview as removed with the price they fall back to (or "unpriced").
6. **Given** a file without a header row or without the required columns, **When** the user imports it, **Then** an error is shown and no prices change.

---

### User Story 3 - See where each price comes from (Priority: P2)

Looking at the Prices tab, the developer wants to know whether a price is built in, imported (and when, from where), or set by hand. With imports covering many models, the table would get long, so by default it shows only the models that matter right now.

**Why this priority**: Without visible sources, layered prices are confusing ("why is this price not what I typed in the CSV?"). The filter keeps the table usable once an import adds dozens of models.

**Independent Test**: After a provider import and a CSV import, open the Prices tab and confirm each row shows its source, the default filter shows only models used in the current window plus manually overridden ones, switching to "All" shows every model, and a status line names each import and its age.

**Acceptance Scenarios**:

1. **Given** prices from several sources, **When** the user opens the Prices tab, **Then** each row shows its effective source: built-in, the provider import with its date, CSV with the file name, or manual.
2. **Given** the Prices tab is opened, **When** no filter has been chosen, **Then** the table shows only models used in the current window plus every model with a manual override.
3. **Given** the filter is set to All, **When** the table is shown, **Then** every model with an effective price appears.
4. **Given** at least one import exists, **When** the Prices tab is shown, **Then** a status line names each import and its age (for example "Anthropic prices from LiteLLM, imported today").
5. **Given** the user edits a row or adds a model, **When** the change is applied, **Then** it becomes a manual override, as it does today, regardless of the row's previous source.

---

### User Story 4 - Remove an import (Priority: P3)

An import turned out wrong or is no longer wanted. The developer opens the Import menu, picks the import to remove (each listed with its date), and the prices fall back to the next layer immediately.

**Why this priority**: It is the undo for Stories 1 and 2. The preview already protects against most mistakes, so removal is needed less often.

**Independent Test**: Apply a provider import, remove it from the Import menu, and confirm the affected models show their built-in prices (or no price) again and the spend figures are recomputed.

**Acceptance Scenarios**:

1. **Given** one or more imports exist, **When** the user opens the Import menu, **Then** there is one removal entry per import, showing its date.
2. **Given** the user chooses a removal entry, **When** the confirmation appears, **Then** it names the import and states how many models would fall back to another price or become unpriced, and Cancel leaves everything unchanged.
3. **Given** the user confirms a removal, **When** the removal completes, **Then** affected models fall back to the next layer, spend is recomputed, and other imports and manual overrides are unaffected.

---

### User Story 5 - Export prices as CSV (Priority: P3)

The developer wants to edit prices in a spreadsheet. They export the current effective price table as CSV, edit it, and re-import it with Story 2.

**Why this priority**: Convenient for bulk edits and for sharing a price table, but not needed to keep spend accurate.

**Independent Test**: Export the prices, re-import the exported file unchanged, and confirm the preview reports every row as unchanged or shadowed and no row as new, changed, removed or skipped.

**Acceptance Scenarios**:

1. **Given** prices from any mix of sources, **When** the user exports as CSV and chooses a location, **Then** a file is written with a header row and one row per model in the effective table, in the same format the import reads.
2. **Given** an exported file, **When** it is imported without changes, **Then** no model is reported as new, changed or removed.

---

### Edge Cases

- A provider list contains several dated variants of the same model with different prices: the undated variant's price is used; otherwise the variant with the latest date.
- A provider list entry lacks cache prices: the missing cache prices take the input price, which is neutral for providers that do not bill cache writes separately.
- A provider list entry lacks input or output price, or is malformed: it is skipped without failing the import.
- The provider list has no usable entries for the chosen provider: an error is shown and nothing changes.
- The response from the price list is larger than 20 MB: the import fails with an error and nothing changes.
- The same model appears in two provider imports: the more recently imported one wins.
- The stored imported prices cannot be read at launch (damaged file): the app logs one line, shows a notice on the Prices tab, and uses manual overrides plus built-in prices. The damaged file stays until the next applied import replaces it; the new file then contains only that import.
- Saving imported prices fails (for example a full disk): an error is shown, and the previously stored imported prices remain intact.
- A model id in an import carries a regional or version suffix: it matches the same price entry as today's built-in table does (existing model id normalization and prefix fallback apply to imported prices too).
- The CSV file starts with a byte-order mark or contains double-quoted fields: both are handled.
- The app is offline: everything except provider imports keeps working with the prices already stored.

## Requirements *(mandatory)*

### Functional Requirements

**Price layering**

- **FR-001**: The app MUST determine a model's effective price from the first layer that has it, in this order: manual overrides, CSV import, provider imports, built-in prices. The layer order is fixed and does not depend on the age of an import or of the app build. Within the provider-import layer, FR-002 decides between providers.
- **FR-002**: When two provider imports contain the same model, the more recently imported one MUST win.
- **FR-003**: The existing model id normalization and prefix fallback MUST apply to the merged table including imported prices.
- **FR-004**: Imports MUST never modify or remove manual overrides.
- **FR-005**: Each effective price MUST carry its source: built-in, manual, or imported (with import kind, origin and import time).

**Provider import**

- **FR-006**: The app MUST offer provider imports for Anthropic, OpenAI (direct and Vertex, merged into one import) and Google Gemini from the public LiteLLM price list.
- **FR-007**: A provider import MUST include all chat models of that provider in the list (for OpenAI also models offered through its responses interface), not only models currently in use.
- **FR-008**: Provider prices MUST be converted to US dollars per million tokens and rounded to 6 decimal places.
- **FR-009**: For each model, the import MUST read input, output, 5-minute cache write, 1-hour cache write and cache read prices; a missing cache price MUST take the input price; entries without input or output price MUST be skipped.
- **FR-010**: Provider-specific id prefixes (for Vertex-hosted OpenAI models and Gemini models) MUST be removed so imported ids match the ids found in session logs.
- **FR-011**: Dated variants of a model MUST be merged under its normalized id; if prices differ, the undated variant wins when present, otherwise the variant with the latest date.
- **FR-012**: The download MUST time out after 30 seconds, MUST be limited to 20 MB, and MUST NOT be cached.
- **FR-013**: Malformed entries in the price list MUST be skipped without failing the import.

**CSV import and export**

- **FR-014**: CSV import MUST require a header row with `model`, `input` and `output` columns and MUST accept optional `cache_write_5m`, `cache_write_1h` and `cache_read` columns, matched case-insensitively and in any order. Values are US dollars per million tokens.
- **FR-015**: Missing cache columns MUST be derived from the input price (5-minute write 1.25 times, 1-hour write 2 times, read 0.1 times), and derived values MUST be marked in the preview.
- **FR-016**: CSV import MUST accept comma or semicolon separators (detected from the header), decimal commas when the separator is a semicolon, double-quoted fields, and a leading byte-order mark.
- **FR-017**: Invalid CSV rows MUST be skipped and reported with line number and reason; valid rows MUST remain importable.
- **FR-017a**: When several CSV rows map to the same normalized model id, the last row MUST win and the earlier rows MUST be reported as skipped with the reason "duplicate model".
- **FR-017b**: A CSV file without any valid row MUST be rejected with the error "no valid rows" and MUST leave all prices unchanged; removing the CSV import is the way to clear CSV prices.
- **FR-018**: A CSV import MUST replace all previously imported CSV prices.
- **FR-019**: CSV export MUST write the full effective price table (all models, all sources) in the import format, so an unchanged export re-imports with no new, changed or removed rows. Export MUST use a comma separator and dot decimals.

**Preview, apply and removal**

- **FR-020**: Every import MUST show a preview before any price changes, with a summary line and lists of new models, changed models (old and new value per changed field), removed models, shadowed models, the count of unchanged models, and (for CSV) skipped rows. The preview compares the effective table before and after the proposed import, so each model lands in exactly one category.
- **FR-020a**: A model MUST be listed as shadowed when the proposed import contains a price for it that differs from its effective price but a higher-ranked source (manual override, or CSV for provider imports) keeps winning; the preview MUST name that source (for example "your override stays in effect").
- **FR-020b**: A model MUST be listed as removed when the import it would replace priced it, the proposed import does not, and its effective price would therefore change; the preview MUST show the price it falls back to, or "unpriced".
- **FR-020c**: New models that appear in the current snapshot's breakdowns MUST be listed in full; all other new models MUST be collapsed into a count that the user can expand to see the full list. Changed, removed, shadowed and skipped entries are always listed in full.
- **FR-021**: Apply MUST store the import, replacing an earlier import of the same kind only, and MUST trigger an immediate recomputation of spend.
- **FR-022**: Cancel MUST discard the proposed import without any change.
- **FR-023**: The user MUST be able to remove each stored import individually. Removal MUST ask for confirmation, naming the import and the number of models that would fall back to another price or become unpriced; once confirmed, removal MUST take effect immediately and trigger recomputation.
- **FR-023a**: Recomputation after an apply or removal MUST only re-price token-based usage from local session logs; it MUST NOT call the subscription usage endpoint.
- **FR-024**: Errors (no network, timeout, unexpected response, oversized response, unusable content, missing CSV header or required columns, failure to save) MUST be shown with the reason (in the preview for imports, in an alert for removal), and MUST leave all prices unchanged. If a CSV export cannot be written, an error with the reason MUST be shown.

**Storage**

- **FR-025**: Imported prices MUST be stored in their own file in the app's configuration directory, separate from the main configuration file, with at most one stored import per kind (Anthropic, OpenAI, Gemini, CSV).
- **FR-026**: Saving imported prices MUST be atomic: a failed save MUST leave the previous stored imports intact.
- **FR-027**: Stored imports MUST be loaded at launch and after every apply or removal. A missing file means no imported prices. An unreadable file MUST be ignored with one log line and a notice on the Prices tab.

**Prices tab**

- **FR-028**: The Prices tab MUST offer an Import menu with entries for each provider import, CSV import, CSV export, and one removal entry per stored import showing its date.
- **FR-029**: The Prices tab MUST show each row's effective source.
- **FR-030**: The Prices tab MUST offer a filter between "Used in this window" (default: models in the current snapshot's breakdowns plus all manually overridden models) and "All". Before the first snapshot exists, "Used in this window" MUST show all models. The chosen filter MUST be remembered across launches.
- **FR-031**: The Prices tab MUST show a status line with each stored import and its age.
- **FR-032**: Editing a row or adding a model MUST create a manual override, as today.

**Logging and network**

- **FR-033**: Each applied import or removal MUST write one line to the diagnostic log with counts (for example imported, new, changed), not individual prices.
- **FR-034**: The app MUST NOT fetch prices in the background; provider imports happen only when the user chooses them.

### Key Entities

- **Price Entry**: Prices for one model in US dollars per million tokens (input, output, 5-minute cache write, 1-hour cache write, cache read) plus its source. Existing entity, gains the imported source.
- **Price Source**: Where an effective price comes from: built-in, manual, or imported. An imported source names the import kind, its origin (price list address or CSV file name) and the import time.
- **Price Import (batch)**: A set of price entries from one import, with kind (Anthropic, OpenAI, Gemini, CSV), origin and import time. At most one per kind is stored; a new import of the same kind replaces it.
- **Import Preview**: The difference between the effective table before and after a proposed import: new models, changed models with per-field old and new values, removed models with their fallback price, unchanged count, shadowed models with the source that keeps winning, and (for CSV) skipped rows with line number and reason. Derived CSV values are flagged.
- **Skipped Row**: A CSV line that could not be imported, with its line number and reason.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A provider's prices can be brought up to date with at most three user actions (open Import menu, choose provider, Apply) in under 30 seconds on a normal connection.
- **SC-002**: In 100% of imports, every price change is visible in the preview before it takes effect, and Cancel leaves all prices unchanged.
- **SC-003**: In 100% of imports, models with a manual override keep their override price after Apply.
- **SC-004**: Without network access, spend figures are computed with the same prices as before going offline, and only provider imports report an error.
- **SC-005**: An exported price table re-imported without edits reports zero new, zero changed, zero removed and zero skipped rows.
- **SC-006**: After importing OpenAI prices, a session using an OpenAI model on Vertex is priced instead of being flagged as unpriced.
- **SC-007**: Imported prices match the source list to within 0.000001 US dollars per million tokens.

## Assumptions

- Re-importing a full export moves every model into the CSV layer, so later provider imports and newer built-in prices are shadowed for those models. This is accepted: the preview lists such models as shadowed by CSV, and removing the CSV import restores the lower layers.
- The LiteLLM price list (`model_prices_and_context_window.json` in the BerriAI/litellm repository on GitHub) stays publicly reachable, machine-readable, and keeps its current field names. Neither Anthropic nor OpenAI offers a price API, and scraping pricing pages is out of scope.
- Prices are in US dollars. Different prices for the same model by provider or region (for example Vertex regional surcharges) are out of scope; direct and Vertex prices are treated as identical, as today.
- Updates are manual only. Automatic or scheduled price updates are out of scope.
- Imported rows cannot be edited in place; editing creates a manual override.
- "Used in this window" refers to the models in the breakdowns of the most recent usage snapshot.
- Applying or removing an import follows the existing settings behavior: it takes effect immediately without a separate save step. Removal asks for confirmation first, like removing an account, because a removed import cannot be restored exactly (a CSV needs the file again, and a provider re-import fetches current prices).
- The derivation factors for missing CSV cache prices (1.25, 2 and 0.1 times input) follow Anthropic's published cache pricing ratios.
- Known discrepancy: LiteLLM lists a different cache read price for Claude Sonnet 5.5 than the built-in table. The preview is how the user notices such differences; resolving them is not part of this feature.

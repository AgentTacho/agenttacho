# Contract: Price CSV

Used for import ("From CSV file…") and export ("Export current prices as CSV…").

```csv
model,input,output,cache_write_5m,cache_write_1h,cache_read
claude-opus-5-5,4,20,5,8,0.2
```

## Import

- The first line is the header. Column names are matched case-insensitively after trimming, in any order. Unknown columns are ignored.
- Required columns: `model`, `input`, `output`. Optional: `cache_write_5m`, `cache_write_1h`, `cache_read`.
- Values are US dollars per million tokens.
- A leading UTF-8 byte-order mark is ignored. Line endings `\n` and `\r\n` are accepted. Empty lines are ignored.
- Separator: semicolon when the header contains `;` and no `,`; otherwise comma. With semicolon, a decimal comma is accepted (`2,50` is 2.5).
- Fields may be wrapped in double quotes; `""` inside quotes is a literal quote; quoted fields may contain the separator.
- A missing or empty optional cell is derived from input: 5-minute write 1.25 times, 1-hour write 2 times, read 0.1 times. Derived values are flagged in the preview.
- Model ids are canonicalized like log model ids.

Row errors (row skipped, reported with its 1-based line number):

| Reason | Example |
|---|---|
| `missing model` | empty model cell |
| `unparsable number in <column>` | `abc` |
| `negative number in <column>` | `-1` |
| `expected N fields, found M` | wrong field count |
| `invalid model id` | a model id with a line break or control character, longer than 200 characters, or starting with `=`, `+`, `-` or `@` (spaces are allowed) |
| `duplicate model` | an earlier row with the same canonical id (the last row wins) |

File errors (nothing changes): `missing header` (empty file), `missing columns: input, output`, `no valid rows`, and a file larger than 5 MB (reported as an unreadable file).

## Export

Header exactly as above, comma separator, dot decimals, no thousands separators, one row per model of the effective table sorted by model id, trailing newline. Values print without trailing zeros (`0.2`, `4`). A model id is quoted only if it contains a comma, quote or line break. Re-importing an unchanged export yields no new, changed, removed or skipped rows.

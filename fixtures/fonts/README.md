# Live font fixtures for round-trip tests

Variable font files are **not** checked into the repository (size/licensing). Integration tests resolve fonts from common local paths and **skip** when missing.

## Expected locations (first match wins)

| Font | Candidate paths |
|------|-----------------|
| Playfair Roman VF | `~/Downloads/PlayfairRomanVF.woff2`, `~/Downloads/~Untitled/PlayfairRomanVF.woff2` |
| Playfair Italic VF | `~/Downloads/PlayfairItalicVF.woff2`, `~/Downloads/~Untitled/PlayfairItalicVF.woff2` |
| Roboto Flex VF | `~/Downloads/RobotoFlex-VariableFont_*.ttf`, `~/Downloads/~FontVaultTESTFiles/Roboto Flex Variable/RobotoFlex-Variable.ttf` |

## Running tests

```bash
cd VarFontEditor && swift test --filter CommitRoundTrip
cd VarFontEditor/Tools/vfcommit && python3 -m unittest discover -s tests
```

## Manual save checklist (Phase 1)

After Save Copy to a `-patched` file:

1. Instance count in patched font matches included count in Studio
2. Spot-check 3 composed names
3. Axis tree stops unchanged for non-edited axes
4. Re-import shows no new plan warnings
5. Font Book opens without corruption warning

See [`docs/SAVE_ROUND_TRIP_LOG.md`](../docs/SAVE_ROUND_TRIP_LOG.md) for automated baseline results.

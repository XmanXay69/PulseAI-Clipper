# Localizing PULSE

PULSE ships in English with the scaffolding for other languages in place (roadmap #457).

## How it works
- `Sources/PulseApp/Resources/<language>.lproj/Localizable.strings` holds the strings. The English table
  (`en.lproj`) uses the English text as the key, so an untranslated key reads correctly.
- `L("Take the Tour")` (see `Sources/PulseApp/Support/L10n.swift`) looks the key up in the app's resource
  bundle (`PULSE_PulseApp.bundle`, copied into the app by `scripts/build-app.sh`) and falls back to the key.
- The package declares `defaultLocalization: "en"`, and the `PulseApp` target processes `Resources/`.

## Adding a language
1. Copy `en.lproj` to `<code>.lproj` (`de.lproj`, `fr.lproj`, `ja.lproj`…).
2. Translate the right-hand side of each line; keep the keys as they are.
3. Build the app. macOS picks the table from System Settings → Language & Region; `L10n.language` says which
   table is in use.

## Wiring more text
Menu items and the main sections go through `L(...)` today. New UI text should too; existing views can be
converted as they are touched. Strings built from numbers or names should use `String(format:)` with a
localized format key rather than concatenation.

# Translations

Ivy uses Signal's official translations for every string it shares with upstream, and keeps its own strings separate.

## Upstream strings

Upstream translations live in `Signal/translations/<locale>.lproj/` (`Localizable.strings`, `PluralAware.stringsdict`, `InfoPlist.strings`). They arrive with every upstream merge (see [UPSTREAM_SYNC.md](UPSTREAM_SYNC.md)); Ivy never edits these files, so merges never conflict on them.

At Signal-iOS 8.32 there are 47 locales:
ar, be, bg, bn, ca, cs, da, de, el, en, es, fa, fi, fr, ga, gu, he, hi, hr, hu, id, it, ja, ko, lt, mr, ms, nb, nl, pl, pt_BR, pt_PT, ro, ru, sk, sr, sv, th, tr, ug, uk, ur, vi, yue, zh_CN, zh_HK, zh_TW.

To list the locales of the current checkout:

```
ls Signal/translations | sed -n 's/\.lproj$//p'
```

## The app name

Many upstream strings say "Signal". Where the word names the app ("Unlock Signal", "Signal needs access to your camera"), Ivy shows "Ivy". Where it names the Signal network, service or organization ("Signal PIN", "Signal will never message you"), it stays "Signal".

- `Scripts/ivy/app-name-rules.json` lists every English string that mentions "Signal" and, for each occurrence, whether it is replaced. Each rule stores a fingerprint of the English text it was reviewed against.
- A build phase in the app target ("Run Script: Ivy app name") applies the rules to the compiled translation files in the app bundle, for every locale. Arabic and Persian spell the name in their own script; those spellings are configured as aliases.
- When a translation has a different number of occurrences than the English text and the rule mixes replaced and kept occurrences, that string is left unchanged.

Useful commands:

```
# Fail if upstream strings changed or new ones need a rule (also runs in CI)
python3 Scripts/ivy/app_name.py check Scripts/ivy/app-name-rules.json Signal/translations

# Show every rule with its English text; replaced occurrences appear as [Ivy]
python3 Scripts/ivy/app_name.py explain Scripts/ivy/app-name-rules.json Signal/translations

# Per locale: how many strings are renamed, which are left unchanged
python3 Scripts/ivy/app_name.py report Scripts/ivy/app-name-rules.json Signal/translations
```

### After an upstream merge

If `check` reports problems:

1. For a **new** string, add a rule under its key with one `true`/`false` per occurrence of "Signal" in the English text (`true` = the app).
2. For a **changed** string, review the decisions against the new English text.
3. Update the fingerprints: `python3 -c 'import sys; sys.path.insert(0, "Scripts/ivy"); import app_name; print(app_name.fingerprint(sys.argv[1]))' "<English text>"`.
4. Remove rules for strings upstream deleted.

## Ivy's own strings

Strings for Ivy's own features have no official translation. They live in a separate table that upstream never touches:

- `Ivy/Translations/<locale>.lproj/Ivy.strings` (and `Ivy.stringsdict` for plurals).
- English is required for every string.
- Other languages are added when translations are available. A string missing in a language falls back to English.

The table and its lookup helper are added with the first Ivy feature that has strings.

## Language selection

Ivy follows the system language. A different language for Ivy alone can be chosen in the system settings:

- iPhone and iPad: Settings → Apps → Ivy → Language.
- Mac: System Settings → General → Language & Region → Applications.

## Right-to-left languages

Arabic, Persian, Hebrew, Uyghur and Urdu use right-to-left layouts. To check a screen, run the app in one of these languages, or use Xcode's "Right-to-Left Pseudolanguage" in the scheme's run options.

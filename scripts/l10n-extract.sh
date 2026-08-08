#!/usr/bin/env bash
#
# Populate HealthInsights/Resources/Localizable.xcstrings from the compiler's
# own extraction — the missing half of the String Catalog infrastructure.
#
# Why this exists (D7, 2026-08-08): the catalog landed on 2026-08-07 and
# `SWIFT_EMIT_LOC_STRINGS` was already YES, so the previous session recorded
# that the literals "extract on the next Xcode build with no source change".
# True — and in this repo that build never happens. **Xcode the IDE syncs a
# String Catalog; `xcodebuild` does not**, and every session here drives the
# project from the command line. An empty catalog that fills itself the day
# somebody opens Xcode is infrastructure that works for a person who does not
# exist. This script is the CLI equivalent of that IDE sync.
#
# How: `xcodebuild -exportLocalizations` compiles the app target and writes the
# strings the *compiler* found (every `Text("…")`, `String(localized:)`,
# `LocalizedStringKey` / `LocalizedStringResource` literal, with interpolations
# already turned into %@/%lld format specifiers) into an .xcloc. That is the
# same machinery Xcode's sync uses — so this never disagrees with what a later
# IDE build would have produced, and it is immune to the regex-shaped
# under-and-over-counting a grep extractor would carry.
#
# Observed on first run (Xcode 16 toolchain, 2026-08-08): `-exportLocalizations`
# **syncs the .xcstrings file in place itself** as part of the export — the
# catalog went 0 → 1122 keys before the merge below ever read it. The merge is
# kept anyway, as belt to that undocumented brace: it re-adds anything the sync
# might one day stop writing, and it enforces two properties the tool does not
# promise:
#
#   - a key no longer extracted is dropped if it carries no translations, and
#     marked "extractionState": "stale" if it does — so a translated string is
#     never silently thrown away;
#   - keys are written sorted with stable formatting, so reruns diff cleanly.
#
# macOS only: it needs xcodebuild and the iOS SDK. On Linux, CI's Mac deploy
# runner is the place this could ever run — a hosted session should not try.
#
# Usage: ./scripts/l10n-extract.sh

set -euo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"

if [ "$(uname)" != "Darwin" ]; then
    echo "l10n-extract: needs xcodebuild (macOS). On Linux the catalog cannot be regenerated — do not hand-edit it; rerun this on the Mac." >&2
    exit 1
fi

catalog=HealthInsights/Resources/Localizable.xcstrings
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "l10n-extract: running xcodebuild -exportLocalizations (compiles the app target)…"
if ! xcodebuild -exportLocalizations \
        -project HealthInsights.xcodeproj \
        -localizationPath "$tmp" \
        -exportLanguage en \
        CODE_SIGNING_ALLOWED=NO > "$tmp/xcodebuild.log" 2>&1; then
    echo "l10n-extract: export failed; last lines of the log:" >&2
    tail -20 "$tmp/xcodebuild.log" >&2
    exit 1
fi

xliff="$tmp/en.xcloc/Localized Contents/en.xliff"
if [ ! -f "$xliff" ]; then
    echo "l10n-extract: no en.xliff at $xliff" >&2
    exit 1
fi

python3 - "$xliff" "$catalog" <<'PY'
import json, sys
import xml.etree.ElementTree as ET

xliff_path, catalog_path = sys.argv[1], sys.argv[2]
ns = {'x': 'urn:oasis:names:tc:xliff:document:1.2'}

extracted = set()
for f in ET.parse(xliff_path).getroot().findall('x:file', ns):
    # Only the units destined for the catalog itself. InfoPlist.strings and
    # AppShortcuts.strings are separate tables with their own files.
    if not (f.get('original') or '').endswith('Localizable.xcstrings'):
        continue
    for unit in f.findall('.//x:trans-unit', ns):
        key = unit.get('id')
        if key is not None:
            extracted.add(key)

with open(catalog_path) as fh:
    catalog = json.load(fh)
strings = catalog.setdefault('strings', {})

added = sorted(extracted - strings.keys())
for key in added:
    strings[key] = {}

removed, stale = [], []
for key in sorted(strings.keys() - extracted):
    entry = strings[key]
    if entry.get('localizations'):
        # Never throw a translation away: mark it the way Xcode would.
        entry['extractionState'] = 'stale'
        stale.append(key)
    else:
        del strings[key]
        removed.append(key)

# A previously stale key that is extracted again stops being stale.
for key in extracted & strings.keys():
    if strings[key].get('extractionState') == 'stale':
        del strings[key]['extractionState']

catalog['strings'] = dict(sorted(strings.items()))
with open(catalog_path, 'w') as fh:
    json.dump(catalog, fh, indent=2, ensure_ascii=False, sort_keys=True)
    fh.write('\n')

# "beyond the export's own sync": the export usually writes the additions
# itself (see header), so `added` being 0 on a run that visibly grew the
# catalog is normal, not a failure.
print(f"l10n-extract: {len(extracted)} keys extracted by the compiler; "
      f"beyond the export's own sync the merge added {len(added)}, "
      f"removed {len(removed)}, kept {len(stale)} as stale; "
      f"catalog now holds {len(catalog['strings'])}.")
PY

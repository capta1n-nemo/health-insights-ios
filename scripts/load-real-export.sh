#!/usr/bin/env bash
#
# Load the reader's own export into a booted simulator, so the app can be looked
# at with real data in it.
#
# ## Why this exists
#
# `SyntheticSeed` made charts verifiable on a Mac, and its ceiling showed up
# immediately: generated data has no *history*. The balance web's grey reference
# shape and its legend both need stored score rows accumulated over real days,
# so neither could be seen on a seeded simulator — they were "phone only" for a
# reason no amount of fixture-writing could fix.
#
# The reader's own export has all of it: samples, the raw catalogue, substance
# events, the medication regimen and each card's replayed score history.
#
# ## Why no app code was needed
#
# `DataStore.loadCachedSamples` still reads a **legacy plain-JSON** cache
# (`synced_samples.json`) for builds predating the compact `HISC` format, and
# `loadCachedOther` reads plain JSON always. The export's `samples` array is
# already exactly `[HealthMetricSample]` and `unmodelled` is exactly
# `[RawMetricSample]`, so this is a file copy — not a converter, not a debug
# hook, and nothing shipped changes shape to accommodate it.
#
# ⚠️ **The file never enters the repo.** It is one person's health record and
# this repository is public — see `docs/privacy-and-ip.md`. It is read from
# `~/HealthSeed/`, which is outside the repo *and* outside iCloud, and written
# only into the simulator's own container.
#
# Usage:
#   ./scripts/load-real-export.sh                       # default export path
#   ./scripts/load-real-export.sh /path/to/export.json

set -euo pipefail

BUNDLE_ID="com.jasonsalway.healthinsights"
EXPORT="${1:-$HOME/HealthSeed/exports/health-insights-export.json}"

die() { printf '\033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Simulators are macOS only."
[ -f "$EXPORT" ] || die "No export at $EXPORT — put one in ~/HealthSeed/exports/."

case "$EXPORT" in
  *"/health-insights-ios/"*)
      die "That path is inside the repo, which is public. Keep real data in ~/HealthSeed/." ;;
esac

udid=$(xcrun simctl list devices | awk '/\(Booted\)/ {print $(NF-1); exit}' | tr -d '()')
[ -n "$udid" ] || die "No booted simulator. Run ./scripts/simulator.sh run first."

container=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data 2>/dev/null) \
    || die "$BUNDLE_ID is not installed. Run ./scripts/simulator.sh run."

# The app must not be running: it holds the samples in memory and rewrites the
# cache on the next save, which would overwrite what we just put there.
xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true

support="$container/Library/Application Support"
mkdir -p "$support"

python3 - "$EXPORT" "$support" <<'PY'
import json, os, sys
from datetime import datetime, timezone
export_path, support = sys.argv[1], sys.argv[2]
with open(export_path) as f:
    d = json.load(f)

samples = d.get("samples") or []
other = d.get("unmodelled") or []

# **Dates have to be rewritten, and this is the whole subtlety of the script.**
#
# `HealthDataExport.json()` sets `.iso8601`, so the file on disk carries date
# *strings*. `DataStore.loadCachedSamples` / `loadCachedOther` decode with a
# plain `JSONDecoder()`, whose default `.deferredToDate` strategy expects a
# **number** — seconds since 2001-01-01. Handing it the export verbatim decodes
# to nothing at all, silently, and the app opens looking freshly installed.
# That happened on the first run of this script and looked exactly like a
# loader that had done nothing.
REFERENCE = datetime(2001, 1, 1, tzinfo=timezone.utc)

def to_interval(value):
    if not isinstance(value, str):
        return value
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return value
    return (parsed - REFERENCE).total_seconds()

def rewrite(rows, keys):
    for row in rows:
        for key in keys:
            if key in row:
                row[key] = to_interval(row[key])
    return rows

samples = rewrite(samples, ("start", "end"))
other = rewrite(other, ("start", "end"))

with open(os.path.join(support, "synced_samples.json"), "w") as f:
    json.dump(samples, f)
with open(os.path.join(support, "synced_other.json"), "w") as f:
    json.dump(other, f)

# The compact cache wins over the legacy one when both exist, so it has to go.
# The name is `DataStore.compactCacheURL`'s — checked, not guessed: the first
# version of this script invented "synced_samples_compact.bin", removed nothing,
# and the app went on reading its old data while reporting a successful load.
compact = os.path.join(support, "synced_samples.hisc")
if os.path.exists(compact):
    os.remove(compact)

# **Everything else that lives in SwiftData, for the same reason.**
#
# The reader, 2026-08-05: "didn't import substances, didn't import all the
# things that populated the cards… so therefore your emulator doesn't look like
# my app, and you can't validate everything". Half of that was this script
# rather than the export: their file already carried the substance log, the
# grounding facts and the side effects, and only the two sample caches were
# ever written. `AppModel.importExportedRecords()` picks this up — Settings ▸
# Developer ▸ Import records from export.
records = {k: d.get(k) for k in ("substances", "symptoms", "sideEffects")}

# **The profile's `inputs` is an alternating key/value ARRAY, not an object.**
# Swift encodes a dictionary whose key is not a `String` that way, so
# `[GroundingKind: GroundingInput]` comes out as
# ["weightGoal", {...}, "score2Region", {...}, ...]. Decoding it as an object in
# Swift throws, and — because one `decode` covered the whole payload — that
# single mismatch silently lost the substances and side effects too. Flattened
# here to {kind: value}, which is all the importer needs.
raw_inputs = ((d.get("profile") or {}).get("inputs")) or []
flat = {}
if isinstance(raw_inputs, list):
    for i in range(0, len(raw_inputs) - 1, 2):
        key, entry = raw_inputs[i], raw_inputs[i + 1]
        if isinstance(key, str) and isinstance(entry, dict) and "value" in entry:
            flat[key] = entry["value"]
elif isinstance(raw_inputs, dict):
    for key, entry in raw_inputs.items():
        flat[key] = entry.get("value") if isinstance(entry, dict) else entry
records["profile"] = {"inputs": flat}
with open(os.path.join(support, "records_import.json"), "w") as f:
    json.dump(records, f, default=str)

# Score history lives in SwiftData, not in a JSON cache, so it cannot be
# written by copying a file. It is dropped here for the debug importer in
# `AppModel.importScoreHistory()` to pick up and replay through `recordScore`
# — the shipped upsert, so the rows land exactly as a real day would write
# them. Without this the balance web's grey "usual" shape and its legend
# cannot be seen at all: both need stored score rows, and generated data has
# no history by construction.
history = [
    {"card": x["card"], "history": x.get("history") or []}
    for x in (d.get("derivedScores") or []) if x.get("history")
]
for card in history:
    for point in card["history"]:
        point["date"] = to_interval(point["date"])
with open(os.path.join(support, "score_history_import.json"), "w") as f:
    json.dump(history, f)

types = {}
for s in samples:
    types[s.get("type")] = types.get(s.get("type"), 0) + 1
print(f"  samples:     {len(samples):,} across {len(types)} metric types")
print(f"  raw entries: {len(other):,}")
print(f"  substances:  {len(d.get('substances') or []):,}")
scored = [x for x in (d.get("derivedScores") or []) if x.get("history")]
print(f"  cards with replayed score history: {len(scored)}")
PY

printf '\n\033[32mLoaded.\033[0m Launch the app — the samples are already in its cache.\n'
printf '\033[33mReminder:\033[0m this is real health data in a simulator container. It is not in the repo and must never be.\n'

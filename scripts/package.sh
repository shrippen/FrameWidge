#!/usr/bin/env bash
# Builds the widget package for a release: OUT/framewidge-VERSION.plasmoid (a zip of package/).
#   scripts/package.sh VERSION OUT
# Stops if the version in package/metadata.json or service/Cargo.toml differs from VERSION,
# or if anything of the demo (only an internal screenshot tool) is in the package.
set -euo pipefail

VERSION="${1:?usage: scripts/package.sh VERSION OUT}"
OUT="${2:?usage: scripts/package.sh VERSION OUT}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/package"
BASE="${VERSION%%-*}"   # 1.3-beta1 -> 1.3

fail() { echo "package.sh: $*" >&2; exit 1; }

widget_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Version"])' "$PACKAGE/metadata.json")"
[ "$widget_version" = "$BASE" ] || fail "package/metadata.json has version $widget_version, tag says $BASE"
service_version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/service/Cargo.toml" | head -n1)"
[[ "$service_version" == "$BASE" || "$service_version" == "$BASE".* ]] || fail "service/Cargo.toml has version $service_version, tag says $BASE"

# The demo lives in demo/ and tests/fixtures/; nothing of it may ship.
leftovers="$(grep -rlE 'ScreenshotRunner|FrameWidge\.Mock|FRAMEWIDGE_SCREENSHOT|Studio Weber' "$PACKAGE" || true)"
[ -z "$leftovers" ] || fail "demo code in the package: $leftovers"
[ -z "$(find "$PACKAGE" -name 'world.json' -o -name 'shots.json' -o -name 'backend.py')" ] || fail "demo data in the package"

mkdir -p "$OUT"
target="$(cd "$OUT" && pwd)/framewidge-$VERSION.plasmoid"
rm -f "$target"
(cd "$PACKAGE" && zip -qr -X "$target" . -x '*/.*')
echo "$target"

#!/usr/bin/env bash
# Render every sample fixture through statusline.sh for visual review.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SL="$HERE/../statusline.sh"
CACHE="$(mktemp -d)"; trap 'rm -rf "$CACHE"' EXIT
for f in "$HERE"/*.json; do
    printf '── %s ──\n' "$(basename "$f" .json)"
    CCV_NO_FETCH=1 CCV_CACHE_DIR="$CACHE" bash "$SL" < "$f"
    printf '\n\n'
done

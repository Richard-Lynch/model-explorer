#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# image-state.sh IMAGE:TAG — does this tag exist in the registry?
#
#   exists       prints its digest (sha256:...) and exits 0
#   not built    prints nothing and exits 0 — ONLY when the registry answers "manifest unknown" /
#                "not found"
#   anything else (auth, network, an unreadable answer) exits 1: the caller must neither build
#                over nor reuse an image whose state is unknown.
set -euo pipefail

ref=${1:?usage: image-state.sh IMAGE:TAG}
err=$(mktemp)
trap 'rm -f "$err"' EXIT

if out=$(docker buildx imagetools inspect "$ref" --format '{{json .Manifest}}' 2>"$err"); then
  d=$(jq -r '.digest // empty' <<<"$out" 2>/dev/null || true)
  if ! [[ "$d" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "image-state: unreadable digest for $ref" >&2
    exit 1
  fi
  echo "$d"
elif grep -qiE 'manifest unknown|: not found' "$err"; then
  exit 0
else
  cat "$err" >&2
  echo "image-state: cannot tell whether $ref exists" >&2
  exit 1
fi

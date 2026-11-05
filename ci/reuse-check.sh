#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# reuse-check.sh IMAGE DIGEST SHA REPO — may the release reuse IMAGE@DIGEST for commit SHA?
#
# Only when BOTH hold:
#   * its org.opencontainers.image.revision label is SHA (this commit built it), and
#   * its build provenance verifies as made by REPO's release workflow on refs/heads/main at
#     commit SHA (verify-provenance.sh).
# A tag can be pushed by anything holding packages:write; a label alone can be written by anyone,
# which is why the signed provenance is required as well. Exit 1 otherwise: bump the version.
set -euo pipefail

image=${1:?image}
digest=${2:?digest}
sha=${3:?sha}
repo=${4:?repo}

docker pull -q "$image@$digest" >/dev/null
rev=$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image@$digest")
if [ "$rev" != "$sha" ]; then
  echo "reuse-check: $image@$digest was built from '$rev', not $sha. Bump the version instead of reusing it." >&2
  exit 1
fi
if ! "$(dirname "$0")/verify-provenance.sh" "$image" "$digest" "$sha" "$repo"; then
  echo "reuse-check: no build provenance for $image@$digest from $repo's release workflow on main at $sha" >&2
  exit 1
fi
echo "reuse-check: $image@$digest is revision $rev with verified provenance"

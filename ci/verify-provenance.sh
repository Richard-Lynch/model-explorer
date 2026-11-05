#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# verify-provenance.sh IMAGE DIGEST SHA REPO — does IMAGE@DIGEST carry build provenance from
# REPO's release workflow, run on refs/heads/main, at commit SHA?
#
# All four are enforced by `gh attestation verify`: the repository, the signing workflow, the
# source ref and the source commit. Without the last two, an attestation from a run of the same
# workflow on another branch, or at another commit, would pass. Exit non-zero on any mismatch.
# --bundle-from-oci reads the attestation pushed beside the image in the registry, so a check right
# after attesting does not depend on the attestations API having caught up.
set -euo pipefail

image=${1:?image}
digest=${2:?digest}
sha=${3:?sha}
repo=${4:?repo}

gh attestation verify "oci://$image@$digest" \
  --repo "$repo" \
  --signer-workflow "$repo/.github/workflows/release.yml" \
  --source-ref refs/heads/main \
  --source-digest "$sha" \
  --bundle-from-oci

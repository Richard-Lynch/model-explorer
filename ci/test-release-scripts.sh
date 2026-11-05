#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The release workflow's two decisions, against a fake `docker` and `gh` on PATH:
#   image-state.sh  exists -> digest; "manifest unknown" -> not built; any other error -> FAIL
#   reuse-check.sh  reuse only when the revision label is this commit AND provenance verifies
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT

cat > "$fake/docker" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "buildx imagetools inspect"*)
    case "$FAKE_INSPECT" in
      exists) echo '{"digest":"sha256:'"$(printf 'a%.0s' $(seq 64))"'"}' ;;
      unknown) echo 'ERROR: ghcr.io/o/r:1.0.0: not found' >&2; exit 1 ;;
      manifest) echo 'manifest unknown' >&2; exit 1 ;;
      denied) echo 'ERROR: unauthorized: authentication required' >&2; exit 1 ;;
      garbage) echo 'not json' ;;
    esac ;;
  "pull"*) exit 0 ;;
  "inspect"*) echo "$FAKE_REVISION" ;;
  *) echo "fake docker: unexpected $*" >&2; exit 2 ;;
esac
EOF
cat > "$fake/gh" <<'EOF'
#!/usr/bin/env bash
# A fake `gh attestation verify` holding ONE attestation (FAKE_ATT_REPO, _WF, _REF, _SHA). Like
# the real one, it enforces only the constraints it is GIVEN, so a caller that omits a flag lets
# a mismatching attestation through, which is what the cases below catch.
[ "$1 $2" = "attestation verify" ] || { echo "fake gh: unexpected $*" >&2; exit 2; }
shift 3
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ "$2" = "$FAKE_ATT_REPO" ] || exit 1 ;;
    --signer-workflow) [ "$2" = "$FAKE_ATT_WF" ] || exit 1 ;;
    --source-ref) [ "$2" = "$FAKE_ATT_REF" ] || exit 1 ;;
    --source-digest) [ "$2" = "$FAKE_ATT_SHA" ] || exit 1 ;;
    --bundle-from-oci) shift; continue ;;
    *) echo "fake gh: unexpected flag $1" >&2; exit 2 ;;
  esac
  shift 2
done
exit 0
EOF
chmod +x "$fake/docker" "$fake/gh"
export PATH="$fake:$PATH"

fails=0
expect() { # expect <want-rc> <want-stdout-pattern|-> <cmd...>
  local want=$1 pat=$2; shift 2
  local out rc=0
  out=$("$@" 2>/dev/null) || rc=$?
  if [ "$rc" != "$want" ] || { [ "$pat" != - ] && ! grep -qE "$pat" <<<"$out"; } || { [ "$pat" = - ] && [ -n "$out" ]; }; then
    echo "FAIL: $* (FAKE_INSPECT=${FAKE_INSPECT:-} FAKE_REVISION=${FAKE_REVISION:-} FAKE_ATT_REF=${FAKE_ATT_REF:-} FAKE_ATT_SHA=${FAKE_ATT_SHA:-}) rc=$rc out=$out"
    fails=$((fails + 1))
  else
    echo "ok:   rc=$rc $*"
  fi
}

S="$here/image-state.sh"
FAKE_INSPECT=exists expect 0 '^sha256:a{64}$' "$S" ghcr.io/o/r:1.0.0
FAKE_INSPECT=unknown expect 0 - "$S" ghcr.io/o/r:1.0.0
FAKE_INSPECT=manifest expect 0 - "$S" ghcr.io/o/r:1.0.0
FAKE_INSPECT=denied expect 1 - "$S" ghcr.io/o/r:1.0.0
FAKE_INSPECT=garbage expect 1 - "$S" ghcr.io/o/r:1.0.0

R="$here/reuse-check.sh"
D="sha256:$(printf 'a%.0s' $(seq 64))"
# The attestation the release workflow makes: this repo, its release.yml, main, this commit.
export FAKE_ATT_REPO=o/r FAKE_ATT_WF=o/r/.github/workflows/release.yml FAKE_ATT_REF=refs/heads/main FAKE_ATT_SHA=abc123
FAKE_REVISION=abc123 expect 0 'verified provenance' "$R" ghcr.io/o/r "$D" abc123 o/r
FAKE_REVISION=other expect 1 - "$R" ghcr.io/o/r "$D" abc123 o/r
FAKE_REVISION="" expect 1 - "$R" ghcr.io/o/r "$D" abc123 o/r
# An attestation from a run on ANOTHER BRANCH, for ANOTHER COMMIT, from ANOTHER WORKFLOW, or
# from ANOTHER REPO must not verify.
FAKE_REVISION=abc123 FAKE_ATT_REF=refs/heads/feature expect 1 - "$R" ghcr.io/o/r "$D" abc123 o/r
FAKE_REVISION=abc123 FAKE_ATT_SHA=def456 expect 1 - "$R" ghcr.io/o/r "$D" abc123 o/r
FAKE_REVISION=abc123 FAKE_ATT_WF=o/r/.github/workflows/ci.yml expect 1 - "$R" ghcr.io/o/r "$D" abc123 o/r
FAKE_REVISION=abc123 FAKE_ATT_REPO=x/y expect 1 - "$R" ghcr.io/o/r "$D" abc123 o/r

# The release step's own check, called directly: the same four bindings.
V="$here/verify-provenance.sh"
expect 0 - "$V" ghcr.io/o/r "$D" abc123 o/r
FAKE_ATT_REF=refs/heads/feature expect 1 - "$V" ghcr.io/o/r "$D" abc123 o/r
FAKE_ATT_SHA=def456 expect 1 - "$V" ghcr.io/o/r "$D" abc123 o/r

[ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
echo "release scripts: all cases pass"

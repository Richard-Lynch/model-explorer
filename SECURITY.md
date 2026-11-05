# Security

## Reporting

Report a vulnerability privately through GitHub's "Report a vulnerability" (Security tab), not in
a public issue.

## What the app trusts

- **Model ids are untrusted.** They come from the gateway's `/v1/models` and a public catalogue,
  and the staging panel turns them into a YAML block that is pasted into configuration a
  templating engine renders. An id must match a strict shape (`src/ids.ts`); anything else is
  withheld from every list and named in the UI, `renderDesiredState` refuses it again, and every
  emitted id is quoted. `tests/ids.test.ts` covers template tags, newlines and `#`.
- **Release images are reused only with proof.** A re-run of the release reuses an existing
  version's image only when its revision label is the releasing commit and its build provenance
  verifies as this repository's release workflow, run on `main`, at that commit
  (`ci/reuse-check.sh` and `ci/verify-provenance.sh`, tested by `ci/test-release-scripts.sh`).
  Verify a published image the same way, with the commit its release names:

      gh attestation verify oci://ghcr.io/richard-lynch/model-explorer@<digest> \
        --repo Richard-Lynch/model-explorer \
        --signer-workflow Richard-Lynch/model-explorer/.github/workflows/release.yml \
        --source-ref refs/heads/main --source-digest <commit>

  Without `--source-ref` and `--source-digest`, an attestation from a run of the same workflow
  on another branch, or at another commit, would also pass.

- **Releases hold no shared key.** The release workflow uses only this repository's own
  `GITHUB_TOKEN`, scoped per job (`packages: write` to push the image, `contents: write` to tag
  and release). The build runs third-party npm code, so no credential that reaches another
  repository is ever present in these workflows. Both write-capable jobs run in the `publish`
  environment, which deploys from `main` only and holds no secret, and a tag is created only for
  a commit on `main`.

## Dependency notes

- `package-lock.json` resolves `@napi-rs/lzma-linux-x64-gnu` (and its platform siblings) as an
  optional dependency of `rollup`, which the Vite build uses. It is a declared dependency of the
  published `rollup` 4.64.3 to 4.64.6, not an injected one: `rollup@4.64.5` carries npm SLSA
  provenance from `rollup/rollup` (built by `.github/workflows/build-and-tests.yml` at tag
  `v4.64.5`), and the lzma packages carry provenance from `Brooooooklyn/lzma`, the napi-rs
  author's repository. `npm ci` verifies every package against the lockfile's integrity hashes,
  and the image build runs it with `--ignore-scripts`.
- Build-time dependencies never reach the runtime image: it holds nginx and the built static
  files only.

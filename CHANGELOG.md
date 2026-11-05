# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-11-05

### Added

- The model explorer: a read-only single-page app that lists every model a
  LiteLLM gateway can reach and labels each by how it is reachable (enumerated
  by `GET /v1/models`, so pickable; or routable through the `openrouter/*`
  wildcard only).
- A container image, `ghcr.io/richard-lynch/model-explorer`: nginx (running as
  a non-root user, port 8080) serving the built bundle, with a strict
  Content-Security-Policy, an uncacheable `catalogue.json` served from a
  read-only directory mount at `/srv/catalogue`, and a
  `HEALTHCHECK` that probes `127.0.0.1` so it cannot fail on an IPv6
  `localhost` against an IPv4 listener. Both base images are pinned by digest.
- Model ids are untrusted input: an id must match a strict shape (path
  segments of letters, digits and `. _ : ~ -`); anything else is withheld from
  every list and named in the UI, and the staged YAML block refuses it again
  and quotes every id, so a template tag, a newline or a `#` in an upstream id
  cannot reach configuration.
- CI builds the image and runs it against a fixture catalogue; a release
  pushes the image and records its digest in the release notes and as the
  `image-digest.txt` release asset.
- A release attests the image's build provenance, and a re-run reuses an
  existing version's image only when its revision label is the releasing
  commit and its provenance verifies.

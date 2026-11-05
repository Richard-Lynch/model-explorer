# model-explorer

A read-only UI listing every model a [LiteLLM](https://github.com/BerriAI/litellm)
gateway can reach, labelled by _how_ it is reachable. It is a static
single-page app (React, Vite) served by nginx from a container image.

```
ghcr.io/richard-lynch/model-explorer
```

Deploy it **by digest**. Each release records the digest of the image it built
in its release notes and in the `image-digest.txt` release asset. Each image carries
build provenance; [SECURITY.md](SECURITY.md) gives the command that verifies it
against this repository, its release workflow, `main` and the release commit.

## The problem it exists to solve

A LiteLLM gateway can **route** far more models than it can **enumerate**:

| source                    | meaning                                             |
| ------------------------- | --------------------------------------------------- |
| `GET /v1/models`          | what Open WebUI can put in its picker               |
| OpenRouter's catalogue    | what `openrouter/*` routes                          |
| the declared picker list  | what is declared explicitly, so in the picker today |

`openrouter/*` **routes** every OpenRouter model and **enumerates none of
them**: LiteLLM has no provider model-info for OpenRouter, so the wildcard
contributes nothing to `/v1/models`, while wildcards such as `anthropic/*` and
`openai/*` _do_ expand. The only enumerated `openrouter/` ids are the ones
declared explicitly.

So a model can work perfectly and be invisible to the picker. The app shows both
populations in one list and labels every row.

## Running it

The image serves the built bundle on port **8080** as a non-root user. It needs
one input: the directory holding the catalogue snapshot (`catalogue.json`), mounted
read-only at `/srv/catalogue`. Mount the directory, not the file: a file-level bind
mount keeps the inode it started with, so a snapshot replaced by an atomic rename would
never be served.

```bash
docker run -d -p 8092:8080 \
  -v "$PWD/catalogue:/srv/catalogue:ro" \
  ghcr.io/richard-lynch/model-explorer@sha256:<digest from the release>
```

The image's `HEALTHCHECK` fetches its own `index.html` from `127.0.0.1:8080`. It
runs with a read-only root filesystem given a writable `/tmp`
(`--read-only --tmpfs /tmp`), which CI checks.

The Ansible role `richard_lynch.services.service_model_explorer`
([ansible-collection-services](https://github.com/Richard-Lynch/ansible-collection-services))
deploys it with Docker Compose, by digest, with the snapshot mounted.

### The catalogue snapshot

The snapshot is the deployment's data, not part of the image, so refreshing it
needs no new image. Its shape is defined (and validated in the browser) by
[`src/schemas.ts`](src/schemas.ts); [`tests/fixtures/catalogue.json`](tests/fixtures/catalogue.json)
is a minimal example:

```json
{
  "generated_at": "2026-01-01T00:00:00Z",
  "gateway_host": "gateway.example.com",
  "counts": { "enumerated": 2, "openrouter_catalogue": 2, "declared_picker": 1 },
  "enumerated": ["anthropic/claude-example", "openrouter/vendor/model-a"],
  "declared_picker": ["openrouter/vendor/model-a"],
  "openrouter": [{ "id": "vendor/model-a", "name": "Model A", "context_length": 128000 }]
}
```

Produce it from the gateway's `GET /v1/models` (with an admin key, on the
gateway's loopback, writing out model **ids only**) and OpenRouter's public,
unauthenticated `/api/v1/models`. `generated_at` should mean "when the data
last changed", so an unchanged export keeps the previous timestamp.

## Development

```bash
npm ci
MODEL_EXPLORER_CATALOGUE=tests/fixtures/catalogue.json npm run dev
npm test             # unit tests (vitest)
npm run build        # typecheck + bundle into dist/
ci/test-release-scripts.sh   # the release workflow's decisions, against a fake docker and gh
docker build -t model-explorer .
```

The dev server serves `MODEL_EXPLORER_CATALOGUE` at the same `/catalogue.json`
path the deployed app fetches.

## The write path: a file, not an API call

**"Add to Open WebUI" stages a model; the deployment's own configuration
applies it.** The checkbox renders the desired-state block for the declared
picker list; a human pastes it into the configuration that deploys the gateway,
reviews and applies it. The app **mutates nothing and holds no credential**.

The alternative, POSTing to the gateway's `/model/new`, is rejected for three
reasons:

1. **The configuration is the source of truth.** The declared picker list is
   curated by hand on purpose: choosing which models a human sees is a
   preference, not a mirror of an upstream catalogue. Writing to the gateway's
   database instead puts configuration where a rebuild does not reproduce it.
2. **No credential in the browser.** `/model/new` needs an admin credential. A
   scoped virtual key would narrow that but would still mean a writable gateway
   credential served from a static file.
3. **It stays reviewable.** With `store_model_in_db` enabled, a `/model/new`
   registration persists across restarts, so mistakes made that way would be
   durable _and_ invisible to the configuration.

## How you know the catalogue is stale

The page says how old the snapshot is, in words, computed from `generated_at`:

| Age              | Renders as                                    | Colour |
| ---------------- | --------------------------------------------- | ------ |
| same day         | `refreshed today`                             | muted  |
| 1–6 days         | `N days old`                                  | muted  |
| 7–29 days        | `N days old — consider re-running the export` | amber  |
| 30+ days         | same, bold                                    | red    |
| unparseable date | `snapshot date unreadable — treat as stale`   | red    |

An unreadable date is treated as **stale**, never fresh.

## Honest failure states

The app never renders an empty list as a stand-in for a failed read:

- the snapshot is parsed through **zod**, so an unexpected shape is an error
  with a path;
- a failed fetch, a non-JSON body or a schema mismatch renders **"could not load
  the catalogue"**, naming the cause and explicitly denying that it means no
  models exist;
- an empty _filter result_ says so, and names the filters as the cause;
- `catalogue.json` is served `no-store`, because a cached old snapshot would
  present retired models as available.

Three shapes in real gateway data are handled rather than papered over:

- **`/v1/models` can return duplicate ids.** Deduplicated, and the UI _says_ so,
  so its count never silently disagrees with the export's.
- **Router models price at `-1`** (no fixed rate). Mapped to _unknown_ rather
  than rendered as a negative price sorted above every free model.
- **`openrouter/openrouter/auto` is correct, not a doubled prefix.** Some models
  have `openrouter` as their literal vendor.

## Security

- No credential reaches the container or the bundle.
- nginx runs as a non-root user; mount the snapshot read-only.
- The Content-Security-Policy allows same-origin scripts only (`style-src`
  carries `'unsafe-inline'` for React's inline styles; `script-src` does not).
- **Do not scrape `/metrics`.** The SPA fallback serves `index.html` for every
  unknown path, so a scrape job would sit `up` while scraping a web page.

## Releases

Bump `version` in `package.json` and add its `CHANGELOG.md` section in a pull
request. On merge, `.github/workflows/release.yml` builds and pushes
`ghcr.io/richard-lynch/model-explorer:<version>`, then creates the `v<version>`
tag and release with the image digest. Nothing is tagged by hand.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

# Maintainers Guide

Development, CI and release documentation for nginx mTLS Proxy. For using the image, see the [README](README.md).

## Repository Layout

| Path | Purpose |
|------|---------|
| `Dockerfile` | Image definition; base image pinned by tag + digest |
| `entrypoint.sh` | Builds the nginx config snippets from environment variables, then runs the stock nginx entrypoint |
| `proxy.conf` | nginx server template (rendered by `envsubst` at container start) |
| `test-ca.sh` | Integration tests |
| `test-certs/gen-certs.sh` | Generates throwaway test certificates |
| `test-certs/test-server.js` | Test mTLS backend |
| `.github/workflows/ci.yml` | Tests + multi-arch build on pull requests |
| `.github/workflows/release.yml` | Builds, publishes and signs releases |
| `.github/workflows/renovate.yml` | Scheduled Renovate run (every 6 hours) |
| `renovate.json` | Renovate configuration |

## Building

```bash
docker build -t nginx-mtls-proxy .
```

## Testing

`test-ca.sh` builds the image, generates throwaway certificates (`test-certs/gen-certs.sh`), starts test mTLS backends and checks the proxy:

- without CA verification
- with CA verification
- with CA verification against a backend whose certificate comes from an untrusted CA (must be rejected with HTTP 502)
- with `MTLS_VERIFY_DEPTH` set
- with a client certificate from an untrusted CA (the backend must reject it with HTTP 401)

```bash
./test-ca.sh      # run the tests
./test-ca.sh -v   # also print the client certificate details received by the backends
```

Requires Docker, Node.js and openssl. Test certificates are generated into `test-certs/generated/` on every run and are gitignored - never commit certificates or keys.

## CI

Every pull request runs:

- `test` - `./test-ca.sh`
- `build (multi-arch)` - builds `linux/amd64` and `linux/arm64` without pushing

## Releasing

The base image is pinned by tag and digest in the `Dockerfile` and kept up to date by [Renovate](https://docs.renovatebot.com/), restricted to nginx **stable** (even minor versions) on **Alpine**:

- **nginx patch releases and base image rebuilds** (e.g. Alpine security fixes) are opened as PRs and auto-merged once CI passes.
- **nginx stable minor releases** (e.g. 1.30 → 1.32, roughly yearly) are opened as PRs for manual review.
- **App changes** are released manually: *Actions → Release → Run workflow* and choose `patch`, `minor` or `major`.

The app version only changes on a manual release. The Release workflow runs in one of two modes:

| Mode | Trigger | Version | GitHub |
|------|---------|---------|--------|
| `release` | Manual run | Next `patch` / `minor` / `major` | Creates the `vX.Y.Z` git tag and GitHub release |
| `rebuild` | Push to `master` that changes nothing but the `Dockerfile` `FROM` line (a merged Renovate PR), or a manual run choosing `rebuild` | Latest existing `vX.Y.Z`, rebuilt from `master` | Appends the build to the `vX.Y.Z` GitHub release |

Because a rebuild publishes `master` under the latest version, release app changes before (or together with) the next base image update - don't leave unreleased changes on `master`.

Each run:

1. Runs the CI workflow (tests + multi-arch build)
2. Builds and pushes the `linux/amd64` + `linux/arm64` image with SBOM and provenance attestations
3. Signs the image with cosign (keyless, GitHub OIDC)
4. Creates or updates the GitHub release with the build's nginx version, image digest, tags and the `cosign verify` command

Published tags:

| Tag | Moves when |
|-----|------------|
| `vX.Y.Z` | Every rebuild of that version |
| `vX.Y.Z-nginx-A.B.C` | Only on a digest-only base image update (same nginx version, patched OS) |
| `nginx-A.B.C` | A newer app version is released on that nginx version |

Quay's own GitHub build trigger must stay disabled - GitHub Actions is the only publisher. Otherwise every release tag would also produce a separate single-arch, unsigned image.

## One-time Setup

### Variables and secrets

Repository **variables** (*Settings → Secrets and variables → Actions → Variables*):

| Variable | Value |
|----------|-------|
| `REGISTRY` | `quay.io` |
| `IMAGE_NAME` | `techcoil/nginx-mtls-proxy` |

Images are published to [`quay.io/techcoil/nginx-mtls-proxy`](https://quay.io/repository/techcoil/nginx-mtls-proxy). To publish elsewhere (e.g. `docker.io`, `ghcr.io`), change these variables and the registry secrets - the workflows are registry-agnostic.

Repository **secrets**:

| Secret | Purpose |
|--------|---------|
| `REGISTRY_USERNAME` | Registry login - a Quay robot account with write access to the repository (e.g. `techcoil+github_actions`) |
| `REGISTRY_PASSWORD` | Registry password / access token |
| `RENOVATE_TOKEN` | Token Renovate uses to open and merge PRs - see below |

Secrets can be set from the CLI without leaking the value into shell history (`gh` prompts for it):

```bash
gh secret set REGISTRY_PASSWORD -R techcoil/nginx-mtls-proxy
```

### Repository settings

- Enable *Settings → General → Allow auto-merge*
- Protect `master` and require the `test` and `build (multi-arch)` status checks, so Renovate can only merge updates that pass the tests

### Renovate token

Renovate needs its own token: merges done with the default `GITHUB_TOKEN` do not trigger other workflows, so the release would never run.

1. Open <https://github.com/settings/personal-access-tokens/new> (*Settings → Developer settings → Personal access tokens → Fine-grained tokens*)
2. **Resource owner**: `techcoil` (the organization). If it isn't listed, an org owner must allow fine-grained tokens under the organization's *Settings → Personal access tokens*
3. **Expiration**: pick a date and set a reminder - Renovate silently stops working when the token expires
4. **Repository access**: *Only select repositories* → `techcoil/nginx-mtls-proxy`
5. **Repository permissions**:

   | Permission | Access | Why |
   |---|---|---|
   | Contents | Read and write | Push update branches, merge |
   | Pull requests | Read and write | Open and auto-merge PRs |
   | Issues | Read and write | Dependency Dashboard issue |
   | Workflows | Read and write | Update action versions in `.github/workflows` |
   | Commit statuses | Read and write | Read CI results before merging |
   | Dependabot alerts | Read-only | Optional - prioritise security updates |

6. Generate the token, then store it: `gh secret set RENOVATE_TOKEN -R techcoil/nginx-mtls-proxy`. If the organization requires approval for fine-grained tokens, it stays pending until an org owner approves it.

Renovate acts as the token's owner: its PRs and merges appear under that account. If branch protection requires approving reviews, those PRs cannot be approved by the same account and will never auto-merge - require status checks only, or exempt Renovate's PRs.

To run Renovate immediately instead of waiting for the schedule: *Actions → Renovate → Run workflow*.

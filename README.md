# npm builder image

Container image for the npm Trusted Libraries factory. Runs onboarder recipes
(`build.entrypoint.sh`, `verify.smoke.sh`) inside Konflux build tasks.

## Toolchain (v1)

All packages from **UBI 8 repositories** (AppStream/BaseOS) — no rustup or
downloads from `static.rust-lang.org`.

| Tool | Source | Pinning |
| ---- | ------ | ------- |
| UBI 8 base | `registry.access.redhat.com/ubi8/ubi` | digest in [`baseimage.lock`](./baseimage.lock) + Containerfile `ARG BASEIMAGE` |
| Node.js 20 LTS (default `PATH`) | AppStream `nodejs:20` module | stream `20` |
| Node.js 22 (side-by-side) | AppStream `nodejs:22` via `dnf --installroot` + wrappers under `/opt/nodejs/22/bin` | stream `22`; recipes select via `select-builder-node`. Install uses `NPM_BUILDER_RELEASEVER` or major from `/etc/os-release` `VERSION_ID` (not hard-coded `8`) |
| Python 3.9 | AppStream `python39:3.9` | used as `npm_config_python` when Node 22 is selected (node-gyp ≥11 needs ≥3.8) |
| Go | AppStream `golang` | distro default |
| **C/C++ (node-gyp)** | **gcc-toolset-14** (CodeReady Builder) | toolset version in [`gcc-toolset.lock`](./gcc-toolset.lock); C++20 on UBI 8 glibc |
| **SBOM** | **Syft** from `registry.redhat.io/rh-syft-tech-preview/syft-rhel9` (digest-pinned via `SYFT_IMAGE`, same as [tssc-dev-multi-ci](https://github.com/redhat-appstudio/tssc-dev-multi-ci/blob/main/Dockerfile)) | SPDX JSON → `package/sboms/redhat.spdx.json` (same name as Python wheels) |
| **Rust** | AppStream **`rust-toolset`** module | **exact RPM VR** in [`rust-toolset.lock`](./rust-toolset.lock) |
| node-gyp deps | `python3`, `openssl-devel`, stock `make`, etc. | stock gcc remains installed; **`CC`/`CXX`** point at toolset |

### Rust pinning (RHEL 8)

Unlike `nodejs:20`, **`rust-toolset` is a rolling Application Stream** — Red Hat
rebases the single module in place. There is no `dnf module install rust-toolset:1.84`
stream selector.

**Edit [`rust-toolset.lock`](./rust-toolset.lock) for Rust** — the Containerfile and
install script read `RUST_VERSION` and `RUST_VR` from there. UBI rust-toolset RPMs
use epoch `(none)`; we pin by installing exact version-release specs, then
`dnf versionlock`.

**Edit [`baseimage.lock`](./baseimage.lock) when bumping UBI** — keep the same
digest in Containerfile `ARG BASEIMAGE` (required before `FROM`; buildkit cannot
read the lock file into that line).

**Edit [`gcc-toolset.lock`](./gcc-toolset.lock) when bumping gcc-toolset** — set
`GCC_TOOLSET` and update Containerfile `ENV` paths
(`/opt/rh/gcc-toolset-${GCC_TOOLSET}/...`).

To refresh the rust lock file from current UBI (uses `baseimage.lock` as the query image).
Requires `docker` on the host (`CONTAINER_RUNTIME=podman` also works):

```bash
./hack/update-rust-toolset-lock.sh
```

Or query manually, then update `rust-toolset.lock` by hand:

```bash
docker run --rm --platform linux/amd64 "$(grep BASEIMAGE= baseimage.lock | cut -d= -f2-)" bash -c \
  'dnf -y module install rust-toolset && rpm -q rust cargo rust-std-static rust-toolset'
```

**Caveat:** UBI CDN may eventually drop older module RPMs after a rebase. If a
pinned VR disappears, the image build fails until you bump `rust-toolset.lock` —
that is intentional.

The Python **`plumbing-builder`** uses the same **gcc-toolset-14** pattern for manylinux
wheels. npm-builder reuses it so Tier C addons (e.g. **better-sqlite3 ≥ 11.2**) can
compile with **C++20** without moving the base image to UBI 9. For Rust, **`plumbing-builder`**
uses **rustup** from the internet; this npm image deliberately uses **Red Hat RPMs only**.

## Quay

Built by Konflux component `npm-builder` under application `calunga-v2`:

```text
quay.io/redhat-user-workloads/calunga-tenant/npm-builder:<tag>
```

### `registry.redhat.io` pull secret (required for Syft)

The Containerfile `COPY --from`s Syft from `registry.redhat.io`, same pattern as
[tssc-dev-multi-ci](https://github.com/redhat-appstudio/tssc-dev-multi-ci/blob/main/Dockerfile).
That registry is authenticated — without a pull secret, buildah fails with
`invalid username/password` / `Please login to the Red Hat Registry`.

1. Create a [registry service account](https://access.redhat.com/terms-based-registry/accounts).
2. In Konflux (`calunga-tenant` → Secrets), add an **Image pull secret** for
   `registry.redhat.io` with those credentials.
3. Link it to component **`npm-builder`** (or all components) so it attaches to
   `build-pipeline-npm-builder`. No PipelineRun YAML change is needed.

Local builds: `podman login registry.redhat.io` before `docker`/`podman` build.

## Scripts

| Script | Role |
| ------ | ---- |
| `build-npm-package` | Run entrypoint + smoke for one manifest |
| `build-npm-packages` | Build multiple package dirs (Tekton `PACKAGES` args) |
| `collect-npm-artifacts` | Stage `out/*.tgz` for OCI push / optional Pulp publish |
| `generate-npm-sbom` | Syft → SPDX JSON embedded as `package/sboms/redhat.spdx.json`, then enrich DocumentRoot with npm `name` / `version` / `pkg:npm/…` purl from `package.json` |
| `verify-npm-sbom` | Assess: require embedded `redhat.spdx.json` with SPDX-2 + npm name/version or purl matching `package.json` |
| `lookup-npm-tl-compliance` | Assess helper: packument lookup for `name` + version or range (optional basic-auth for allowlisted Lightwell registry URLs) |
| `assess-npm-compliance` | Assess: inductive L1/L2/L3 from packed `package.json` `dependencies` + `lookup-npm-tl-compliance`; write `*.tl-compliance.json` |
| `npm-publish-pulp` | Optional Pulp npm publish (deferred; Tekton step only) |
| `build_scripts/install-gcc-toolset.sh` | Install gcc-toolset from `gcc-toolset.lock` |
| `build_scripts/install-rust-toolset.sh` | Install + versionlock pinned rust-toolset RPMs |
| `build_scripts/install-nodejs-side.sh` | Install an extra Node major beside default 20 (`/opt/nodejs/<N>/bin`) |
| `select-builder-node` | Entrypoint helper: put Node 20 or 22 first on `PATH` (source or `eval "$(select-builder-node 22)"`) |
| `hack/update-rust-toolset-lock.sh` | Refresh `rust-toolset.lock` from UBI |

### Selecting Node 20 vs 22 in a recipe

Default `PATH` is Node 20. For packages with `engines.node: ">=22"` (e.g. `better-sqlite3@13`):

```bash
# shellcheck source=/dev/null
source "$(command -v select-builder-node)"
select_builder_node_from_engines package.json
# or: select_builder_node 22
```

`node-gyp` / `npm` then use the selected major. Prefer selecting **before** install/compile/smoke load checks.

Publishing to Quay (OCI artifact) and optional Pulp are handled in **Tekton steps**.
Package attestations are **release-phase** (like Python `rh-sign-python-wheels`); see
`utils/scripts/generate-and-sign-npm-attestations`.

## Local build

Requires `docker` on the host (`CONTAINER_RUNTIME=podman ./hack/update-rust-toolset-lock.sh` for lock refresh only).

```bash
docker build -t npm-builder -f Containerfile .
docker run --rm npm-builder node --version
docker run --rm npm-builder go version
docker run --rm npm-builder g++ --version
docker run --rm npm-builder bash -c 'echo | g++ -std=c++20 -x c++ - -o /dev/null -'
docker run --rm npm-builder rustc --version
docker run --rm npm-builder cargo --version
docker run --rm npm-builder syft version
```

## Tests

Konflux / `docker build` runs `tests/run_tests.sh` in a Containerfile stage and
will not produce the final image if they fail (same pattern as `utils/`).

```bash
./npm-builder/tests/run_tests.sh
```

Local runs need bash 4+ (`mapfile`), `sha256sum`, and `oras`. On macOS:

```bash
brew install bash coreutils oras
```

The probe scripts prepend Homebrew `bash` and GNU `sha256sum` when present.

## Closure index (PoC probes)

Local end-to-end without Konflux SBOM/signing. **`hack/` probes are not used in
Tekton** — they invoke the same production scripts that run on Linux in CI.

| Surface | Image | macOS shims? |
| ------- | ----- | ------------ |
| `assess-npm-compliance` | npm-builder | No |
| `update-npm-closure`, `npm-rebalance-closure` | plumbing-utils | No |
| `npm-pulp-upload` | plumbing-utils | No |
| `hack/npm-closure-probe` | local only | Yes (Python; prepends `utils/scripts`, `npm-builder/scripts`) |

Schema v3: per-package `*.tl-compliance.json` (immutable `direct_dependencies`,
mutable `missing_gaps` / `pending_l3_gaps`) plus global `npm-closure-index.json`
OCI. See `npm-registry/docs/tl-compliance-schema-v3.md`.

### `hack/npm-closure-probe` (unified local CLI)

Subcommands call the same production scripts as the release pipeline:

| Subcommand | Pipeline steps |
| ---------- | -------------- |
| `add NAME VERSION` | **assess** (`assess-npm-compliance`) → **publish** (`npm-pulp-upload`, `oras`, `npm-release-closure-update`) |
| `seed [--init-index]` | `update-npm-closure seed` |
| `rebalance [--index-only]` | `update-npm-closure rebalance` |
| `e2e [--mode …]` | Multi-package scenario (runs `add` repeatedly + assertions) |
| `assess NAME VERSION` | assess only (no Quay prefixes) |

**Probe env** (prefixes required; never defaulted):

```bash
cd plumbing
export PULP_USERNAME='...'
export PULP_PASSWORD='...'
export COMPLIANCE_IMAGE_PREFIX='quay.io/<org>/npm-compliance'
export SNAPSHOT_IMAGE_PREFIX='quay.io/<org>/npm-snapshot'
# optional: CLOSURE_INDEX_IMAGE='quay.io/<org>/npm-compliance/npm-closure-index:latest'
```

```bash
./hack/npm-closure-probe seed --init-index
./hack/npm-closure-probe e2e
./hack/npm-closure-probe add depd 2.0.0
./hack/npm-closure-probe rebalance --index-only
./hack/npm-closure-probe assess express 4.22.2
```

Seed/rebalance need `COMPLIANCE_IMAGE_PREFIX` only (no snapshot prefix).

OCI artifacts:

| Ref | Contents |
| --- | -------- |
| `SNAPSHOT_IMAGE_PREFIX:<name-version>` | package `.tgz` only |
| `COMPLIANCE_IMAGE_PREFIX:<name-version>` | `*.tl-compliance.json` (schema v3) |
| `…/npm-closure-index:latest` | global reverse gap index |

Release `update-npm-closure update` drains index waiters when a blocker lands,
registers the release on gap keys, and updates Pulp `tl.compliance_level` /
`tl.compliance_oci_digest` (no index digest on Pulp).

Repair: `update-npm-closure rebalance` or `npm-rebalance-closure` (utils image).

Requires `docker login quay.io` for OCI push/pull steps.

### Closure index + level propagation E2E

Two tier-A consumers with shared deps; lands `ms@2.0.0` (debug). In parents phase,
`send@0.19.0` registers gap blockers on the index, then `ms@2.1.3` is probed.

| `--mode` | What it does |
| -------- | ------------ |
| `all` (default) | Shared chain → index assertions → finalhandler L3 |
| `shared` | Land shared deps + refresh debug |
| `parents` | Probe send/finalhandler + assert index links (e.g. ms→send) |
| `levels` | finalhandler-only deps + assert finalhandler L3 |
| `verify` | No probes; assert index + levels on current OCI |

```bash
./hack/npm-closure-probe e2e 2>&1 | tee /tmp/npm-closure-parent-e2e.log
./hack/npm-closure-probe e2e --mode verify
./hack/npm-closure-probe e2e --mode parents
```

Add packages:

```bash
./hack/npm-closure-probe add depd 2.0.0
./hack/npm-closure-probe add ms 2.1.3 --seed-first
```

Seed / rebalance:

```bash
./hack/npm-closure-probe seed --init-index
./hack/npm-closure-probe rebalance --index-only
./hack/npm-closure-probe rebalance
```

Exits non-zero if assertions fail.


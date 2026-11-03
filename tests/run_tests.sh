#!/usr/bin/env bash
# Unit tests for npm-builder compliance helpers.
# Run from repo:  ./npm-builder/tests/run_tests.sh
# Or via Containerfile test stage.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# assess-npm-compliance needs bash 4+ (mapfile) and GNU sha256sum.
for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "${b}" ]]; then
        export PATH="$(dirname "${b}"):${PATH}"
        break
    fi
done
for p in /opt/homebrew/opt/coreutils/libexec/gnubin /usr/local/opt/coreutils/libexec/gnubin; do
    if [[ -x "${p}/sha256sum" ]]; then
        export PATH="${p}:${PATH}"
        break
    fi
done

python3 "${ROOT}/test_lookup_npm_tl_compliance.py" -v
bash "${ROOT}/test_assess_npm_compliance.sh"

# Dual Node helpers only exist in the built image (or when wrappers were installed).
if [[ -x /opt/nodejs/22/bin/node ]]; then
    # Prefer image copy of select-builder-node when present.
    if [[ -x /usr/local/bin/select-builder-node ]]; then
        :
    elif [[ -f "${ROOT}/../scripts/select-builder-node" ]]; then
        cp "${ROOT}/../scripts/select-builder-node" /tmp/select-builder-node
        chmod +x /tmp/select-builder-node
        # test script sources /usr/local/bin first; fall back via PATH
        export PATH="/tmp:${PATH}"
    fi
    bash "${ROOT}/test_select_builder_node.sh"
else
    echo "[test] skip select-builder-node (Node 22 side install not present on host)"
fi

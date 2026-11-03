#!/usr/bin/env bash
# Dual-Node selection smoke (runs in Containerfile test stage on the tools image).
set -euo pipefail

echo "[test] default node is 20.x"
default_ver="$(/usr/bin/node -v)"
[[ "${default_ver}" == v20.* ]] || {
    echo "expected default /usr/bin/node v20.*, got ${default_ver}" >&2
    exit 1
}

echo "[test] side Node 22 wrappers exist"
[[ -x /opt/nodejs/22/bin/node ]] || {
    echo "missing /opt/nodejs/22/bin/node" >&2
    exit 1
}
side_ver="$(/opt/nodejs/22/bin/node -v)"
[[ "${side_ver}" == v22.* ]] || {
    echo "expected side node v22.*, got ${side_ver}" >&2
    exit 1
}
/opt/nodejs/22/bin/npm -v >/dev/null

echo "[test] select-builder-node CLI / source API"
_selector=""
for candidate in \
    /usr/local/bin/select-builder-node \
    /src/scripts/select-builder-node \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/select-builder-node"; do
    if [[ -f "${candidate}" ]]; then
        _selector="${candidate}"
        break
    fi
done
[[ -n "${_selector}" ]] || {
    echo "select-builder-node script not found" >&2
    exit 1
}
# shellcheck source=/dev/null
source "${_selector}"

select_builder_node 22
cur="$(node -v)"
[[ "${cur}" == v22.* ]] || {
    echo "after select 22 expected v22.*, got ${cur}" >&2
    exit 1
}
[[ "${npm_config_python:-}" == /usr/bin/python3.9 ]] || {
    echo "expected npm_config_python=/usr/bin/python3.9 after select 22, got '${npm_config_python:-}'" >&2
    exit 1
}
[[ -x /usr/bin/python3.9 ]] || {
    echo "python3.9 missing" >&2
    exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
printf '%s\n' '{"engines":{"node":">=22"}}' >"${tmpdir}/package.json"
select_builder_node_from_engines "${tmpdir}/package.json"
cur="$(node -v)"
[[ "${cur}" == v22.* ]] || {
    echo "from engines >=22 expected v22.*, got ${cur}" >&2
    exit 1
}

select_builder_node 20
cur="$(node -v)"
[[ "${cur}" == v20.* ]] || {
    echo "after select 20 expected v20.*, got ${cur}" >&2
    exit 1
}

echo "[test] select-builder-node CLI eval exports Python for Node 22"
# Fresh PATH for CLI mode (script is also executable).
cli_out="$(PATH="/usr/bin:/bin" "${_selector}" 22)"
eval "${cli_out}"
cur="$(node -v)"
[[ "${cur}" == v22.* ]] || {
    echo "CLI select 22 expected v22.*, got ${cur}" >&2
    exit 1
}
[[ "${npm_config_python:-}" == /usr/bin/python3.9 ]] || {
    echo "CLI select 22 expected npm_config_python=/usr/bin/python3.9, got '${npm_config_python:-}'" >&2
    exit 1
}

echo "[test] select-builder-node OK"

#!/usr/bin/env bash
# apply-publish-version-override is a no-op without the env var, and fails closed
# when the override is set but the recipe checkout has no rewrite script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="${ROOT}/scripts/apply-publish-version-override"
PASS=0
FAIL=0

ok() { echo "ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

if SOURCE_ROOT="${tmp}" bash "${APPLY}" packages/left-pad/1.2.3; then
    ok "empty override is a no-op"
else
    bad "empty override should succeed"
fi

mkdir -p "${tmp}/packages/left-pad/1.2.3"
if SOURCE_ROOT="${tmp}" LIGHTWELL_SCRATCH_PUBLISH_VERSION="1.2.3-lwci.0" \
    bash "${APPLY}" packages/left-pad/1.2.3; then
    bad "missing rewrite script should fail"
else
    ok "missing rewrite script fails closed"
fi

mkdir -p "${tmp}/hack"
cat > "${tmp}/hack/manifest_publish_version.py" <<'PY'
import sys
from pathlib import Path
Path("called").write_text(" ".join(sys.argv[1:]) + "\n", encoding="utf-8")
PY
manifest="${tmp}/packages/left-pad/1.2.3/manifest.json"
run_override() {
    (
        cd "${tmp}"
        SOURCE_ROOT="${tmp}" \
            LIGHTWELL_SCRATCH_PUBLISH_VERSION="${1}" \
            LIGHTWELL_BUILD_INTENT="${2:-}" \
            PUBLISH_TO_PULP="${3:-false}" \
            bash "${APPLY}" packages/left-pad/1.2.3
    )
}

printf '%s\n' '{"name":"left-pad","version":"1.2.3","stream":"remediated"}' > "${manifest}"
if run_override "1.2.3-lwci.0" scratch; then
    bad "remediated stream should fail"
else
    ok "remediated stream fails"
fi
[[ ! -f "${tmp}/called" ]] \
    && ok "remediated failure does not rewrite" \
    || bad "remediated failure should stop before the rewrite script"

printf '%s\n' '{"name":"left-pad","version":"1.2.3","stream":"novel"}' > "${manifest}"
if run_override "1.2.3-lwci.0" scratch; then
    bad "novel stream should fail"
else
    ok "novel stream fails"
fi

printf '%s\n' '{"name":"left-pad","version":"1.2.3","stream":"validated"}' > "${manifest}"
if run_override "1.2.3-lwci.0" release; then
    bad "release intent should fail"
else
    ok "validated release intent fails"
fi
if run_override "1.2.3-lwci.0"; then
    bad "unset intent should fail"
else
    ok "unset intent fails closed"
fi
if run_override "9.9.9" scratch; then
    bad "unrelated version should fail"
else
    ok "override must be the manifest version plus a ci suffix"
fi
if run_override "1.2.3-rhlw.1" scratch; then
    bad "rhlw suffix should fail"
else
    ok "remediated publish suffix fails"
fi
if run_override "1.2.3-lwci.0" scratch true; then
    bad "pulp publish with override should fail"
else
    ok "override with PUBLISH_TO_PULP fails"
fi

rm -f "${tmp}/called"
if run_override "1.2.3-lwci.0" scratch \
    && [[ "$(cat "${tmp}/called")" == "1.2.3-lwci.0 packages/left-pad/1.2.3" ]] \
    && [[ ! -f "${tmp}/lightwell-ci-reversion.json" ]]; then
    ok "scratch validated override rewrites the recipe manifests"
else
    bad "scratch validated override should rewrite the recipe manifests"
fi

cat > "${tmp}/hack/manifest_publish_version.py" <<'PY'
import sys
from pathlib import Path
Path("called").write_text(sys.executable + "\n", encoding="utf-8")
PY
rm -f "${tmp}/called"
if run_override "1.2.3-lwci.0" scratch; then
    exe="$(tr -d '\n' < "${tmp}/called")"
    if [[ -x /usr/bin/python3.9 ]]; then
        [[ "${exe}" == "/usr/bin/python3.9" ]] \
            && ok "rewrite script runs under /usr/bin/python3.9" \
            || bad "expected /usr/bin/python3.9, got ${exe}"
    else
        ok "rewrite script runs under ${exe} (no /usr/bin/python3.9 on this host)"
    fi
else
    bad "interpreter probe should succeed"
fi

real_script="${ROOT}/../calunga-javascript/hack/manifest_publish_version.py"
if [[ -f "${real_script}" ]]; then
    cp "${real_script}" "${tmp}/hack/manifest_publish_version.py"
    printf '%s\n' '{"name":"left-pad","version":"1.2.3","stream":"validated","outputs":[{"path":"out/left-pad-1.2.3.tgz"}],"optional_dependencies_published":["left-pad-native@1.2.3"]}' > "${manifest}"
    if run_override "1.2.3-lwci.0" scratch \
        && "${exe:-python3}" -c '
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["version"] == "1.2.3-lwci.0", data["version"]
assert data["outputs"][0]["path"] == "out/left-pad-1.2.3-lwci.0.tgz"
assert data["optional_dependencies_published"] == ["left-pad-native@1.2.3-lwci.0"]
' "${manifest}"; then
        ok "real calunga rewrite script rewrites the manifest"
    else
        bad "real calunga rewrite script should rewrite the manifest"
    fi
else
    echo "skip real calunga script (not beside npm-builder)"
fi

echo "apply-publish-version-override: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]]

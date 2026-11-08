# Shared npm SPDX identity helpers — source from generate/verify scripts.
# Do not execute directly.

# Build a purl-spec npm Package URL (scoped namespace "@" → %40).
npm_sbom_purl() {
    local name="${1:?}"
    local version="${2:?}"
    if [[ "${name}" == @*/* ]]; then
        # %% → literal % so "%40" is not a printf conversion.
        printf 'pkg:npm/%%40%s@%s\n' "${name#@}" "${version}"
    else
        printf 'pkg:npm/%s@%s\n' "${name}" "${version}"
    fi
}

# Path to the shared jq filter next to this sourced file.
_npm_sbom_identity_jq() {
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "${here}/npm-sbom-identity.jq"
}

# Exit 0 if sbom JSON has SPDX-2 + npm name/version or matching purl.
# Usage: npm_sbom_identity_ok <sbom.json> <name> <version>
npm_sbom_identity_ok() {
    local sbom="${1:?}"
    local name="${2:?}"
    local version="${3:?}"
    local purl jqfile
    purl="$(npm_sbom_purl "${name}" "${version}")"
    jqfile="$(_npm_sbom_identity_jq)"
    jq -e \
        --arg name "${name}" \
        --arg version "${version}" \
        --arg purl "${purl}" \
        -f "${jqfile}" \
        "${sbom}" >/dev/null
}

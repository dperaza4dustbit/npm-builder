#!/usr/bin/env bash
# generate-npm-sbom: Syft dir scan + package.json name/version/purl enrichment.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="${ROOT}/scripts/generate-npm-sbom"
VERIFY="${ROOT}/scripts/verify-npm-sbom"
# shellcheck source=../scripts/lib/npm-sbom-identity.sh
source "${ROOT}/scripts/lib/npm-sbom-identity.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

# Stub syft: path-only root via DESCRIBES (Syft leaves documentDescribes null).
mkdir -p "${tmpdir}/bin"
cat > "${tmpdir}/bin/syft" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "version" ]]; then
  echo "syft stub 0.0.0"
  exit 0
fi
out=""
dir=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  a="${args[$i]}"
  if [[ "${a}" == -o ]]; then
    out="${args[$((i + 1))]#spdx-json=}"
  elif [[ "${a}" == dir:* ]]; then
    dir="${a#dir:}"
  fi
done
: "${out:?syft stub missing -o spdx-json=}"
cat > "${out}" <<JSON
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "${dir}",
  "packages": [
    {
      "SPDXID": "SPDXRef-Package-dir-root",
      "name": "${dir}",
      "downloadLocation": "NOASSERTION",
      "filesAnalyzed": false
    }
  ],
  "relationships": [
    {
      "spdxElementId": "SPDXRef-DOCUMENT",
      "relatedSpdxElement": "SPDXRef-Package-dir-root",
      "relationshipType": "DESCRIBES"
    }
  ]
}
JSON
EOF
chmod +x "${tmpdir}/bin/syft"
export PATH="${tmpdir}/bin:${PATH}"

artifact="${tmpdir}/artifact"
mkdir -p "${artifact}"

# Unscoped + scoped packages
for spec in 'lodash|4.17.21' '@scope/demo|1.2.3'; do
  name="${spec%%|*}"
  version="${spec##*|}"
  safe="${name//\//-}"
  mkdir -p "${tmpdir}/build/${safe}/package"
  jq -nc --arg n "${name}" --arg v "${version}" \
    '{name:$n, version:$v, files:["index.js"]}' \
    > "${tmpdir}/build/${safe}/package/package.json"
  echo ok > "${tmpdir}/build/${safe}/package/index.js"
  tar -czf "${artifact}/${safe}-${version}.tgz" -C "${tmpdir}/build/${safe}" package
done

"${GEN}" "${artifact}"
"${VERIFY}" "${artifact}"

for tgz in "${artifact}"/*.tgz; do
  pkg_json="$(tar -xOf "${tgz}" package/package.json)"
  name="$(jq -r '.name' <<<"${pkg_json}")"
  version="$(jq -r '.version' <<<"${pkg_json}")"
  purl="$(npm_sbom_purl "${name}" "${version}")"
  sbom="$(tar -xOf "${tgz}" package/sboms/redhat.spdx.json)"
  echo "${sbom}" | jq -e --arg n "${name}" --arg v "${version}" --arg p "${purl}" '
    .name == ($n + "@" + $v)
    and any(.packages[]?;
      .name == $n and .versionInfo == $v
      and any(.externalRefs[]?;
        .referenceType == "purl"
        and (.referenceLocator == $p or (.referenceLocator | startswith($p + "?")))))
  ' >/dev/null
  echo "[ok] ${name}@${version} identity in SBOM"
done

# Preserve richer Syft purl (same coords + qualifiers); do not replace with bare.
cat > "${tmpdir}/bin/syft" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "version" ]]; then
  echo "syft stub 0.0.0"
  exit 0
fi
out=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" == -o ]]; then
    out="${args[$((i + 1))]#spdx-json=}"
  fi
done
: "${out:?syft stub missing -o spdx-json=}"
cat > "${out}" <<'JSON'
{
  "spdxVersion": "SPDX-2.3",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "rich",
  "documentDescribes": ["SPDXRef-Package-rich-root"],
  "packages": [
    {
      "SPDXID": "SPDXRef-Package-rich-root",
      "name": "path-only",
      "downloadLocation": "NOASSERTION",
      "filesAnalyzed": false,
      "externalRefs": [
        {
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:npm/rich@9.9.9?arch=x64"
        },
        {
          "referenceCategory": "OTHER",
          "referenceType": "purl",
          "referenceLocator": "pkg:npm/unrelated@1.0.0"
        }
      ]
    }
  ]
}
JSON
EOF
chmod +x "${tmpdir}/bin/syft"

rich_art="${tmpdir}/artifact-rich-purl"
mkdir -p "${rich_art}" "${tmpdir}/build/rich/package"
jq -nc '{name:"rich", version:"9.9.9", files:["index.js"]}' \
  > "${tmpdir}/build/rich/package/package.json"
echo ok > "${tmpdir}/build/rich/package/index.js"
tar -czf "${rich_art}/rich-9.9.9.tgz" -C "${tmpdir}/build/rich" package

"${GEN}" "${rich_art}"
"${VERIFY}" "${rich_art}"
rich_sbom="$(tar -xOf "${rich_art}/rich-9.9.9.tgz" package/sboms/redhat.spdx.json)"
echo "${rich_sbom}" | jq -e '
  any(.packages[]?;
    .name == "rich" and .versionInfo == "9.9.9"
    and any(.externalRefs[]?;
      .referenceType == "purl"
      and .referenceLocator == "pkg:npm/rich@9.9.9?arch=x64")
    and (any(.externalRefs[]?; .referenceLocator == "pkg:npm/rich@9.9.9") | not)
    and (any(.externalRefs[]?; .referenceLocator == "pkg:npm/unrelated@1.0.0") | not))
' >/dev/null
echo "[ok] preserve richer matching purl; drop conflicting purl"

# Fail closed: packages present but no documentDescribes/DESCRIBES must not enrich packages[0].
cat > "${tmpdir}/bin/syft" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "version" ]]; then
  echo "syft stub 0.0.0"
  exit 0
fi
out=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" == -o ]]; then
    out="${args[$((i + 1))]#spdx-json=}"
  fi
done
: "${out:?syft stub missing -o spdx-json=}"
cat > "${out}" <<'JSON'
{
  "spdxVersion": "SPDX-2.3",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "orphan",
  "packages": [
    {
      "SPDXID": "SPDXRef-Package-something-else",
      "name": "not-the-root",
      "downloadLocation": "NOASSERTION",
      "filesAnalyzed": false
    }
  ]
}
JSON
EOF
chmod +x "${tmpdir}/bin/syft"

fail_art="${tmpdir}/artifact-no-describes"
mkdir -p "${fail_art}" "${tmpdir}/build/failcase/package"
jq -nc '{name:"failcase", version:"0.0.1", files:["index.js"]}' \
  > "${tmpdir}/build/failcase/package/package.json"
echo ok > "${tmpdir}/build/failcase/package/index.js"
tar -czf "${fail_art}/failcase-0.0.1.tgz" -C "${tmpdir}/build/failcase" package

if "${GEN}" "${fail_art}"; then
  echo "FAIL: expected generate-npm-sbom to error without documentDescribes/DESCRIBES" >&2
  exit 1
fi
echo "[ok] refuse packages[0] fallback when documentDescribes/DESCRIBES missing"

echo "PASS: generate-npm-sbom enrichment"

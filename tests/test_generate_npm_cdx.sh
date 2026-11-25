#!/usr/bin/env bash
# generate-npm-cdx: CycloneDX SBOM next to the SPDX identity, with stream pedigree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="${ROOT}/scripts/generate-npm-cdx"
REPO_URL="https://example.test/npm/validated"
fail=0

pass() { echo "PASS: $*"; }
die() { echo "FAIL: $*" >&2; fail=1; }

make_tarball() {
    local dest="$1" name="$2" version="$3" purl="$4"
    local dir
    dir="$(mktemp -d)"
    mkdir -p "${dir}/package/sboms"
    jq -n --arg name "${name}" --arg version "${version}" \
        '{name: $name, version: $version}' > "${dir}/package/package.json"
    jq -n --arg name "${name}" --arg version "${version}" --arg purl "${purl}" \
        '{
          spdxVersion: "SPDX-2.3",
          name: ($name + "@" + $version),
          packages: [{
            SPDXID: "SPDXRef-Package",
            name: $name,
            versionInfo: $version,
            externalRefs: [{referenceType: "purl", referenceLocator: $purl}]
          }]
        }' > "${dir}/package/sboms/redhat.spdx.json"
    tar -czf "${dest}" -C "${dir}" package
    rm -rf "${dir}"
}

git_tip() {
    local repo="$1" branch="$2" message="$3"
    git init -q "${repo}"
    git -C "${repo}" checkout -q -b "${branch}"
    echo tip > "${repo}/README"
    git -C "${repo}" add README
    git -C "${repo}" \
        -c user.email="cdx@example.com" \
        -c user.name="cdx" \
        -c commit.gpgsign=false \
        commit -q -m "${message}"
}

run_case() {
    local work="$1"
    SBOM_REPOSITORY_URL="${REPO_URL}" \
    ARTIFACT_ROOT="${work}/artifact" \
    SOURCE_ROOT="${work}/source" \
    BUILT_LIST="${work}/built.txt" \
    CDX_ROOT="${work}/cdx" \
    WORKDIR_ROOT="${work}" \
        "${GEN}"
}

# --- validated: ancestor, empty patches, no git read ---
work="$(mktemp -d)"
mkdir -p "${work}/source/packages/left-pad/1.2.3" "${work}/artifact"
jq -n --arg url "https://invalid.example/does-not-exist.git" '{
  name: "left-pad",
  version: "1.2.3",
  stream: "validated",
  upstream: {version: "1.2.3", source: {url: "https://example.test/left-pad.git", ref: "1.2.3"}},
  source: {url: $url, ref: "1.2.3"}
}' > "${work}/source/packages/left-pad/1.2.3/manifest.json"
make_tarball "${work}/artifact/left-pad-1.2.3.tgz" left-pad 1.2.3 "pkg:npm/left-pad@1.2.3"
printf '%s\n' "packages/left-pad/1.2.3" > "${work}/built.txt"
if run_case "${work}"; then
    doc="$(find "${work}/cdx" -name '*.cdx.json' | head -1)"
    comp="$(jq -c '.metadata.component' "${doc}")"
    name="$(jq -r '.metadata.component.name' "${doc}")"
    version="$(jq -r '.metadata.component.version' "${doc}")"
    purl="$(jq -r '.metadata.component.purl' "${doc}")"
    patches="$(jq -c '.metadata.component.pedigree.patches' "${doc}")"
    ancestor="$(jq -r '.metadata.component.pedigree.ancestors[0].version' "${doc}")"
    supplier="$(jq -r '.metadata.supplier.name' "${doc}")"
    vulns="$(jq '.vulnerabilities // empty' "${doc}")"
    same="$(jq -e '.metadata.component == .components[0]' "${doc}" >/dev/null && echo yes || echo no)"
    [[ "${name}" == "left-pad" && "${version}" == "1.2.3" ]] || die "validated identity ${name}@${version}"
    [[ "${purl}" == "pkg:npm/left-pad@1.2.3?repository_url=https%3A%2F%2Fexample.test%2Fnpm%2Fvalidated" ]] \
        || die "validated purl ${purl}"
    [[ "${patches}" == "[]" && "${ancestor}" == "1.2.3" ]] || die "validated pedigree patches=${patches} ancestor=${ancestor}"
    [[ "${supplier}" == "Red Hat Lightwell" && -z "${vulns}" && "${same}" == "yes" ]] \
        || die "validated supplier/vex/component copy"
    [[ -n "${comp}" ]] || die "validated missing component"
    pass "validated SBOM has ancestor and empty patches"
else
    die "validated generate-npm-cdx failed"
fi
rm -rf "${work}"

# --- missing repository url ---
work="$(mktemp -d)"
if SBOM_REPOSITORY_URL="" ARTIFACT_ROOT="${work}" BUILT_LIST="${work}/built.txt" \
    SOURCE_ROOT="${work}" CDX_ROOT="${work}/cdx" "${GEN}" >/dev/null 2>&1
then
    die "empty repository url should fail"
else
    pass "empty repository url fails"
fi
rm -rf "${work}"

# --- SPDX mismatch ---
work="$(mktemp -d)"
mkdir -p "${work}/source/packages/left-pad/1.2.3" "${work}/artifact"
jq -n '{name:"left-pad",version:"1.2.3",stream:"validated",upstream:{version:"1.2.3"},source:{url:"https://example.test/x.git",ref:"1.2.3"}}' \
    > "${work}/source/packages/left-pad/1.2.3/manifest.json"
make_tarball "${work}/artifact/left-pad-1.2.3.tgz" left-pad 1.2.3 "pkg:npm/left-pad@9.9.9"
printf '%s\n' "packages/left-pad/1.2.3" > "${work}/built.txt"
if run_case "${work}" >/dev/null 2>&1; then
    die "SPDX mismatch should fail"
else
    pass "SPDX identity mismatch fails"
fi
rm -rf "${work}"

# --- remediated: trailers only, not the branch name or the subject ---
work="$(mktemp -d)"
repo="${work}/upstream"
mkdir -p "${work}/source/packages/left-pad/1.2.4-rhlw.1" "${work}/artifact"
git_tip "${repo}" "1.2.3-rhlw.1-cve-CVE-2020-1111" "$(cat <<'EOF'
fix: backport onto left-pad, subject mentions CVE-2019-0001

Lightwell-Fix: fix=LW-2026-6255, cve=CVE-2024-1234, jira=LTWL-201, status=applied_clean, source=CVE-2024-1234/1.2.3/pipeline-1
Lightwell-Fix: fix=LW-2026-6301, cve=CVE-2024-9999, jira=LTWL-202, status=applied_clean, source=CVE-2024-9999/1.2.3/pipeline-2
EOF
)"
sha="$(git -C "${repo}" rev-parse HEAD)"
jq -n --arg url "${repo}" '{
  name: "left-pad",
  version: "1.2.4-rhlw.1",
  stream: "remediated",
  upstream: {version: "1.2.3"},
  source: {url: $url, ref: "1.2.3-rhlw.1-cve-CVE-2020-1111"}
}' > "${work}/source/packages/left-pad/1.2.4-rhlw.1/manifest.json"
make_tarball "${work}/artifact/left-pad-1.2.4-rhlw.1.tgz" left-pad "1.2.4-rhlw.1" \
    "pkg:npm/left-pad@1.2.4-rhlw.1"
printf '%s\n' "packages/left-pad/1.2.4-rhlw.1" > "${work}/built.txt"
if run_case "${work}"; then
    doc="$(find "${work}/cdx" -name '*.cdx.json')"
    ids="$(jq -r '.metadata.component.pedigree.patches[].resolves[0].id' "${doc}" | LC_ALL=C sort | paste -sd, -)"
    diff="$(jq -r '.metadata.component.pedigree.patches[0].diff.url' "${doc}")"
    ancestor="$(jq -r '.metadata.component.pedigree.ancestors[0].version' "${doc}")"
    notes="$(jq -r '.metadata.component.pedigree.notes' "${doc}")"
    [[ "${ids}" == "CVE-2024-1234,CVE-2024-9999" ]] || die "remediated patch ids ${ids}"
    [[ "${diff}" == "${repo}/commit/${sha}" ]] || die "remediated diff url ${diff}"
    [[ "${ancestor}" == "1.2.3" ]] || die "remediated ancestor ${ancestor}"
    [[ "${notes}" == *"backported security fixes"* ]] || die "remediated notes ${notes}"
    pass "remediated SBOM patches come from Lightwell-Fix trailers"
else
    die "remediated generate-npm-cdx failed"
fi
rm -rf "${work}"

# --- remediated without a CVE trailer ---
work="$(mktemp -d)"
repo="${work}/upstream"
mkdir -p "${work}/source/packages/left-pad/1.2.4-rhlw.1" "${work}/artifact"
git_tip "${repo}" "fix-branch" "$(cat <<'EOF'
fix: subject mentions CVE-2024-1234 but has no trailer
EOF
)"
jq -n --arg url "${repo}" '{
  name: "left-pad", version: "1.2.4-rhlw.1", stream: "remediated",
  upstream: {version: "1.2.3"},
  source: {url: $url, ref: "fix-branch"}
}' > "${work}/source/packages/left-pad/1.2.4-rhlw.1/manifest.json"
make_tarball "${work}/artifact/left-pad.tgz" left-pad "1.2.4-rhlw.1" "pkg:npm/left-pad@1.2.4-rhlw.1"
printf '%s\n' "packages/left-pad/1.2.4-rhlw.1" > "${work}/built.txt"
if run_case "${work}" >/dev/null 2>&1; then
    die "remediated without Lightwell-Fix CVE should fail"
else
    pass "remediated without a CVE trailer fails"
fi
rm -rf "${work}"

# --- novel LW id: required, and it does not become a backport patch ---
work="$(mktemp -d)"
repo="${work}/upstream"
mkdir -p "${work}/source/packages/left-pad/1.2.4-rhlw.1.n.1" "${work}/artifact"
git_tip "${repo}" "novel" "$(cat <<'EOF'
fix: novel

Lightwell-Fix: fix=LW-2026-7001, cve=none, jira=LTWL-9, status=applied_clean, source=novel
EOF
)"
jq -n --arg url "${repo}" '{
  name: "left-pad", version: "1.2.4-rhlw.1.n.1", stream: "novel",
  upstream: {version: "1.2.3"},
  source: {url: $url, ref: "novel"}
}' > "${work}/source/packages/left-pad/1.2.4-rhlw.1.n.1/manifest.json"
make_tarball "${work}/artifact/left-pad.tgz" left-pad "1.2.4-rhlw.1.n.1" \
    "pkg:npm/left-pad@1.2.4-rhlw.1.n.1"
printf '%s\n' "packages/left-pad/1.2.4-rhlw.1.n.1" > "${work}/built.txt"
if run_case "${work}"; then
    doc="$(find "${work}/cdx" -name '*.cdx.json')"
    patches="$(jq -c '.metadata.component.pedigree.patches' "${doc}")"
    notes="$(jq -r '.metadata.component.pedigree.notes' "${doc}")"
    [[ "${patches}" == "[]" ]] || die "novel LW patches ${patches}"
    [[ "${notes}" == *"novel fix"* ]] || die "novel notes ${notes}"
    pass "novel LW trailer keeps patches empty"
else
    die "novel generate-npm-cdx failed"
fi
rm -rf "${work}"

# --- scoped purl base matches the SPDX helper ---
work="$(mktemp -d)"
mkdir -p "${work}/source/packages/@scope/pkg/1.0.0" "${work}/artifact"
jq -n '{name:"@scope/pkg",version:"1.0.0",stream:"validated",upstream:{version:"1.0.0"},source:{url:"https://example.test/x.git",ref:"1.0.0"}}' \
    > "${work}/source/packages/@scope/pkg/1.0.0/manifest.json"
make_tarball "${work}/artifact/pkg.tgz" "@scope/pkg" "1.0.0" "pkg:npm/%40scope/pkg@1.0.0"
printf '%s\n' "packages/@scope/pkg/1.0.0" > "${work}/built.txt"
if run_case "${work}"; then
    purl="$(jq -r '.metadata.component.purl' "${work}/cdx/"*.cdx.json)"
    [[ "${purl}" == "pkg:npm/%40scope/pkg@1.0.0?repository_url=https%3A%2F%2Fexample.test%2Fnpm%2Fvalidated" ]] \
        || die "scoped purl ${purl}"
    pass "scoped package purl matches SPDX base"
else
    die "scoped generate-npm-cdx failed"
fi
rm -rf "${work}"

if [[ "${fail}" -ne 0 ]]; then
    echo "generate-npm-cdx tests failed" >&2
    exit 1
fi
echo "PASS: generate-npm-cdx"

#!/usr/bin/env bash
# Install a second Node.js major beside the default AppStream nodejs:20.
# UBI modules cannot both own /usr/bin/node; this uses dnf --installroot and
# thin wrappers under /opt/nodejs/<major>/bin so recipes can PATH-select.
#
# Usage: install-nodejs-side.sh <major>
# Example: install-nodejs-side.sh 22
#
# Optional env:
#   NPM_BUILDER_RELEASEVER — dnf --releasever (default: major from /etc/os-release VERSION_ID)
set -euo pipefail

MAJOR="${1:?usage: install-nodejs-side.sh <major>}"
if [[ ! "${MAJOR}" =~ ^[0-9]+$ ]]; then
    echo "error: major must be numeric (got: ${MAJOR})" >&2
    exit 2
fi

INSTALLROOT="/var/lib/npm-builder/nodejs-${MAJOR}-root"
BINDIR="/opt/nodejs/${MAJOR}/bin"
MODULE_STREAM="nodejs:${MAJOR}"

if [[ -n "${NPM_BUILDER_RELEASEVER:-}" ]]; then
    RELEASEVER="${NPM_BUILDER_RELEASEVER}"
else
    # shellcheck source=/dev/null
    source /etc/os-release
    RELEASEVER="${VERSION_ID%%.*}"
fi
if [[ -z "${RELEASEVER}" || ! "${RELEASEVER}" =~ ^[0-9]+$ ]]; then
    echo "error: could not determine dnf releasever (set NPM_BUILDER_RELEASEVER)" >&2
    exit 2
fi

echo "Installing ${MODULE_STREAM} into ${INSTALLROOT} (wrappers → ${BINDIR}, releasever=${RELEASEVER})"

rm -rf "${INSTALLROOT}"
mkdir -p "${INSTALLROOT}"/{etc,var/lib/rpm,var/cache/dnf}
# Repos + PKI so installroot can resolve AppStream modules.
cp -a /etc/yum.repos.d "${INSTALLROOT}/etc/"
if [[ -d /etc/pki ]]; then
    cp -a /etc/pki "${INSTALLROOT}/etc/"
fi

dnf_ir=(dnf -y -q --installroot="${INSTALLROOT}" --releasever="${RELEASEVER}" --setopt=install_weak_deps=0)

if ! "${dnf_ir[@]}" module info "${MODULE_STREAM}" >/dev/null 2>&1; then
    echo "error: AppStream module stream '${MODULE_STREAM}' not available for releasever=${RELEASEVER}" >&2
    echo "Available nodejs streams (if any):" >&2
    "${dnf_ir[@]}" module list nodejs 2>&1 | head -n 40 >&2 || true
    exit 1
fi

"${dnf_ir[@]}" module enable "${MODULE_STREAM}"
"${dnf_ir[@]}" install nodejs npm

NODE_BIN="$(readlink -f "${INSTALLROOT}/usr/bin/node" 2>/dev/null || true)"
if [[ -z "${NODE_BIN}" || ! -x "${NODE_BIN}" ]]; then
    # Prefer versioned binary when present (e.g. node-22).
    if [[ -x "${INSTALLROOT}/usr/bin/node-${MAJOR}" ]]; then
        NODE_BIN="${INSTALLROOT}/usr/bin/node-${MAJOR}"
    else
        echo "error: node binary not found under ${INSTALLROOT}/usr/bin" >&2
        ls -la "${INSTALLROOT}/usr/bin" >&2 || true
        exit 1
    fi
fi

LIBDIR="${INSTALLROOT}/usr/lib64"
NPM_CLI="${INSTALLROOT}/usr/lib/node_modules/npm/bin/npm-cli.js"
NPX_CLI="${INSTALLROOT}/usr/lib/node_modules/npm/bin/npx-cli.js"
[[ -f "${NPM_CLI}" ]] || {
    echo "error: npm-cli.js missing at ${NPM_CLI}" >&2
    exit 1
}

mkdir -p "${BINDIR}"

# Wrappers keep LD_LIBRARY_PATH pointed at the installroot libs (libnode.so.*).
# npm/npx must be invoked via this node — RPM shebangs reference /usr/bin/node-N.
cat >"${BINDIR}/node" <<EOF
#!/bin/bash
export LD_LIBRARY_PATH="${LIBDIR}:\${LD_LIBRARY_PATH:-}"
exec "${NODE_BIN}" "\$@"
EOF

cat >"${BINDIR}/npm" <<EOF
#!/bin/bash
export LD_LIBRARY_PATH="${LIBDIR}:\${LD_LIBRARY_PATH:-}"
export PATH="${BINDIR}:\${PATH}"
exec "${BINDIR}/node" "${NPM_CLI}" "\$@"
EOF

if [[ -f "${NPX_CLI}" ]]; then
    cat >"${BINDIR}/npx" <<EOF
#!/bin/bash
export LD_LIBRARY_PATH="${LIBDIR}:\${LD_LIBRARY_PATH:-}"
export PATH="${BINDIR}:\${PATH}"
exec "${BINDIR}/node" "${NPX_CLI}" "\$@"
EOF
    chmod +x "${BINDIR}/npx"
fi

chmod +x "${BINDIR}/node" "${BINDIR}/npm"

echo -n "side Node ${MAJOR}: "
"${BINDIR}/node" -v
echo -n "side npm: "
"${BINDIR}/npm" -v
echo -n "default Node remains: "
/usr/bin/node -v

echo "Installed Node ${MAJOR} side-by-side at ${BINDIR}"

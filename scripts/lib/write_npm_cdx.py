#!/usr/bin/env python3
"""Write one CycloneDX SBOM for a packed npm package.

Identity comes from the caller (the SPDX purl base and the packed name/version).
This module only adds the repository_url qualifier and the pedigree. Validated
builds pass no vulnerability ids. Remediated builds must name at least one CVE.
Novel builds must name at least one CVE or LW id; only CVE ids become patches.

No VEX block is written. Python 3.6 compatible (UBI8 python3).
"""

from __future__ import print_function

import json
import os
import sys
import uuid
import urllib.parse
from datetime import datetime, timezone

_STREAM_NOTES = {
    "validated": "Lightwell validated build of {name} {upstream}. Build {version}.",
    "remediated": (
        "Lightwell remediation: backported security fixes to {name} {upstream}. Build {version}."
    ),
    "novel": "Lightwell novel fix: security fixes to {name} {upstream}. Build {version}.",
}


def _env(name):
    value = os.environ.get(name, "")
    if not value:
        raise SystemExit("write_npm_cdx: missing {0}".format(name))
    return value


def _vuln_ids():
    raw = os.environ.get("CDX_VULN_IDS", "")
    ids = []
    seen = set()
    for item in raw.splitlines():
        item = item.strip()
        if not item or item in seen:
            continue
        seen.add(item)
        ids.append(item)
    return ids


def _patches(ids, diff_url):
    patches = []
    for vuln_id in ids:
        if not vuln_id.startswith("CVE-"):
            continue
        if not diff_url:
            raise SystemExit("write_npm_cdx: CVE patch missing diff url for {0}".format(vuln_id))
        patches.append(
            {
                "type": "backport",
                "diff": {"url": diff_url},
                "resolves": [
                    {
                        "type": "security",
                        "id": vuln_id,
                        "source": {
                            "name": "NVD",
                            "url": "https://nvd.nist.gov/vuln/detail/{0}".format(vuln_id),
                        },
                    }
                ],
            }
        )
    return patches


def _check_stream(stream, ids):
    cve_ids = [item for item in ids if item.startswith("CVE-")]
    if stream == "validated":
        return
    if stream == "remediated" and not cve_ids:
        raise SystemExit("write_npm_cdx: remediated SBOM requires at least one CVE id")
    if stream == "novel" and not ids:
        raise SystemExit("write_npm_cdx: novel SBOM requires a Lightwell-Fix id")
    if stream not in _STREAM_NOTES:
        raise SystemExit("write_npm_cdx: unsupported stream {0}".format(stream))


def build_document():
    """Return the CycloneDX document for the current environment."""
    name = _env("CDX_NAME")
    version = _env("CDX_VERSION")
    upstream = _env("CDX_UPSTREAM_VERSION")
    base_purl = _env("CDX_BASE_PURL")
    ancestor_purl = _env("CDX_ANCESTOR_PURL")
    repository_url = _env("CDX_REPOSITORY_URL")
    stream = _env("CDX_STREAM")
    diff_url = os.environ.get("CDX_DIFF_URL", "")
    if "?" in base_purl or "?" in ancestor_purl:
        raise SystemExit("write_npm_cdx: purl base must not carry qualifiers")
    if not repository_url.startswith("https://"):
        raise SystemExit("write_npm_cdx: repository_url must be an https URL")
    ids = _vuln_ids()
    _check_stream(stream, ids)
    if stream == "validated":
        ids = []
        diff_url = ""
    patches = _patches(ids, diff_url)
    qualified = "{0}?repository_url={1}".format(
        base_purl,
        urllib.parse.quote(repository_url, safe=""),
    )
    notes = _STREAM_NOTES[stream].format(name=name, upstream=upstream, version=version)
    ancestor = {
        "type": "library",
        "bom-ref": ancestor_purl,
        "name": name,
        "version": upstream,
        "purl": ancestor_purl,
    }
    component = {
        "type": "library",
        "bom-ref": base_purl,
        "name": name,
        "version": version,
        "purl": qualified,
        "pedigree": {
            "ancestors": [ancestor],
            "patches": patches,
            "notes": notes,
        },
    }
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": "urn:uuid:{0}".format(uuid.uuid4()),
        "version": 1,
        "metadata": {
            "timestamp": timestamp,
            "supplier": {"name": "Red Hat Lightwell"},
            "component": component,
        },
        "components": [dict(component)],
    }


def main(argv):
    """Write the document to the path in argv[1]."""
    if len(argv) != 2:
        raise SystemExit("usage: write_npm_cdx.py <output>")
    document = build_document()
    with open(argv[1], "w") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

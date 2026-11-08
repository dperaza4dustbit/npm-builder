# Shared SPDX npm identity predicate for generate-npm-sbom + verify-npm-sbom.
# Expects --arg name, --arg version, --arg purl (purl-spec %40 for scoped names).
(.spdxVersion | type == "string" and startswith("SPDX-2"))
and ((.packages // []) | length) > 0
and any(.packages[]?;
  (.name == $name and .versionInfo == $version)
  or any(
    (.externalRefs // [])[]?;
    .referenceType == "purl" and .referenceLocator == $purl
  ))

# t_provenance

Generate Reproducibility & Audit Provenance Bundle

Collects local project metadata (`tproject.toml`), locked Nix flake inputs (`flake.lock`), the latest `_pipeline/build_log_*.json` with `foreign_meta` sidecars, and `intent { ... }` blocks into an offline, deterministic provenance manifest. Supports RO-Crate 1.1 JSON-LD (`"ro-crate"`), CycloneDX 1.5 SBOM (`"sbom"`), and T-native JSON (`"json"`).

## Parameters

- **format** (`String`): = "ro-crate" Output format: "ro-crate", "sbom", or "json".

- **output** (`String`): = NA Optional file path to write the manifest to.

- **dir** (`String`): = "." Optional project root directory.

- **file** (`String`): = NA Optional `.t` file to extract `intent` blocks from.

- **include_meta** (`Bool`): = true Include `foreign_meta` sidecars in the manifest.


## Returns

The formatted JSON provenance manifest.

## Examples

```t
t_provenance()
t_provenance(format = "sbom", output = "sbom.cdx.json")
t_provenance(format = "ro-crate", output = "ro-crate-metadata.json", include_meta = false)
```

## See Also

[pipeline_metrics](pipeline_metrics.html), [pipeline_overview](pipeline_overview.html), [pipeline_report](pipeline_report.html)


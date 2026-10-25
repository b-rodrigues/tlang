# Vendored PMML jars

`flake.nix` copies the two jars in this directory into the `t-lang` output
(`share/java/`). Pipeline node builds, generated project shells, and the `t`
wrapper read them from there. Nothing downloads or builds these jars, so a
deleted or retagged upstream release cannot break a build.

| File | Tool | Version | Upstream release asset |
|------|------|---------|------------------------|
| `jpmml-statsmodels.jar` | `jpmml-statsmodels` | 1.3.13 | `https://github.com/jpmml/jpmml-statsmodels/releases/download/1.3.13/pmml-statsmodels-example-executable-1.3.13.jar` |
| `jpmml-evaluator.jar` | `jpmml-evaluator` | 1.7.7 | `https://github.com/jpmml/jpmml-evaluator/releases/download/1.7.7/pmml-evaluator-example-executable-1.7.7.jar` |

Both files are the published executable jars, byte for byte
(sha256 `bf0c2a1d…cdb6` and `3cf48082…1f0e`). `scripts/check_vendored_jars.sh`
verifies the hashes, that each file is a valid archive, and that `flake.nix`
does not fetch them again. CI runs that script.

Both jars are AGPL-3.0-only. Their licence and copyright belong to the JPMML
project; they are redistributed here as unmodified upstream artifacts.

To upgrade a jar:

1. Download the new release asset.
2. Replace the file here and set the new `version` in `flake.nix`.
3. Update the expected hash in `scripts/check_vendored_jars.sh`.
4. Run `nix build .#t-lang` and score a PMML model with `predict()`.

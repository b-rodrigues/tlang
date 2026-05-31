# t_make

Build and Run a Pipeline File

Reads, parses, evaluates, and builds a T pipeline script path. This is a high-level orchestrator often used from the interactive T REPL to trigger full builds.

## Signatures

* **Named Signature**:
  ```t
  t_make(filename = "src/pipeline.t", nix_options = [...], verbose = 1, failfast = false)
  ```
* **Positional Signature**:
  ```t
  t_make(filename, nix_options, verbose, failfast)
  ```

## Parameters

* **filename** (`String`): (Optional) The pipeline build script path. Must be `"src/pipeline.t"`. Defaults to `"src/pipeline.t"`.
* **nix_options** (`Dict`): (Optional) A dictionary of Nix orchestration options:
  - `max_jobs` (`Int`): The maximum parallel build jobs. Maps to `--max-jobs`.
  - `max_cores` (`Int`): The maximum number of cores per job. Maps to `--cores`.
  - `cache` (`String`): Cachix cache name to use as a binary substituter.
  - `targets` (`String`|`List[String]`): Specific node names to build. Maps to `-A`.
  - `force` (`Bool`): Force rebuilds even if cached. Maps to `--check`.
  - `dry_run` (`Bool`): Plan and show what would be built without executing. Maps to `--dry-run`.
  - `builders` (`String`): Nix remote builders configuration.
  - `keep_env` (`String`|`List[String]`): Environment variables to pass through to the sandbox.
  - `sandbox` (`Bool`|`String`): Nix isolation sandbox policy (`"relaxed"`, `"strict"`, `"none"`).
* **verbose** (`Int`): (Optional) The Nix build verbosity level. `0` is quiet, values `> 0` enable build output and failure diagnostics.
* **failfast** (`Bool`): (Optional) If `true`, stops immediately on evaluation/build errors. Defaults to `false`.

## Examples

Using named parameters:
```t
t_make(nix_options = [max_jobs: 4, dry_run: true])
```

Using the positional signature:
```t
t_make("src/pipeline.t", [max_jobs: 8], 2, true)
```

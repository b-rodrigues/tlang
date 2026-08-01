# unknown

Print Failed Node Logs

Prints stderr log sections for each failed node by resolving its derivation path through `nix log`.

## Parameters

- **drv_paths** (`Hashtbl`): Captured derivation paths keyed by node name.

- **errored** (`List[String]`): Node names that failed during the build.



# t_gc

Run System Garbage Collection

Runs the global Nix garbage collector (nix-store --gc) to delete any unreferenced, stale, or unused paths from the local Nix store.

## Returns

A status message summarizing the deleted store paths.

## Examples

```t
t_gc()
```


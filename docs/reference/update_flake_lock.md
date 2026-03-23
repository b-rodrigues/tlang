# update_flake_lock

Update Dependencies

Regenerates the `flake.nix` file from the current TOML configuration and runs `nix flake update` to lock dependencies to their latest versions within the specified tags.

## Returns

Ok(()) or an error message.


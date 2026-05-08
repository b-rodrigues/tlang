# Guidelines for Agents

- **No `flake.nix` or `flake.lock`**: Do not commit `flake.nix` or `flake.lock` files.
- **No `_pipeline` folder**: Do not commit the `_pipeline` folder.
- **Gitignore**: Do not edit the `.gitignore` unless explicitly instructed (note: a general ignore for these files has been added to `t_demos/.gitignore`).
- **Adding Demos**: When adding new demos, always add the corresponding action to run it by copying one of the existing ones and changing only what is necessary.
- **TProject Configuration**: In the `tproject.toml` files of the demos, never add a `nixpkgs` date.

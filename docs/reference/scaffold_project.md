# scaffold_project

Scaffold a new T project

Generates the directory structure and boilerplate files for a new T data analysis project. Creates a `tproject.toml`, `flake.nix`, and sets up `data/`, `outputs/`, and `src/` directories, including default `r-dependencies`, `py-dependencies`, and `julia-dependencies` sections in `tproject.toml`.

## Parameters

- **opts** (`ScaffoldOptions`): The options provided via CLI.


## Returns

Ok(()) or an error message.

(* src/package_manager/package_types.ml *)
(* Types for T package and project metadata *)

(** A dependency on another T package *)
type dependency = {
  dep_name : string;
  git_url : string;
  tag : string;
}

(** Package metadata parsed from DESCRIPTION.toml *)
type package_config = {
  name : string;
  version : string;
  description : string;
  authors : string list;
  license : string;
  homepage : string;
  repository : string;
  dependencies : dependency list;
  min_t_version : string;
}

(** Project metadata parsed from tproject.toml *)
type project_config = {
  proj_name : string;
  proj_description : string;
  proj_dependencies : dependency list;
  proj_min_t_version : string;
}

(** CLI options for scaffolding commands *)
type scaffold_options = {
  target_name : string;
  author : string;
  license : string;
  no_git : bool;
  force : bool;
}

(** Default scaffold options *)
let default_options name = {
  target_name = name;
  author = "Your Name <email@example.com>";
  license = "EUPL-1.2";
  no_git = false;
  force = false;
}

(** Default package config *)
let default_package_config name = {
  name;
  version = "0.1.0";
  description = "A T package";
  authors = ["Your Name <email@example.com>"];
  license = "EUPL-1.2";
  homepage = "";
  repository = "";
  dependencies = [];
  min_t_version = "0.5.0";
}

(** Default project config *)
let default_project_config name = {
  proj_name = name;
  proj_description = "A T data analysis project";
  proj_dependencies = [];
  proj_min_t_version = "0.5.0";
}

(** Validate a package/project name: lowercase, alphanumeric, hyphens only *)
let validate_name name =
  let len = String.length name in
  if len = 0 then Error "Name cannot be empty"
  else if len > 64 then Error "Name cannot exceed 64 characters"
  else
    let valid = ref true in
    for i = 0 to len - 1 do
      let c = name.[i] in
      if not (c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c = '-' || c = '_') then
        valid := false
    done;
    if name.[0] = '-' || name.[0] = '_' then
      Error "Name must start with a letter or digit"
    else if not !valid then
      Error "Name must contain only lowercase letters, digits, hyphens, or underscores"
    else
      Ok name

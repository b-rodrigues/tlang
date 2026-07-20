(* src/packages/pipeline/t_fix.ml *)
(* REPL-callable version of `t fix` — mechanically applies suggested fixes
   from check diagnostics (column renames, node argument additions). *)

open Ast

(*
--# Mechanically Apply Suggested Fixes
--#
--# Runs `t check --schema` on a file, extracts diagnostics with suggested_fix,
--# and applies them (e.g., renaming columns, adding missing node arguments).
--# Uses bottom-up line order to avoid line-number drift.
--#
--# @name t_fix
--# @param file :: String The path to the .t file to fix.
--# @param dry_run :: Bool = false Show what would be fixed without modifying the file.
--# @return :: String Summary of fixes applied (or would be applied).
--# @family pipeline
--# @export
*)

let format_fix_result (result : Fix.fix_result) =
  if result.Fix.applied = 0 && result.Fix.would_apply = 0 && result.Fix.skipped = 0 then
    "No fixes to apply.\n"
  else
    let buf = Buffer.create 256 in
    if result.Fix.would_apply > 0 then
      Buffer.add_string buf (Printf.sprintf "Would apply %d fix(es), skipped %d.\n" result.Fix.would_apply result.Fix.skipped)
    else
      Buffer.add_string buf (Printf.sprintf "Applied %d fix(es), skipped %d.\n" result.Fix.applied result.Fix.skipped);
    List.iter (fun (d : Diagnostics.diagnostic) ->
      let fix_desc = match d.diag_suggested_fix with
        | Diagnostics.Rename_column { old_name; new_name; _ } ->
            Printf.sprintf "  Rename column '%s' to '%s'" old_name new_name
        | Diagnostics.Add_node_arg _ -> "  Add node argument"
        | Diagnostics.Suggest_identifier { name; suggestion; _ } ->
            Printf.sprintf "  Did you mean '%s' instead of '%s'?" suggestion name
        | Diagnostics.Run_command { command; _ } ->
            Printf.sprintf "  Run: %s" command
        | Diagnostics.NoFix -> "  No fix"
      in
      Buffer.add_string buf (Printf.sprintf "%s:%d: %s\n"
        (Option.value ~default:"<unknown>" d.diag_file)
        (Option.value ~default:0 d.diag_line)
        fix_desc)
    ) result.Fix.diagnostics;
    Buffer.contents buf

let register env =
  Env.add "t_fix"
    (make_builtin_named ~name:"t_fix" ~variadic:true 1 (fun named_args _env ->
      let named_keys = List.filter_map (fun (k, _) -> k) named_args in
      let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
      match List.find_opt (fun k -> not (List.mem k ["file"; "dry_run"])) named_keys with
      | Some k ->
          Error.type_error (Printf.sprintf "t_fix: unknown argument '%s'" k)
      | None when positional_count > 1 ->
          Error.make_error ArityError
            (Printf.sprintf "Function `t_fix` accepts at most 1 positional argument but received %d." positional_count)
      | None ->
        match Pipeline_args.get_arg "file" 1 (VNA NAGeneric) named_args with
        | (_, VString file) ->
            let (_, dry_run_val) = Pipeline_args.get_arg "dry_run" 2 (VBool false) named_args in

            let dry_run_result =
              match dry_run_val with
              | VBool b -> Ok b
              | _ -> Error (Error.type_error "Function `t_fix` expects `dry_run` to be a Bool.")
            in

            let (let*) x f = match x with Ok v -> f v | Error e -> e in
            let* do_dry_run = dry_run_result in

            let check_result = Check_utils.run_check ~schema:true Typecheck.Strict file Env.empty in
            let diags = Diagnostics.check_result_entries check_result in
            let fixes = diags
              |> List.filter_map (fun (d : Diagnostics.diagnostic) ->
                match d.diag_suggested_fix with Diagnostics.NoFix -> None | _ -> Some d)
              |> Fix.sort_fixes_by_descending_line
            in
            let result = Fix.apply_fixes ~dry_run:do_dry_run ~default_file:file fixes in
            VString (format_fix_result result)
        | (_, other) ->
            Error.type_error
              (Printf.sprintf "Function `t_fix` expects a file path (String) as first argument, but got %s."
                 (Utils.type_name other))
    )) env

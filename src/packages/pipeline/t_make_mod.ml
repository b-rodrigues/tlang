open Ast

(* --- Helpers moved from Rep/Eval to be self-contained or use Error module --- *)

let source_location ?file pos : Ast.source_location =
  {
    file;
    line = pos.Lexing.pos_lnum;
    column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1);
  }

let make_located_error ?file code message pos =
  VError {
    code;
    message;
    context = [];
    location = Some (source_location ?file pos);
    na_count = 0;
  }

let interrupt_error () =
  VError {
    code = RuntimeError;
    message = "Interrupted.";
    context = [];
    location = None;
    na_count = 0;
  }

(*
--# Build and run a pipeline file
--#
--# Reads, parses, evaluates and builds a T pipeline file. This is a 
--# high-level build orchestrator often used from the CLI (repl) to
--# trigger a full project build. It supports named and positional 
--# arguments for common Nix build controls.
--#
--# @name t_make
--# @param filename :: String The pipeline file path. Must be `src/pipeline.t`.
--# @param max_jobs :: Int The maximum number of jobs for Nix to run in parallel.
--# @param max_cores :: Int The maximum number of cores per job for Nix to use.
--# @param verbose :: Int The Nix build verbosity level. `0` is quiet; values > 0 enable internal node failure logs.
--# @return :: Null
--# @family pipeline
--# @export
*)
let register env =
  Env.add "t_make"
    (VBuiltin { b_name = Some "t_make"; b_arity = 0; b_variadic = true;
      b_func = (fun named_args env_ref ->
        let filename = ref "src/pipeline.t" in
        let nix_args = ref [] in
        let verbose = ref !Builder_internal.default_nix_build_verbose in
        let arg_error_opt = ref None in
        
        let named_only, positional_only =
          List.partition (fun (k_opt, _) -> k_opt <> None) named_args
        in
        
        List.iter (function
          | (Some "filename", VString s) -> filename := s
          | (Some "filename", _) ->
              arg_error_opt := Some (TypeError, "t_make: 'filename' must be a String")
          | (Some "max_jobs", VInt i) ->
              nix_args := (string_of_int i) :: "--max-jobs" :: !nix_args
          | (Some "max_jobs", _) ->
              arg_error_opt := Some (TypeError, "t_make: 'max_jobs' must be an Int")
          | (Some "max_cores", VInt i) ->
              nix_args := (string_of_int i) :: "--cores" :: !nix_args
          | (Some "max_cores", _) ->
              arg_error_opt := Some (TypeError, "t_make: 'max_cores' must be an Int")
          | (Some "verbose", VInt i) when i >= 0 ->
              verbose := i
          | (Some "verbose", VInt _) ->
              arg_error_opt := Some (ValueError, "t_make: 'verbose' must be a non-negative Int")
          | (Some "verbose", _) ->
              arg_error_opt := Some (TypeError, "t_make: 'verbose' must be an Int")
          | (Some k, _) ->
              arg_error_opt := Some (TypeError, Printf.sprintf "t_make: unknown argument '%s'" k)
          | _ -> ()
        ) named_only;

        let _ = List.fold_left (fun idx (_, v) ->
          (match idx, v with
           | 0, VString s -> filename := s
           | 1, VInt i -> nix_args := (string_of_int i) :: "--max-jobs" :: !nix_args
           | 2, VInt i -> nix_args := (string_of_int i) :: "--cores" :: !nix_args
           | 3, VInt i when i >= 0 -> verbose := i
           | 3, VInt _ -> arg_error_opt := Some (ValueError, "t_make: 'verbose' must be a non-negative Int")
           | n, _ -> arg_error_opt := Some (TypeError, Printf.sprintf "t_make: unexpected argument at position %d" n));
          idx + 1
        ) 0 positional_only in

        match !arg_error_opt with
        | Some (code, msg) ->
            Error.make_error code msg
        | None ->
            (match Pipeline_script.validate_t_make_filename !filename with
             | Error msg ->
                 Error.make_error ValueError msg
             | Ok () ->
                 let prev_nix_build_args = !Builder_internal.nix_build_args in
                 let prev_nix_build_verbose = !Builder_internal.default_nix_build_verbose in
                 Fun.protect
                   ~finally:(fun () ->
                     Builder_internal.nix_build_args := prev_nix_build_args;
                     Builder_internal.default_nix_build_verbose := prev_nix_build_verbose)
                   (fun () ->
                     Builder_internal.nix_build_args := List.rev !nix_args;
                     Builder_internal.default_nix_build_verbose := !verbose;
                     try
                       let content =
                         let ch = open_in !filename in
                         Fun.protect
                           ~finally:(fun () -> close_in_noerr ch)
                           (fun () -> really_input_string ch (in_channel_length ch))
                       in
                       let lexbuf = Lexing.from_string content in
                       (try
                          let program = Parser.program Lexer.token lexbuf in
                          let eval_env = Pipeline_script.reload_env_for_pipeline_entry ~filename:!filename program !env_ref in
                          let (v, new_env) = Eval.eval_program program eval_env in
                          match v with
                          | VError _ -> v
                          | _ ->
                              env_ref := Pipeline_script.remember_pipeline_entry_bindings ~filename:!filename program new_env;
                              Printf.printf "Pipeline %s evaluated successfully.\n" !filename;
                              VNA NAGeneric
                        with
                        | Lexer.SyntaxError msg ->
                            let pos = Lexing.lexeme_start_p lexbuf in
                            make_located_error ~file:!filename SyntaxError ("Syntax error in '" ^ !filename ^ "': " ^ msg) pos
                        | Parser.Error ->
                            let pos = Lexing.lexeme_start_p lexbuf in
                            make_located_error ~file:!filename SyntaxError (Printf.sprintf "Parse error in '%s'" !filename) pos
                        | Sys.Break ->
                            interrupt_error ())
                     with
                     | Sys_error msg ->
                         Error.make_error FileError (Printf.sprintf "t_make failed: %s" msg))))
       })
     env

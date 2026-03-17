(* src/lsp_server.ml *)

open Lsp.Types

module Transport = struct
  let read_message () =
    (* Read all header lines until blank line, then extract Content-Length
       regardless of header order, per LSP/message framing conventions. *)
    let rec read_headers acc =
      let line = input_line stdin in
      if String.trim line = "" then List.rev acc
      else read_headers (line :: acc)
    in
    let rec find_content_length = function
      | [] -> None
      | line :: rest -> (
          match String.index_opt line ':' with
          | None -> find_content_length rest
          | Some idx ->
              let name =
                String.sub line 0 idx |> String.trim |> String.lowercase_ascii
              in
              if name = "content-length" then
                let value =
                  String.sub line (idx + 1) (String.length line - idx - 1)
                  |> String.trim
                in
                (try Some (int_of_string value) with Failure _ -> None)
              else find_content_length rest)
    in
    try
      let headers = read_headers [] in
      match find_content_length headers with
      | None -> None
      | Some len ->
          let body = really_input_string stdin len in
          Some (Yojson.Safe.from_string body)
    with
    | End_of_file | Failure _ | Yojson.Json_error _ -> None

  let write_message (json : Yojson.Safe.t) =
    let body = Yojson.Safe.to_string json in
    Printf.printf "Content-Length: %d\r\n\r\n%s%!" (String.length body) body
end

module Server = struct
  type doc_state = {
    uri : DocumentUri.t;
    text : string;
    mutable scope : Symbol_table.scope;
    mutable diagnostics : Diagnostic.t list;
    mutable definitions : Ast.source_location Analyzer.Definition_map.t;
  }

  type t = {
    documents : (DocumentUri.t, doc_state) Hashtbl.t;
    base_scope : Symbol_table.scope;
  }

  let create () =
    Packages.ensure_docs_loaded ();
    let base_env = Packages.init_env () in
    let base_scope = Symbol_table.create_scope () in
    Symbol_table.register_keywords base_scope;
    Symbol_table.populate_from_env base_scope base_env;
    { documents = Hashtbl.create 10; base_scope }

  let send_diagnostics uri diagnostics =
    let json =
      `Assoc
        [
          ("jsonrpc", `String "2.0");
          ("method", `String "textDocument/publishDiagnostics");
          (
            "params",
            `Assoc
              [
                ("uri", `String (DocumentUri.to_string uri));
                ("diagnostics", `List (List.map Diagnostic.yojson_of_t diagnostics));
              ]
          );
        ]
    in
    Transport.write_message json

  let log_timing label started_at =
    let elapsed_ms = (Unix.gettimeofday () -. started_at) *. 1000.0 in
    Printf.eprintf "[lsp] %s in %.2fms\n%!" label elapsed_ms

  let log_analysis_exception exn =
    let backtrace = Printexc.get_backtrace () in
    if String.length backtrace = 0 then
      Printf.eprintf "[lsp] analysis error: %s\n%!" (Printexc.to_string exn)
    else
      Printf.eprintf "[lsp] analysis error: %s\n%s%!"
        (Printexc.to_string exn) backtrace

  let make_diagnostic ~line ~character ~message =
    Diagnostic.create
      ~range:
        (Range.create
           ~start:(Position.create ~line ~character)
           ~end_:(Position.create ~line ~character))
      ~message:(`String message)
      ~severity:DiagnosticSeverity.Error
      ()

  let diagnostic_at_lexeme lexbuf message =
    let pos = Lexing.lexeme_start_p lexbuf in
    let line = max 0 (pos.Lexing.pos_lnum - 1) in
    let character = max 0 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol) in
    make_diagnostic ~line ~character ~message

  let is_op_char = function
    | '|' | '>' | '?' | '+' | '-' | '*' | '/' | '=' | '!' | '<' | '&' | '%' | '~' | '.' -> true
    | _ -> false

  let extract_word_at line_text character =
    let line_len = String.length line_text in
    if line_len = 0 then None
    else
      let max_idx = line_len - 1 in
      let clamped_character = max 0 (min character max_idx) in
      let c = line_text.[clamped_character] in
      let check = 
        if Lexer.is_ident_char c then Lexer.is_ident_char
        else if is_op_char c then is_op_char
        else (fun _ -> false)
      in
      let rec find_start idx =
        if idx < 0 || not (check line_text.[idx]) then idx + 1
        else find_start (idx - 1)
      in
      let start_idx = find_start clamped_character in
      let rec find_end idx =
        if idx >= line_len || not (check line_text.[idx]) then idx
        else find_end (idx + 1)
      in
      let end_idx = find_end clamped_character in
      if start_idx < end_idx then
        Some (String.sub line_text start_idx (end_idx - start_idx))
      else None

  let col_regex = Str.regexp {|\$\([a-zA-Z_][a-zA-Z0-9_]*\|`[^`]*`\)|}

  let extract_columns text =
    let rec loop acc pos =
      try
        let _ = Str.search_forward col_regex text pos in
        let matched = Str.matched_group 1 text in
        let name = if String.starts_with ~prefix:"`" matched then
                     String.sub matched 1 (String.length matched - 2)
                   else matched in
        loop (Symbol_table.StringSet.add name acc) (Str.match_end ())
      with Not_found -> acc
    in
    loop Symbol_table.StringSet.empty 0 |> Symbol_table.StringSet.elements

  let update_document server uri text ~source ~started_at =
    let scope = Symbol_table.copy_scope server.base_scope in
    
    (* Resiliency: Extract columns from the entire file regardless of syntax validity *)
    List.iter (Symbol_table.add_observed_column scope) (extract_columns text);

    let diagnostics = ref [] in
    let definitions = ref Analyzer.Definition_map.empty in
    let lexbuf = Lexing.from_string text in
    (try
       let program = Parser.program Lexer.token lexbuf in
       let analysis = Analyzer.analyze program scope in
       definitions := analysis.definitions
       with
       | Parser.Error ->
          diagnostics := [ diagnostic_at_lexeme lexbuf "Syntax error" ]
      | Lexer.SyntaxError msg ->
          diagnostics :=
            [ diagnostic_at_lexeme lexbuf (Printf.sprintf "Lexer error: %s" msg) ]
      | exn ->
          log_analysis_exception exn;
          diagnostics :=
            [ diagnostic_at_lexeme lexbuf "Internal analysis error" ]);
    let doc =
      { uri; text; scope; diagnostics = !diagnostics; definitions = !definitions }
    in
    Hashtbl.replace server.documents uri doc;
    send_diagnostics uri !diagnostics;
    log_timing (Printf.sprintf "%s -> publishDiagnostics" source) started_at

  let handle_initialize _params =
    let capabilities = ServerCapabilities.create 
      ~textDocumentSync:(`TextDocumentSyncOptions (TextDocumentSyncOptions.create 
        ~openClose:true 
        ~change:TextDocumentSyncKind.Full
        ()))
      ~completionProvider:(CompletionOptions.create ~triggerCharacters:["$"; "."] ())
      ~hoverProvider:(`Bool true)
      ~definitionProvider:(`Bool true)
      ()
    in
    InitializeResult.create ~capabilities ()

  let handle_completion server (params : CompletionParams.t) =
    let uri = params.textDocument.uri in
    match Hashtbl.find_opt server.documents uri with
    | None -> []
    | Some doc ->
        let line = params.position.line in
        let character = params.position.character in
        let lines = String.split_on_char '\n' doc.text in
        if line < List.length lines then
          let line_text = List.nth lines line in
          let cursor = min character (String.length line_text) in
          let (start_pos, matches) = Completion.complete doc.scope ~buffer:line_text ~cursor in
          List.map (fun m -> 
            let range = Range.create
              ~start:(Position.create ~line ~character:start_pos)
              ~end_:(Position.create ~line ~character:cursor)
            in
            let textEdit = `TextEdit (TextEdit.create ~range ~newText:m) in
            CompletionItem.create ~label:m ~textEdit ()
          ) matches
        else []

  let handle_hover server (params : HoverParams.t) =
    let uri = params.textDocument.uri in
    match Hashtbl.find_opt server.documents uri with
    | None -> None
    | Some doc ->
        let line = params.position.line in
        let character = params.position.character in
        let lines = String.split_on_char '\n' doc.text in
        if line < List.length lines then
          let line_text = List.nth lines line in
          match extract_word_at line_text character with
            | Some name -> (
               match Symbol_table.lookup doc.scope name with
               | Some sym ->
                  let type_str =
                    match sym.typ with
                    | Some ty -> Semantic_type.to_string ty
                    | None -> "Unknown"
                  in
                  let content =
                    match Tdoc_registry.lookup name with
                    | Some entry ->
                        let signature =
                          let args = List.map (fun (p : Tdoc_types.param_doc) ->
                             p.name ^ ": " ^ (Option.value ~default:"any" p.type_info |> String.lowercase_ascii)
                          ) entry.params in
                          let ret = match entry.return_value with
                            | Some r -> Option.value ~default:"any" r.type_info |> String.lowercase_ascii
                            | None -> "any"
                          in
                          Printf.sprintf "Function(%s -> %s)" (String.concat ", " args) ret
                        in
                        Printf.sprintf "**%s**: `%s`\n\n%s" name signature entry.description_brief
                    | None -> 
                       let diag = if Tdoc_registry.get_all () = [] then "\n\n*(Documentation not loaded)*" else "" in
                       Printf.sprintf "**%s**: `%s`%s" sym.name type_str diag
                  in
                  let content = content ^ "\n\n*(LSP v0.5.3)*" in
                  let markup = MarkupContent.create ~kind:MarkupKind.Markdown ~value:content in
                  Some (Hover.create ~contents:(`MarkupContent markup) ())
               | None -> (
                  (* Special constructs not in symbol table *)
                  match name with
                  | "|>" ->
                      let content = "**|>**: `x |> f(...) -> f(x, ...)`\n\nPipe operator. Passes the value on the left as the first argument to the function on the right.\n\n*(LSP v0.5.3)*" in
                      let markup = MarkupContent.create ~kind:MarkupKind.Markdown ~value:content in
                      Some (Hover.create ~contents:(`MarkupContent markup) ())
                  | "?|>" ->
                      let content = "**?|>**: `x ?|> f(...) -> f(x, ...)`\n\nSafe pipe operator. Only executes the function if `x` is not `null` or `NA`. Otherwise returns `null`/`NA`.\n\n*(LSP v0.5.3)*" in
                      let markup = MarkupContent.create ~kind:MarkupKind.Markdown ~value:content in
                      Some (Hover.create ~contents:(`MarkupContent markup) ())
                  | _ -> None
               ))
          | None -> None
        else None

  let handle_definition server (params : DefinitionParams.t) =
    let uri = params.textDocument.uri in
    match Hashtbl.find_opt server.documents uri with
    | None -> None
    | Some doc ->
        let line = params.position.line in
        let character = params.position.character in
        let lines = String.split_on_char '\n' doc.text in
        if line < List.length lines then
          let line_text = List.nth lines line in
          match extract_word_at line_text character with
           | Some name -> (
              match Analyzer.Definition_map.find_opt name doc.definitions with
              | Some loc ->
                  let def_line = max 0 (loc.Ast.line - 1) in
                  let def_character = max 0 (loc.Ast.column - 1) in
                  let range =
                    Range.create
                      ~start:(Position.create ~line:def_line ~character:def_character)
                      ~end_:
                        (Position.create ~line:def_line
                           ~character:(def_character + String.length name))
                  in
                  Some (`Location (Location.create ~uri ~range))
              | None -> None)
           | None -> None
        else None

  let dispatch server (packet : Jsonrpc.Packet.t) =
    let params_to_yojson = function
      | None -> `Null
      | Some s -> Jsonrpc.Structured.yojson_of_t s
    in
    match packet with
    | Notification notif ->
        (match notif.method_ with
        | "textDocument/didOpen" ->
            let params = DidOpenTextDocumentParams.t_of_yojson (params_to_yojson notif.params) in
            let started_at = Unix.gettimeofday () in
            update_document server params.textDocument.uri params.textDocument.text
              ~source:"didOpen" ~started_at
        | "textDocument/didChange" ->
            let params = DidChangeTextDocumentParams.t_of_yojson (params_to_yojson notif.params) in
            let started_at = Unix.gettimeofday () in
            (match params.contentChanges with
            | [change] ->
                update_document server params.textDocument.uri change.text
                  ~source:"didChange" ~started_at
            | _ -> ())
        | "textDocument/didClose" ->
            let params = DidCloseTextDocumentParams.t_of_yojson (params_to_yojson notif.params) in
            Hashtbl.remove server.documents params.textDocument.uri
        | _ -> ())
    | Request req ->
        (match req.method_ with
        | "initialize" ->
            let result = handle_initialize () in
            Transport.write_message (Jsonrpc.Response.ok req.id (InitializeResult.yojson_of_t result) |> Jsonrpc.Response.yojson_of_t)
        | "shutdown" ->
            Transport.write_message (Jsonrpc.Response.ok req.id `Null |> Jsonrpc.Response.yojson_of_t)
        | "textDocument/completion" ->
            let started_at = Unix.gettimeofday () in
            let params = CompletionParams.t_of_yojson (params_to_yojson req.params) in
            let items = handle_completion server params in
            let result = `List (List.map (fun i -> CompletionItem.yojson_of_t i) items) in
            Transport.write_message (Jsonrpc.Response.ok req.id result |> Jsonrpc.Response.yojson_of_t);
            log_timing "completion request -> response" started_at
        | "textDocument/hover" ->
            let params = HoverParams.t_of_yojson (params_to_yojson req.params) in
            let result =
              match handle_hover server params with
              | Some h -> Hover.yojson_of_t h
              | None -> `Null
            in
            Transport.write_message (Jsonrpc.Response.ok req.id result |> Jsonrpc.Response.yojson_of_t)
        | "textDocument/definition" ->
            let params = DefinitionParams.t_of_yojson (params_to_yojson req.params) in
            let result =
              match handle_definition server params with
              | Some (`Location l) -> Location.yojson_of_t l
              | Some _ -> `Null
              | None -> `Null
            in
            Transport.write_message (Jsonrpc.Response.ok req.id result |> Jsonrpc.Response.yojson_of_t)
        | _ ->
            let err = Jsonrpc.Response.Error.make ~code:MethodNotFound ~message:"Unknown method" () in
            Transport.write_message (Jsonrpc.Response.error req.id err |> Jsonrpc.Response.yojson_of_t))
    | Response _ -> ()
    | Batch_call _ | Batch_response _ -> ()

  let run server =
    let rec loop () =
      match Transport.read_message () with
      | Some json ->
          let packet = Jsonrpc.Packet.t_of_yojson json in
          (match packet with
           | Notification { method_ = "exit"; _ } -> ()
           | _ -> 
               dispatch server packet;
               loop ())
      | None -> ()
    in
    loop ()
end

let () =
  Printexc.record_backtrace true;
  let server = Server.create () in
  Server.run server

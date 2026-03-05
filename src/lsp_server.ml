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
  }

  type t = {
    documents : (DocumentUri.t, doc_state) Hashtbl.t;
    base_env : Ast.value Ast.Env.t;
  }

  let create () = {
    documents = Hashtbl.create 10;
    base_env = Packages.init_env ();
  }

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

  let update_document server uri text =
    let scope = Symbol_table.create_scope () in
    Symbol_table.register_keywords scope;
    Symbol_table.populate_from_env scope server.base_env;
    let diagnostics = ref [] in
    (try
       let lexbuf = Lexing.from_string text in
       let program = Parser.program Lexer.token lexbuf in
       Analyzer.analyze program scope
     with
     | Parser.Error ->
         (* Simple error reporting for now - ideally we'd get position from lexbuf *)
         let d =
           Diagnostic.create ~range:(Range.create ~start:(Position.create ~line:0 ~character:0) ~end_:(Position.create ~line:0 ~character:0))
             ~message:(`String "Syntax error") ~severity:DiagnosticSeverity.Error ()
         in
         diagnostics := [ d ]
     | Lexer.SyntaxError msg ->
         let d =
           Diagnostic.create ~range:(Range.create ~start:(Position.create ~line:0 ~character:0) ~end_:(Position.create ~line:0 ~character:0))
             ~message:(`String (Printf.sprintf "Lexer error: %s" msg)) ~severity:DiagnosticSeverity.Error ()
         in
         diagnostics := [ d ]
     | _ -> ());
    let doc = { uri; text; scope; diagnostics = !diagnostics } in
    Hashtbl.replace server.documents uri doc;
    send_diagnostics uri !diagnostics

  let handle_initialize _params =
    let capabilities = ServerCapabilities.create 
      ~textDocumentSync:(`TextDocumentSyncOptions (TextDocumentSyncOptions.create 
        ~openClose:true 
        ~change:TextDocumentSyncKind.Full
        ()))
      ~completionProvider:(CompletionOptions.create ~triggerCharacters:["."] ())
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
          let matches = Completion.complete doc.scope ~buffer:line_text ~cursor in
          List.map (fun m -> 
            CompletionItem.create ~label:m ()
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
          let line_len = String.length line_text in
          if line_len = 0 then None
          else
            let max_idx = line_len - 1 in
            let clamped_character = max 0 (min character max_idx) in
            (* Simple word extraction at character *)
            let rec get_word start_idx =
              if start_idx < 0 || not (Lexer.is_ident_char line_text.[start_idx]) then
                let s = start_idx + 1 in
                let rec find_end idx =
                  if idx >= line_len || not (Lexer.is_ident_char line_text.[idx]) then idx
                  else find_end (idx + 1)
                in
                let e = find_end clamped_character in
                if s < e then Some (String.sub line_text s (e - s)) else None
              else get_word (start_idx - 1)
            in
            match get_word clamped_character with
          | Some name -> (
              match Symbol_table.lookup doc.scope name with
              | Some sym ->
                  let type_str =
                    match sym.typ with
                    | Some ty -> Semantic_type.to_string ty
                    | None -> "Unknown"
                  in
                  let content = Printf.sprintf "**%s** : `%s`" sym.name type_str in
                  let markup = MarkupContent.create ~kind:MarkupKind.Markdown ~value:content in
                  Some (Hover.create ~contents:(`MarkupContent markup) ())
              | None -> None)
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
          let line_len = String.length line_text in
          if line_len = 0 then None
          else
            let max_idx = line_len - 1 in
            let clamped_character = max 0 (min character max_idx) in
            let rec get_word start_idx =
              if start_idx < 0 || not (Lexer.is_ident_char line_text.[start_idx]) then
                let s = start_idx + 1 in
                let rec find_end idx =
                  if idx >= line_len || not (Lexer.is_ident_char line_text.[idx]) then idx
                  else find_end (idx + 1)
                in
                let e = find_end clamped_character in
                if s < e then Some (String.sub line_text s (e - s)) else None
              else get_word (start_idx - 1)
            in
            match get_word clamped_character with
          | Some name -> (
              (* Best effort: Find where 'name =' or 'name : type =' appears in the document *)
              let assignment_re = Str.regexp (Printf.sprintf "^[ \t]*%s[ \t]*[:=]" (Str.quote name)) in
              let rec find_in_lines idx = function
                | [] -> None
                | l :: rest ->
                    if Str.string_match assignment_re l 0 then
                      let range = Range.create 
                        ~start:(Position.create ~line:idx ~character:0) 
                        ~end_:(Position.create ~line:idx ~character:(String.length l)) in
                      Some (`Location (Location.create ~uri ~range))
                    else find_in_lines (idx + 1) rest
              in
              find_in_lines 0 lines)
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
            update_document server params.textDocument.uri params.textDocument.text
        | "textDocument/didChange" ->
            let params = DidChangeTextDocumentParams.t_of_yojson (params_to_yojson notif.params) in
            (match params.contentChanges with
            | [change] -> update_document server params.textDocument.uri change.text
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
            let params = CompletionParams.t_of_yojson (params_to_yojson req.params) in
            let items = handle_completion server params in
            let result = `List (List.map (fun i -> CompletionItem.yojson_of_t i) items) in
            Transport.write_message (Jsonrpc.Response.ok req.id result |> Jsonrpc.Response.yojson_of_t)
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
  let server = Server.create () in
  Server.run server


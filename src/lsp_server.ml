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
  }


  type t = {
    documents : (DocumentUri.t, doc_state) Hashtbl.t;
    base_env : Ast.value Ast.Env.t;
  }


  let create () = {
    documents = Hashtbl.create 10;
    base_env = Packages.init_env ();
  }

  let update_document server uri text =
    let scope = Symbol_table.create_scope () in
    Symbol_table.register_keywords scope;
    Symbol_table.populate_from_env scope server.base_env;
    (try
      let lexbuf = Lexing.from_string text in
      let program = Parser.program Lexer.token lexbuf in
      Analyzer.analyze program scope
    with _ -> ());
    Hashtbl.replace server.documents uri { uri; text; scope }

  let handle_initialize _params =
    let capabilities = ServerCapabilities.create 
      ~textDocumentSync:(`TextDocumentSyncOptions (TextDocumentSyncOptions.create 
        ~openClose:true 
        ~change:TextDocumentSyncKind.Full (* Simpler for now *)
        ()))
      ~completionProvider:(CompletionOptions.create ~triggerCharacters:["."] ())
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
            (* For Full sync, the first content change is the whole text *)
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
            let result = `List (List.map CompletionItem.yojson_of_t items) in
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


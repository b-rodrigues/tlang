(* src/package_manager/template_engine.ml *)
(* Simple {{variable}} template substitution engine *)

(** A substitution context: list of (key, value) pairs *)
type context = (string * string) list

(** Replace all occurrences of {{key}} with the corresponding value from context.
    Unknown variables are left as-is. *)
let substitute (ctx : context) (template : string) : string =
  let buf = Buffer.create (String.length template) in
  let len = String.length template in
  let i = ref 0 in
  while !i < len do
    if !i + 1 < len && template.[!i] = '{' && template.[!i + 1] = '{' then begin
      (* Found opening {{ — look for closing }} *)
      let start = !i + 2 in
      let j = ref start in
      let found = ref false in
      while !j + 1 < len && not !found do
        if template.[!j] = '}' && template.[!j + 1] = '}' then
          found := true
        else
          incr j
      done;
      if !found then begin
        let key = String.trim (String.sub template start (!j - start)) in
        (match List.assoc_opt key ctx with
         | Some value -> Buffer.add_string buf value
         | None -> 
           (* Leave unknown variables as-is *)
           Buffer.add_string buf "{{";
           Buffer.add_string buf key;
           Buffer.add_string buf "}}");
        i := !j + 2
      end else begin
        (* No closing }} found — emit literal {{ *)
        Buffer.add_string buf "{{";
        i := start
      end
    end else begin
      Buffer.add_char buf template.[!i];
      incr i
    end
  done;
  Buffer.contents buf

(** Build a template context from scaffold options *)
let context_of_options (opts : Package_types.scaffold_options) : context =
  let today =
    let t = Unix.gmtime (Unix.gettimeofday ()) in
    Printf.sprintf "%04d-%02d-%02d" (1900 + t.Unix.tm_year) (t.Unix.tm_mon + 1) t.Unix.tm_mday
  in
  [
    ("name", opts.target_name);
    ("author", opts.author);
    ("license", opts.license);
    ("date", today);
    ("t_version", "0.5.0");
    ("nixpkgs_date", "2026-02-10");
  ]

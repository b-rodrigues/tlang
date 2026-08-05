(* tests/core/test_strings.ml *)

(* Note: The signature for run_tests in this project seems to be:
   pass_count: int ref
   fail_count: int ref
   eval_string: string -> Ast.value
   eval_string_env: string -> Ast.environment -> Ast.value * Ast.environment
   test: string -> string -> string -> unit
*)

let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Phase 7 — Core: String Operations:\n";
  
  Printf.printf "  Inspection:\n";
  test "is_empty true" "is_empty(\"\")" "true";
  test "is_empty false" "is_empty(\"a\")" "false";
  test "length string error" "length(\"hello\")" {|Error(TypeError: "length does not work on strings. Use str_nchar() to get the number of characters in a string.")|};
  test "length list" "length([1, 2, 3])" "3";
  test "length vector" "length(seq(1, 10))" "10";
  test "length vector of strings" "length([\"a\", \"bc\"])" "2";
  test "nchar string" "str_nchar(\"hello\")" "5";
  test "nchar vector" "str_nchar([\"a\", \"bc\"])" "[1, 2]";
  test "nchar counts unicode code points" "str_nchar(\"h\u{00E9}llo\")" "5";
  test "nchar counts multibyte CJK" "str_nchar(\"\u{65E5}\u{672C}\u{8A9E}\")" "3";

  Printf.printf "  Substrings:\n";
  test "substring simple" "str_substring(\"hello\", 1, 3)" "\"el\"";
  test "slice alias" "slice(\"hello\", 0, 5)" "\"hello\"";
  test "char_at" "char_at(\"abc\", 1)" "\"b\"";
  test "substring utf8 never splits characters" "str_substring(\"\u{65E5}\u{672C}\u{8A9E}\", 0, 2)" "\"\u{65E5}\u{672C}\"";
  test "substring utf8 self roundtrip" "str_substring(\"h\u{00E9}llo\", 0, str_nchar(\"h\u{00E9}llo\"))" "\"h\u{00E9}llo\"";
  test "char_at utf8 returns whole character" "char_at(\"h\u{00E9}llo\", 1)" "\"\u{00E9}\"";
  test "substring out of bounds" "str_substring(\"a\", 0, 2)" {|Error(ValueError: "Invalid substring indices.")|};
  
  Printf.printf "  Search:\n";
  test "index_of found" "index_of(\"hello\", \"l\")" "2";
  test "index_of not found" "index_of(\"hello\", \"z\")" "-1";
  test "index_of returns character index for multibyte" "index_of(\"h\u{00E9}llo\", \"llo\")" "2";
  test "last_index_of found" "last_index_of(\"hello\", \"l\")" "3";
  test "last_index_of returns character index for multibyte" "last_index_of(\"h\u{00E9}llo\", \"l\")" "3";
  test "last_index_of empty needle returns char count" "last_index_of(\"h\u{00E9}llo\", \"\")" "5";
  test "contains false" "contains(\"team\", \"i\")" "false"; 
  test "contains true" "contains(\"team\", \"ea\")" "true";
  test "starts_with true" "starts_with(\"prefix\", \"pre\")" "true";
  test "starts_with false" "starts_with(\"prefix\", \"fix\")" "false";
  test "ends_with true" "ends_with(\"suffix\", \"fix\")" "true";
  
  Printf.printf "  Modification:\n";
  test "replace all" "str_replace(\"banana\", \"a\", \"o\")" "\"bonono\"";
  test "replace first" "replace_first(\"banana\", \"a\", \"o\")" "\"bonana\"";
  
  Printf.printf "  Case:\n";
  test "to_upper" "to_upper(\"test\")" "\"TEST\"";
  test "to_lower" "to_lower(\"TEST\")" "\"test\"";
  test "to_upper unicode" "to_upper(\"éàüç\")" "\"ÉÀÜÇ\"";
  test "to_lower unicode" "to_lower(\"ÉÀÜÇ\")" "\"éàüç\"";
  test "to_upper eszett expands to SS" "to_upper(\"ß\")" "\"SS\"";
  test "to_lower eszett" "to_lower(\"ß\")" "\"ß\"";
  test "to_upper roundtrip back to lower" "to_lower(to_upper(\"éàüç\"))" "\"éàüç\"";
  
  Printf.printf "  Vectorization:\n";
  test "to_upper vector" "to_upper([\"hello\", \"world\"])" "[\"HELLO\", \"WORLD\"]";
  test "substring vector" "str_substring([\"hello\", \"world\"], 1, 3)" "[\"el\", \"or\"]";
  test "contains vector scalar" "contains([\"hello\", \"help\"], \"lo\")" "[true, false]";

  test "join list" "str_join([\"a\", \"b\", \"c\"], \"-\")" "\"a-b-c\"";
  test "join vector" "str_join(seq(1, 3), \", \")" "\"1, 2, 3\"";
  test "join scalar" "str_join(\"a\", \"-\")" "\"a\"";
  test "concat error" "\"a\" + \"b\"" {|Error(TypeError: "String concatenation with '+' is not supported. Use 'str_join([a, b], sep)' or 'paste(a, b, sep)' instead.")|};

  Printf.printf "  Trim:\n";
  test "trim both" "str_trim(\"  hello  \")" "\"hello\"";
  test "trim start" "trim_start(\"  hello  \")" "\"hello  \"";
  test "trim end" "trim_end(\"  hello  \")" "\"  hello\"";
  test "trim newline" "str_trim(\"\\n\\t hello \\n\")" "\"hello\"";
  
  Printf.printf "  Lines & Words:\n";
  test "lines basic" "str_lines(\"a\\nb\\nc\")" "[\"a\", \"b\", \"c\"]";
  test "lines trailing" "str_lines(\"a\\nb\\nc\\n\")" "[\"a\", \"b\", \"c\"]";
  test "lines windows" "str_lines(\"a\\r\\nb\\r\\nc\")" "[\"a\", \"b\", \"c\"]";
  test "lines empty" "str_lines(\"\")" "[\"\"]";
  test "words basic" "str_words(\"hello   world\")" "[\"hello\", \"world\"]";
  test "words leading" "str_words(\"  leading and trailing  \")" "[\"leading\", \"and\", \"trailing\"]";
  test "words empty" "str_words(\"\")" "[]";
  
  Printf.printf "  Repeat & Format:\n";
  test "str_repeat" "str_repeat(\"x\", 3)" "\"xxx\"";
  test "str_repeat zero" "str_repeat(\"x\", 0)" "\"\"";
  test "str_repeat negative" "str_repeat(\"x\", -1)" {|Error(ValueError: "str_repeat: count must be non-negative.")|};
  test "str_format dict" "str_format(\"Hello, {name}!\", [name: \"Bruno\"])" "\"Hello, Bruno!\"";
  test "str_format list" "str_format(\"Host: {host}, Port: {port}\", [host: \"localhost\", port: \"5432\"])" "\"Host: localhost, Port: 5432\"";
  test "str_format missing" "str_format(\"Hello, {name}!\", [:])" {|Error(KeyError: "str_format: no value provided for key '{name}'.")|};
  test "str_format unclosed" "str_format(\"Hello, {name!\", [name: \"x\"])" {|Error(ValueError: "str_format: unclosed '{' in format string.")|};
  test "str_format escape lbrace" "str_format(\"{{val}}\", [:])" "\"{val}\"";
  test "str_format escape mixed" "str_format(\"{{{name}}}\", [name: \"x\"])" "\"{x}\"";
  test "str_format escape only braces" "str_format(\"{{}}\", [:])" "\"{}\"";
  test "str_extract first match" "str_extract(\"abc123def\", \"[0-9]+\")" "\"123\"";
  test "str_extract no match" "str_extract(\"abcdef\", \"[0-9]+\")" "NA(String)";
  test "str_extract_all matches" "str_extract_all(\"a1b22\", \"[0-9]+\")" "[\"1\", \"22\"]";
  test "str_detect regex" "str_detect([\"abc\", \"123\"], \"^[a-z]+$\")" "[true, false]";
  test "str_pad left" "str_pad(\"7\", 3, side = \"left\", pad = \"0\")" "\"007\"";
  test "str_trunc right" "str_trunc(\"abcdefgh\", 5)" "\"ab...\"";
  test "str_flatten collapse" "str_flatten([\"a\", \"b\", \"c\"], collapse = \"-\")" "\"a-b-c\"";
  test "str_count regex" "str_count(\"banana\", \"a\")" "3";
  test "str_detect dot matches a full multibyte char" "str_detect([\"h\u{00E9}llo\"], \"^h.llo$\")" "[true]";
  test "str_count dot counts code points not bytes" "str_count(\"h\u{00E9}llo\", \".\")" "5";
  test "str_extract unicode letter class" "str_extract(\"h\u{00E9}llo\", \"\\\\p{L}+\")" "\"h\u{00E9}llo\"";
  test "str_extract_all unicode letters split by digit" "str_extract_all(\"h\u{00E9}1llo2\", \"\\\\p{L}+\")" "[\"h\u{00E9}\", \"llo\"]";
  test "str_detect ascii class still excludes accents" "str_detect([\"h\u{00E9}llo\"], \"^[a-z]+$\")" "[false]";

  Printf.printf "  UTF-8 regressions:\n";
  test "str_split empty separator splits code points not bytes"
    "str_split(\"h\u{00E9}llo\", \"\")"
    "[\"h\", \"\u{00E9}\", \"l\", \"l\", \"o\"]";
  test "str_pad counts characters not bytes"
    "str_pad(\"\u{00E9}\", 3, side = \"left\", pad = \"x\")"
    "\"xx\u{00E9}\"";
  test "str_trunc keeps full multibyte string at char width"
    "str_trunc(\"\u{00E9}llo\", 4)"
    "\"\u{00E9}llo\"";
  test "str_trunc never splits a multibyte character"
    "str_trunc(\"\u{65E5}\u{672C}\u{8A9E}\", 2)"
    "\"..\"";
  test "index_of empty needle returns zero"
    "index_of(\"h\u{00E9}llo\", \"\")"
    "0";

  print_newline ()

let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Colcraft Coverage Regression Tests:\n";

  test "fill up fills string values from below"
    {|df_fill = dataframe([
  [grp: NA, txt: "top", flag: NA, amount: NA, ratio: NA],
  [grp: "a", txt: NA, flag: true, amount: 1, ratio: 1.5],
  [grp: NA, txt: NA, flag: NA, amount: NA, ratio: NA],
  [grp: "b", txt: "bottom", flag: false, amount: 4, ratio: 4.5]
]); fill(df_fill, $grp, .direction = "up").grp|}
    {|Vector["a", "a", "b", "b"]|};
  test "fill downup fills integer and float gaps"
    {|df_fill = dataframe([
  [grp: NA, txt: "top", flag: NA, amount: NA, ratio: NA],
  [grp: "a", txt: NA, flag: true, amount: 1, ratio: 1.5],
  [grp: NA, txt: NA, flag: NA, amount: NA, ratio: NA],
  [grp: "b", txt: "bottom", flag: false, amount: 4, ratio: 4.5]
]); result = fill(df_fill, $amount, $ratio, .direction = "downup"); result.ratio|}
    "Vector[1.5, 1.5, 1.5, 4.5]";
  test "fill updown fills boolean gaps"
    {|df_fill = dataframe([
  [grp: NA, txt: "top", flag: NA],
  [grp: "a", txt: NA, flag: true],
  [grp: NA, txt: NA, flag: NA],
  [grp: "b", txt: "bottom", flag: false]
]); fill(df_fill, $flag, .direction = "updown").flag|}
    "Vector[true, true, false, false]";
  test "fill rejects invalid direction"
    {|df_fill = dataframe([[x: 1], [x: NA]]); fill(df_fill, $x, .direction = "sideways")|}
    {|Error(TypeError: "Function `fill` received invalid `.direction` value: "sideways". Supported values are: down, up, downup, updown.")|};
  test "fill rejects missing columns"
    {|fill(dataframe([[x: 1]]), $missing)|}
    {|Error(KeyError: "Function `fill`: column(s) not found: missing")|};

  test "replace_na fills integer column from named dict"
    {|df_replace = dataframe([[i: 1, f: 1.5, s: "x", b: true], [i: NA, f: NA, s: NA, b: NA]]);
replace_na(df_replace, replace = [i: 9, f: 9.5, s: "missing", b: false]).i|}
    "Vector[1, 9]";
  test "replace_na fills float column from positional dict"
    {|df_replace = dataframe([[i: 1, f: 1.5, s: "x", b: true], [i: NA, f: NA, s: NA, b: NA]]);
replace_na(df_replace, [i: 9, f: 9.5, s: "missing", b: false]).f|}
    "Vector[1.5, 9.5]";
  test "replace_na fills string and bool columns"
    {|df_replace = dataframe([[i: 1, f: 1.5, s: "x", b: true], [i: NA, f: NA, s: NA, b: NA]]);
result = replace_na(df_replace, [i: 9, f: 9.5, s: "missing", b: false]); result.s|}
    {|Vector["x", "missing"]|};
  test "replace_na rejects non-dataframe input"
    {|replace_na(42, [x: 1])|}
    {|Error(TypeError: "Function `replace_na` expects a DataFrame as first argument.")|};

  test "complete explicit false preserves explicit missing values"
    {|df_complete = dataframe([
  [g: "a", item: "x", value: 1],
  [g: "a", item: "y", value: NA],
  [g: "b", item: "x", value: 2]
]);
completed = complete(df_complete, $g, $item, fill = [value: 0], explicit = false);
replace_na(completed, [value: -1]).value|}
    "Vector[1, -1, 2, 0]";
  test "complete with nesting limits nested combinations"
    {|df_nested = dataframe([
  [g: "a", item: "x", label: "X", value: 1],
  [g: "b", item: "x", label: "X", value: 2],
  [g: "b", item: "y", label: "Y", value: 3]
]);
complete(df_nested, $g, nesting($item, $label)) |> nrow|}
    "4";
  test "complete requires at least one selector"
    {|complete(dataframe([[x: 1]]))|}
    {|Error(ValueError: "Function `complete` requires at least one column or nesting() expression.")|};
  test "complete rejects missing selector columns"
    {|complete(dataframe([[x: 1]]), $missing)|}
    {|Error(KeyError: "Column(s) not found: missing")|};

  test "relocate defaults to moving columns to the front"
    {|relocate(dataframe([[a: 1, b: 2, c: 3]]), $c)|}
    "DataFrame(1 rows x 3 cols: [c, a, b])";
  test "relocate moves columns after a target"
    {|relocate(dataframe([[a: 1, b: 2, c: 3]]), $a, .after = $c)|}
    "DataFrame(1 rows x 3 cols: [b, c, a])";
  test "relocate with no selected columns is a no-op"
    {|relocate(dataframe([[a: 1, b: 2, c: 3]]))|}
    "DataFrame(1 rows x 3 cols: [a, b, c])";
  test "relocate rejects non-dataframe input"
    {|relocate(42, $x)|}
    {|Error(TypeError: "Function `relocate` expects a DataFrame as first argument.")|};
  test "relocate requires a dataframe"
    {|relocate()|}
    {|Error(ArityError: "Function `relocate` requires a DataFrame and columns to move.")|};

  test "count without keys returns one-row count"
    {|count(dataframe([[x: 1], [x: 2]]), name = "rows").rows|}
    "Vector[2]";
  test "count uses existing group keys when grouped"
    {|df_count = dataframe([[g: "a", x: 1], [g: "a", x: 2], [g: "b", x: 3]]);
grouped = group_by(df_count, $g);
count(grouped, name = "rows").rows|}
    "Vector[2, 1]";
  test "n counts dataframe rows"
    {|n(dataframe([[x: 1], [x: 2], [x: 3]]))|}
    "3";
  test "n counts vector length"
    {|n([1, 2, 3, 4])|}
    "4";
  test "n rejects calls outside summarize context with no args"
    {|n()|}
    {|Error(ValueError: "Function `n` is only valid inside `summarize()`.")|};
  test "n rejects invalid aggregation contexts"
    {|n("oops")|}
    {|Error(TypeError: "Function `n` expects a DataFrame, vector, or list aggregation context.")|};

  test "slice selects rows by 0-based indices"
    {|slice(dataframe([[x: 1], [x: 2], [x: 3]]), [0, 2]).x|}
    "Vector[1, 3]";
  test "slice supports empty index vectors"
    {|slice(dataframe([[x: 1], [x: 2], [x: 3]]), []) |> nrow|}
    "0";
  test "slice delegates to substring for strings"
    {|slice("abcd", 1, 3)|}
    {|"bc"|};
  test "slice rejects out-of-range indices"
    {|slice(dataframe([[x: 1], [x: 2]]), [2])|}
    {|Error(ValueError: "Function `slice` index out of range (indices must be 0-based and within [0, nrow-1]).")|};
  test "slice rejects non-vector indices"
    {|slice(dataframe([[x: 1]]), 2)|}
    {|Error(TypeError: "Function `slice` expects a Vector or List of integer indices.")|};

  test "unnest supports named cols argument"
    {|df_nested = dataframe([[g: "a", x: 1, y: 10], [g: "a", x: 2, y: 20], [g: "b", x: 3, y: 30]]);
nested = nest(df_nested, $x, $y);
unnest(nested, cols = $data).y|}
    "Vector[10, 20, 30]";
  test "unnest handles empty nested selections"
    {|df_nested = dataframe([[g: "a", x: 1]]);
nested = nest(df_nested, $x);
empty_nested = slice(nested, []);
unnest(empty_nested, $data) |> nrow|}
    "0";
  test "unnest rejects non-list columns"
    {|unnest(dataframe([[x: 1]]), $x)|}
    {|Error(TypeError: "Column `x` is not a list-column.")|};
  test "unnest requires a column selection"
    {|unnest(dataframe([[x: 1]]))|}
    {|Error(ArityError: "unnest expects a column to unnest ($col).")|};

  test "expand with no selectors returns an empty dataframe"
    {|expand(dataframe([[x: 1]])) |> nrow|}
    "0";
  test "expand combines columns with explicit vectors"
    {|df_expand = dataframe([[g: "a", x: 1], [g: "a", x: 2], [g: "b", x: 2]]);
expand(df_expand, $g, [1, 2, 2]) |> nrow|}
    "4";
  test "expand nesting preserves only observed combinations"
    {|df_expand = dataframe([[g: "a", x: 1], [g: "a", x: 2], [g: "b", x: 2]]);
expand(df_expand, nesting($g, $x)) |> nrow|}
    "3";
  test "crossing returns zero rows when any input is empty"
    {|crossing(x = [], y = ["a"]) |> nrow|}
    "0";

  test "select with starts_with matcher"
    {|wide = dataframe([[name: "Alice", age: 30, score: 95.5, dept: "eng", is_remote: true]]);
select(wide, starts_with("na")) |> ncol|}
    "1";
  test "select with ends_with matcher"
    {|wide = dataframe([[name: "Alice", age: 30, score: 95.5, dept: "eng", is_remote: true]]);
select(wide, ends_with("pt")) |> ncol|}
    "1";
  test "select with contains matcher"
    {|wide = dataframe([[name: "Alice", age: 30, score: 95.5, dept: "eng", is_remote: true]]);
select(wide, contains("rem")) |> ncol|}
    "1";
  test "select with everything matcher"
    {|wide = dataframe([[name: "Alice", age: 30, score: 95.5, dept: "eng", is_remote: true]]);
select(wide, everything()) |> ncol|}
    "5";
  test "selection helpers fall back to string operations"
    {|starts_with("alphabet", "alp")|}
    "true";
  test "matches rejects invalid regexes"
    {|matches("[")|}
    {|Error(ValueError: "[L1:C1] Function `matches` received an invalid regex: [ class not closed by ]")|};
  test "where selects logical columns"
    {|wide = dataframe([[name: "Alice", age: 30, score: 95.5, dept: "eng", is_remote: true]]);
select(wide, where(is_logical)) |> ncol|}
    "1";
  test "where rejects non-builtin predicates"
    {|where(42)|}
    {|Error(TypeError: "Function `where` expects a builtin predicate function.")|};
  test "is_factor recognises factor vectors with NA values"
    {|is_factor(fct(["a", NA, "b"]))|}
    "true";
  test "is_character recognises scalar strings"
    {|is_character("hello")|}
    "true";

  test "separate splits column into multiple"
    {|df = dataframe([[x: "a-b-c"]]); separate(df, $x, into = ["v1", "v2", "v3"], sep = "-") |> colnames()|}
    {|["v1", "v2", "v3"]|};
  test "separate handles too few parts"
    {|df = dataframe([[x: "a-b"]]); separate(df, $x, into = ["v1", "v2", "v3"], sep = "-") |> pull("v3")|}
    "Vector[\"\"]";
  test "separate_rows expands rows by splitting"
    {|df = dataframe([[id: 1, x: "a;b"]]); separate_rows(df, $x, sep = ";") |> nrow|}
    "2";
  test "separate_rows preserves other columns"
    {|df = dataframe([[id: 1, x: "a;b"]]); separate_rows(df, $x, sep = ";").id|}
    "Vector[1, 1]";
  test "uncount duplicates rows by weight"
    {|df = dataframe([[x: "a", w: 3]]); uncount(df, $w) |> nrow|}
    "3";
  test "slice_max returns rows with largest values"
    {|df = dataframe([[x: 1], [x: 5], [x: 3]]); slice_max(df, $x, n = 2).x|}
    "Vector[5, 3]";
  test "slice_min returns rows with smallest values"
    {|df = dataframe([[x: 1], [x: 5], [x: 3]]); slice_min(df, $x, n = 2).x|}
    "Vector[1, 3]";
  test "distinct removes duplicate rows"
    {|df = dataframe([[x: 1], [x: 1], [x: 2]]); distinct(df) |> nrow|}
    "2";

  print_newline ()

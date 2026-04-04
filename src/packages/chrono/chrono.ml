open Ast

let micros_per_second = 1_000_000L
let micros_per_minute = 60_000_000L
let micros_per_hour = 3_600_000_000L
let micros_per_day = 86_400_000_000L

let month_abbrevs = [|"Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"; "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec"|]
let month_names = [|"January"; "February"; "March"; "April"; "May"; "June"; "July"; "August"; "September"; "October"; "November"; "December"|]
let weekday_abbrevs = [|"Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat"|]

let empty_period = {
  p_years = 0;
  p_months = 0;
  p_days = 0;
  p_hours = 0;
  p_minutes = 0;
  p_seconds = 0;
  p_micros = 0;
}

let positive_mod a b =
  let r = a mod b in
  if r < 0 then r + b else r

let floor_div_int a b =
  let q = a / b in
  let r = a mod b in
  if r <> 0 && ((a < 0) <> (b < 0)) then q - 1 else q

let floor_div_int64 a b =
  let q = Int64.div a b in
  let r = Int64.rem a b in
  if r <> 0L && ((a < 0L) <> (b < 0L)) then Int64.sub q 1L else q

let is_leap_year year =
  (year mod 4 = 0 && year mod 100 <> 0) || year mod 400 = 0

let days_in_month year month =
  match month with
  | 1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
  | 4 | 6 | 9 | 11 -> 30
  | 2 -> if is_leap_year year then 29 else 28
  | _ -> 0

let is_valid_date year month day =
  month >= 1 && month <= 12 && day >= 1 && day <= days_in_month year month

let is_valid_time hour minute second micros =
  hour >= 0 && hour <= 23
  && minute >= 0 && minute <= 59
  && second >= 0 && second <= 59
  && micros >= 0 && micros < 1_000_000

let days_from_civil year month day =
  let y = if month <= 2 then year - 1 else year in
  let era = floor_div_int (if y >= 0 then y else y - 399) 400 in
  let yoe = y - era * 400 in
  let mp = month + (if month > 2 then -3 else 9) in
  let doy = (153 * mp + 2) / 5 + day - 1 in
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy in
  era * 146097 + doe - 719468

let civil_from_days days =
  let z = days + 719468 in
  let era = floor_div_int (if z >= 0 then z else z - 146096) 146097 in
  let doe = z - era * 146097 in
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 in
  let y = yoe + era * 400 in
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100) in
  let mp = (5 * doy + 2) / 153 in
  let d = doy - (153 * mp + 2) / 5 + 1 in
  let m = mp + if mp < 10 then 3 else -9 in
  let y = y + if m <= 2 then 1 else 0 in
  (y, m, d)

let day_of_year year month day =
  let rec loop acc m =
    if m >= month then acc else loop (acc + days_in_month year m) (m + 1)
  in
  loop day 1

let sunday_wday_from_days days =
  positive_mod (days + 4) 7 + 1

let monday_wday_from_days days =
  positive_mod (days + 3) 7 + 1

let iso_year_start_days year =
  let jan4 = days_from_civil year 1 4 in
  jan4 - (monday_wday_from_days jan4 - 1)

let iso_week_and_year days =
  let year, _, _ = civil_from_days days in
  let iso_year =
    if days < iso_year_start_days year then year - 1
    else if days >= iso_year_start_days (year + 1) then year + 1
    else year
  in
  (iso_year, ((days - iso_year_start_days iso_year) / 7) + 1)

let split_datetime_micros micros =
  let day_index = floor_div_int64 micros micros_per_day in
  let remainder = Int64.sub micros (Int64.mul day_index micros_per_day) in
  let total = Int64.to_int remainder in
  let hour = total / Int64.to_int micros_per_hour in
  let rem_after_hour = total mod Int64.to_int micros_per_hour in
  let minute = rem_after_hour / Int64.to_int micros_per_minute in
  let rem_after_minute = rem_after_hour mod Int64.to_int micros_per_minute in
  let second = rem_after_minute / Int64.to_int micros_per_second in
  let micros = rem_after_minute mod Int64.to_int micros_per_second in
  let year, month, day = civil_from_days (Int64.to_int day_index) in
  (year, month, day, hour, minute, second, micros)

let datetime_of_components year month day hour minute second micros =
  Int64.add
    (Int64.mul (Int64.of_int (days_from_civil year month day)) micros_per_day)
    (Int64.add
       (Int64.mul (Int64.of_int hour) micros_per_hour)
       (Int64.add
          (Int64.mul (Int64.of_int minute) micros_per_minute)
          (Int64.add
             (Int64.mul (Int64.of_int second) micros_per_second)
             (Int64.of_int micros))))

let parse_int_opt s =
  try Some (int_of_string s) with Failure _ -> None

let int_list_of_options opts =
  let rec loop acc = function
    | [] -> Some (List.rev acc)
    | Some v :: rest -> loop (v :: acc) rest
    | None :: _ -> None
  in
  loop [] opts

let digit_groups s =
  let re = Str.regexp "[0-9]+" in
  let rec loop pos acc =
    match (try Some (Str.search_forward re s pos) with Not_found -> None) with
    | None -> List.rev acc
    | Some _ -> loop (Str.match_end ()) (Str.matched_string s :: acc)
  in
  loop 0 []

let split_compact_date order digits =
  if String.length digits <> 8 then None
  else
    let seg start len = String.sub digits start len in
    match order with
    | `YMD -> Some [seg 0 4; seg 4 2; seg 6 2]
    | `MDY -> Some [seg 0 2; seg 2 2; seg 4 4]
    | `DMY -> Some [seg 0 2; seg 2 2; seg 4 4]
    | `YDM -> Some [seg 0 4; seg 4 2; seg 6 2]

let split_compact_datetime order count digits =
  let expected = match count with 4 -> 10 | 5 -> 12 | _ -> 14 in
  if String.length digits <> expected then None
  else
    let seg start len = String.sub digits start len in
    let date_segments =
      match order with
      | `YMD -> [seg 0 4; seg 4 2; seg 6 2]
      | `MDY -> [seg 0 2; seg 2 2; seg 4 4]
      | `DMY -> [seg 0 2; seg 2 2; seg 4 4]
      | `YDM -> [seg 0 4; seg 4 2; seg 6 2]
    in
    let time_segments =
      match count with
      | 4 -> [seg 8 2]
      | 5 -> [seg 8 2; seg 10 2]
      | _ -> [seg 8 2; seg 10 2; seg 12 2]
    in
    Some (date_segments @ time_segments)

let parts_of_order order = function
  | [a; b; c] ->
      (match order with
       | `YMD -> Some (a, b, c)
       | `MDY -> Some (c, a, b)
       | `DMY -> Some (c, b, a)
       | `YDM -> Some (a, c, b))
  | _ -> None

let parse_shorthand_date order s =
  let raw =
    match digit_groups s with
    | [digits] -> split_compact_date order digits
    | groups -> Some groups
  in
  match raw with
  | None -> None
  | Some groups ->
      let ints = List.map parse_int_opt groups in
      (match int_list_of_options ints with
       | None -> None
       | Some ints ->
           (match parts_of_order order ints with
            | Some (year, month, day) when is_valid_date year month day ->
                Some (VDate (days_from_civil year month day))
            | _ -> None))

let parse_shorthand_datetime order count ?tz s =
  let raw =
    match digit_groups s with
    | [digits] -> split_compact_datetime order count digits
    | groups -> Some groups
  in
  match raw with
  | None -> None
  | Some groups ->
      let ints = List.map parse_int_opt groups in
      (match int_list_of_options ints with
       | None -> None
       | Some ints ->
           let date_parts, time_parts =
             let rec split n acc rest =
               if n = 0 then (List.rev acc, rest)
               else match rest with
                 | [] -> (List.rev acc, [])
                 | h :: t -> split (n - 1) (h :: acc) t
             in
             split 3 [] ints
           in
           (match parts_of_order order date_parts with
            | Some (year, month, day) when is_valid_date year month day ->
                let hour, minute, second =
                  match time_parts with
                  | [h] -> (h, 0, 0)
                  | [h; m] -> (h, m, 0)
                  | [h; m; sec] -> (h, m, sec)
                  | _ -> (-1, -1, -1)
                in
                if is_valid_time hour minute second 0 then
                  Some (VDatetime (datetime_of_components year month day hour minute second 0, tz))
                else None
            | _ -> None))

let read_exact_digits s pos len =
  if pos + len > String.length s then None
  else
    let sub = String.sub s pos len in
    if String.for_all (fun c -> c >= '0' && c <= '9') sub then Some (sub, pos + len) else None

let read_word s pos =
  let rec loop i =
    if i < String.length s then
      let c = s.[i] in
      if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c = '_' || c = '/' then loop (i + 1) else i
    else i
  in
  let stop = loop pos in
  if stop = pos then None else Some (String.sub s pos (stop - pos), stop)

let month_of_name name =
  let lower = String.lowercase_ascii name in
  let find arr =
    let rec loop i =
      if i >= Array.length arr then None
      else if String.lowercase_ascii arr.(i) = lower then Some (i + 1)
      else loop (i + 1)
    in
    loop 0
  in
  match find month_abbrevs with
  | Some month -> Some month
  | None -> find month_names

let parse_custom_format kind s format tz_override =
  let year = ref None
  and month = ref None
  and day = ref None
  and hour = ref 0
  and minute = ref 0
  and second = ref 0
  and micros = ref 0
  and tz = ref tz_override in
  let rec loop i j =
    if j >= String.length format then Some i
    else if format.[j] = '%' then
      if j + 1 >= String.length format then None
      else begin
        match format.[j + 1] with
        | 'Y' ->
            (match read_exact_digits s i 4 with Some (digits, i2) -> year := parse_int_opt digits; loop i2 (j + 2) | None -> None)
        | 'm' ->
            (match read_exact_digits s i 2 with Some (digits, i2) -> month := parse_int_opt digits; loop i2 (j + 2) | None -> None)
        | 'd' ->
            (match read_exact_digits s i 2 with Some (digits, i2) -> day := parse_int_opt digits; loop i2 (j + 2) | None -> None)
        | 'H' ->
            (match read_exact_digits s i 2 with
             | Some (digits, i2) ->
                 (match parse_int_opt digits with
                  | Some h -> hour := h; loop i2 (j + 2)
                  | None -> None)
             | None -> None)
        | 'M' ->
            (match read_exact_digits s i 2 with
             | Some (digits, i2) ->
                 (match parse_int_opt digits with
                  | Some m -> minute := m; loop i2 (j + 2)
                  | None -> None)
             | None -> None)
        | 'S' ->
            (match read_exact_digits s i 2 with
             | Some (digits, i2) ->
                 (match parse_int_opt digits with
                  | None -> None
                  | Some sec ->
                      second := sec;
                      if i2 < String.length s && s.[i2] = '.' then
                        let rec stop k = if k < String.length s && s.[k] >= '0' && s.[k] <= '9' then stop (k + 1) else k in
                        let i3 = stop (i2 + 1) in
                        let frac = String.sub s (i2 + 1) (i3 - i2 - 1) in
                        let frac6 =
                          if String.length frac >= 6 then String.sub frac 0 6
                          else frac ^ String.make (6 - String.length frac) '0'
                        in
                        (match parse_int_opt frac6 with
                         | Some us -> micros := us; loop i3 (j + 2)
                         | None -> None)
                      else loop i2 (j + 2))
             | None -> None)
        | 'b' | 'B' ->
            (match read_word s i with Some (word, i2) -> month := month_of_name word; loop i2 (j + 2) | None -> None)
        | 'Z' ->
            (match read_word s i with Some (word, i2) -> tz := Some word; loop i2 (j + 2) | None -> None)
        | _ -> None
      end
    else if i < String.length s && s.[i] = format.[j] then loop (i + 1) (j + 1)
    else None
  in
  match loop 0 0 with
  | Some consumed when consumed = String.length s ->
      (match !year, !month, !day with
       | Some y, Some m, Some d when is_valid_date y m d ->
           if kind = `Date then Some (VDate (days_from_civil y m d))
           else if is_valid_time !hour !minute !second !micros then
             Some (VDatetime (datetime_of_components y m d !hour !minute !second !micros, !tz))
           else None
       | _ -> None)
  | _ -> None

let current_utc_datetime () =
  let now = Unix.gettimeofday () in
  let tm = Unix.gmtime now in
  let micros = int_of_float ((now -. floor now) *. 1_000_000.) in
  (tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec, micros)

let current_date_value () =
  let year, month, day, _, _, _, _ = current_utc_datetime () in
  VDate (days_from_civil year month day)

let current_datetime_value tz =
  let year, month, day, hour, minute, second, micros = current_utc_datetime () in
  VDatetime (datetime_of_components year month day hour minute second micros, tz)

let positional_args named_args =
  List.filter_map (function None, v -> Some v | _ -> None) named_args

let find_named_arg name named_args =
  List.find_map (function Some n, v when n = name -> Some v | _ -> None) named_args

let bool_named_arg name default named_args =
  match find_named_arg name named_args with
  | None -> Ok default
  | Some (VBool b) -> Ok b
  | Some v -> Error (Error.type_error (Printf.sprintf "Argument `%s` must be Bool, got %s." name (Utils.type_name v)))

let int_named_arg name default named_args =
  match find_named_arg name named_args with
  | None -> Ok default
  | Some (VInt i) -> Ok i
  | Some v -> Error (Error.type_error (Printf.sprintf "Argument `%s` must be Int, got %s." name (Utils.type_name v)))

let string_named_arg name default named_args =
  match find_named_arg name named_args with
  | None -> Ok default
  | Some (VString s) -> Ok (Some s)
  | Some (VNA NAGeneric) -> Ok None
  | Some v -> Error (Error.type_error (Printf.sprintf "Argument `%s` must be String, got %s." name (Utils.type_name v)))

let parse_scalar_string function_name parse_fn = function
  | VString s -> (match parse_fn s with Some v -> v | None -> Error.value_error (Printf.sprintf "Function `%s` could not parse %S." function_name s))
  | VNA _ -> (VNA NAGeneric)
  | _ -> Error.type_error (Printf.sprintf "Function `%s` expects a String or Vector[String]." function_name)

let parse_scalar_string_vectorized parse_fn = function
  | VString s -> (match parse_fn s with Some v -> v | None -> (VNA NAGeneric))
  | VNA _ -> (VNA NAGeneric)
  | _ -> (VNA NAGeneric)

let scalar_component function_name fn value =
  let rec apply = function
    | VVector arr -> VVector (Array.map apply arr)
    | VNA _ -> (VNA NAGeneric)
    | value ->
        (match fn value with
         | Some out -> out
         | None ->
             Error.type_error
               (Printf.sprintf
                  "Function `%s` expects a Date, Datetime, or Vector of them."
                  function_name))
  in
  apply value

let add_months_to_date year month day month_delta =
  let month_index = year * 12 + (month - 1) + month_delta in
  let new_year = floor_div_int month_index 12 in
  let new_month = positive_mod month_index 12 + 1 in
  let new_day = min day (days_in_month new_year new_month) in
  (new_year, new_month, new_day)

let period_has_time_components period =
  period.p_hours <> 0
  || period.p_minutes <> 0
  || period.p_seconds <> 0
  || period.p_micros <> 0

let add_period_to_value value period =
  match value with
  | VDate days ->
      let year, month, day = civil_from_days days in
      let year, month, day = add_months_to_date year month day (period.p_years * 12 + period.p_months) in
      let days = days_from_civil year month day + period.p_days in
      if not (period_has_time_components period) then
        VDate days
      else
        VDatetime (
          Int64.add
            (Int64.mul (Int64.of_int days) micros_per_day)
            (Int64.add
               (Int64.mul (Int64.of_int period.p_hours) micros_per_hour)
               (Int64.add
                  (Int64.mul (Int64.of_int period.p_minutes) micros_per_minute)
                  (Int64.add
                     (Int64.mul (Int64.of_int period.p_seconds) micros_per_second)
                     (Int64.of_int period.p_micros)))),
          None)
  | VDatetime (micros, tz) ->
      let year, month, day, hour, minute, second, micro = split_datetime_micros micros in
      let year, month, day = add_months_to_date year month day (period.p_years * 12 + period.p_months) in
      let base = datetime_of_components year month day hour minute second micro in
      VDatetime (
        Int64.add base
          (Int64.add
             (Int64.mul (Int64.of_int period.p_days) micros_per_day)
             (Int64.add
                (Int64.mul (Int64.of_int period.p_hours) micros_per_hour)
                (Int64.add
                   (Int64.mul (Int64.of_int period.p_minutes) micros_per_minute)
                   (Int64.add
                      (Int64.mul (Int64.of_int period.p_seconds) micros_per_second)
                      (Int64.of_int period.p_micros))))),
        tz)
  | _ -> Error.type_error "Date arithmetic expects a Date or Datetime value."

let negate_period p =
  {
    p_years = -p.p_years;
    p_months = -p.p_months;
    p_days = -p.p_days;
    p_hours = -p.p_hours;
    p_minutes = -p.p_minutes;
    p_seconds = -p.p_seconds;
    p_micros = -p.p_micros;
  }

let date_diff_period left right =
  match left, right with
  | VDate d1, VDate d2 -> VPeriod { empty_period with p_days = d1 - d2 }
  | VDatetime (t1, _), VDatetime (t2, _) -> VDuration (Int64.to_float (Int64.sub t1 t2) /. 1_000_000.0)
  | _ -> Error.type_error "Date subtraction expects Date or Datetime values."

let format_datetime_value micros tz format =
  let year, month, day, hour, minute, second, micro = split_datetime_micros micros in
  let wday = sunday_wday_from_days (days_from_civil year month day) in
  let replace = function
    | "%Y" -> Printf.sprintf "%04d" year
    | "%m" -> Printf.sprintf "%02d" month
    | "%d" -> Printf.sprintf "%02d" day
    | "%H" -> Printf.sprintf "%02d" hour
    | "%M" -> Printf.sprintf "%02d" minute
    | "%S" -> if micro = 0 then Printf.sprintf "%02d" second else Printf.sprintf "%02d.%06d" second micro
    | "%b" -> month_abbrevs.(month - 1)
    | "%B" -> month_names.(month - 1)
    | "%a" -> weekday_abbrevs.(wday - 1)
    | "%Z" -> (match tz with Some zone -> zone | None -> "UTC")
    | token -> token
  in
  let rec loop i acc =
    if i >= String.length format then String.concat "" (List.rev acc)
    else if format.[i] = '%' && i + 1 < String.length format then
      loop (i + 2) (replace (String.sub format i 2) :: acc)
    else
      loop (i + 1) (String.make 1 format.[i] :: acc)
  in
  loop 0 []

let month_value label = function
  | VDate days ->
      let _, month, _ = civil_from_days days in
      Some (if label then VString month_abbrevs.(month - 1) else VInt month)
  | VDatetime (micros, _) ->
      let _, month, _, _, _, _, _ = split_datetime_micros micros in
      Some (if label then VString month_abbrevs.(month - 1) else VInt month)
  | _ -> None

let simple_component extractor value =
  match value with
  | VDate days -> Some (VInt (extractor (civil_from_days days)))
  | VDatetime (micros, _) ->
      let year, month, day, _, _, _, _ = split_datetime_micros micros in
      Some (VInt (extractor (year, month, day)))
  | _ -> None

let parse_round_unit function_name = function
  | "second" | "minute" | "hour" | "day" | "month" | "year" as unit_name -> Ok unit_name
  | other ->
      Error
        (Error.value_error
           (Printf.sprintf
              "Function `%s` unit must be one of \"second\", \"minute\", \"hour\", \"day\", \"month\", or \"year\", got %S."
              function_name other))

let floor_datetime_unit unit micros tz =
  let year, month, day, hour, minute, second, _ = split_datetime_micros micros in
  match unit with
  | "second" -> VDatetime (datetime_of_components year month day hour minute second 0, tz)
  | "minute" -> VDatetime (datetime_of_components year month day hour minute 0 0, tz)
  | "hour" -> VDatetime (datetime_of_components year month day hour 0 0 0, tz)
  | "day" -> VDatetime (datetime_of_components year month day 0 0 0 0, tz)
  | "month" -> VDatetime (datetime_of_components year month 1 0 0 0 0, tz)
  | "year" -> VDatetime (datetime_of_components year 1 1 0 0 0 0, tz)
  | _ -> VDatetime (micros, tz)

let shift_floor_datetime unit micros tz delta =
  match floor_datetime_unit unit micros tz with
  | VDatetime (ts, _) -> VDatetime (Int64.add ts delta, tz)
  | _ -> VDatetime (micros, tz)

let next_datetime_boundary unit micros tz =
  let year, month, _, _, _, _, _ = split_datetime_micros micros in
  match unit with
  | "second" -> shift_floor_datetime unit micros tz micros_per_second
  | "minute" -> shift_floor_datetime unit micros tz micros_per_minute
  | "hour" -> shift_floor_datetime unit micros tz micros_per_hour
  | "day" -> shift_floor_datetime unit micros tz micros_per_day
  | "month" ->
      let next_year, next_month, _ = add_months_to_date year month 1 1 in
      VDatetime (datetime_of_components next_year next_month 1 0 0 0 0, tz)
  | "year" ->
      VDatetime (datetime_of_components (year + 1) 1 1 0 0 0 0, tz)
  | _ -> VDatetime (micros, tz)

let floor_date_unit unit days =
  let year, month, _ = civil_from_days days in
  match unit with
  | "day" -> VDate days
  | "month" -> VDate (days_from_civil year month 1)
  | "year" -> VDate (days_from_civil year 1 1)
  | _ ->
      Error.type_error
        "Date rounding only supports units \"day\", \"month\", and \"year\" for Date values."

let next_date_boundary unit days =
  let year, month, _ = civil_from_days days in
  match unit with
  | "day" -> VDate (days + 1)
  | "month" ->
      let next_year, next_month, _ = add_months_to_date year month 1 1 in
      VDate (days_from_civil next_year next_month 1)
  | "year" -> VDate (days_from_civil (year + 1) 1 1)
  | _ ->
      Error.type_error
        "Date rounding only supports units \"day\", \"month\", and \"year\" for Date values."

let compare_temporal a b =
  match a, b with
  | VDate d1, VDate d2 -> compare d1 d2
  | VDatetime (t1, _), VDatetime (t2, _) -> Int64.compare t1 t2
  | _ -> 0

let temporal_distance a b =
  match a, b with
  | VDate d1, VDate d2 -> float_of_int (abs (d1 - d2))
  | VDatetime (t1, _), VDatetime (t2, _) ->
      Int64.abs (Int64.sub t1 t2) |> Int64.to_float
  | _ -> infinity

let rec floor_temporal function_name unit = function
  | VDate days -> floor_date_unit unit days
  | VDatetime (micros, tz) -> floor_datetime_unit unit micros tz
  | VVector arr -> VVector (Array.map (floor_temporal function_name unit) arr)
  | VNA _ -> (VNA NAGeneric)
  | _ ->
      Error.type_error
        (Printf.sprintf
           "Function `%s` expects a Date, Datetime, or Vector of them."
           function_name)

and ceiling_temporal function_name unit = function
  | VDate days as value ->
      (match floor_date_unit unit days with
       | VError _ as err -> err
       | floored ->
           if compare_temporal floored value = 0 then floored
           else next_date_boundary unit days)
  | VDatetime (micros, tz) as value ->
      let floored = floor_datetime_unit unit micros tz in
      if compare_temporal floored value = 0 then floored
      else next_datetime_boundary unit micros tz
  | VVector arr -> VVector (Array.map (ceiling_temporal function_name unit) arr)
  | VNA _ -> (VNA NAGeneric)
  | _ ->
      Error.type_error
        (Printf.sprintf
           "Function `%s` expects a Date, Datetime, or Vector of them."
           function_name)

and round_temporal function_name unit = function
  | (VDate _ | VDatetime _) as value ->
      let floored = floor_temporal function_name unit value in
      let ceiled = ceiling_temporal function_name unit value in
      (match floored, ceiled with
       | VError _ as err, _ -> err
       | _, (VError _ as err) -> err
       | _ ->
            if temporal_distance value floored <= temporal_distance ceiled value then
              floored
            else
             ceiled)
  | VVector arr -> VVector (Array.map (round_temporal function_name unit) arr)
  | VNA _ -> (VNA NAGeneric)
  | _ ->
      Error.type_error
        (Printf.sprintf
           "Function `%s` expects a Date, Datetime, or Vector of them."
           function_name)

let round_date_impl function_name kind args _env =
  match args with
  | [value; VString unit_name] ->
      (match parse_round_unit function_name unit_name with
       | Error err -> err
       | Ok unit ->
           (match kind with
            | `Floor -> floor_temporal function_name unit value
            | `Ceiling -> ceiling_temporal function_name unit value
            | `Round -> round_temporal function_name unit value))
  | [_; _] ->
      Error.type_error
        (Printf.sprintf "Function `%s` expects (Date|Datetime, String)." function_name)
  | values -> Error.arity_error_named function_name 2 (List.length values)

let rec relabel_timezone function_name timezone = function
  | VDatetime (micros, _) -> VDatetime (micros, Some timezone)
  | VVector arr -> VVector (Array.map (relabel_timezone function_name timezone) arr)
  | VNA _ -> (VNA NAGeneric)
  | _ ->
      Error.type_error
        (Printf.sprintf
           "Function `%s` expects a Datetime or Vector of datetimes."
           function_name)

let timezone_impl function_name args _env =
  match args with
  | [value; VString timezone] -> relabel_timezone function_name timezone value
  | [_; _] ->
      Error.type_error
        (Printf.sprintf "Function `%s` expects (Datetime, String)." function_name)
  | values -> Error.arity_error_named function_name 2 (List.length values)

let leap_year_impl args _env =
  let rec apply = function
    | VInt year -> VBool (is_leap_year year)
    | VDate days ->
        let year, _, _ = civil_from_days days in
        VBool (is_leap_year year)
    | VDatetime (micros, _) ->
        let year, _, _, _, _, _, _ = split_datetime_micros micros in
        VBool (is_leap_year year)
    | VVector arr -> VVector (Array.map apply arr)
    | VNA _ -> VNA NABool
    | _ ->
        Error.type_error
          "Function `is_leap_year` expects an Int year, Date, Datetime, or Vector of them."
  in
  match args with
  | [value] -> apply value
  | values -> Error.arity_error_named "is_leap_year" 1 (List.length values)

let rec days_in_month_impl args _env =
  match args with
  | [VInt year; VInt month] -> VInt (days_in_month year month)
  | [VDate days] ->
      let year, month, _ = civil_from_days days in
      VInt (days_in_month year month)
  | [VDatetime (micros, _)] ->
      let year, month, _, _, _, _, _ = split_datetime_micros micros in
      VInt (days_in_month year month)
  | [VVector arr] ->
      VVector (Array.map (fun value ->
        match days_in_month_impl [value] _env with
        | VError _ as err -> err
        | other -> other
      ) arr)
  | [_] ->
      Error.type_error "Function `days_in_month` expects (Int, Int) or a Date/Datetime."
  | [_; _] ->
      Error.type_error "Function `days_in_month` expects (Int, Int) or a Date/Datetime."
  | _ ->
      Error.make_error ArityError "Function `days_in_month` expects either 1 or 2 arguments."

let interval_impl args _env =
  let instant_and_tz = function
    | VDate days -> Ok (Int64.mul (Int64.of_int days) micros_per_day, None)
    | VDatetime (micros, tz) -> Ok (micros, tz)
    | _ -> Error (Error.type_error "Function `interval` expects Date or Datetime arguments.")
  in
  match args with
  | [start_value; end_value] ->
      (match instant_and_tz start_value, instant_and_tz end_value with
       | Ok (start_micros, start_tz), Ok (end_micros, end_tz) ->
           if Int64.compare start_micros end_micros > 0 then
             Error.value_error "Function `interval` requires `start` to be less than or equal to `end`."
           else
             VInterval {
               iv_start = start_micros;
               iv_end = end_micros;
               iv_tz = (match start_tz with Some _ -> start_tz | None -> end_tz);
             }
       | Error err, _ | _, Error err -> err)
  | values -> Error.arity_error_named "interval" 2 (List.length values)

let within_impl args _env =
  let rec apply interval = function
    | VDate days ->
        let instant = Int64.mul (Int64.of_int days) micros_per_day in
        VBool (Int64.compare instant interval.iv_start >= 0 && Int64.compare instant interval.iv_end <= 0)
    | VDatetime (micros, _) ->
        VBool (Int64.compare micros interval.iv_start >= 0 && Int64.compare micros interval.iv_end <= 0)
    | VVector arr -> VVector (Array.map (apply interval) arr)
    | VNA _ -> VNA NABool
    | _ ->
        Error.type_error "Function `%within%` expects a Date, Datetime, or Vector of them."
  in
  match args with
  | [value; VInterval interval] -> apply interval value
  | [_; _] -> Error.type_error "Function `%within%` expects (Date|Datetime, Interval)."
  | values -> Error.arity_error_named "%within%" 2 (List.length values)

(*
--# Parse dates from strings
--#
--# Parses strings or string vectors into Date values using an explicit format string.
--#
--# @name parse_date
--# @family chrono
--# @export
*)
(*
--# Parse datetimes from strings
--#
--# Parses strings or string vectors into Datetime values using an explicit format string and optional timezone.
--#
--# @name parse_datetime
--# @family chrono
--# @export
*)
(*
--# Get the current date
--#
--# Returns the current local date as a Date value.
--#
--# @name today
--# @family chrono
--# @export
*)
(*
--# Get the current datetime
--#
--# Returns the current datetime and accepts an optional timezone override.
--#
--# @name now
--# @family chrono
--# @export
*)
(*
--# Extract the year component
--#
--# Returns the calendar year from Date or Datetime values.
--#
--# @name year
--# @family chrono
--# @export
*)
(*
--# Extract or label the month
--#
--# Returns the month number, or month labels when requested, from Date or Datetime values.
--#
--# @name month
--# @family chrono
--# @export
*)
(*
--# Extract the day of month
--#
--# Returns the day-of-month component from Date or Datetime values.
--#
--# @name day
--# @family chrono
--# @export
*)
(*
--# Extract the day of month
--#
--# Alias for day() that returns the day-of-month component from Date or Datetime values.
--#
--# @name mday
--# @family chrono
--# @export
*)
(*
--# Extract the day of year
--#
--# Returns the day-of-year component from Date or Datetime values.
--#
--# @name yday
--# @family chrono
--# @export
*)
(*
--# Extract or label the weekday
--#
--# Returns weekday numbers, or weekday labels when requested, from Date or Datetime values.
--#
--# @name wday
--# @family chrono
--# @export
*)
(*
--# Extract the week number
--#
--# Returns the week number for Date or Datetime values.
--#
--# @name week
--# @family chrono
--# @export
*)
(*
--# Extract the ISO week number
--#
--# Returns the ISO week number for Date or Datetime values.
--#
--# @name isoweek
--# @family chrono
--# @export
*)
(*
--# Extract the ISO week-based year
--#
--# Returns the ISO week-based year for Date or Datetime values.
--#
--# @name isoyear
--# @family chrono
--# @export
*)
(*
--# Extract the quarter
--#
--# Returns the quarter number for Date or Datetime values.
--#
--# @name quarter
--# @family chrono
--# @export
*)
(*
--# Extract the semester
--#
--# Returns 1 for the first half of the year and 2 for the second half.
--#
--# @name semester
--# @family chrono
--# @export
*)
(*
--# Extract the hour
--#
--# Returns the hour component from Datetime values.
--#
--# @name hour
--# @family chrono
--# @export
*)
(*
--# Extract the minute
--#
--# Returns the minute component from Datetime values.
--#
--# @name minute
--# @family chrono
--# @export
*)
(*
--# Extract the second
--#
--# Returns the second component from Datetime values.
--#
--# @name second
--# @family chrono
--# @export
*)
(*
--# Extract the timezone label
--#
--# Returns the timezone string attached to a Datetime value.
--#
--# @name tz
--# @family chrono
--# @export
*)
(*
--# Create a period value
--#
--# Builds a period from named year, month, day, hour, minute, and second components.
--#
--# @name make_period
--# @family chrono
--# @export
*)
(*
--# Format dates as strings
--#
--# Formats Date values with a user-supplied format string.
--#
--# @name format_date
--# @family chrono
--# @export
*)
(*
--# Format datetimes as strings
--#
--# Formats Datetime values with a user-supplied format string.
--#
--# @name format_datetime
--# @family chrono
--# @export
*)
(*
--# Convert values to Date
--#
--# Converts strings, datetimes, and related temporal values to Date values.
--#
--# @name as_date
--# @family chrono
--# @export
*)
(*
--# Convert values to Datetime
--#
--# Converts strings, dates, and related temporal values to Datetime values.
--#
--# @name as_datetime
--# @family chrono
--# @export
*)
(*
--# Round dates down
--#
--# Rounds Date or Datetime values down to the requested unit boundary.
--#
--# @name floor_date
--# @family chrono
--# @export
*)
(*
--# Round dates up
--#
--# Rounds Date or Datetime values up to the requested unit boundary.
--#
--# @name ceiling_date
--# @family chrono
--# @export
*)
(*
--# Round dates to the nearest unit
--#
--# Rounds Date or Datetime values to the nearest requested unit boundary.
--#
--# @name round_date
--# @family chrono
--# @export
*)
(*
--# Convert a datetime to a new timezone
--#
--# Retains the instant in time while changing the displayed timezone label.
--#
--# @name with_tz
--# @family chrono
--# @export
*)
(*
--# Retag a datetime with a timezone
--#
--# Reinterprets local clock components under a new timezone label.
--#
--# @name force_tz
--# @family chrono
--# @export
*)
(*
--# Create an interval
--#
--# Builds an interval from two Date or Datetime endpoints.
--#
--# @name interval
--# @family chrono
--# @export
*)
(*
--# Test interval membership
--#
--# Returns true when a Date or Datetime value falls inside an interval.
--#
--# @name %within%
--# @family chrono
--# @export
*)
(*
--# Check for leap years
--#
--# Returns true when the supplied year or date falls in a leap year.
--#
--# @name is_leap_year
--# @family chrono
--# @export
*)
(*
--# Get the number of days in a month
--#
--# Returns the number of days in the month described by a date, datetime, or explicit year/month pair.
--#
--# @name days_in_month
--# @family chrono
--# @export
*)
(*
--# Construct a Date value
--#
--# Builds a Date value from named year, month, and day components.
--#
--# @name make_date
--# @family chrono
--# @export
*)
(*
--# Construct a Datetime value
--#
--# Builds a Datetime value from named date, time, and timezone components.
--#
--# @name make_datetime
--# @family chrono
--# @export
*)
(*
--# Check whether a time is before noon
--#
--# Returns true for Date values and for Datetime values whose hour is earlier than 12.
--#
--# @name am
--# @family chrono
--# @export
*)
(*
--# Check whether a time is after noon
--#
--# Returns true for Datetime values whose hour is 12 or later.
--#
--# @name pm
--# @family chrono
--# @export
*)
let register env =
  let parse_date_result s fmt =
    match parse_custom_format `Date s fmt None with
    | Some v -> v
    | None ->
        Error.value_error
          (Printf.sprintf
             "Function `parse_date` could not parse %S with format %S."
             s fmt)
  in
  let parse_date_vector_value fmt = function
    | VString s ->
        (match parse_custom_format `Date s fmt None with
         | Some v -> v
         | None -> (VNA NAGeneric))
    | VNA _ -> (VNA NAGeneric)
    | _ -> (VNA NAGeneric)
  in
  let parse_datetime_result tz s fmt =
    match parse_custom_format `Datetime s fmt tz with
    | Some v -> v
    | None ->
        Error.value_error
          (Printf.sprintf
             "Function `parse_datetime` could not parse %S with format %S."
             s fmt)
  in
  let parse_datetime_vector_value tz fmt = function
    | VString s ->
        (match parse_custom_format `Datetime s fmt tz with
         | Some v -> v
         | None -> (VNA NAGeneric))
    | VNA _ -> (VNA NAGeneric)
    | _ -> (VNA NAGeneric)
  in
  let scalar_date_component name fn =
    make_builtin ~name 1 (fun args _env ->
      match args with
      | [v] -> scalar_component name fn v
      | _ -> Error.arity_error_named name 1 (List.length args))
  in
  let add_simple_parser env name order =
    Env.add name (make_builtin ~name 1 (fun args _env ->
      match args with
      | [VVector arr] -> VVector (Array.map (parse_scalar_string_vectorized (parse_shorthand_date order)) arr)
      | [value] -> parse_scalar_string name (parse_shorthand_date order) value
      | _ -> Error.arity_error_named name 1 (List.length args))) env
  in
  let add_datetime_parser env name order count =
    Env.add name (make_builtin_named ~name ~variadic:true 1 (fun named_args _env ->
      match string_named_arg "tz" None named_args with
      | Error err -> err
      | Ok tz ->
          (match positional_args named_args with
           | [VVector arr] -> VVector (Array.map (parse_scalar_string_vectorized (parse_shorthand_datetime order count ?tz)) arr)
           | [value] -> parse_scalar_string name (parse_shorthand_datetime order count ?tz) value
           | values -> Error.arity_error_named name 1 (List.length values)))) env
  in
  let add_period_ctor env name f =
    Env.add name (make_builtin ~name 1 (fun args _env ->
      match args with
      | [VInt n] -> VPeriod (f n)
      | [VNA _] -> (VNA NAGeneric)
      | [_] -> Error.type_error (Printf.sprintf "Function `%s` expects an Int." name)
      | _ -> Error.arity_error_named name 1 (List.length args))) env
  in
  let add_predicate env name pred =
    Env.add name (make_builtin ~name 1 (fun args _env ->
      match args with
      | [v] -> VBool (pred v)
      | _ -> Error.arity_error_named name 1 (List.length args))) env
  in
  let env = add_simple_parser env "ymd" `YMD in
  let env = add_simple_parser env "mdy" `MDY in
  let env = add_simple_parser env "dmy" `DMY in
  let env = add_simple_parser env "ydm" `YDM in
  let env = add_datetime_parser env "ymd_h" `YMD 4 in
  let env = add_datetime_parser env "ymd_hm" `YMD 5 in
  let env = add_datetime_parser env "ymd_hms" `YMD 6 in
  let env = add_datetime_parser env "mdy_hms" `MDY 6 in
  let env = add_datetime_parser env "dmy_hms" `DMY 6 in
  let env =
    Env.add "parse_date"
      (make_builtin ~name:"parse_date" 2 (fun args _env ->
         match args with
         | [VString s; VString fmt] -> parse_date_result s fmt
         | [VVector arr; VString fmt] ->
             VVector (Array.map (parse_date_vector_value fmt) arr)
         | [_; _] ->
             Error.type_error
               "Function `parse_date` expects (String, String) or (Vector[String], String)."
         | _ ->
             Error.arity_error_named "parse_date" 2 (List.length args)))
      env
  in
  let env = Env.add "parse_datetime" (make_builtin_named ~name:"parse_datetime" ~variadic:true 2 (fun named_args _env ->
    match string_named_arg "tz" None named_args with
    | Error err -> err
    | Ok tz ->
        (match positional_args named_args with
         | [VString s; VString fmt] -> parse_datetime_result tz s fmt
         | [VVector arr; VString fmt] ->
             VVector (Array.map (parse_datetime_vector_value tz fmt) arr)
         | [_; _] -> Error.type_error "Function `parse_datetime` expects (String, String) or (Vector[String], String)."
         | values -> Error.arity_error_named "parse_datetime" 2 (List.length values)))) env in
  let env = Env.add "today" (make_builtin ~name:"today" 0 (fun _args _env -> current_date_value ())) env in
  let env = Env.add "now" (make_builtin_named ~name:"now" ~variadic:true 0 (fun named_args _env ->
    match string_named_arg "tz" None named_args with
    | Ok tz -> current_datetime_value tz
    | Error err -> err)) env in
  let env = Env.add "year" (scalar_date_component "year" (simple_component (fun (y, _, _) -> y))) env in
  let env = Env.add "month" (make_builtin_named ~name:"month" ~variadic:true 1 (fun named_args _env ->
    match bool_named_arg "label" false named_args with
    | Error err -> err
    | Ok label ->
        (match positional_args named_args with
         | [v] -> scalar_component "month" (month_value label) v
         | values -> Error.arity_error_named "month" 1 (List.length values)))) env in
  let env = Env.add "day" (scalar_date_component "day" (simple_component (fun (_, _, d) -> d))) env in
  let env = Env.add "mday" (scalar_date_component "mday" (simple_component (fun (_, _, d) -> d))) env in
  let env =
    Env.add "yday"
      (scalar_date_component "yday" (fun value ->
           match value with
           | VDate days ->
               let y, m, d = civil_from_days days in
               Some (VInt (day_of_year y m d))
           | VDatetime (micros, _) ->
               let y, m, d, _, _, _, _ = split_datetime_micros micros in
               Some (VInt (day_of_year y m d))
           | _ -> None))
      env
  in
  let env = Env.add "wday" (make_builtin_named ~name:"wday" ~variadic:true 1 (fun named_args _env ->
    match bool_named_arg "label" false named_args, int_named_arg "week_start" 7 named_args with
    | Ok label, Ok week_start ->
        let rec fn value =
          match value with
          | VDate days ->
              let base = sunday_wday_from_days days in
              let start_base = if week_start = 7 then 1 else week_start + 1 in
              let adjusted = positive_mod (base - start_base) 7 + 1 in
              Some (if label then VString weekday_abbrevs.(base - 1) else VInt adjusted)
          | VDatetime (micros, _) ->
              let y, m, d, _, _, _, _ = split_datetime_micros micros in
              fn (VDate (days_from_civil y m d))
          | _ -> None
        in
        (match positional_args named_args with
         | [v] -> scalar_component "wday" fn v
         | values -> Error.arity_error_named "wday" 1 (List.length values))
    | Error err, _ | _, Error err -> err)) env in
  let week_component value =
    match value with
    | VDate days -> Some (VInt (snd (iso_week_and_year days)))
    | VDatetime (micros, _) ->
        let y, m, d, _, _, _, _ = split_datetime_micros micros in
        Some (VInt (snd (iso_week_and_year (days_from_civil y m d))))
    | _ -> None
  in
  let env = Env.add "week" (scalar_date_component "week" week_component) env in
  let env = Env.add "isoweek" (scalar_date_component "isoweek" week_component) env in
  let env =
    Env.add "isoyear"
      (scalar_date_component "isoyear" (fun value ->
           match value with
           | VDate days -> Some (VInt (fst (iso_week_and_year days)))
           | VDatetime (micros, _) ->
               let y, m, d, _, _, _, _ = split_datetime_micros micros in
               Some (VInt (fst (iso_week_and_year (days_from_civil y m d))))
           | _ -> None))
      env
  in
  let env =
    Env.add "quarter"
      (scalar_date_component "quarter" (fun value ->
           match month_value false value with
           | Some (VInt month) -> Some (VInt (((month - 1) / 3) + 1))
           | _ -> None))
      env
  in
  let env =
    Env.add "semester"
      (scalar_date_component "semester" (fun value ->
           match month_value false value with
           | Some (VInt month) -> Some (VInt (((month - 1) / 6) + 1))
           | _ -> None))
      env
  in
  let env =
    Env.add "hour"
      (scalar_date_component "hour" (fun value ->
           match value with
           | VDate _ -> Some (VInt 0)
           | VDatetime (micros, _) ->
               let _, _, _, h, _, _, _ = split_datetime_micros micros in
               Some (VInt h)
           | _ -> None))
      env
  in
  let env =
    Env.add "minute"
      (scalar_date_component "minute" (fun value ->
           match value with
           | VDate _ -> Some (VInt 0)
           | VDatetime (micros, _) ->
               let _, _, _, _, m, _, _ = split_datetime_micros micros in
               Some (VInt m)
           | _ -> None))
      env
  in
  let env =
    Env.add "second"
      (scalar_date_component "second" (fun value ->
           match value with
           | VDate _ -> Some (VFloat 0.0)
           | VDatetime (micros, _) ->
               let _, _, _, _, _, s, us = split_datetime_micros micros in
               Some (VFloat (float_of_int s +. (float_of_int us /. 1_000_000.0)))
           | _ -> None))
      env
  in
  let env =
    Env.add "tz"
      (scalar_date_component "tz" (fun value ->
           match value with
           | VDate _ | VDatetime (_, None) -> Some (VString "UTC")
           | VDatetime (_, Some zone) -> Some (VString zone)
           | _ -> None))
      env
  in
  let env = add_period_ctor env "years" (fun n -> { empty_period with p_years = n }) in
  let env = add_period_ctor env "months" (fun n -> { empty_period with p_months = n }) in
  let env = add_period_ctor env "weeks" (fun n -> { empty_period with p_days = n * 7 }) in
  let env = add_period_ctor env "days" (fun n -> { empty_period with p_days = n }) in
  let env = add_period_ctor env "hours" (fun n -> { empty_period with p_hours = n }) in
  let env = add_period_ctor env "minutes" (fun n -> { empty_period with p_minutes = n }) in
  let env = add_period_ctor env "seconds" (fun n -> { empty_period with p_seconds = n }) in
  let env = add_period_ctor env "milliseconds" (fun n -> { empty_period with p_micros = n * 1000 }) in
  let env = add_period_ctor env "microseconds" (fun n -> { empty_period with p_micros = n }) in
  let env = add_period_ctor env "nanoseconds" (fun n -> { empty_period with p_micros = n / 1000 }) in
  let env =
    Env.add "make_period"
      (make_builtin_named ~name:"make_period" ~variadic:true 0 (fun named_args _env ->
         let get_int name =
           match find_named_arg name named_args with
           | Some (VInt n) -> Ok n
           | None -> Ok 0
           | Some v ->
               Error
                 (Error.type_error
                    (Printf.sprintf
                       "Argument `%s` must be Int, got %s."
                       name (Utils.type_name v)))
         in
         let ( let* ) result f =
           match result with
           | Ok value -> f value
           | Error err -> Error err
         in
         match
           let* years = get_int "years" in
           let* months = get_int "months" in
           let* days = get_int "days" in
           let* hours = get_int "hours" in
           let* minutes = get_int "minutes" in
           let* seconds = get_int "seconds" in
           Ok { empty_period with
                p_years = years;
                p_months = months;
                p_days = days;
                p_hours = hours;
                p_minutes = minutes;
                p_seconds = seconds; }
         with
         | Ok period -> VPeriod period
         | Error err -> err))
      env
  in
  let env =
    List.fold_left (fun env (name, getter) ->
      Env.add name (make_builtin ~name 1 (fun args _env ->
        match args with
        | [VPeriod p] -> VInt (getter p)
        | [_] -> Error.type_error (Printf.sprintf "Function `%s` expects a Period." name)
        | _ -> Error.arity_error_named name 1 (List.length args))) env
    ) env [
      ("period_years", (fun p -> p.p_years));
      ("period_months", (fun p -> p.p_months));
      ("period_days", (fun p -> p.p_days));
      ("period_hours", (fun p -> p.p_hours));
      ("period_minutes", (fun p -> p.p_minutes));
      ("period_seconds", (fun p -> p.p_seconds));
    ]
  in
  let env = Env.add "format_date" (make_builtin ~name:"format_date" 2 (fun args _env ->
    match args with
    | [VDate days; VString fmt] -> VString (format_datetime_value (Int64.mul (Int64.of_int days) micros_per_day) None fmt)
    | [VDatetime (micros, tz); VString fmt] -> VString (format_datetime_value micros tz fmt)
    | [_; _] -> Error.type_error "Function `format_date` expects (Date, String)."
    | _ -> Error.arity_error_named "format_date" 2 (List.length args))) env in
  let env = Env.add "format_datetime" (make_builtin ~name:"format_datetime" 2 (fun args _env ->
    match args with
    | [VDate days; VString fmt] -> VString (format_datetime_value (Int64.mul (Int64.of_int days) micros_per_day) None fmt)
    | [VDatetime (micros, tz); VString fmt] -> VString (format_datetime_value micros tz fmt)
    | [_; _] -> Error.type_error "Function `format_datetime` expects (Date|Datetime, String)."
    | _ -> Error.arity_error_named "format_datetime" 2 (List.length args))) env in
  let env = Env.add "as_date" (make_builtin_named ~name:"as_date" ~variadic:true 1 (fun named_args _env ->
    let origin =
      match string_named_arg "origin" None named_args with
      | Error err -> Error err
      | Ok None -> Ok 0
      | Ok (Some origin) ->
          (match parse_shorthand_date `YMD origin with
           | Some (VDate days) -> Ok days
           | _ -> Error (Error.value_error (Printf.sprintf "Function `as_date` could not parse origin %S." origin)))
    in
    match origin with
    | Error err -> err
    | Ok origin_days ->
        (match positional_args named_args with
         | [VDate d] -> VDate d
         | [VDatetime (micros, _)] -> VDate (Int64.to_int (floor_div_int64 micros micros_per_day))
         | [VString s] -> (match parse_shorthand_date `YMD s with Some v -> v | None -> Error.value_error (Printf.sprintf "Function `as_date` could not parse %S as a date." s))
         | [VInt n] -> VDate (origin_days + n)
         | [VFloat f] -> VDate (origin_days + int_of_float f)
         | [VNA _] -> (VNA NAGeneric)
         | [_] -> Error.type_error "Function `as_date` expects a String, Date, Datetime, Int, or Float."
         | values -> Error.arity_error_named "as_date" 1 (List.length values)))) env in
  let env = Env.add "as_datetime" (make_builtin_named ~name:"as_datetime" ~variadic:true 1 (fun named_args _env ->
    let origin =
      match string_named_arg "origin" None named_args with
      | Error err -> Error err
      | Ok None -> Ok 0
      | Ok (Some origin) ->
          (match parse_shorthand_date `YMD origin with
           | Some (VDate days) -> Ok days
           | _ -> Error (Error.value_error (Printf.sprintf "Function `as_datetime` could not parse origin %S." origin)))
    in
    match origin, string_named_arg "tz" None named_args with
    | Error err, _ | _, Error err -> err
    | Ok origin_days, Ok tz ->
        (match positional_args named_args with
         | [VDate days] -> VDatetime (Int64.mul (Int64.of_int days) micros_per_day, tz)
         | [VDatetime (micros, tz0)] -> VDatetime (micros, (match tz with Some _ -> tz | None -> tz0))
         | [VString s] ->
             (match parse_shorthand_datetime `YMD 6 ?tz s with
              | Some v -> v
              | None -> (match parse_custom_format `Datetime s "%Y-%m-%d %H:%M:%S" tz with Some v -> v | None -> Error.value_error (Printf.sprintf "Function `as_datetime` could not parse %S as a datetime." s)))
         | [VInt n] ->
             VDatetime (
               Int64.add
                 (Int64.mul (Int64.of_int origin_days) micros_per_day)
                 (Int64.mul (Int64.of_int n) micros_per_second),
               tz)
         | [VFloat f] ->
             VDatetime (
               Int64.add
                 (Int64.mul (Int64.of_int origin_days) micros_per_day)
                 (Int64.of_float (f *. 1_000_000.0)),
               tz)
         | [VNA _] -> (VNA NAGeneric)
         | [_] -> Error.type_error "Function `as_datetime` expects a String, Date, Datetime, Int, or Float."
         | values -> Error.arity_error_named "as_datetime" 1 (List.length values)))) env in
  let env = add_predicate env "is_date" (function VDate _ -> true | _ -> false) in
  let env = add_predicate env "is_datetime" (function VDatetime _ -> true | _ -> false) in
  let env = add_predicate env "is_period" (function VPeriod _ -> true | _ -> false) in
  let env = add_predicate env "is_duration" (function VDuration _ -> true | _ -> false) in
  let env = add_predicate env "is_interval" (function VInterval _ -> true | _ -> false) in
  let env = Env.add "floor_date" (make_builtin ~name:"floor_date" 2 (round_date_impl "floor_date" `Floor)) env in
  let env = Env.add "ceiling_date" (make_builtin ~name:"ceiling_date" 2 (round_date_impl "ceiling_date" `Ceiling)) env in
  let env = Env.add "round_date" (make_builtin ~name:"round_date" 2 (round_date_impl "round_date" `Round)) env in
  let env = Env.add "with_tz" (make_builtin ~name:"with_tz" 2 (timezone_impl "with_tz")) env in
  let env = Env.add "force_tz" (make_builtin ~name:"force_tz" 2 (timezone_impl "force_tz")) env in
  let env = Env.add "interval" (make_builtin ~name:"interval" 2 interval_impl) env in
  let env = Env.add "%within%" (make_builtin ~name:"%within%" 2 within_impl) env in
  let env = Env.add "is_leap_year" (make_builtin ~name:"is_leap_year" 1 leap_year_impl) env in
  let env = Env.add "days_in_month" (make_builtin ~name:"days_in_month" ~variadic:true 1 days_in_month_impl) env in
  let env = Env.add "make_date" (make_builtin_named ~name:"make_date" ~variadic:true 0 (fun named_args _env ->
    let get_int name default = match int_named_arg name default named_args with Ok v -> Ok v | Error e -> Error e in
    let ( let* ) result f = match result with Ok value -> f value | Error err -> Error err in
    match
      let* year = get_int "year" 1970 in
      let* month = get_int "month" 1 in
      let* day = get_int "day" 1 in
      Ok (year, month, day)
    with
    | Ok (y, m, d) ->
        if is_valid_date y m d then
          VDate (days_from_civil y m d)
        else
          Error.value_error (Printf.sprintf "Invalid date components: %04d-%02d-%02d" y m d)
    | Error err -> err)) env in
  let env = Env.add "make_datetime" (make_builtin_named ~name:"make_datetime" ~variadic:true 0 (fun named_args _env ->
    let get_int name default = match int_named_arg name default named_args with Ok v -> Ok v | Error e -> Error e in
    let ( let* ) result f = match result with Ok value -> f value | Error err -> Error err in
    match
      let* year = get_int "year" 1970 in
      let* month = get_int "month" 1 in
      let* day = get_int "day" 1 in
      let* hour = get_int "hour" 0 in
      let* min = get_int "min" 0 in
      let* sec = get_int "sec" 0 in
      let* tz = string_named_arg "tz" (Some "UTC") named_args in
      Ok (year, month, day, hour, min, sec, tz)
    with
    | Ok (y, mo, d, h, m, s, tz) ->
        if is_valid_date y mo d && is_valid_time h m s 0 then
          VDatetime (datetime_of_components y mo d h m s 0, tz)
        else
          Error.value_error (Printf.sprintf "Invalid datetime components: %04d-%02d-%02d %02d:%02d:%02d" y mo d h m s)
    | Error err -> err)) env in
  let env =
    Env.add "am"
      (scalar_date_component "am" (fun value ->
           match value with
           | VDate _ -> Some (VBool true)
           | VDatetime (micros, _) ->
               let _, _, _, h, _, _, _ = split_datetime_micros micros in
               Some (VBool (h < 12))
           | _ -> None))
      env
  in
  let env =
    Env.add "pm"
      (scalar_date_component "pm" (fun value ->
           match value with
           | VDate _ -> Some (VBool false)
           | VDatetime (micros, _) ->
               let _, _, _, h, _, _, _ = split_datetime_micros micros in
               Some (VBool (h >= 12))
           | _ -> None))
      env
  in
  env

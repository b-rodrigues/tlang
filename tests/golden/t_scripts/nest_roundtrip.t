df = read_csv("tests/golden/data/mtcars.csv")

-- Test 1: Roundtrip nest/unnest
-- Note: nest($mpg, $hp) will group by all other columns
nt_round = df |> nest($mpg, $hp) |> unnest($data) |> select(
  $car_name, $mpg, $cyl, $disp, $hp, $drat, $wt, $qsec, $vs, $am, $gear, $carb
) |> arrange($car_name)
write_csv(nt_round, "tests/golden/t_outputs/mtcars_nest_unnest.csv")

-- Test 2: Grouped nest/unnest
nt_grouped = df |> group_by($cyl) |> nest(data = [$mpg, $hp]) |> unnest($data) |> select(
  $car_name, $mpg, $cyl, $disp, $hp, $drat, $wt, $qsec, $vs, $am, $gear, $carb
) |> arrange($car_name)
write_csv(nt_grouped, "tests/golden/t_outputs/mtcars_nest_grouped.csv")

print("✓ nest_roundtrip tests complete")

-- Test 3: Grouped nest/unnest with implicit column selection
nt_grouped_implicit = df |> group_by($cyl) |> nest() |> unnest($data) |> select(
  $car_name, $mpg, $cyl, $disp, $hp, $drat, $wt, $qsec, $vs, $am, $gear, $carb
) |> arrange($car_name)
write_csv(nt_grouped_implicit, "tests/golden/t_outputs/mtcars_nest_grouped_implicit.csv")

print("✓ nest_grouped_implicit test complete")

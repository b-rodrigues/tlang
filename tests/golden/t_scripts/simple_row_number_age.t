-- Test: row_number window function on simple.age
-- Compares to: dplyr::mutate(row_number_age = row_number(age))
df = read_csv("tests/golden/data/simple.csv")
result = mutate(df, "row_number_age", row_number(df.age))
write_csv(result, "tests/golden/t_outputs/simple_row_number_age.csv")
print("✓ row_number(age) complete")

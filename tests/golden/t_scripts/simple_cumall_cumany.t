-- Test: cumall and cumany window functions on simple dataset
-- Compares to: dplyr::mutate(high_score = score > 85, cumall_high = cumall(high_score), cumany_high = cumany(high_score))
df = read_csv("tests/golden/data/simple.csv")
df2 = mutate(df, "high_score", \(row) row.score > 85)
df3 = mutate(df2, "cumall_high", cumall(df2.high_score))
result = mutate(df3, "cumany_high", cumany(df3.high_score))
write_csv(result, "tests/golden/t_outputs/simple_cumall_cumany.csv")
print("✓ cumall/cumany complete")

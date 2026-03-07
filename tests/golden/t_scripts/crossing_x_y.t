-- Test: crossing(x = [1, 2, 3], y = ["a", "b"])
result = crossing(x = [1, 2, 3], y = ["a", "b"])
write_csv(result, "tests/golden/t_outputs/crossing_x_y.csv")
print("✓ crossing_x_y complete")

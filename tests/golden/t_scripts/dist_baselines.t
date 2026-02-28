-- Test: distribution primitives
result = dataframe([
  [
    pnorm_1: pnorm(1.0),
    pnorm_196: pnorm(1.96),
    pt_2_10: pt(2.0, 10),
    pf_3_2_30: pf(3.0, 2, 30),
    pchisq_384_1: pchisq(3.84, 1)
  ]
])

print("DataFrame created:")
print(result)

res = write_csv(result, "tests/golden/t_outputs/dist_baselines.csv")
if (is_error(res)) {
  print("Error writing dist_baselines.csv:")
  print(res)
} else {
  print("✓ dist_baselines complete")
}

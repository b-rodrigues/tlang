-- Test: residuals() (response & pearson) for mpg ~ wt
df = read_csv("tests/golden/data/mtcars.csv")
model = lm(mpg ~ wt, data: df)
res_resp = residuals(df, model, type: "response")
res_pear = residuals(df, model, type: "pearson")

-- Build a DataFrame of residual results using explicit vector assignment
result1 = mutate(res_resp, response: res_resp.resid)
result2 = select(result1, $response)
result_final = mutate(result2, pearson: res_pear.resid)

write_csv(result_final, "tests/golden/t_outputs/lm_residuals_m1.csv")
print("✓ lm_residuals_m1 complete")

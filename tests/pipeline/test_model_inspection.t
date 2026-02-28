df = read_csv("tests/pipeline/data/mtcars.csv", separator: "|")
model = lm(mpg ~ wt + hp, data: df, name: "mtcars_model")

print("nobs:", nobs(model))
print("df_residual:", df_residual(model))
print("sigma:", sigma(model))

print("VCOV:")
v = vcov(model)
print(v)

print("Residuals:")
r = residuals(df, model)
glimpse(r)

print("Augment:")
aug = augment(df, model)
glimpse(head(aug))

print("Score:")
s = score(df, model)
print(s)

-- Compare with itself
comp = compare(model, model)
print("Compare Wide:")
print(comp)

print("SUCCESS")

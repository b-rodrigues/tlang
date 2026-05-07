df = dataframe([x: [1, 2, 3, 4], y: [1, 2, 2, 4]])
model = lm(data = df, formula = y ~ x, weights = [1, 1, 2, 2])
print(model)

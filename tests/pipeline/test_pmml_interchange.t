-- test_pmml_interchange.t

model_node = node(
    command = <{
        # In R
        data <- read.csv("data/mtcars.csv", sep="|", header=TRUE)
        fit <- lm(mpg ~ wt + hp, data = data)
        fit
    }>,
    runtime = "R",
    serializer = "pmml"
)

-- Native T prediction
preds_node = node(
    command = <{
        model = model_node
        
        print("Model coefficients:")
        print(model.coefficients)
        
        print("Tidy summary via summary(model):")
        print(summary(model))
        
        -- Use the CSV data
        test_df = read_csv("data/mtcars.csv", separator: "|")
        
        p = predict(test_df, model)
        print("Predictions:")
        print(p)
        p
    }>,
    runtime = "T",
    deserializer = "pmml"
)

p = pipeline {
    model_node = model_node
    preds_node = preds_node
}

print("Building pipeline...")
res = build_pipeline(p)

-- Verify
results = read_node("preds_node")
print("Verified Predictions in T:")
print(results)

-- Final check
expected = [23.5723294033, 22.583482564, 25.2758187247]
-- Check first value
if (abs(get(results, 0) - get(expected, 0)) < 0.001) {
    print("Test Passed: Native T predictions match R model via PMML")
} else {
    print("Test Failed: Predictions do not match expectations")
}

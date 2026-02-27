import stats
import dataframe

-- Create sample data
data = [
    [x: 1.0, y: 0.0],
    [x: 2.0, y: 0.0],
    [x: 3.0, y: 1.0],
    [x: 4.0, y: 1.0],
    [x: 5.0, y: 1.0]
]
df = dataframe(data)

p = pipeline {
    data_node = node(
        command = <{ df }>,
        runtime = T,
        serializer = "arrow"
    );
    
    model_node = node(
        command = <{
            # data_node is available as an R object (data.frame)
            fit <- glm(y ~ x, data = data_node, family = binomial(link = "logit"))
            # t_write_pmml is provided by the bridge
            t_write_pmml(fit, "$out/artifact")
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

-- Build the pipeline
-- We need to provide the 'df' as an initial value for data_node if it wasn't a node
-- But here data_node just returns df.

print("Building GLM pipeline...")
res = build_pipeline(p)
print("Pipeline build successful.")

model = read_node("model_node")

print("Model Class:")
print(model.class)

print("Model Family:")
print(model.family)

print("Model Link:")
print(model.link)

print("Coefficients:")
print(model.coefficients)

preds = predict(df, model)
print("Predictions type:")
print(type(preds))
print("Predictions:")
print(preds)

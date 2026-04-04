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
        command = <{
            data.frame(
                x = c(1.0, 2.0, 3.0, 4.0, 5.0),
                y = c(0.0, 0.0, 1.0, 1.0, 1.0)
            )
        }>,
        runtime = R,
        serializer = "arrow"
    );
    
    model_node = node(
        command = <{
            data_node$y <- as.factor(data_node$y)
            glm(y ~ x, data = data_node, family = binomial(link = "logit"))
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

print("Building GLM (R) pipeline...")
res = build_pipeline(p, verbose=1)
print("Build Result:")
print(res)
print("----------------")

model = read_node("model_node")

print("Model Summary:")
print(summary(model))

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

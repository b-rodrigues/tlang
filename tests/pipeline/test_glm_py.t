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
            import statsmodels.api as sm
            import pandas as pd
            # data_node is a pandas DataFrame
            y = data_node['y']
            X = sm.add_constant(data_node['x'])
            sm.GLM(y, X, family=sm.families.Binomial()).fit()
            # t_write_pmml uses the JPMML-StatsModels bridge for this
        }>,
        runtime = Python,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

print("Building GLM (Python) pipeline...")
res = build_pipeline(p, verbose=1)
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

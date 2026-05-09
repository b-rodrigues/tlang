# t_score_pmml

Score a PMML model using JPMML

Evaluates a PMML model against a DataFrame using the JPMML-evaluator library. Requires a Java runtime and the JPMML-evaluator JAR to be available.

## Parameters

- **df** (`DataFrame`): The data to score.

- **model** (`Dict`): The PMML model dictionary (loaded via `t_read_pmml`).


## Returns

| DataFrame The model predictions.


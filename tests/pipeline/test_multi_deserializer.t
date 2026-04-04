-- tests/pipeline/test_multi_deserializer.t

data_node = node(
    command = <{
# In Python
import pandas as pd
data_node = {"x": [1, 2, 3], "y": [4, 5, 6]}
    }>,
    runtime = "Python",
    serializer = "json"
)

model_node = node(
    command = <{
# In R
data <- data.frame(mpg=c(21.0, 21.0, 22.8), wt=c(2.62, 2.875, 2.32), hp=c(110, 110, 93))
model_node <- lm(mpg ~ wt+hp, data = data)
    }>,
    runtime = "R",
    serializer = "pmml"
)

combined_node = node(
    command = <{
        print("Data from Python (JSON):")
        print(data_node)
        
        print("Model from R (PMML):")
        print(model_node.coefficients)
        
        -- Verify types
        -- JSON dicts in T are VDict
        if (type(data_node) != "Dict") {
            print("FAILED: data_node should be a Dict, got", type(data_node))
            exit(1)
        } else {
            print("data_node is a Dict")
        }
        
        -- PMML models in T are VDict
        if (type(model_node) != "Dict") {
            print("FAILED: model_node should be a Dict, got", type(model_node))
            exit(1)
        } else {
            print("model_node is a Dict")
        }
        
        "SUCCESS"
    }>,
    runtime = "T",
    deserializer = [data_node: "json", model_node: "pmml"]
)

p = pipeline {
    data_node = data_node
    model_node = model_node
    combined_node = combined_node
}

print("Populating and building multi-deserializer pipeline...")
res = build_pipeline(p, verbose=1)

if (is_error(res)) {
    print("FATAL: Pipeline build failed!")
    print(res)
    exit(1)
} else {
    print("Pipeline populated and built.")
}

final_val = read_node("combined_node")
print("Final result from combined node:", final_val)

if (final_val == "SUCCESS") {
    print("SUCCESS: Multi-deserializer map integration test passed!")
    0
} else {
    print("FAILED: Multi-deserializer map returned", final_val)
    exit(1)
}

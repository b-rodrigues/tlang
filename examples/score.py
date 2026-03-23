# examples/score.py

# T automatically detects dependencies. If you use 'model_r' here,
# the 'scored' node will depend on 'model_r' and provide its value.
# (If 'scored' has deserializer='pmml', model_r will be a PMML model object).

# In the Python runtime, dependencies are provided as global variables 
# matching their node names.
try:
    print(f"Python node: received model_r with type {type(model_r)}")
except NameError:
    print("Python node: model_r not available (check dependency detection)")

# T expects the node's result to be assigned to a variable 
# matching the node's name (in this case, 'scored').
scored = {
    "status": "success",
    "prediction": 123.45,
    "has_model": 'model_r' in globals()
}

# The generated runner will automatically serialize 'scored' to $out/artifact.

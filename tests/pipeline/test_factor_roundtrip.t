-- tests/pipeline/test_factor_roundtrip.t
-- Roundtrip test for Factors: R -> T -> Python -> R

node_r = node(
    command = <{
        df_r <- data.frame(
            id = 1:3,
            cat = factor(c("low", "high", "medium"), levels = c("low", "medium", "high")),
            stringsAsFactors = FALSE
        )
        print("R: Created data frame with factor")
        print(df_r)
        print(str(df_r))
        df_r
    }>,
    runtime = R,
    serializer = "arrow"
)

node_t = node(
    command = <{
        print("T: Received data from R")
        glimpse(node_r)
        
        -- Check the 'cat' column type in T
        -- Note: Arrow deserialization of dictionary-encoded arrays is not yet
        -- fully implemented in the FFI path, so the column may arrive as String
        -- rather than Factor. We log the type for diagnostic purposes only.
        cat_col = pull(node_r, $cat)
        first_val = get(cat_col, 0)
        print(str_join("T: Type of 'cat' column first value: ", type(first_val)))
        
        -- Pass it through
        node_r
    }>,
    runtime = T,
    deserializer = "arrow",
    serializer = "arrow"
)

node_py = node(
    command = <{
import pandas as pd
print("Python: Received data from T")
print(node_t.dtypes)
print(node_t)

# In pandas, factors are Categorical
if not isinstance(node_t['cat'].dtype, pd.CategoricalDtype):
     print("ERROR: Expected Categorical type in Python")
     import sys
     sys.exit(1)
     
print("Python: Verified Categorical type")
# Add a row
new_row = pd.DataFrame({'id': [4], 'cat': ['medium']})
new_row['cat'] = new_row['cat'].astype(node_t['cat'].dtype)
output = pd.concat([node_t, new_row], ignore_index=True)
print("Python: final df:")
print(output)
output
    }>,
    runtime = Python,
    deserializer = "arrow",
    serializer = "arrow"
)

node_r_final = node(
    command = <{
        print("R: Received data from Python")
        print(node_py)
        print(str(node_py))
        
        if (!is.factor(node_py$cat)) {
            stop("ERROR: Expected factor in R final node")
        }
        
        expected_levels <- c("low", "medium", "high")
        if (!all(levels(node_py$cat) == expected_levels)) {
            print("Actual levels:")
            print(levels(node_py$cat))
            stop("ERROR: Level mismatch in R final node")
        }
        
        print("R: Final verification SUCCESS")
        node_py
    }>,
    runtime = R,
    deserializer = "arrow",
    serializer = "arrow"
)

p = pipeline {
    node_r = node_r
    node_t = node_t
    node_py = node_py
    node_r_final = node_r_final
}

print("Building Factor Roundtrip Pipeline...")
build_res = build_pipeline(p, verbose=1)
if (is_error(build_res)) {
    print("FATAL: Pipeline build failed:")
    print(build_res)
    exit(1)
}

print("Reading final result in T:")
res = read_node("node_r_final")
if (is_error(res)) {
    print("FATAL: Failed to read node_r_final:")
    print(res)
    exit(1)
}

glimpse(res)

if (nrow(res) != 4) {
    print("ERROR: Expected 4 rows in final result")
    exit(1)
}

print("SUCCESS: Factor Roundtrip Pipeline completed!")

-- Test Arrow interchange between R and Python
-- Phase 2 of sandbox-interchange-protocol.md

df_r = node(
    command = <{
df_r <- data.frame(
    id = 1:5,
    val = c(1.1, 2.2, 3.3, 4.4, 5.5),
    label = c("A", "B", "C", "D", "E"),
    flag = c(TRUE, FALSE, TRUE, FALSE, TRUE)
)
    }>,
    runtime = R,
    serializer = "arrow"
)

df_py = node(
    command = <{
print("Python received Arrow data:")
print(df_r)
# Calculate something to return
res = df_r.copy()
res['val'] = res['val'] * 2
df_py = res
    }>,
    runtime = Python,
    deserializer = "arrow",
    serializer = "arrow"
)

final_t = node(
    command = <{
print("T received Arrow data from Python:")
glimpse(df_py)
df_py
    }>,
    runtime = T,
    deserializer = "arrow"
)

p = pipeline {
    df_r = df_r
    df_py = df_py
    final_t = final_t
}

print("Building pipeline...")
build_pipeline(p, verbose=1)

print("Reading df_py from Arrow file in T:")
df_res = read_node("df_py")
glimpse(df_res)

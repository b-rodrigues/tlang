p = pipeline {
    w_node = node(
        command = <{ [1, 2, 3] }>
    )

}

populate_pipeline(p, build=true, verbose=1)
res = read_node(p, "w_node")
print(res)
print(res.warnings)

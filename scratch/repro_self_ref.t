p = pipeline {
    processed_data = node(command = <{ 1 }>, runtime = Python)
    julia_flux_model = jln(
        processed_data,
        command = <{
            julia_flux_model = 42
        }>,
        serializer = [something: processed_data]
    )
}
print(p)

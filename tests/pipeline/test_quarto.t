-- Quarto Runtime Test
--
-- This pipeline tests the Quarto runtime by generating data in T
-- and rendering a .qmd file that consumes that data via read_node().

p = pipeline {
  data = "Success: Data read from T-Lang"
  
  report = node(
    script = "tests/pipeline/test_quarto.qmd",
    runtime = Quarto,
    args = [
      to: "html",
      standalone: true
    ]
  )
}

-- build=true triggers nix-build
populate_pipeline(p, build=true)

-- Test pipeline_copy
print("Copying results to local directory...")
res = pipeline_copy()
print(res)

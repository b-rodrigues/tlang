-- Pipeline Integration Test — Build Script
--
-- Exercises the full pipeline lifecycle with real data.
-- This script mirrors the hello_t_pipeline demo.
-- Data: mtcars.csv (pipe-separated) downloaded from rixpress_demos.

p = pipeline {
  -- Load mtcars data (pipe-separated)
  mtcars = read_csv("data/mtcars.csv", separator = "|")

  -- Basic stats on miles per gallon
  avg_mpg = mtcars.mpg |> mean
  sd_mpg  = mtcars.mpg |> sd

  -- Filter to 6-cylinder cars
  six_cyl = mtcars |> filter($cyl == 6)

  -- Average horsepower of 6-cyl cars
  avg_hp_6cyl = six_cyl.hp |> mean
}

populate_pipeline(p, build=true)


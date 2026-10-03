# Unit Test Audit

## Goal

Review all unit tests, one by one.
Make sure each test tests what its name says.
Remove placeholders.
Remove false assertions.
Keep only strong tests.

## Scope

Source of truth is `tests/test_runner.ml`.
It contains 109 test modules.
Test code lives in `tests/` and subfolders.
Review in `test_runner.ml` order.
Do not skip a module.

Order:

1. Test_arithmetic
2. Test_comparisons
3. Test_logical
4. Test_in
5. Test_operators
6. Test_scalar_strictness
7. Test_typing_mode
8. Test_bitwise_error
9. Test_variables
10. Test_functions
11. Test_strings
12. Test_pipe
13. Test_ifelse
14. Test_match
15. Test_lists
16. Test_dicts
17. Test_builtins
18. Test_chrono
19. Test_rng
20. Test_shell
21. Test_lsp_support
22. Test_sh_node
23. Test_converters
24. Test_na
25. Test_na_edge_cases
26. Test_errors
27. Test_records
28. Test_unions
29. Test_expect_equal
30. Test_expect_more
31. Test_expect_condition
32. Test_expect_pipeline
33. Test_expect_pass_fail_msg
34. Test_expect_ds_coverage
35. Test_property
36. Test_property_base
37. Test_property_testcraft
38. Test_property_verbs
39. Test_property_math
40. Test_property_strcraft
41. Test_property_core
42. Test_property_chrono
43. Test_property_stats
44. Test_property_dataframe
45. Test_property_lens
46. Test_property_explain
47. Test_property_pipeline
48. Test_reserved_names
49. Test_fetchurl
50. Test_dataframe
51. Test_pipeline
52. Test_shell_diff
53. Test_julia_diff
54. Test_strategy_closed
55. Test_colcraft
56. Test_colcraft_coverage
57. Test_window
58. Test_math
59. Test_stats
60. Test_stats_coverage
61. Test_pmml_random_forest
62. Test_pmml_io
63. Test_pmml_xgboost
64. Test_pmml_lightgbm
65. Test_onnx_native
66. Test_broom_golden
67. Test_explain_tests
68. Test_cli
69. Test_demo
70. Test_golden
71. Test_boolean_golden
72. Test_core_semantics
73. Test_arrow_integration
74. Test_owl_bridge
75. Test_arrow_performance
76. Test_colcraft_edge_cases
77. Test_window_edge_cases
78. Test_formula_edge_cases
79. Test_large_datasets
80. Test_error_recovery
81. Test_package_manager
82. Test_toml_parser
83. Test_lens
84. Test_serializers
85. Test_quotation
86. Test_pipeline_ops
87. Test_explicit_deps
88. Test_pipeline_comments
89. Test_nix_emit
90. Test_import_file_from
91. Test_structural_integrity
92. Test_agent_scaffold
93. Test_coverage_boost
94. Test_misc_coverage
95. Test_dataframe_diff
96. Test_model_diff
97. Test_scalar_diff
98. Test_generic_diff
99. Test_pipeline_diff
100. Test_builder_diff
101. Test_check
102. Test_fix
103. Test_ndjson
104. Test_model_accessors
105. Test_drop_na_and_factors
106. Test_factor_grouping
107. Test_chrono_components
108. Test_trig_hyperbolic
109. Test_misc_functions

## Bad Patterns

Reject these patterns:

- Placeholder test with no assertion.
- Assertion that always passes, such as `TRUE`, `true`, `1 == 1`.
- Name and input do not match. Example: name says `filter` but input tests `select`.
- Expected value is too weak. Example: expected `.*` or empty string.
- Regex match hides a failure. `test` uses regex. `test_env` uses literal match. Prefer the strict check.
- Manual `incr pass_count` for a simple check. Use `test` or `test_env`.
- Test prints output but makes zero assertions.
- Test depends on prior state but uses `test`. Use `test_env` with explicit `env`.
- Silent catch of exceptions. The test must show the error value.

## Review Steps

Do these steps for each test:

1. Run the single module with `--only <Name>`.
2. Run again in strict mode with `TLANG_TEST_STRICT=1`.
3. Read the test name.
4. Read the input expression.
5. Read the expected output.
6. Check that the input exercises the named behavior.
7. Check that the expected output proves the behavior.
8. Check that the test fails when the code is wrong. Mutate the input in your head.
9. Repair weak tests. Keep the repair small.
10. Do not change unrelated code.
11. Update the tracker line at the end of this file.

Commands:

```bash
nix develop
dune build
dune exec tests/test_runner.exe -- --only Test_arithmetic
TLANG_TEST_STRICT=1 dune exec tests/test_runner.exe -- --only Test_arithmetic
dune runtest
```

## Fix Rules

- Keep the data argument first. This keeps the pipe operator valid.
- Return `VError` for user errors. Do not raise OCaml exceptions.
- Do not use `Option.get` or `List.hd` on possibly empty data.
- Do not add aliases for functions.
- Do not change parser or semantics. Ask the maintainer first if such a change is necessary.
- Add a regression test for each repaired behavior when the module allows it.

## Progress Log

Add a short line per reviewed module below, in order.
Use format: `- [x] <MODULE>: <result>`.
Result is one of: `OK`, `REPAIRED`, `SPLIT`, `REMOVED`.
Example: `- [x] Test_arithmetic: REPAIRED, 3 weak assertions fixed`.

Start of log:

- [ ] Audit starts. No module reviewed yet.

## Tracker Rule

The last line of this file is the tracker.
It shows the last reviewed test.
It has format `LAST_REVIEWED: <MODULE>.<test-name> [<n>/109]`.
For module-level progress, test-name can be `done`.
Do not add text after this line.
Update it after each test.

LAST_REVIEWED: NONE [0/109]

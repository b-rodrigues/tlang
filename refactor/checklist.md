# OCaml Code Review Guidelines Checklist

| Filename | Checked according to guidelines |
| :--- | :---: |
| `src/analyzer.ml` | [x] |
| `src/analyzer.mli` | [x] |
| `src/arrow/arrow_bridge.ml` | [x] |
| `src/arrow/arrow_bridge.mli` | [x] |
| `src/arrow/arrow_column.ml` | [x] |
| `src/arrow/arrow_column.mli` | [x] |
| `src/arrow/arrow_compute.ml` | [x] |
| `src/arrow/arrow_compute.mli` | [x] |
| `src/arrow/arrow_ffi.ml` | [x] |
| `src/arrow/arrow_ffi.mli` | [x] |
| `src/arrow/arrow_io.ml` | [x] |
| `src/arrow/arrow_owl_bridge.ml` | [x] |
| `src/arrow/arrow_table.ml` | [x] |
| `src/ast.ml` | [x] |
| `src/cli_args.ml` | [x] |
| `src/completion.ml` | [x] |
| `src/diff.ml` | [x] |
| `src/error.ml` | [x] |
| `src/eval.ml` | [x] |
| `src/import_registry.ml` | [x] |
| `src/lexer.mll` | [x] |
| `src/lsp_server.ml` | [x] |
| `src/package_manager/documentation_manager.ml` | [x] |
| `src/package_manager/nix_generator.ml` | [x] |
| `src/package_manager/package_doctor.ml` | [x] |
| `src/package_manager/package_loader.ml` | [x] |
| `src/package_manager/package_types.ml` | [x] |
| `src/package_manager/release_manager.ml` | [ ] |
| `src/package_manager/scaffold.ml` | [ ] |
| `src/package_manager/template_engine.ml` | [ ] |
| `src/package_manager/test_discovery.ml` | [ ] |
| `src/package_manager/toml_parser.ml` | [ ] |
| `src/package_manager/update_manager.ml` | [ ] |
| `src/packages/base/deserialize.ml` | [ ] |
| `src/packages/base/error_mod.ml` | [ ] |
| `src/packages/base/error_utils.ml` | [ ] |
| `src/packages/base/is_na.ml` | [ ] |
| `src/packages/base/na.ml` | [ ] |
| `src/packages/base/serialize.ml` | [ ] |
| `src/packages/base/t_assert.ml` | [ ] |
| `src/packages/base/t_json.ml` | [ ] |
| `src/packages/chrono/chrono.ml` | [ ] |
| `src/packages/colcraft/arrange.ml` | [ ] |
| `src/packages/colcraft/count.ml` | [ ] |
| `src/packages/colcraft/distinct.ml` | [ ] |
| `src/packages/colcraft/drop_na.ml` | [ ] |
| `src/packages/colcraft/expand.ml` | [ ] |
| `src/packages/colcraft/factors.ml` | [ ] |
| `src/packages/colcraft/fill.ml` | [ ] |
| `src/packages/colcraft/group_by.ml` | [ ] |
| `src/packages/colcraft/joins.ml` | [ ] |
| `src/packages/colcraft/mutate.ml` | [ ] |
| `src/packages/colcraft/n.ml` | [ ] |
| `src/packages/colcraft/n_distinct.ml` | [ ] |
| `src/packages/colcraft/nest.ml` | [ ] |
| `src/packages/colcraft/pivot_longer.ml` | [ ] |
| `src/packages/colcraft/pivot_wider.ml` | [ ] |
| `src/packages/colcraft/relocate.ml` | [ ] |
| `src/packages/colcraft/rename.ml` | [ ] |
| `src/packages/colcraft/replace_na.ml` | [ ] |
| `src/packages/colcraft/selection_helpers.ml` | [ ] |
| `src/packages/colcraft/separate.ml` | [ ] |
| `src/packages/colcraft/separate_rows.ml` | [ ] |
| `src/packages/colcraft/slice.ml` | [ ] |
| `src/packages/colcraft/slice_min_max.ml` | [ ] |
| `src/packages/colcraft/summarize.ml` | [ ] |
| `src/packages/colcraft/t_complete.ml` | [ ] |
| `src/packages/colcraft/t_filter.ml` | [ ] |
| `src/packages/colcraft/t_select.ml` | [ ] |
| `src/packages/colcraft/uncount.ml` | [ ] |
| `src/packages/colcraft/ungroup.ml` | [ ] |
| `src/packages/colcraft/unite.ml` | [ ] |
| `src/packages/colcraft/unnest.ml` | [ ] |
| `src/packages/colcraft/window_cumulative.ml` | [ ] |
| `src/packages/colcraft/window_offset.ml` | [ ] |
| `src/packages/colcraft/window_rank.ml` | [ ] |
| `src/packages/core/args.ml` | [ ] |
| `src/packages/core/converters.ml` | [ ] |
| `src/packages/core/file_ops.ml` | [ ] |
| `src/packages/core/head.ml` | [ ] |
| `src/packages/core/help.ml` | [ ] |
| `src/packages/core/is_error.ml` | [ ] |
| `src/packages/core/packages.ml` | [ ] |
| `src/packages/core/path_ops.ml` | [ ] |
| `src/packages/core/pretty_print.ml` | [ ] |
| `src/packages/core/show_plot.ml` | [ ] |
| `src/packages/core/sum.ml` | [ ] |
| `src/packages/core/t_boolean.ml` | [ ] |
| `src/packages/core/t_get.ml` | [ ] |
| `src/packages/core/t_map.ml` | [ ] |
| `src/packages/core/t_print.ml` | [ ] |
| `src/packages/core/t_seq.ml` | [ ] |
| `src/packages/core/t_type.ml` | [ ] |
| `src/packages/core/t_write_text.ml` | [ ] |
| `src/packages/core/tail.ml` | [ ] |
| `src/packages/dataframe/clean_colnames.ml` | [ ] |
| `src/packages/dataframe/colnames.ml` | [ ] |
| `src/packages/dataframe/glimpse.ml` | [ ] |
| `src/packages/dataframe/ncol.ml` | [ ] |
| `src/packages/dataframe/nrow.ml` | [ ] |
| `src/packages/dataframe/t_dataframe.ml` | [ ] |
| `src/packages/dataframe/t_read_arrow.ml` | [ ] |
| `src/packages/dataframe/t_read_csv.ml` | [ ] |
| `src/packages/dataframe/t_read_parquet.ml` | [ ] |
| `src/packages/dataframe/t_write_arrow.ml` | [ ] |
| `src/packages/dataframe/t_write_csv.ml` | [ ] |
| `src/packages/explain/explain_json.ml` | [ ] |
| `src/packages/explain/intent_fields.ml` | [ ] |
| `src/packages/explain/intent_get.ml` | [ ] |
| `src/packages/explain/t_explain.ml` | [ ] |
| `src/packages/lens/lens.ml` | [ ] |
| `src/packages/math/acos.ml` | [ ] |
| `src/packages/math/acosh.ml` | [ ] |
| `src/packages/math/asin.ml` | [ ] |
| `src/packages/math/asinh.ml` | [ ] |
| `src/packages/math/atan.ml` | [ ] |
| `src/packages/math/atan2.ml` | [ ] |
| `src/packages/math/atanh.ml` | [ ] |
| `src/packages/math/ceiling.ml` | [ ] |
| `src/packages/math/cos.ml` | [ ] |
| `src/packages/math/cosh.ml` | [ ] |
| `src/packages/math/floor.ml` | [ ] |
| `src/packages/math/math_common.ml` | [ ] |
| `src/packages/math/ndarray.ml` | [ ] |
| `src/packages/math/pow.ml` | [ ] |
| `src/packages/math/round.ml` | [ ] |
| `src/packages/math/sign.ml` | [ ] |
| `src/packages/math/signif.ml` | [ ] |
| `src/packages/math/sin.ml` | [ ] |
| `src/packages/math/sinh.ml` | [ ] |
| `src/packages/math/t_abs.ml` | [ ] |
| `src/packages/math/t_exp.ml` | [ ] |
| `src/packages/math/t_iota.ml` | [ ] |
| `src/packages/math/t_log.ml` | [ ] |
| `src/packages/math/t_sqrt.ml` | [ ] |
| `src/packages/math/tan.ml` | [ ] |
| `src/packages/math/tanh.ml` | [ ] |
| `src/packages/math/trunc.ml` | [ ] |
| `src/packages/pipeline/arrange_node.ml` | [ ] |
| `src/packages/pipeline/build_log.ml` | [ ] |
| `src/packages/pipeline/build_pipeline.ml` | [ ] |
| `src/packages/pipeline/export_artifacts.ml` | [ ] |
| `src/packages/pipeline/filter_node.ml` | [ ] |
| `src/packages/pipeline/import_artifacts.ml` | [ ] |
| `src/packages/pipeline/inspect_artifacts.ml` | [ ] |
| `src/packages/pipeline/inspect_pipeline.ml` | [ ] |
| `src/packages/pipeline/jln_docs.ml` | [ ] |
| `src/packages/pipeline/mutate_node.ml` | [ ] |
| `src/packages/pipeline/node_docs.ml` | [ ] |
| `src/packages/pipeline/pipeline_cache_status.ml` | [ ] |
| `src/packages/pipeline/pipeline_composition.ml` | [ ] |
| `src/packages/pipeline/pipeline_copy.ml` | [ ] |
| `src/packages/pipeline/pipeline_dag_ops.ml` | [ ] |
| `src/packages/pipeline/pipeline_deps.ml` | [ ] |
| `src/packages/pipeline/pipeline_diff.ml` | [ ] |
| `src/packages/pipeline/pipeline_gc.ml` | [ ] |
| `src/packages/pipeline/pipeline_inspect2.ml` | [ ] |
| `src/packages/pipeline/pipeline_node.ml` | [ ] |
| `src/packages/pipeline/pipeline_nodes.ml` | [ ] |
| `src/packages/pipeline/pipeline_run.ml` | [ ] |
| `src/packages/pipeline/pipeline_set_ops.ml` | [ ] |
| `src/packages/pipeline/pipeline_to_drv.ml` | [ ] |
| `src/packages/pipeline/pipeline_to_frame.ml` | [ ] |
| `src/packages/pipeline/pipeline_to_store.ml` | [ ] |
| `src/packages/pipeline/populate_pipeline.ml` | [ ] |
| `src/packages/pipeline/pyn_docs.ml` | [ ] |
| `src/packages/pipeline/qn_docs.ml` | [ ] |
| `src/packages/pipeline/read_node.ml` | [ ] |
| `src/packages/pipeline/rename_node.ml` | [ ] |
| `src/packages/pipeline/rn_docs.ml` | [ ] |
| `src/packages/pipeline/select_node.ml` | [ ] |
| `src/packages/pipeline/set_nix_defaults.ml` | [ ] |
| `src/packages/pipeline/shn_docs.ml` | [ ] |
| `src/packages/pipeline/t_make_mod.ml` | [ ] |
| `src/packages/pipeline/trace_nodes.ml` | [ ] |
| `src/packages/pipeline/which_nodes.ml` | [ ] |
| `src/packages/stats/add_diagnostics.ml` | [ ] |
| `src/packages/stats/anova.ml` | [ ] |
| `src/packages/stats/basis.ml` | [ ] |
| `src/packages/stats/coef.ml` | [ ] |
| `src/packages/stats/compare.ml` | [ ] |
| `src/packages/stats/conf_int.ml` | [ ] |
| `src/packages/stats/cor.ml` | [ ] |
| `src/packages/stats/cov.ml` | [ ] |
| `src/packages/stats/cv.ml` | [ ] |
| `src/packages/stats/deviance.ml` | [ ] |
| `src/packages/stats/df_residual.ml` | [ ] |
| `src/packages/stats/dispersion.ml` | [ ] |
| `src/packages/stats/distributions.ml` | [ ] |
| `src/packages/stats/fit_stats.ml` | [ ] |
| `src/packages/stats/fivenum.ml` | [ ] |
| `src/packages/stats/huber_loss.ml` | [ ] |
| `src/packages/stats/iqr.ml` | [ ] |
| `src/packages/stats/kurtosis.ml` | [ ] |
| `src/packages/stats/lm.ml` | [ ] |
| `src/packages/stats/mad.ml` | [ ] |
| `src/packages/stats/math_utils.ml` | [ ] |
| `src/packages/stats/max.ml` | [ ] |
| `src/packages/stats/mean.ml` | [ ] |
| `src/packages/stats/median.ml` | [ ] |
| `src/packages/stats/min.ml` | [ ] |
| `src/packages/stats/mode.ml` | [ ] |
| `src/packages/stats/nobs.ml` | [ ] |
| `src/packages/stats/normalize.ml` | [ ] |
| `src/packages/stats/onnx_ffi.ml` | [ ] |
| `src/packages/stats/predict.ml` | [ ] |
| `src/packages/stats/quantile.ml` | [ ] |
| `src/packages/stats/range.ml` | [ ] |
| `src/packages/stats/residuals.ml` | [ ] |
| `src/packages/stats/scale.ml` | [ ] |
| `src/packages/stats/score.ml` | [ ] |
| `src/packages/stats/sd.ml` | [ ] |
| `src/packages/stats/sigma.ml` | [ ] |
| `src/packages/stats/skewness.ml` | [ ] |
| `src/packages/stats/standardize.ml` | [ ] |
| `src/packages/stats/summary.ml` | [ ] |
| `src/packages/stats/t_native_scoring.ml` | [ ] |
| `src/packages/stats/t_read_onnx.ml` | [ ] |
| `src/packages/stats/t_read_pmml.ml` | [ ] |
| `src/packages/stats/t_score_pmml.ml` | [ ] |
| `src/packages/stats/trimmed_mean.ml` | [ ] |
| `src/packages/stats/var.ml` | [ ] |
| `src/packages/stats/vcov.ml` | [ ] |
| `src/packages/stats/wald_test.ml` | [ ] |
| `src/packages/stats/winsorize.ml` | [ ] |
| `src/packages/strcraft/string_ops.ml` | [ ] |
| `src/parser.mly` | [ ] |
| `src/pipeline/builder.ml` | [ ] |
| `src/pipeline/builder_artifacts.ml` | [ ] |
| `src/pipeline/builder_copy.ml` | [ ] |
| `src/pipeline/builder_inspect.ml` | [ ] |
| `src/pipeline/builder_internal.ml` | [ ] |
| `src/pipeline/builder_logs.ml` | [ ] |
| `src/pipeline/builder_nix_store.ml` | [ ] |
| `src/pipeline/builder_populate.ml` | [ ] |
| `src/pipeline/builder_read_node.ml` | [ ] |
| `src/pipeline/builder_utils.ml` | [ ] |
| `src/pipeline/builder_write_dag.ml` | [ ] |
| `src/pipeline/nix_emit_node.ml` | [ ] |
| `src/pipeline/nix_emit_pipeline.ml` | [ ] |
| `src/pipeline/nix_emitter.ml` | [ ] |
| `src/pipeline/nix_unparse.ml` | [ ] |
| `src/pipeline/nix_utils.ml` | [ ] |
| `src/pipeline/pipeline_dependency_requirements.ml` | [ ] |
| `src/pipeline_script.ml` | [ ] |
| `src/pmml_utils.ml` | [ ] |
| `src/repl.ml` | [ ] |
| `src/semantic_type.ml` | [ ] |
| `src/serialization.ml` | [ ] |
| `src/serialization_registry.ml` | [ ] |
| `src/stats.ml` | [ ] |
| `src/symbol_table.ml` | [ ] |
| `src/tdoc/tdoc_json.ml` | [ ] |
| `src/tdoc/tdoc_markdown.ml` | [ ] |
| `src/tdoc/tdoc_parser.ml` | [ ] |
| `src/tdoc/tdoc_registry.ml` | [ ] |
| `src/tdoc/tdoc_types.ml` | [ ] |
| `src/typecheck.ml` | [ ] |
| `src/value_hash.ml` | [ ] |

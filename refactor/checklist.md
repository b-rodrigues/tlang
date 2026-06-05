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
| `src/package_manager/release_manager.ml` | [x] |
| `src/package_manager/scaffold.ml` | [x] |
| `src/package_manager/template_engine.ml` | [x] |
| `src/package_manager/test_discovery.ml` | [x] |
| `src/package_manager/toml_parser.ml` | [x] |
| `src/package_manager/update_manager.ml` | [x] |
| `src/packages/base/deserialize.ml` | [x] |
| `src/packages/base/error_mod.ml` | [x] |
| `src/packages/base/error_utils.ml` | [x] |
| `src/packages/base/is_na.ml` | [x] |
| `src/packages/base/na.ml` | [x] |
| `src/packages/base/serialize.ml` | [x] |
| `src/packages/base/t_assert.ml` | [x] |
| `src/packages/base/t_json.ml` | [x] |
| `src/packages/chrono/chrono.ml` | [x] |
| `src/packages/colcraft/arrange.ml` | [x] |
| `src/packages/colcraft/count.ml` | [x] |
| `src/packages/colcraft/distinct.ml` | [x] |
| `src/packages/colcraft/drop_na.ml` | [x] |
| `src/packages/colcraft/expand.ml` | [x] |
| `src/packages/colcraft/factors.ml` | [x] |
| `src/packages/colcraft/fill.ml` | [x] |
| `src/packages/colcraft/group_by.ml` | [x] |
| `src/packages/colcraft/joins.ml` | [x] |
| `src/packages/colcraft/mutate.ml` | [x] |
| `src/packages/colcraft/n.ml` | [x] |
| `src/packages/colcraft/n_distinct.ml` | [x] |
| `src/packages/colcraft/nest.ml` | [x] |
| `src/packages/colcraft/pivot_longer.ml` | [x] |
| `src/packages/colcraft/pivot_wider.ml` | [x] |
| `src/packages/colcraft/relocate.ml` | [x] |
| `src/packages/colcraft/rename.ml` | [x] |
| `src/packages/colcraft/replace_na.ml` | [x] |
| `src/packages/colcraft/selection_helpers.ml` | [x] |
| `src/packages/colcraft/separate.ml` | [x] |
| `src/packages/colcraft/separate_rows.ml` | [x] |
| `src/packages/colcraft/slice.ml` | [x] |
| `src/packages/colcraft/slice_min_max.ml` | [x] |
| `src/packages/colcraft/summarize.ml` | [x] |
| `src/packages/colcraft/t_complete.ml` | [x] |
| `src/packages/colcraft/t_filter.ml` | [x] |
| `src/packages/colcraft/t_select.ml` | [x] |
| `src/packages/colcraft/uncount.ml` | [x] |
| `src/packages/colcraft/ungroup.ml` | [x] |
| `src/packages/colcraft/unite.ml` | [x] |
| `src/packages/colcraft/unnest.ml` | [x] |
| `src/packages/colcraft/window_cumulative.ml` | [x] |
| `src/packages/colcraft/window_offset.ml` | [x] |
| `src/packages/colcraft/window_rank.ml` | [x] |
| `src/packages/core/args.ml` | [x] |
| `src/packages/core/converters.ml` | [x] |
| `src/packages/core/file_ops.ml` | [x] |
| `src/packages/core/head.ml` | [x] |
| `src/packages/core/help.ml` | [x] |
| `src/packages/core/is_error.ml` | [x] |
| `src/packages/core/packages.ml` | [x] |
| `src/packages/core/path_ops.ml` | [x] |
| `src/packages/core/pretty_print.ml` | [x] |
| `src/packages/core/show_plot.ml` | [x] |
| `src/packages/core/sum.ml` | [x] |
| `src/packages/core/t_boolean.ml` | [x] |
| `src/packages/core/t_get.ml` | [x] |
| `src/packages/core/t_map.ml` | [x] |
| `src/packages/core/t_print.ml` | [x] |
| `src/packages/core/t_seq.ml` | [x] |
| `src/packages/core/t_type.ml` | [x] |
| `src/packages/core/t_write_text.ml` | [x] |
| `src/packages/core/tail.ml` | [x] |
| `src/packages/dataframe/clean_colnames.ml` | [x] |
| `src/packages/dataframe/colnames.ml` | [x] |
| `src/packages/dataframe/glimpse.ml` | [x] |
| `src/packages/dataframe/ncol.ml` | [x] |
| `src/packages/dataframe/nrow.ml` | [x] |
| `src/packages/dataframe/t_dataframe.ml` | [x] |
| `src/packages/dataframe/t_read_arrow.ml` | [x] |
| `src/packages/dataframe/t_read_csv.ml` | [x] |
| `src/packages/dataframe/t_read_parquet.ml` | [x] |
| `src/packages/dataframe/t_write_arrow.ml` | [x] |
| `src/packages/dataframe/t_write_csv.ml` | [x] |
| `src/packages/explain/explain_json.ml` | [x] |
| `src/packages/explain/intent_fields.ml` | [x] |
| `src/packages/explain/intent_get.ml` | [x] |
| `src/packages/explain/t_explain.ml` | [x] |
| `src/packages/lens/lens.ml` | [x] |
| `src/packages/math/acos.ml` | [x] |
| `src/packages/math/acosh.ml` | [x] |
| `src/packages/math/asin.ml` | [x] |
| `src/packages/math/asinh.ml` | [x] |
| `src/packages/math/atan.ml` | [x] |
| `src/packages/math/atan2.ml` | [x] |
| `src/packages/math/atanh.ml` | [x] |
| `src/packages/math/ceiling.ml` | [x] |
| `src/packages/math/cos.ml` | [x] |
| `src/packages/math/cosh.ml` | [x] |
| `src/packages/math/floor.ml` | [x] |
| `src/packages/math/math_common.ml` | [x] |
| `src/packages/math/ndarray.ml` | [x] |
| `src/packages/math/pow.ml` | [x] |
| `src/packages/math/round.ml` | [x] |
| `src/packages/math/sign.ml` | [x] |
| `src/packages/math/signif.ml` | [x] |
| `src/packages/math/sin.ml` | [x] |
| `src/packages/math/sinh.ml` | [x] |
| `src/packages/math/t_abs.ml` | [x] |
| `src/packages/math/t_exp.ml` | [x] |
| `src/packages/math/t_iota.ml` | [x] |
| `src/packages/math/t_log.ml` | [x] |
| `src/packages/math/t_sqrt.ml` | [x] |
| `src/packages/math/tan.ml` | [x] |
| `src/packages/math/tanh.ml` | [x] |
| `src/packages/math/trunc.ml` | [x] |
| `src/packages/pipeline/arrange_node.ml` | [x] |
| `src/packages/pipeline/build_log.ml` | [x] |
| `src/packages/pipeline/build_pipeline.ml` | [x] |
| `src/packages/pipeline/export_artifacts.ml` | [x] |
| `src/packages/pipeline/filter_node.ml` | [x] |
| `src/packages/pipeline/import_artifacts.ml` | [x] |
| `src/packages/pipeline/inspect_artifacts.ml` | [x] |
| `src/packages/pipeline/inspect_pipeline.ml` | [x] |
| `src/packages/pipeline/jln_docs.ml` | [x] |
| `src/packages/pipeline/mutate_node.ml` | [x] |
| `src/packages/pipeline/node_docs.ml` | [x] |
| `src/packages/pipeline/pipeline_cache_status.ml` | [x] |
| `src/packages/pipeline/pipeline_composition.ml` | [x] |
| `src/packages/pipeline/pipeline_copy.ml` | [x] |
| `src/packages/pipeline/pipeline_dag_ops.ml` | [x] |
| `src/packages/pipeline/pipeline_deps.ml` | [x] |
| `src/packages/pipeline/pipeline_diff.ml` | [x] |
| `src/packages/pipeline/pipeline_gc.ml` | [x] |
| `src/packages/pipeline/pipeline_inspect2.ml` | [x] |
| `src/packages/pipeline/pipeline_node.ml` | [x] |
| `src/packages/pipeline/pipeline_nodes.ml` | [x] |
| `src/packages/pipeline/pipeline_run.ml` | [x] |
| `src/packages/pipeline/pipeline_set_ops.ml` | [x] |
| `src/packages/pipeline/pipeline_to_drv.ml` | [x] |
| `src/packages/pipeline/pipeline_to_frame.ml` | [x] |
| `src/packages/pipeline/pipeline_to_store.ml` | [x] |
| `src/packages/pipeline/populate_pipeline.ml` | [x] |
| `src/packages/pipeline/pyn_docs.ml` | [x] |
| `src/packages/pipeline/qn_docs.ml` | [x] |
| `src/packages/pipeline/read_node.ml` | [x] |
| `src/packages/pipeline/rename_node.ml` | [x] |
| `src/packages/pipeline/rn_docs.ml` | [x] |
| `src/packages/pipeline/select_node.ml` | [x] |
| `src/packages/pipeline/set_nix_defaults.ml` | [x] |
| `src/packages/pipeline/shn_docs.ml` | [x] |
| `src/packages/pipeline/t_make_mod.ml` | [x] |
| `src/packages/pipeline/trace_nodes.ml` | [x] |
| `src/packages/pipeline/which_nodes.ml` | [x] |
| `src/packages/stats/add_diagnostics.ml` | [x] |
| `src/packages/stats/anova.ml` | [x] |
| `src/packages/stats/basis.ml` | [x] |
| `src/packages/stats/coef.ml` | [x] |
| `src/packages/stats/compare.ml` | [ ] |
| `src/packages/stats/conf_int.ml` | [x] |
| `src/packages/stats/cor.ml` | [x] |
| `src/packages/stats/cov.ml` | [x] |
| `src/packages/stats/cv.ml` | [x] |
| `src/packages/stats/deviance.ml` | [x] |
| `src/packages/stats/df_residual.ml` | [x] |
| `src/packages/stats/dispersion.ml` | [x] |
| `src/packages/stats/distributions.ml` | [x] |
| `src/packages/stats/fit_stats.ml` | [x] |
| `src/packages/stats/fivenum.ml` | [x] |
| `src/packages/stats/huber_loss.ml` | [x] |
| `src/packages/stats/iqr.ml` | [x] |
| `src/packages/stats/kurtosis.ml` | [x] |
| `src/packages/stats/lm.ml` | [x] |
| `src/packages/stats/mad.ml` | [x] |
| `src/packages/stats/math_utils.ml` | [x] |
| `src/packages/stats/max.ml` | [x] |
| `src/packages/stats/mean.ml` | [x] |
| `src/packages/stats/median.ml` | [x] |
| `src/packages/stats/min.ml` | [x] |
| `src/packages/stats/mode.ml` | [x] |
| `src/packages/stats/nobs.ml` | [x] |
| `src/packages/stats/normalize.ml` | [x] |
| `src/packages/stats/onnx_ffi.ml` | [x] |
| `src/packages/stats/predict.ml` | [x] |
| `src/packages/stats/quantile.ml` | [x] |
| `src/packages/stats/range.ml` | [x] |
| `src/packages/stats/residuals.ml` | [x] |
| `src/packages/stats/scale.ml` | [x] |
| `src/packages/stats/score.ml` | [x] |
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

# Agent Rules for TLang Project

## GitHub Actions Workflows
When modifying or creating GitHub Actions workflow files (`.github/workflows/*.yml`):

1.  **Validate with actionlint**: Always run `actionlint` after editing a workflow file to catch syntax errors and best practice violations.
2.  **Use Nix for Linting**: Since this is a Nix project, run the linter through the development shell:
    ```bash
    nix develop --command actionlint .github/workflows/your-file.yml
    ```
3.  **Indentation Matters**: Be extremely careful with indentation, especially when using shell heredocs (`<<EOF`) inside YAML block scalars (`run: |`). YAML requires consistent indentation for the entire block.

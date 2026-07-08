# Implementation Guide: Agent Skills for `t init`

**Feature:** Ship a Claude Skill alongside every scaffolded T project/package, so AI agents get
a fast, example-driven playbook in addition to the existing `AGENTS.md` and
`T-LANGUAGE-REFERENCE.md`.

**Status:** Reference patch already exists (`tlang-t-quickstart-skills.patch`) — this document
explains what it does and why, so you can review, adapt, or extend it rather than reverse-engineer
the diff.

---

## 1. Motivation

`t init` already generates two files for AI agents working in a scaffolded project:

- **`AGENTS.md`** — static conventions (environment rules, coding standards, project structure).
- **`T-LANGUAGE-REFERENCE.md`** — a tiered API index (small/medium/full/huge), generated per the
  `--context` flag.

Neither of these is procedural. They tell an agent *what the rules are* and *what functions
exist*, but not *how to do the five things it will actually be asked to do* — add a node, debug a
broken pipeline, add an exported function with correct T-Doc, etc. That's a gap best filled by a
[Claude Skill](https://docs.claude.com/en/docs/build-with-claude/skills): a markdown file with
YAML frontmatter (`name`, `description`) that Claude Code and compatible agents discover
automatically and consult only when relevant, rather than always injecting into context.

Two skills are added, mirroring the existing project/package split:

| Skill | Trigger context | Covers |
|---|---|---|
| `t-project` | Directory has `tproject.toml` + pipeline `.t` scripts | Choosing `node`/`rn`/`pyn`/`shn`, adding a node, debugging (`t explain`, `read_node`), common pipeline mistakes |
| `t-package` | Directory has `DESCRIPTION.toml`, `src/`, `tests/` | Writing exported functions, T-Doc blocks, testing workflow, data-first API design |

---

## 2. What ships where

```
tlang/                                    # the tlang repo itself
├── agents/
│   ├── agents-project.md                 # existing
│   ├── agents-package.md                 # existing
│   ├── t-reference-{small,medium,full,huge}.md   # existing
│   ├── skill-t-project.md                # NEW — source template
│   └── skill-t-package.md                # NEW — source template
└── src/package_manager/scaffold.ml       # scaffolding logic

my-t-project/                             # a project created via `t init`
├── AGENTS.md
├── T-LANGUAGE-REFERENCE.md
├── tproject.toml
├── ...
└── .claude/
    └── skills/
        └── t-project/
            └── SKILL.md                  # copied from agents/skill-t-project.md

my-t-package/                             # a package created via `t init --package`
├── AGENTS.md
├── T-LANGUAGE-REFERENCE.md
├── DESCRIPTION.toml
├── ...
└── .claude/
    └── skills/
        └── t-package/
            └── SKILL.md                  # copied from agents/skill-t-package.md
```

The `.claude/skills/<name>/SKILL.md` path is Claude Code's discovery convention — Claude Code
scans this directory in a project and reads `SKILL.md` frontmatter to decide when to consult it,
the same mechanism the `skill-creator` tool itself uses.

---

## 3. Source templates: `agents/skill-t-*.md`

Two new flat files in the existing `agents/` directory, following the naming pattern already used
for `agents-project.md` / `agents-package.md`. Each is a complete, standalone Skill:

```markdown
---
name: t-project
description: <trigger conditions — see full file for exact wording>
---

# T Project Quickstart
...
```

**Content guidelines if you're revising these:**

- Point to `AGENTS.md`/`T-LANGUAGE-REFERENCE.md` rather than duplicating them. The skill's job is
  the procedural layer on top, not a third copy of the rules.
- Every section should answer "what does an agent actually do here," ideally with a runnable code
  example, not just a restated rule.
- Keep the `description` field specific about trigger conditions (file presence, task shape) —
  that field is the entire mechanism by which the skill gets picked up. See
  `docs.claude.com` skill-authoring guidance if you want to tune triggering further.
- Full current text of both files is in the patch / attached standalone files
  (`skill-t-project.md`, `skill-t-package.md`).

---

## 4. Code changes: `src/package_manager/scaffold.ml`

### 4.1 New function: `copy_skill_file`

Add directly after `copy_agent_files` (reuses its helpers: `discover_agents_dir`,
`copy_text_file`, `create_dir`):

```ocaml
(** Copy the bundled agent Skill (SKILL.md) that gives AI agents a fast,
    example-driven playbook for common T tasks, as a companion to AGENTS.md
    and T-LANGUAGE-REFERENCE.md. Lands at .claude/skills/<name>/SKILL.md so
    Claude Code (and other Skill-aware agents) discover it automatically.

    @param dir The destination directory.
    @param is_package [true] for package setups, [false] for projects.
    @return [true] if successful, [false] otherwise. *)
let copy_skill_file dir is_package =
  let skill_name = if is_package then "t-package" else "t-project" in
  let src_name = "skill-" ^ skill_name ^ ".md" in
  match discover_agents_dir () with
  | None -> false
  | Some agents_dir ->
      let src_path = Filename.concat agents_dir src_name in
      if not (Sys.file_exists src_path) then begin
        Printf.eprintf "Warning: Skill template not found: %s\n" src_path;
        false
      end else begin
        let skill_dir =
          Filename.concat (Filename.concat dir ".claude/skills") skill_name
        in
        create_dir skill_dir;
        let dest_path = Filename.concat skill_dir "SKILL.md" in
        copy_text_file src_path dest_path
      end
```

Notes for reviewers:

- `create_dir` already does `mkdir -p`-style recursive creation (see its definition earlier in
  the file), so `Filename.concat dir ".claude/skills/<name>"` as a single call is safe even though
  none of `.claude`, `.claude/skills`, or the leaf directory exist yet.
- Deliberately **not** gated behind `agent_context` (`small`/`medium`/`full`/`huge`) — the skill
  is a fixed, small file regardless of how verbose the language reference is. Open question for
  the team: should `--context small` skip it? See §6.

### 4.2 Call sites

In `scaffold_project`, immediately after the existing `copy_agent_files` call:

```ocaml
let _ = copy_agent_files dir false opts.agent_context in
let _ = copy_skill_file dir false in
```

In `scaffold_package`, immediately after its `copy_agent_files` call:

```ocaml
let _ = copy_agent_files dir true opts.agent_context in
let _ = copy_skill_file dir true in
```

### 4.3 Success-message tree output

Both `scaffold_project` and `scaffold_package` print an ASCII tree of the generated structure
after a successful run. Add the new path to both, e.g. for the project tree:

```ocaml
Printf.printf "  ├── tests/\n";
Printf.printf "  └── .claude/skills/t-project/\n";
Printf.printf "      └── SKILL.md\n";
```

(and analogously for the package tree, `.claude/skills/t-package/`). This is purely cosmetic but
matters for user trust — silently creating a `.claude/` directory without mentioning it in the
"here's what I made" output would be surprising.

---

## 5. Deployment: no `flake.nix` changes needed

Check `flake.nix` before assuming you need to touch it — the install phase already does:

```nix
mkdir -p $out/share/tlang/agents
cp -r agents/* $out/share/tlang/agents/
```

Since this is a glob copy of the whole `agents/` directory, the two new `skill-t-*.md` files ship
automatically once they exist in the repo. `discover_agents_dir` resolves to
`$out/share/tlang/agents` at runtime for installed builds, or `$TLANG_AGENTS_DIR` /
local `agents/` in dev — both already handled by the existing lookup logic, unchanged here.

---

## 6. Testing

### 6.1 Unit tests

`tests/package_manager/test_agent_scaffold.ml` already exercises `copy_agent_files` against mock
templates written to a temp `TLANG_AGENTS_DIR`. Extend the same fixture:

1. In the mock-template setup, add:
   ```ocaml
   write_mock "skill-t-project.md" "Project Skill";
   write_mock "skill-t-package.md" "Package Skill";
   ```
2. Add two test cases calling `copy_skill_file` directly (one `is_package = false`, one `true`),
   asserting the file lands at `<dest>/.claude/skills/t-project/SKILL.md` (or `t-package/...`)
   with the expected mock content.

This follows the exact pattern already used for the `AGENTS.md` / `T-LANGUAGE-REFERENCE.md` tests
in the same file — same temp-dir setup, same `Fun.protect` cleanup, same env var restore.

Run via the project's existing test command:

```bash
dune build
dune runtest
```

### 6.2 Manual smoke test

```bash
nix develop
t init --project smoke-test-proj
ls smoke-test-proj/.claude/skills/t-project/SKILL.md   # should exist
cat smoke-test-proj/.claude/skills/t-project/SKILL.md   # should render the real content, not a warning

t init --package smoke-test-pkg
ls smoke-test-pkg/.claude/skills/t-package/SKILL.md
```

Also verify the warning path: temporarily rename `agents/skill-t-project.md` and confirm `t init`
still succeeds (skill copy is non-fatal, matching `copy_agent_files`'s behavior) but prints
`Warning: Skill template not found: ...` to stderr.

---

## 7. Open decisions for the team

These weren't resolved in the reference patch — worth a quick team discussion before merging:

1. **Context-level gating.** Should `--context small` (minimal token budget) skip the skill file,
   or is it small enough to always include? Current patch always includes it.
2. **Tool-agnostic duplication.** `.claude/skills/` is Claude Code–specific. If we want this to
   help agents that don't use that discovery convention, consider either (a) a second copy at a
   neutral path referenced from `AGENTS.md`, or (b) leaving it Claude Code–only for now and
   revisiting if another tool's convention gains traction.
3. **Skill content ownership/versioning.** These skills will drift from `T-LANGUAGE-REFERENCE.md`
   as the language evolves (new node types, new stdlib functions). Decide who owns keeping them in
   sync — probably whoever touches `agents-project.md`/`agents-package.md` should touch the
   matching skill file in the same PR.
4. **`--force` re-init behavior.** `t init --force` on an existing directory will overwrite
   `SKILL.md` (via `copy_text_file`, which truncates and rewrites) but won't touch anything else a
   user may have added under `.claude/skills/`. Confirm this matches expectations — it does today
   for `AGENTS.md` too, so it's consistent, just worth calling out explicitly in review.

---

## 8. Reference

- Patch: `tlang-t-quickstart-skills.patch` (apply with `git apply` from repo root)
- Standalone skill sources: `skill-t-project.md`, `skill-t-package.md`
- Files touched: `agents/skill-t-project.md` (new), `agents/skill-t-package.md` (new),
  `src/package_manager/scaffold.ml` (modified), `tests/package_manager/test_agent_scaffold.ml`
  (modified)

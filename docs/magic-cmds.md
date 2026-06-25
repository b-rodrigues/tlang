# Magic Commands

Magic commands are REPL-only shortcuts prefixed with `%`. They provide quick access to common operations without parentheses or string quotes.

## `%cd <dir>`

Change the current working directory.

```t
%cd /tmp
%pwd      -- /tmp
%cd ~     -- expands ~ correctly
```

If the directory does not exist, an error message is printed. The shell escape `?<{cd ...}>` also changes the T interpreter's working directory via the same mechanism.

## `%env`

Print all environment variables, one per line.

```t
%env
HOME=/home/user
PATH=/usr/bin:/bin
...
```

## `%history`

Show the last 50 entries from the REPL command history (`~/.t_history`).

```t
%history
    1  x = 42
    2  y = x + 1
    3  %pwd
```

If no history exists, displays `(no history)`.

## `%ls`

List files and directories in the current working directory.

```t
%ls
file1.t  file2.t  data.csv
```

## `%magic`

List all available magic commands with descriptions.

```t
%magic
```

Equivalent to the `:help` section on magic commands.

## `%objects`

List all user-defined variables, their types, and a compact summary.

```t
x = 42
df = read_csv("data.csv")
%objects
--  name  type       summary
--  x     Int        42
--  df    DataFrame  150 rows x 5 cols
```

Alias: `%who`.

## `%pwd`

Print the current working directory.

```t
%pwd
/home/user/projects
```

## `%reset`

Remove all user-defined variables and return to the clean base environment. Also clears the session transcript for `%save`.

```t
x = 42
%reset
%objects
-- (no user objects)
```

## `%save <file>` / `%save verbose <file>`

Save a session transcript — every command and its result — to a file. Each entry is written as `# command` followed by `# result`.

**Compact mode** (`%save file.t`) uses `value_summary`:
```t
# x = 42
# 42

# read_csv("data.csv")
# DataFrame: 150 rows x 5 cols
```

**Verbose mode** (`%save verbose file.t`) uses the full pretty-printed output:
```t
# x = 42
# 42

# read_csv("data.csv")
# ┌──────┬──────┐
# │ col1 │ col2 │
# ├──────┼──────┤
# │ ...  │ ...  │
# └──────┴──────┘
```

Can be combined with `%reset` to start a fresh transcript before recording.

## `%time <expr>`

Evaluate any T expression and print its result along with execution time.

```t
%time 1 + 1
2
Execution time: 0.0002 seconds
```

```t
%time df |> filter($x > 10) |> nrow()
42
Execution time: 0.1540 seconds
```

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `%cd <dir>` | Change directory |
| `%env` | List environment variables |
| `%history` | Show command history |
| `%ls` | List directory contents |
| `%magic` | List magic commands |
| `%objects` / `%who` | List user-defined objects |
| `%pwd` | Print working directory |
| `%reset` | Reset environment to base |
| `%save <file>` | Save session transcript (compact) |
| `%save verbose <file>` | Save session transcript (verbose) |
| `%time <expr>` | Time an expression |

Typing an unknown magic command triggers fuzzy matching: `%objcts` suggests `Did you mean: %objects?`.

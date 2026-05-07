# Copilot Instructions — `dex`

`dex` is a **single-file Bash script** (~1160 lines) that runs commands inside a persistent Docker container, transparently mirroring the developer's host environment. The git repository root is auto-detected and mounted as `/workspace`; the host working directory is translated to the equivalent container path automatically.

## Repository layout

```
Unix/Scripts/custom/dex/
├── dex                      ← the script (bash, executable)
├── README.md                       ← user-facing documentation
├── dex.conf.example         ← global config template  (~/.dex.conf)
├── dex.repo.conf.example    ← repo config template    (<git-root>/.dex.conf)
├── dex.d/
│   └── example.conf                ← local project config template (~/.dex.d/)
└── .github/
    └── copilot-instructions.md     ← this file
```

---

## Configuration hierarchy

Config files are loaded in **ascending priority order** (lowest first, highest wins):

| Priority | Location | Typical use |
|---|---|---|
| 3 – Global (lowest) | `~/.dex.conf` (fallback `~/.local/share/.dex.conf`) | Optional personal defaults |
| 2 – Repository | `<git-root>/.dex.conf` | Committed shared defaults |
| 1 – Local project (highest) | `~/.dex.d/<name>.conf` (fallback `~/.local/share/.dex.d/`) | Personal per-project overrides |

All three sources are **optional**. At least one must define the active profile.

**Local project config matching:** files in `~/.dex.d/` are scanned alphabetically; the first whose `pattern` key (bash ERE) matches the absolute git root path is used.

**Profile name resolution order:**
1. Start with `"default"`
2. Repo config's `[project] profile` overrides it
3. Local project config's `[project] profile` overrides that
4. `--profile <name>` / `-p <name>` CLI flag overrides everything

---

## INI parser

All config files share the same format. Parsed by `ini_parse()` into the global associative array `_CFG`:

```
_CFG["<absolute-file-path>::::<section-name>::::<key>"] = value
```

Separator `::::` (`_SEP`) must not appear in file paths or section names.

**Alias section qualification:** when parsing the global config, `[alias:build]` appearing inside a `[clang]` profile block is stored as `alias:clang:build`. In repo / local project configs `[alias:build]` stays as `alias:build`.

Helper functions: `ini_get <file> <section> <key> [default]`, `ini_has_section <file> <section>`, `ini_sections <file>`.

**Limitations:** no multi-line values, no end-of-line `#` comments (comments must be on their own line), no quoted strings.

---

## Config file format

### Global config (`~/.dex.conf`)

```ini
[<profile-name>]
image      = <image:tag>
dockerfile = <path>               # relative → resolved from config file's dir
ports      = 8080:8080,443:443    # comma-separated host:container
env        = KEY,KEY=VAL,KEY=$(cmd)

[alias:<name>]                    # scoped to the preceding profile
cmd         = <shell command>     # executed via sh -c inside container
workdir     = /workspace          # container path; supports $(cmd) substitution
env         = KEY,...             # alias-level env (merged with profile env)
pipeline    = alias1,alias2,...   # pipeline alias; cmd is unused
interactive = true                # always run with docker exec -it
```

### Repo config (`<git-root>/.dex.conf`) and local project config (`~/.dex.d/<name>.conf`)

```ini
[project]
pattern    = .*/myproject(/.*)?   # local project only: bash ERE to match git root
profile    = default
image      = ...
dockerfile = ...

[<profile-name>]                  # override profile fields
image = ...
ports = ...
env   = ...

[alias:<name>]                    # unscoped — all profiles; highest precedence
cmd     = ...
workdir = ...
env     = ...
interactive = true

[alias:<profile>:<name>]          # profile-scoped alias
cmd = ...
```

---

## Alias keys reference

| Key | Description |
|---|---|
| `cmd` | Shell command run via `sh -c` inside the container. Required for non-pipeline aliases. |
| `workdir` | Container working directory; supports `$(cmd)` substitution. Defaults to `/workspace`. |
| `env` | Comma-separated env spec (same forms as profile `env`). Merged with profile env at runtime. |
| `pipeline` | Comma-separated list of step alias names. Makes this a pipeline alias; `cmd` is unused. |
| `interactive` | `true` → always run with `docker exec -it`, even inside a pipeline. |
| `hidden` | `true` → exclude from `--list` and disable direct invocation; usable only as a pipeline step. |

---

## Alias precedence (highest wins within a layer; layers stack lowest→highest)

```
global profile alias
  < repo profile-scoped alias  [alias:<profile>:<name>]
    < repo unscoped alias       [alias:<name>]
      < local project profile-scoped alias
        < local project unscoped alias          ← always wins
```

`env` in a higher-priority alias **replaces** lower-priority alias `env` entirely. Profile base `env` is always prepended at runtime.

---

## Environment variable specs (`env =`)

Comma-separated. Four forms:

| Form | Behaviour |
|---|---|
| `KEY` | Pass the host value of `KEY`; silently skipped if unset |
| `KEY=VALUE` | Fixed value |
| `KEY=$(cmd)` | Evaluate `cmd` on the host at run time; use stdout as value |
| `` KEY=`cmd` `` | Same, backtick style |

**`build_env_flags` implementation:** detects `$(` or backtick, then uses `eval "_val=${_rawval}"` (no extra double-quote wrapping). Double-quote wrapping causes single-quoted strings inside `$()` to become literals and corrupts bash's variable-context stack with `pop_var_context` errors. Outputs null-delimited `-e KEY=VALUE` pairs; callers use `while IFS= read -r -d '' …`.

**CLI override (`-e` / `--env`):** `CLI_ENV` accumulates comma-separated specs from multiple `-e` flags or a single comma-separated value. Appended last to `COMBINED_ENV` → highest priority at runtime.

**`COMBINED_ENV` build:**
```bash
COMBINED_ENV="$PROFILE_ENV"
[[ -n "$_aenv"   ]] && COMBINED_ENV="${COMBINED_ENV}${COMBINED_ENV:+,}${_aenv}"
[[ -n "$CLI_ENV" ]] && COMBINED_ENV="${COMBINED_ENV}${COMBINED_ENV:+,}${CLI_ENV}"
```

---

## Key global variables

| Variable | Type | Purpose |
|---|---|---|
| `_CFG` | `declare -A` | All parsed INI values |
| `GLOBAL_CONFIG` | string | `~/.dex.conf` path |
| `PROJECT_CONFIG_DIR` | string | `~/.dex.d/` path |
| `REPO_CONFIG` | string | `<git-root>/.dex.conf` if found, else `""` |
| `PROJECT_FILE` | string | Matched local project config path, else `""` |
| `PROFILE_IMAGE` | string | Image from base profile section |
| `PROFILE_ENV` | string | Base env from profile section |
| `PROFILE_DOCKERFILE` | string | Dockerfile from profile section |
| `PROFILE_PORTS` | string | Comma-separated `host:container` port mappings |
| `PROJECT_IMAGE` | string | Image override from `[project]` section |
| `PROJECT_DOCKERFILE` | string | Dockerfile from `[project]` section |
| `EFFECTIVE_DOCKERFILE` | string | `PROJECT_DOCKERFILE ?: PROFILE_DOCKERFILE` |
| `FINAL_IMAGE` | string | Resolved Docker image used for the run |
| `CONTAINER_NAME` | string | `dex-<git-slug>-<profile-slug>` |
| `ALIAS_CMD` | `declare -A` | name → shell command string |
| `ALIAS_WORKDIR` | `declare -A` | name → container working directory |
| `ALIAS_ENV` | `declare -A` | name → env spec string |
| `ALIAS_PIPELINE` | `declare -A` | name → comma-separated step list |
| `ALIAS_INTERACTIVE` | `declare -A` | name → `"true"` or `""` |
| `ALIAS_HIDDEN` | `declare -A` | name → `"true"` or `""`; hidden aliases are excluded from `--list` and direct invocation |
| `INTERACTIVE` | int | `1` if `-I` was passed |
| `STEP_INTERACTIVE` | int | `1` for the current step |
| `CLI_ENV` | string | Extra env from `-e`/`--env` CLI flags |
| `ENV_FLAGS` | array | Expanded `-e KEY=VAL` arguments for `docker exec` |
| `EXEC_CMD` | string | Alias command for current step |
| `EXEC_ARGS` | array | Literal command args for current step |
| `EXEC_WORKDIR` | string | Container workdir for current step |
| `DISPLAY_CMD` | string | Human-readable command label for summary header |
| `COMBINED_ENV` | string | Merged `profile_env,alias_env,cli_env` |
| `ENV_DISPLAY` | string | Human-readable env list for summary header |
| `_STEP_SIG_RECEIVED` | string | `"INT"` / `"TERM"` if step was interrupted |
| `_active_tmpfifo` | string | Path to FIFO; cleaned up by EXIT trap |
| `_CB _CCY _CYL _CGR _CDIM _CR` | strings | ANSI color codes for inline message content; empty when stderr is not a TTY |

---

## Function map

| Function | Purpose |
|---|---|
| `die` / `warn` / `info` | Styled output to stderr; detect TTY for colors |
| `ini_parse` / `ini_get` / `ini_has_section` / `ini_sections` | INI config parser |
| `load_profile(profile)` | Load the base profile from the lowest-priority source that has it |
| `find_project_config(git_root)` | Scan `~/.dex.d/` for a matching local project config |
| `find_repo_config(git_root)` | Look for `<git-root>/.dex.conf` and parse it |
| `_apply_config_layer(src, profile)` | Apply one config layer's overrides on top of already-loaded state |
| `apply_project_config(profile)` | Call `_apply_config_layer` for repo then local project config |
| `build_env_flags(env_spec)` | Output null-delimited `-e KEY=VAL` pairs from comma-separated spec |
| `container_name_from_path(path)` | Derive DNS-safe container name from git root |
| `ensure_image(image, dockerfile, force_rebuild)` | Build from Dockerfile or no-op |
| `ensure_container(name, image, git_root, ports, force_restart)` | Create / start container |
| `_rolling_display(max, logfile)` | Live rolling terminal display for non-interactive output |
| `_now_ms` / `_fmt_duration` | Timing helpers |
| `print_footer(exit_code, elapsed_ms, logfile)` | Result/duration footer box to stderr |
| `print_summary(...)` | Pre-execution summary header box to stderr |
| `list_aliases()` | Print formatted alias table and exit |
| `show_help()` | Print colored help text and exit |
| `_setup_step(alias, pipeline_label)` | Resolve globals for one step; print summary |
| `run_exec_step(logfile)` | Execute one step; print footer; return exit code |

---

## Config loading sequence (main flow)

```
1. [[ -f GLOBAL_CONFIG ]] && ini_parse GLOBAL_CONFIG    (optional)
2. find_repo_config GIT_ROOT     → sets REPO_CONFIG; ini_parse if found
3. find_project_config GIT_ROOT  → sets PROJECT_FILE; ini_parse if found
4. Resolve PROFILE_NAME          ("default" → repo [project].profile → local [project].profile → --profile)
5. load_profile PROFILE_NAME     → reads base from lowest-priority source that has the profile
6. apply_project_config PROFILE_NAME → _apply_config_layer REPO_CONFIG, then PROJECT_FILE
7. Resolve FINAL_IMAGE / EFFECTIVE_DOCKERFILE / CONTAINER_NAME
```

---

## Dispatch modes

### Literal command
```
docker exec [-it] -w CONTAINER_WORKDIR ${ENV_FLAGS[@]} CONTAINER_NAME "$@"
```
`COMBINED_ENV = PROFILE_ENV + CLI_ENV`.

### Single alias
1. `_setup_step ALIAS_NAME` — resolves workdir (with `$(cmd)` eval), cmd, `COMBINED_ENV = PROFILE_ENV + alias_env + CLI_ENV`, interactive flag; prints summary header
2. `run_exec_step` — executes and prints footer

### Pipeline alias
Iterates `ALIAS_PIPELINE[name]` (comma-separated, whitespace trimmed). Calls `_setup_step` + `run_exec_step` per step. Steps share one logfile. Stops on first non-zero exit.

---

## Execution modes

### Non-interactive (default)
```
docker exec (no -t) → stdout+stderr → FIFO → _rolling_display → terminal
                                           → logfile (mktemp)
```
- FIFO: `mktemp -u` + `mkfifo`; cleaned up by EXIT trap and at end of step
- Rolling display: last 10 physical rows live in terminal
- Logfile: `mktemp -t dex.XXXXXX.log`; **not removed**; old files (>3 min) purged at startup
- SIGINT/SIGTERM: host-side signal to docker PID + `docker exec … sh -c "kill -SIG -1"` in container

### Interactive (`-I` or `interactive = true`)
```
docker exec -it → foreground (terminal connected directly)
```
- No FIFO, no rolling display, no logfile
- SIGINT caught and re-raised as exit code 130

---

## Rolling display details (`_rolling_display`)

- Buffer: circular array of ≤ `max` (10) slots; **each slot = exactly 1 physical terminal row**
- `PFX = "   │ "` (3 spaces + pipe + space = 5 display columns); colored pipe when TTY
- `content_width = tput cols − 5`
- Each incoming line is ANSI-stripped, split into `content_width`-wide chunks; each chunk = one buffer slot
- Cursor-up on redraw is always exactly `$max` (buffer slots == physical rows, no recalculation needed)
- Non-TTY / unknown width (`content_width == 0`): no splitting, lines printed verbatim
- `\r`-style progress lines: `line="${line##*$'\r'}"` strips everything before last `\r`
- ANSI regex in variable `_ansi_re=$'\033\[[0-9;]*[A-Za-z]'` (avoids bash misparse of `[` inside `[[ ]]`)
- Raw lines (ANSI-intact) written to logfile before display processing

---

## Visual output style

All script-generated messages use a consistent style with TTY detection:

- **`info`:** ` ·  message` — cyan `·` icon
- **`warn`:** ` ⚠  warning:  message` — bold yellow
- **`die`:** `\n ✗  error:  message\n` — bold red, blank lines around it
- **`print_summary`:** cyan box with `┌`/`│`/`└` border; 1-space left indent on all lines
- **`print_footer`:** cyan box with result (green ✓ / red ✗), duration, log path
- **`list_aliases`:** cyan box; profile in yellow, pipelines in magenta, regular aliases in yellow, config source paths shown in header (Global / Repo / Local, each only if present)
- **`show_help`:** section headers in bold cyan, flags in yellow, paths in green, examples in yellow

Inline content coloring uses globals `_CB _CCY _CYL _CGR _CDIM _CR` set once at startup based on `[[ -t 2 ]]`.
`show_help` and `list_aliases` use local color vars based on `[[ -t 1 ]]` (stdout).
ANSI-C quoting (`$'\033[...'`) is used for colors stored in variables used as `%s` args to printf.
Plain `"\033[..."` is used when appearing only in format strings.

---

## Container lifecycle

- Name: `dex-<git-root-slug>-<profile-slug>` (one per profile per repo)
- `ensure_image`: builds from Dockerfile if configured; skips if image exists (unless `--rebuild`)
- `ensure_container`: creates with `docker run -d --name … -v git_root:/workspace [-p …] image sleep infinity`, or starts if stopped
- Port mappings applied **only at container creation time** — use `--restart` to recreate after changing `ports`
- `--restart` (`FORCE_RESTART=1`): runs `docker rm -f` before recreating

---

## CLI options

| Flag | Variable set | Notes |
|---|---|---|
| `-h`, `--help` | — | Print help and exit |
| `-l`, `--list` | `LIST_ALIASES=1` | Print alias table and exit (no Docker) |
| `-p`, `--profile <name>` | `PROFILE_OVERRIDE` | Highest-priority profile selector |
| `-e`, `--env <spec>` | `CLI_ENV` (appended) | Extra env vars; comma-sep or repeated; highest env priority |
| `-I`, `--interactive` | `INTERACTIVE=1` | Force all steps to use `docker exec -it` |
| `-r`, `--restart` | `FORCE_RESTART=1` | Remove + recreate container before running |
| `-b`, `--rebuild` | `FORCE_REBUILD=1` | Force Dockerfile rebuild |

---

## Script invariants

- `set -euo pipefail` active throughout; all external commands must succeed or be guarded
- `ini_parse` must be called before `ini_get`/`ini_has_section`/`ini_sections` for that file
- `load_profile` must run before `apply_project_config`
- `_setup_step` must run before `run_exec_step`; it sets `EXEC_CMD`, `EXEC_WORKDIR`, `ENV_FLAGS`, `DISPLAY_CMD`, `STEP_INTERACTIVE`, `ENV_DISPLAY`
- Container runs `sleep infinity` as PID 1; must be running before any `docker exec`
- One shared logfile per invocation (even pipeline steps); created before dispatch
- Signal re-raise at end: if `_overall_exit > 128`, script re-raises the signal to the parent shell
- `build_env_flags` emits null-delimited output; callers must use `while IFS= read -r -d '' …`
- `eval "_val=${_rawval}"` in `build_env_flags` — do NOT add outer double-quote wrapping (breaks single-quoted regex patterns and causes `pop_var_context` errors)
- `eval "EXEC_WORKDIR=${EXEC_WORKDIR}"` for workdir command substitution — same no-wrapping rule

---

## Adding new features — checklist

**New alias key:**
1. Add `declare -A ALIAS_<KEY>=()` global alongside the others
2. Read it in `load_profile()` alias loop
3. Read/override it in `_apply_config_layer()` Pass 1 (profile-scoped) and Pass 2 (unscoped)
4. Consume it in `_setup_step()` (and/or dispatch section if it affects alias resolution)
5. Optionally display it in `list_aliases()`

**New profile/project key:**
- Read in `load_profile()` and in `_apply_config_layer()` (both `[project]` block and profile-override block as appropriate)

**New CLI flag:**
- Add `case` arm in the `while [[ $# -gt 0 ]]` argument parser
- Document in `show_help()`
- Document in `README.md` options table

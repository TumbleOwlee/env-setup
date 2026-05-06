# Copilot Instructions — `docker-run`

`docker-run` is a single-file Bash script that runs commands inside a **persistent Docker container**, transparently mirroring the developer's host environment.  The git repository root is auto-detected and mounted as `/workspace`; the host working directory is translated to the equivalent container path automatically.

All code lives in `Unix/Scripts/custom/docker-run`.  Companion example configs are:
- `Unix/Scripts/custom/docker-run.conf.example` — global profile config
- `Unix/Scripts/custom/docker-run.d/example.conf` — per-project config

---

## Requirements

| # | Requirement | Implementation |
|---|---|---|
| 1 | Run any command inside a container that mirrors the host repo | `docker exec` with `-w` set to the translated CWD |
| 2 | Project config aliases take highest precedence | Pass 2 of `apply_project_config()` — unscoped `[alias:<name>]` always wins |
| 3 | Profile config can be fully overridden per-project | Pass 1 of `apply_project_config()` — profile-scoped overrides |
| 4 | Alias `env` in project config always overwrites, never merges | `ALIAS_ENV["$aname"]="$aenv"` (unconditional assignment) |
| 5 | Build image from Dockerfile instead of pulling | `ensure_image` + `EFFECTIVE_DOCKERFILE` precedence chain |
| 6 | Pipeline aliases — multi-step, fail-fast | Pipeline dispatch block; shared logfile across steps |
| 7 | Per-alias interactive mode for pipeline use | `ALIAS_INTERACTIVE` map + `STEP_INTERACTIVE` per step |
| 8 | Global `-I` forces all steps interactive | `INTERACTIVE` global; checked alongside `ALIAS_INTERACTIVE` in `_setup_step()` |
| 9 | Rolling output display (non-interactive) | `_rolling_display()` with pre-split line buffer |
| 10 | Lines wider than terminal don't break the rolling display | ANSI-stripped lines are pre-split to `tput cols − 2` chunks before buffering |
| 11 | Stderr from the container process is captured in rolling display | Both stdout and stderr redirected through FIFO: `>"$_tmpfifo" 2>&1` |
| 12 | Log file written for every non-interactive step | `mktemp` logfile created unconditionally; shared across pipeline steps |
| 13 | Host env-var passthrough by name | `build_env_flags`: bare `KEY` spec uses `${!spec+x}` indirect expansion |
| 14 | Command substitution in env specs | `build_env_flags`: detects `$(` or backtick, uses `eval "_val=\"${_rawval}\""` |
| 15 | Signal propagation (Ctrl-C) | Non-interactive: kills docker exec host-side + container-side; re-raises signal after exit |
| 16 | Container auto-created/started | `ensure_container()` checks `docker container inspect` status |
| 18 | Per-profile port mapping published at container creation | `PROFILE_PORTS` → `ensure_container` builds `-p` flags |

---

## Configuration System

### File Locations

| Config | Primary | Fallback |
|---|---|---|
| Global profile config | `~/.docker-run.conf` | `~/.local/share/.docker-run.conf` |
| Project config dir | `~/.docker-run.d/` | `~/.local/share/.docker-run.d/` |

### INI Parser

All config files are parsed with the custom `ini_parse()` function.  Values are stored in the global associative array `_CFG` with keys:

```
"<absolute-file-path>::::<section-name>::::<key>"
```

The `::::` separator (`_SEP`) must not appear in file paths or section names.

**Alias sections inside a profile are qualified** at parse time:

- In the global config, `[alias:build]` appearing after `[clang]` is stored as `alias:clang:build`.
- In project configs (no profile headers before them), `[alias:build]` is stored as `alias:build`.

Helper functions: `ini_get`, `ini_has_section`, `ini_sections`.

Inline `# comments` after values are NOT stripped by the parser — do not rely on them in actual config values.

---

## Global Profile Config (`~/.docker-run.conf`)

```ini
[<profile-name>]
image      = <image:tag>          # Docker image to pull/use
dockerfile = <path>               # Optional: build image from this Dockerfile
ports      = 8080:8080,443:443    # Optional: host:container port mappings (comma-separated)
env        = KEY,KEY=VAL,KEY=$(cmd)  # Base env for all aliases in this profile

[alias:<name>]                    # Alias section (scoped to the preceding profile)
cmd         = <shell command>     # Command executed via sh -c inside the container
workdir     = /workspace          # Container working directory (default: /workspace)
env         = KEY,KEY=VAL,...     # Alias-level env (merged with profile env at runtime)
pipeline    = alias1,alias2,...   # Makes this a pipeline alias (cmd is unused)
interactive = true                # Always run this alias with docker exec -it
```

Profiles are identified by their `[section-name]` header.  The section named `default` is used when no project config specifies a different profile.

---

## Project Config (`~/.docker-run.d/<name>.conf`)

```ini
[project]
pattern    = .*/Github/myproject(/.*)?   # Bash ERE matched against git root path
profile    = default                     # Which global profile to activate
image      = myorg/image:tag             # Override profile image for this project
dockerfile = Dockerfile.dev              # Override/set dockerfile for this project
# Note: 'ports' is a profile-level key; override it in a [<profile>] section below

[alias:<name>]          # Unscoped alias — highest precedence, all profiles
cmd     = ...
workdir = ...
env     = ...
interactive = true

[<profile-name>]        # Profile override header
image = ...             # Override profile image only for this profile
ports = 8080:8080       # Override profile port mappings for this project

[alias:<name>]          # Profile-scoped alias — scoped to the preceding profile header
cmd = ...
```

**Precedence (highest wins):** project unscoped alias > project profile-scoped alias > global profile alias.

`env` in a project alias always **overwrites** the global alias's `env` — it is never merged.  The profile's base `env` is still merged at runtime.

---

## Alias Keys Reference

| Key | Required | Description |
|---|---|---|
| `cmd` | Yes (unless `pipeline`) | Shell command executed via `sh -c "$cmd"` |
| `workdir` | No | Container working directory; defaults to `/workspace` |
| `env` | No | Comma-separated env specs (see below) |
| `pipeline` | No | Comma-separated alias names to run as a sequence |
| `interactive` | No | `true` → always use `docker exec -it` for this alias |

A `pipeline` alias and a `cmd` alias are mutually exclusive.  `pipeline` takes effect if the key exists.

---

## Environment Variable Specs (`env =`)

`env` values are comma-separated.  Four forms are supported:

| Form | Behaviour |
|---|---|
| `KEY` | Pass the host value of `KEY`; silently skipped if `KEY` is unset on the host |
| `KEY=VALUE` | Always set `KEY` to the literal `VALUE` |
| `KEY=$(cmd)` | Evaluate `cmd` on the **host** at run time; use its output as the value |
| `` KEY=`cmd` `` | Same, backtick style |

**Merging:** at runtime, the profile's base `env` and the alias's `env` are concatenated with a comma before being passed to `build_env_flags()`.  A project alias's `env` replaces the global alias's `env` entirely, but the profile base `env` is always prepended.

**Implementation:** `build_env_flags()` outputs null-delimited `-e KEY=VALUE` pairs for use with `readarray -d ''`.

---

## Dockerfile / Image Precedence

```
PROJECT_DOCKERFILE  (from [project] section of project config)
  └─ takes precedence over
     PROFILE_DOCKERFILE  (from profile section of global or project config)
```

Combined into `EFFECTIVE_DOCKERFILE`.  When set:
- Built image is tagged `docker-run-<git-root-slug>-<profile-slug>:local`
- Built automatically on first use
- Rebuilt when `--rebuild` is passed

Relative `dockerfile` paths are resolved against the directory of the config file that contains the key.

---

## Container Lifecycle

- Container name: `docker-run-<git-root-slug>-<profile-slug>` (one container per profile per repo)
- `ensure_image()` — builds from Dockerfile if configured; no-ops for pre-built images
- `ensure_container()` — creates container with `docker run -d … sleep infinity`; or starts it if stopped
- Port mappings (`PROFILE_PORTS`) are passed as `-p host:container` flags **only at container creation** — they cannot be changed on an existing container.  If ports are configured and the container already exists, a warning is emitted advising to use `--restart` or `docker rm -f <container-name>`.  `--restart` (`FORCE_RESTART=1`) automates this: it runs `docker rm -f` before `ensure_container` recreates the container.
- The git root is mounted read-write as `/CONTAINER_MOUNT` (`/workspace`)

---

## CLI Interface

```
docker-run [OPTIONS] [ALIAS | COMMAND [ARGS...]]

Options:
  -h, --help                 Show help and exit
  -l, --list                 List all aliases for the selected profile and exit
  -p, --profile <name>       Override the active profile
  -I, --interactive          Force all steps interactive (docker exec -it)
  -r, --restart              Remove and recreate the container before running
  -b, --rebuild              Force rebuild of the Docker image
```

- No arguments → prints help
- `-l` / `--list` alone → resolves profile + project config, prints alias table, exits (no Docker interaction)
- First argument matches a known alias → alias dispatch
- First argument matches a pipeline alias → pipeline dispatch
- Otherwise → literal command dispatch (all args forwarded to `docker exec`)

---

## Dispatch Modes

### Literal command
```bash
docker exec -w "$CONTAINER_WORKDIR" "${ENV_FLAGS[@]}" "$CONTAINER_NAME" "$@"
```
Uses only the profile's base `env`.  `STEP_INTERACTIVE` mirrors the global `-I` flag.

### Single alias
1. `_setup_step "$ALIAS_NAME"` — resolves workdir, cmd, env, interactive flag; prints header
2. `run_exec_step` — executes and prints footer

### Pipeline alias
Same as single alias, repeated for each step alias in `ALIAS_PIPELINE[$ALIAS_NAME]`.  Steps share one logfile.  Stops on first non-zero exit.

---

## Execution Modes

### Non-interactive (default)
```
docker exec (no -t) → stdout+stderr → FIFO → _rolling_display → terminal
                                            ↘ logfile
```
- FIFO: `mktemp -u` + `mkfifo`; cleaned up by EXIT trap
- Rolling display: last 10 physical rows kept live in the terminal
- Logfile: `mktemp -t docker-run.XXXXXX.log` in `$TMPDIR`; survives for 3 minutes
- SIGINT/SIGTERM: host-side `kill` + `docker exec … kill -SIG -1` in container

### Interactive (`-I` or `interactive = true`)
```
docker exec -it → foreground (terminal connected directly)
```
- No FIFO, no rolling display, no logfile
- SIGINT is caught and re-raised as exit code 130

---

## Rolling Display (`_rolling_display`)

- Buffer: circular array of ≤ `max` (10) slots; each slot = exactly 1 physical terminal row
- `content_width = tput cols − 2` (subtracts the `│ ` prefix)
- Each incoming line is ANSI-stripped, then split into `content_width`-wide chunks before insertion; each chunk occupies one buffer slot
- Cursor-up on each redraw is always exactly `$max` (since buffer slots == physical rows)
- When `content_width` is 0 (non-TTY or unknown): no splitting, lines printed verbatim
- Raw (ANSI-intact) lines are written to the logfile before display processing
- `\r`-style progress-bar output: `line="${line##*$'\r'}"` strips everything before the last `\r`
- ANSI regex stored in variable `_ansi_re=$'\033\[[0-9;]*[A-Za-z]'` (avoids bash misparse of `[` inside `[[ ]]`)

---

## Key Global Variables

| Variable | Type | Purpose |
|---|---|---|
| `_CFG` | `declare -A` | All parsed INI values |
| `GLOBAL_CONFIG` | string | Path to `~/.docker-run.conf` |
| `PROJECT_CONFIG_DIR` | string | Path to `~/.docker-run.d/` |
| `PROJECT_FILE` | string | Matched project config file path |
| `PROFILE_IMAGE` | string | Image from profile section |
| `PROFILE_ENV` | string | Base env from profile section |
| `PROFILE_DOCKERFILE` | string | Dockerfile from profile section |
| `PROFILE_PORTS` | string | Port mappings from profile section (comma-separated `host:container`) |
| `PROJECT_IMAGE` | string | Image override from `[project]` section |
| `PROJECT_DOCKERFILE` | string | Dockerfile from `[project]` section |
| `EFFECTIVE_DOCKERFILE` | string | `PROJECT_DOCKERFILE ?: PROFILE_DOCKERFILE` |
| `FINAL_IMAGE` | string | Resolved Docker image to use |
| `CONTAINER_NAME` | string | `docker-run-<slug>-<profile>` |
| `ALIAS_CMD` | `declare -A` | `[name]` → shell command string |
| `ALIAS_WORKDIR` | `declare -A` | `[name]` → container working directory |
| `ALIAS_ENV` | `declare -A` | `[name]` → env spec string |
| `ALIAS_PIPELINE` | `declare -A` | `[name]` → comma-separated step list |
| `ALIAS_INTERACTIVE` | `declare -A` | `[name]` → `"true"` or `""` |
| `INTERACTIVE` | int | `1` if `-I` was passed |
| `STEP_INTERACTIVE` | int | `1` for the current step (per-step flag) |
| `ENV_FLAGS` | array | Expanded `-e KEY=VAL` arguments |
| `EXEC_CMD` | string | Alias command for current step |
| `EXEC_ARGS` | array | Literal command args for current step |
| `EXEC_WORKDIR` | string | Container workdir for current step |
| `DISPLAY_CMD` | string | Human-readable command label for header |
| `COMBINED_ENV` | string | Merged `profile_env,alias_env` |
| `ENV_DISPLAY` | string | Human-readable env list for header |
| `_STEP_SIG_RECEIVED` | string | `"INT"` / `"TERM"` if step was signalled |
| `_active_tmpfifo` | string | Path to FIFO; cleaned on EXIT |

---

## Script Invariants and Constraints

- `set -euo pipefail` is active throughout; all external commands must succeed or be explicitly guarded (`|| true`, `|| _exit=$?`, etc.)
- `ini_parse` must be called before any `ini_get` / `ini_has_section` / `ini_sections` call for that file
- `load_profile` must be called before `apply_project_config`; `apply_project_config` may overwrite `PROFILE_*` globals in-place
- `_setup_step` must be called before `run_exec_step`; it sets `EXEC_CMD`, `EXEC_WORKDIR`, `ENV_FLAGS`, `DISPLAY_CMD`, `STEP_INTERACTIVE`, `ENV_DISPLAY`
- Container is created with `sleep infinity` as PID 1; it must be running before any `docker exec`
- One shared logfile per invocation (even across pipeline steps); created with `mktemp` before dispatch
- Signal re-raise at end: if `_overall_exit > 128`, the script re-raises the signal to the parent shell
- `build_env_flags` emits null-delimited output; callers must use `while IFS= read -r -d '' …` or equivalent
- `eval "_val=\"${_rawval}\""` in `build_env_flags` is intentional for command substitution; values with unescaped double-quotes inside `$()` are a known edge-case limitation

---

## Adding New Features — Guidelines

**New alias key:** add to all four places that load alias data:
1. `load_profile()` alias loop
2. `apply_project_config()` Pass 1 (profile-scoped)
3. `apply_project_config()` Pass 2 (unscoped)
4. `_setup_step()` (consume it)

Also declare a new `declare -A ALIAS_<KEY>=()` alongside the others.

**New profile/project key:** read it in `load_profile()` and `apply_project_config()` (both the profile-override block and the `[project]` section as appropriate).

**New CLI flag:** add a `case` arm in the `while [[ $# -gt 0 ]]` argument parser; document it in `show_help()`.

**INI parser limitations:** does not support multi-line values, quoted strings, or `#` comments at end of value lines.  Keep config values on one line; avoid `#` in values.

# dex — Docker Execute

Run commands transparently inside a **persistent Docker container** without thinking about container lifecycle. The git repository root is automatically mounted as `/workspace`; your current working directory is translated to the equivalent path inside the container so every command behaves as if it runs locally.

---

## Table of Contents

1. [Quick start](#quick-start)
2. [How it works](#how-it-works)
3. [Installation](#installation)
4. [Usage](#usage)
5. [Configuration hierarchy](#configuration-hierarchy)
6. [Config file reference](#config-file-reference)
   - [Profile sections](#profile-sections)
   - [Alias sections](#alias-sections)
   - [Pipeline aliases](#pipeline-aliases)
   - [The \[project\] section](#the-project-section)
7. [Environment variables in config](#environment-variables-in-config)
8. [Dockerfile-based images](#dockerfile-based-images)
9. [Port mappings](#port-mappings)
10. [Interactive mode](#interactive-mode)
11. [Listing aliases](#listing-aliases)
12. [Options reference](#options-reference)
13. [Example files](#example-files)

---

## Quick start

```sh
# 1. Put the script somewhere on your PATH
cp dex ~/.local/bin/dex
chmod +x ~/.local/bin/dex

# 2. Drop a config into the repository root (or create a global/local one)
cp dex.repo.conf.example /path/to/your-repo/.dex.conf
#    edit .dex.conf — set image, aliases, etc.

# 3. Use it
cd /path/to/your-repo
dex build          # run the 'build' alias
dex cmake -S . -B build   # or any arbitrary command
dex -l             # list all aliases
```

---

## How it works

1. **Container lifecycle** — On the first invocation the container is created (`docker run -d`) and kept alive. Subsequent calls reuse it (`docker exec`). Use `--restart` to recreate it (e.g. after changing port mappings or the image).
2. **Mount & CWD** — The git root is mounted read-write at `/workspace`. The host CWD is converted to the equivalent path inside the container automatically.
3. **Config** — All behaviour is driven by INI-style config files. The script merges three layers of config (see [Configuration hierarchy](#configuration-hierarchy)).
4. **Aliases** — Short names defined in config map to commands, a working directory, and env vars. Pipelines chain multiple aliases with automatic pass/fail reporting.

---

## Installation

```sh
# Option A: copy to a directory on $PATH
cp dex ~/.local/bin/dex
chmod +x ~/.local/bin/dex

# Option B: symlink (stays in sync with edits here)
ln -s "$(pwd)/dex" ~/.local/bin/dex
```

No external dependencies beyond **bash ≥ 4.2** and **docker** (accessible without `sudo`).

---

## Usage

```
dex [OPTIONS] [ALIAS | COMMAND [ARGS...]]
```

If the first positional argument matches a defined alias the alias is expanded; otherwise the full argument list is passed verbatim to the container shell.

```sh
dex build                  # run the 'build' alias
dex ci                     # run the 'ci' pipeline
dex -p clang build         # use the 'clang' profile
dex cmake -S . -B build    # arbitrary command
dex bash                   # interactive shell (if not aliased)
dex -e JOBS=8 build        # pass an extra env var (overrides config)
dex -e A=1 -e B=2 build    # multiple extra env vars
dex -e 'TOKEN=$(cat ~/.token)' build  # command substitution in -e
dex -l                     # list all aliases
dex --help                 # full help
```

---

## Configuration hierarchy

Config files are **merged** in the following priority order (highest priority first):

| Priority | Location | Purpose |
|----------|----------|---------|
| **1 – Local project** | `~/.dex.d/<name>.conf` (or `~/.local/share/.dex.d/<name>.conf`) | Personal overrides, never committed |
| **2 – Repository** | `<git-root>/.dex.conf` | Committed defaults, shared with the team |
| **3 – Global** | `~/.dex.conf` (or `~/.local/share/.dex.conf`) | Optional personal defaults across all projects |

When the same key is defined in multiple files the **highest-priority file wins**. All three files are optional — a project only needs the repository config to work out of the box.

### Local project config matching

Files in `~/.dex.d/` are scanned in alphabetical order. The first file whose `pattern` key (a bash ERE regex) matches the absolute path of the current git root is selected. This lets one file cover all worktrees of a project.

```ini
[project]
pattern = .*/Github/myproject(/.*)?
```

---

## Config file reference

All config files share the same INI format. Lines starting with `#` are comments. Keys use `=`. Section headers are in `[square brackets]`.

### Profile sections

A profile section defines the Docker image and default environment for a named set of aliases.

```ini
[default]
image  = ubuntu:22.04
env    = CC,CXX,MAKEFLAGS
ports  = 8080:8080
```

| Key | Description |
|-----|-------------|
| `image` | Docker image to use (pulled automatically if absent). |
| `dockerfile` | Path to a Dockerfile to build the image from. Relative paths are resolved from the config file's directory. See [Dockerfile-based images](#dockerfile-based-images). |
| `env` | Comma-separated list of environment variable specs. See [Environment variables in config](#environment-variables-in-config). |
| `ports` | Comma-separated `host:container` port mappings (same format as `docker run -p`). Applied at container creation time only. |

Multiple profiles can coexist in one file. Select a profile with `-p <name>`:

```ini
[default]
image = ubuntu:22.04

[clang]
image = silkeh/clang:18
env   = CC=clang,CXX=clang++
```

```sh
dex -p clang build
```

### Alias sections

Aliases are defined with `[alias:<name>]` (unscoped, available in all profiles) or `[alias:<profile>:<name>]` (scoped to a specific profile).

```ini
[alias:build]
cmd         = cmake --build /workspace/build
workdir     = /workspace/build
env         = JOBS=4
interactive = false

[alias:shell]
cmd         = bash
interactive = true
```

| Key | Description |
|-----|-------------|
| `cmd` | Command to run inside the container. Required for non-pipeline aliases. |
| `workdir` | Working directory inside the container. Defaults to `/workspace`. Supports command substitution: `workdir = /workspace/$(git branch --show-current)`. |
| `env` | Alias-level environment variables (see [Environment variables in config](#environment-variables-in-config)). These are merged on top of the profile-level env. |
| `interactive` | Set to `true` to always run with a TTY (`docker exec -it`), even inside a pipeline. |

#### Alias precedence (highest wins)

1. Project-level unscoped alias (`[alias:<name>]` before any profile header in a local or repo config)
2. Project-level profile-scoped alias (`[alias:<profile>:<name>]`)
3. Global profile alias (`[alias:<name>]` in the global config under a profile header)

### Pipeline aliases

A pipeline alias runs a sequence of other aliases in order, stopping on the first failure.

```ini
[alias:ci]
pipeline = configure,build,test

[alias:configure]
cmd = cmake -S . -B build

[alias:build]
cmd = cmake --build build

[alias:test]
cmd = ctest --test-dir build --output-on-failure
```

```sh
dex ci   # runs configure → build → test
```

Each step prints its own summary header and footer. The overall pipeline stops immediately if any step fails.

### The [project] section

The `[project]` section in **repository** and **local project** config files controls script-level settings.

```ini
[project]
# --- local project config only ---
pattern    = .*/Github/myproject(/.*)?   # regex to match the git root

# --- both repository and local project config ---
profile    = default    # which profile to activate by default
image      = myorg/custom-image:1.2.3   # override the profile image
dockerfile = Dockerfile.dev             # build image from this Dockerfile
```

---

## Environment variables in config

The `env` key (in both profile and alias sections) accepts a comma-separated list of variable specs:

| Form | Behaviour |
|------|-----------|
| `KEY` | Pass the host value of `KEY` into the container. Skipped silently if `KEY` is unset on the host. |
| `KEY=VALUE` | Set `KEY` to the literal string `VALUE`. |
| `KEY=$(cmd)` | Evaluate `cmd` on the host at run time; use its stdout as the value. |
| `KEY=\`cmd\`` | Same as above, backtick style. |

**Examples:**

```ini
[default]
# Pass compiler toolchain from the host, set a fixed flag, and derive a
# JIRA ticket number from the current branch name at run time.
env = CC,CXX,MAKEFLAGS,BUILD_TYPE=Release,JIRA=$(git branch --show-current | grep -oP 'PRJ-\d+')
```

```ini
[alias:test]
env = CTEST_OUTPUT_ON_FAILURE=1,TEST_DATA=/workspace/testdata,BRANCH=$(git branch --show-current)
```

You can also inject env vars at invocation time with `-e` / `--env`. These take the **highest priority** and override any same-named variable from config:

```sh
dex -e JOBS=8 build
dex -e A=1 -e B=2 build          # repeat -e for multiple vars
dex -e 'JOBS=8,VERBOSE=1' build  # or comma-separate in one -e
dex -e 'TOKEN=$(cat ~/.token)' build  # command substitution works too
```

---

## Dockerfile-based images

Instead of pulling a pre-built image you can point to a local Dockerfile. The script builds the image automatically on first use and tags it as `dex-<project-slug>-<profile-slug>:local`.

```ini
# In a profile or [project] section:
dockerfile = Dockerfile.dev
```

- **Relative paths** are resolved relative to the directory containing the config file.
- Use `--rebuild` to force a fresh build even if the image already exists.
- The `dockerfile` key in a `[project]` section takes precedence over one in a profile section.

```sh
dex --rebuild build   # rebuild image, then run 'build' alias
```

---

## Port mappings

```ini
[default]
ports = 8080:8080,5432:5432
```

Port bindings are applied **only at container creation time** (like `docker run -p`). If you change `ports` after the container already exists, recreate it:

```sh
dex --restart build
```

---

## Interactive mode

By default commands run non-interactively (`docker exec` without `-it`). Two ways to enable TTY allocation:

**1. Per alias** — set `interactive = true` in the alias section:

```ini
[alias:shell]
cmd         = bash
interactive = true
```

**2. Global flag** — pass `-I` / `--interactive` on the command line to force all steps interactive:

```sh
dex -I shell
```

---

## Listing aliases

```sh
dex -l           # list aliases for the active (default) profile
dex -l -p clang  # list aliases for the 'clang' profile
```

The output shows, for each alias: the command, working directory, alias-level env vars, and whether it is interactive or a pipeline. Config file sources are shown in the header so you can see which layer each setting comes from.

---

## Options reference

| Option | Description |
|--------|-------------|
| `-h`, `--help` | Show help and exit. |
| `-l`, `--list` | List all aliases for the selected profile and exit. |
| `-p`, `--profile <name>` | Select a named profile defined in any config file. |
| `-e`, `--env <spec>` | Inject extra environment variables for this invocation only (highest priority, overrides config). Accepts comma-separated specs (`KEY=val,OTHER=val`) and may be repeated (`-e KEY=val -e OTHER=val`). Supports the same forms as the `env` config key: plain pass-through (`KEY`), fixed value (`KEY=val`), and command substitution (`KEY=$(cmd)`). |
| `-I`, `--interactive` | Force all commands to run with a TTY (`docker exec -it`). |
| `-r`, `--restart` | Remove and recreate the container before running. Applies updated port mappings and other creation-time settings. |
| `-b`, `--rebuild` | Force a rebuild of the Docker image (requires `dockerfile` in config). |

---

## Example files

| File | Description |
|------|-------------|
| [`dex.conf.example`](dex.conf.example) | Global config template — copy to `~/.dex.conf`. Defines profiles, aliases, and pipelines. |
| [`dex.repo.conf.example`](dex.repo.conf.example) | Repository config template — copy to `<git-root>/.dex.conf`. Committed and shared with the team. |
| [`dex.d/example.conf`](dex.d/example.conf) | Local project config template — copy to `~/.dex.d/<project>.conf`. Personal, never committed. |

---

### Typical team setup

```
your-repo/
├── .dex.conf          ← committed: image, shared aliases, pipeline
└── ...

~/.dex.d/
└── myproject.conf            ← personal: pattern match + local overrides

~/.dex.conf            ← optional: global personal defaults
```

With this setup any developer clones the repo and `dex build` works immediately. Individuals can layer personal overrides (different image tags, extra env vars, custom aliases) without touching the committed config.

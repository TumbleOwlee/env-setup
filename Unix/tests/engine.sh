#!/bin/bash
# shellcheck disable=SC2016,SC2034 # the checks are evaluated by check
# Tests of the engine with fixture modules. Installs nothing. Requires root or
# passwordless sudo, because the engine checks for it.
#   bash Unix/tests/engine.sh

SETUP="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/setup.sh"
FAILED=0

function check {
    if eval "$2"; then
        echo "ok   - $1"
    else
        echo "FAIL - $1"
        FAILED=1
    fi
}

# Run the setup without terminal: engine <flags>. Sets OUT and RC.
function engine {
    OUT="$(setsid -w env HOME="$HOME_DIR" PATH="$SANDBOX/bin:$PATH" ENV_SETUP_MODULES="$MODULES" XDG_STATE_HOME= \
        timeout 20 bash "$SETUP" "$@" 2>&1 </dev/null)"
    RC=$?
}

SANDBOX="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$SANDBOX"' EXIT
MODULES="$SANDBOX/modules"
HOME_DIR="$SANDBOX/home"
mkdir -p "$MODULES" "$HOME_DIR"

cat >"$MODULES/a.sh" <<'FIXTURE'
module good --desc "good"
function good_install { echo cached >"$XDG_CACHE_HOME/file"; echo temp >"$TMPDIR/file"; }
module needs-good --deps "good"
function needs_good_install { echo ran >"$HOME/needs-good"; }
module broken --desc "broken"
function broken_install { false; echo continued >"$HOME/after-false"; }
module needs-broken --deps "broken"
function needs_broken_install { echo ran >"$HOME/needs-broken"; }
module later --after "broken"
function later_install { echo ran >"$HOME/later"; }
module off --optional
function off_install { echo ran >"$HOME/off"; }
module slim --no-minimal
FIXTURE

engine --bogus
check "unknown flag is an error" '[ "$RC" -eq 1 ] && [[ "$OUT" == *"Unknown flag"* ]]'
engine --skip=nope
check "unknown module is an error" '[ "$RC" -eq 1 ] && [[ "$OUT" == *"Unknown module"* ]]'
engine --dry-run --only=needs-good
check "--only pulls dependencies" '[[ "$OUT" == *good*needs-good* ]] && [[ "$OUT" != *later* ]]'
engine --dry-run
check "dry run leaves off optional modules" '[[ "$OUT" != *" off"* ]]'
engine --dry-run --include=off
check "--include adds optional modules" '[[ "$OUT" == *" off"* ]]'
engine --dry-run --skip=good
check "skipped dependency leaves out its dependents" '[[ "$OUT" == *"Leaving out needs-good"* ]]'
engine --dry-run --minimal
check "--minimal leaves out modules" '[[ "$OUT" != *slim* ]]'
engine --dry-run --minimal --include=slim
check "--include wins over --minimal" '[[ "$OUT" == *slim* ]]'

# No -n on purpose: without a terminal it must neither ask nor retry
engine --skip=later
check "failure without terminal terminates" '[ "$RC" -eq 1 ]'
check "failure without terminal retries exactly once" '[ "$(grep -c "trying once more" <<<"$OUT")" -eq 2 ]'
check "failure shows the log" '[[ "$OUT" == *"last lines of"* ]]'
check "set -e stops a failing module" '[ ! -e "$HOME_DIR/after-false" ]'
check "dependent of a failed module is left out" '[ ! -e "$HOME_DIR/needs-broken" ]'
check "other modules continue after a failure" '[ -e "$HOME_DIR/.local/state/env-setup" ] && [[ "$OUT" == *needs-good*done* ]]'
check "log survives a failure" 'compgen -G "$HOME_DIR/.local/state/env-setup/*.log" >/dev/null'

rm -rf -- "${HOME_DIR:?}"
mkdir -p "$HOME_DIR/.local/state/env-setup"
echo mine >"$HOME_DIR/.local/state/env-setup/mine.log"
for i in 1 2 3 4 5 6 7; do
    : >"$HOME_DIR/.local/state/env-setup/20200101-00000$i.log"
done
engine --only=good
check "old logs are pruned" '[ ! -e "$HOME_DIR/.local/state/env-setup/20200101-000001.log" ]'
check "other files next to the logs stay" '[ -e "$HOME_DIR/.local/state/env-setup/mine.log" ]'
check "success exits 0" '[ "$RC" -eq 0 ]'
check "log survives success" 'compgen -G "$HOME_DIR/.local/state/env-setup/*.log" >/dev/null'
check "no caches in the home directory" '[ ! -e "$HOME_DIR/.cache" ]'
check "work directory is removed" '! compgen -G "/var/tmp/env-setup.*" >/dev/null'

cat >"$MODULES/b.sh" <<'FIXTURE'
module hang
function hang_install { echo $$ >"$HOME/hang.pid"; sh -c 'echo $$ >"$HOME/hang-child.pid"; exec sleep 300'; }
FIXTURE
setsid env HOME="$HOME_DIR" ENV_SETUP_MODULES="$MODULES" bash "$SETUP" --only=hang >/dev/null 2>&1 </dev/null &
ENGINE=$!
for _ in $(seq 1 50); do
    [ -s "$HOME_DIR/hang-child.pid" ] && break
    sleep 0.1
done
kill -TERM "$ENGINE" 2>/dev/null
sleep 1
check "SIGTERM stops the running module with its children" '! kill -0 "$(cat "$HOME_DIR/hang-child.pid")" 2>/dev/null'
check "SIGTERM removes the work directory" '! compgen -G "/var/tmp/env-setup.*" >/dev/null'

# A plugin that keeps failing is moved and cloned again, names from the output are not trusted
mkdir -p "$SANDBOX/bin" "$HOME_DIR/.local/share/nvim/lazy/broken" "$HOME_DIR/.local/share/nvim/keep"
: >"$HOME_DIR/.local/share/nvim/lazy/broken/partial"
: >"$HOME_DIR/.local/share/nvim/keep/mine"
cat >"$SANDBOX/bin/nvim" <<'FIXTURE'
#!/bin/bash
if [ -e "$HOME/.local/share/nvim/lazy/broken/partial" ]; then
    echo "SyncInstall: installing these plugins failed: ../keep, broken"
    exit 1
fi
FIXTURE
chmod +x "$SANDBOX/bin/nvim"
cat >"$MODULES/c.sh" <<'FIXTURE'
source "$ROOT/modules/neovim.sh"
module sync
function sync_install { _neovim_sync; }
FIXTURE
engine --only=sync
check "broken plugin is replaced and the run succeeds" '[ "$RC" -eq 0 ] && [ ! -e "$HOME_DIR/.local/share/nvim/lazy/broken" ]'
check "broken plugin is moved, not deleted" 'compgen -G "$HOME_DIR/.local/share/nvim/lazy-failed.*/broken/partial" >/dev/null'
check "unsafe plugin name is ignored" '[ -e "$HOME_DIR/.local/share/nvim/keep/mine" ]'

exit "$FAILED"

#!/usr/bin/env bats
#
# Behavioral tests for entrypoint.sh.
#
# Strategy: run the real entrypoint.sh (real socat/nc, no mocks) against a
# throwaway TCP target and a scratch socket directory, so what's exercised
# matches production exactly. UNIX-LISTEN binds immediately without the TCP
# target being reachable, so TARGET_HOST/TARGET_PORT can safely point at
# nothing for most tests.
#
# Process PIDs are looked up on demand via `pgrep -f` against a unique,
# per-test path/name rather than captured with `$!` — under bats-core's own
# subshell/job-control plumbing, `$!` does not reliably resolve to the
# process actually started here.

setup() {
    TEST_DIR="$(mktemp -d)"
    # mktemp defaults to 700 (root-only traversal); a real bind-mounted host
    # directory is typically world-traversable, so match that here — otherwise
    # the non-root user entrypoint.sh drops to can't even reach its own
    # (correctly chowned) socket subdirectory.
    chmod 755 "$TEST_DIR"
    cp "$BATS_TEST_DIRNAME/../entrypoint.sh" "$TEST_DIR/"
    cp "$BATS_TEST_DIRNAME/../VERSION" "$TEST_DIR/"
    chmod +x "$TEST_DIR/entrypoint.sh"

    export TARGET_HOST=127.0.0.1
    export TARGET_PORT=1
    export UNIX_SOCKET_NAME="test-$BATS_TEST_NUMBER.sock"
    export UNIX_SOCKET_PATH="$TEST_DIR/socket"
    export HOST_SOCKET_PATH="$TEST_DIR/host"
    unset DEBUG_LEVEL
}

teardown() {
    pkill -9 -f "$TEST_DIR/entrypoint.sh" 2>/dev/null
    pkill -9 -f "UNIX-LISTEN:.*$UNIX_SOCKET_NAME" 2>/dev/null
    pkill -9 -f "nc .*34599" 2>/dev/null
    rm -rf "$TEST_DIR"
}

run_entrypoint_bg() {
    LOG="$TEST_DIR/out.log"
    # Invoked via the absolute path (not a bare `./entrypoint.sh`) so its
    # /proc cmdline actually contains $TEST_DIR for entrypoint_pid() to match.
    ( cd "$TEST_DIR" && exec "$TEST_DIR/entrypoint.sh" >"$LOG" 2>&1 ) &
    disown 2>/dev/null || true
}

entrypoint_pid() {
    pgrep -f "$TEST_DIR/entrypoint.sh" | head -n1
}

socat_pid() {
    pgrep -f "UNIX-LISTEN:.*$UNIX_SOCKET_NAME" | head -n1
}

wait_for_log() {
    pattern="$1"
    tries=0
    # 40 * 0.25s = 10s — merge-triggered runs can land on a cold runner
    # (evicted Docker cache, first container start), pushing the very first
    # backgrounded entrypoint.sh past a tighter budget even though nothing's
    # actually wrong; a rerun on a warm runner always passes.
    while [ "$tries" -lt 40 ]; do
        grep -qE "$pattern" "$LOG" 2>/dev/null && return 0
        tries=$((tries + 1))
        sleep 0.25
    done
    return 1
}

wait_for_pid_gone() {
    pid="$1"
    tries=0
    while kill -0 "$pid" 2>/dev/null && [ "$tries" -lt 20 ]; do
        tries=$((tries + 1))
        sleep 0.25
    done
    ! kill -0 "$pid" 2>/dev/null
}

# ---- Environment variable validation -------------------------------------

@test "fails when TARGET_HOST is missing" {
    unset TARGET_HOST
    run "$TEST_DIR/entrypoint.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"TARGET_HOST environment variable is required"* ]]
}

@test "fails when TARGET_PORT is missing" {
    unset TARGET_PORT
    run "$TEST_DIR/entrypoint.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"TARGET_PORT environment variable is required"* ]]
}

@test "fails when UNIX_SOCKET_NAME is missing" {
    unset UNIX_SOCKET_NAME
    run "$TEST_DIR/entrypoint.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNIX_SOCKET_NAME environment variable is required"* ]]
}

@test "fails when UNIX_SOCKET_PATH is missing" {
    unset UNIX_SOCKET_PATH
    run "$TEST_DIR/entrypoint.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNIX_SOCKET_PATH environment variable is required"* ]]
}

@test "fails when HOST_SOCKET_PATH is missing" {
    unset HOST_SOCKET_PATH
    run "$TEST_DIR/entrypoint.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"HOST_SOCKET_PATH environment variable is required"* ]]
}

# ---- PUID/PGID privilege dropping ------------------------------------------

@test "fails when PUID is not numeric" {
    export PUID=abc
    run "$TEST_DIR/entrypoint.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PUID 'abc' is not a valid numeric user id."* ]]
}

@test "fails when PGID is not numeric" {
    export PGID=abc
    run "$TEST_DIR/entrypoint.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PGID 'abc' is not a valid numeric group id."* ]]
}

@test "creates appuser/appgroup at the default 911 PUID/PGID and owns the socket dir" {
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"
    grep -q "No existing group with GID 911, creating 'appgroup'" "$LOG"
    grep -q "No existing user with UID 911, creating 'appuser'" "$LOG"
    owner="$(stat -c '%U:%G' "$UNIX_SOCKET_PATH")"
    [ "$owner" = "appuser:appgroup" ]
}

@test "reuses an existing user/group instead of creating one" {
    export PUID=0
    export PGID=0
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"
    grep -q "Reusing existing group 'root' (GID 0)" "$LOG"
    grep -q "Reusing existing user 'root' (UID 0)" "$LOG"
}

@test "creates the socket with mode 666 so other-UID consumers can connect" {
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"
    mode="$(stat -c '%a' "$UNIX_SOCKET_PATH/$UNIX_SOCKET_NAME")"
    [ "$mode" = "666" ]
}

@test "prints the version banner from the VERSION file" {
    echo "9.9.9" > "$TEST_DIR/VERSION"
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"
    grep -q "Version 9.9.9" "$LOG"
}

# ---- Socket path preparation ----------------------------------------------

@test "removes a pre-existing file at the socket path before starting" {
    mkdir -p "$UNIX_SOCKET_PATH"
    touch "$UNIX_SOCKET_PATH/$UNIX_SOCKET_NAME"
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"
    grep -q "exists, removing it" "$LOG"
    grep -q "Removed existing socket" "$LOG"
}

@test "creates the socket directory when it does not exist" {
    [ ! -d "$UNIX_SOCKET_PATH" ]
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"
    grep -q "Created directory $UNIX_SOCKET_PATH" "$LOG"
    [ -d "$UNIX_SOCKET_PATH" ]
}

@test "reports the socat-created socket as active once it is listening" {
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"
    grep -q "Socat socket is active" "$LOG"
    [ -S "$UNIX_SOCKET_PATH/$UNIX_SOCKET_NAME" ]
}

# ---- Target connectivity check (informational, non-fatal) -----------------

@test "warns but continues when the TCP target is unreachable" {
    export TARGET_PORT=1
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"
    grep -q "Cannot connect to $TARGET_HOST:$TARGET_PORT" "$LOG"
    grep -q "Container is ready and running" "$LOG"
}

@test "reports success when the TCP target is reachable" {
    ( nc -l 127.0.0.1 34599 >/dev/null 2>&1 & )
    disown 2>/dev/null || true
    sleep 0.3
    export TARGET_PORT=34599
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"
    grep -q "Connection to $TARGET_HOST:$TARGET_PORT is working" "$LOG"
}

# ---- Debug level -> socat flags mapping -----------------------------------

@test "maps an unset DEBUG_LEVEL default of 1 to a single -d flag" {
    run_entrypoint_bg
    wait_for_log "Using debug level"
    grep -q "Using debug level: 1 (-d)" "$LOG"
}

@test "maps DEBUG_LEVEL=2 to two -d flags" {
    export DEBUG_LEVEL=2
    run_entrypoint_bg
    wait_for_log "Using debug level"
    grep -q "Using debug level: 2 (-d -d)" "$LOG"
}

@test "maps DEBUG_LEVEL=3 to three -d flags" {
    export DEBUG_LEVEL=3
    run_entrypoint_bg
    wait_for_log "Using debug level"
    grep -q "Using debug level: 3 (-d -d -d)" "$LOG"
}

@test "maps an unrecognized DEBUG_LEVEL to no debug flags" {
    export DEBUG_LEVEL=0
    run_entrypoint_bg
    wait_for_log "Using debug level"
    grep -q "Using debug level: 0 ()" "$LOG"
}

# ---- Shutdown behavior ------------------------------------------------------

@test "shuts down gracefully and stops socat on SIGTERM" {
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"

    ep_pid="$(entrypoint_pid)"
    sc_pid="$(socat_pid)"
    [ -n "$ep_pid" ]
    [ -n "$sc_pid" ]

    kill -TERM "$ep_pid"
    wait_for_pid_gone "$ep_pid"

    grep -q "Received SIGTERM, shutting down gracefully" "$LOG"
    grep -q "Cleanup completed, exiting" "$LOG"
    ! kill -0 "$sc_pid" 2>/dev/null
}

@test "exits 1 once socat's process dies unexpectedly" {
    run_entrypoint_bg
    wait_for_log "Socat socket is active|Socat socket not found"

    ep_pid="$(entrypoint_pid)"
    sc_pid="$(socat_pid)"
    [ -n "$ep_pid" ]
    [ -n "$sc_pid" ]

    kill -9 "$sc_pid"
    wait_for_pid_gone "$ep_pid"

    grep -q "Socat process has stopped" "$LOG"
}
